const hre = require("hardhat");
const { assert, expect } = require("chai");
const { getEventFromTx } = require("../../helpers/utils");
const ethers = hre.ethers;

// ─── Enums (mirror Solidity) ──────────────────────────────────────────────────
const RequestType = { AllowNetworkAccess: 0, TrustedAlgorithm: 1, TrustedAlgorithmPublisher: 2 };
const Status = { Pending: 0, Cancelled: 1, Approved: 2, Resolved: 3, Rejected: 4 };

// ─── Helpers ──────────────────────────────────────────────────────────────────
async function increaseTime(seconds) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine", []);
}

function bitmap(...types) {
    return types.reduce((acc, t) => acc | (1 << t), 0);
}

// ─── Test Suite ───────────────────────────────────────────────────────────────
describe("MetadataRequestManager", () => {
    let manager;
    let votingWeight;  // MockVotingWeight instance
    let dataset;       // MockERC721 — acts as the dataset NFT
    let algorithm;     // MockERC721 — acts as the algorithm NFT

    let owner, requester, voter1, voter2, stranger;

    const ONE_DAY = 86400;
    const THIRTY_DAYS = 30 * ONE_DAY;

    // ─── Factory helpers ────────────────────────────────────────────────────────
    // These deploy from compiled Hardhat artifacts whose source matches the
    // VOTING_WEIGHT_BYTECODE_SRC / ERC721_BYTECODE_SRC strings above.
    async function deployMockVotingWeight() {
        const Factory = await ethers.getContractFactory("MockVotingWeight");
        const instance = await Factory.deploy();
        await instance.deployed();
        return instance;
    }

    async function deployMockERC721() {
        const Factory = await ethers.getContractFactory("MockERC721");
        const instance = await Factory.deploy();
        await instance.deployed();
        return instance;
    }

    // ─── Default params builder ─────────────────────────────────────────────────
    function defaultParams(overrides = {}) {
        return {
            datasetAddress: dataset.address,
            algorithmAddress: algorithm.address,
            requestTypes: [RequestType.TrustedAlgorithm],
            data: ["test"],
            reason: "Update dataset permissions",
            expiresIn: ONE_DAY,
            ...overrides,
        };
    }

    beforeEach(async () => {
        [owner, requester, voter1, voter2, stranger] = await ethers.getSigners();

        votingWeight = await deployMockVotingWeight();
        dataset = await deployMockERC721();
        algorithm = await deployMockERC721();

        const Manager = await ethers.getContractFactory("MetadataRequestManager");
        manager = await Manager.deploy();
        await manager.deployed();

        await manager.connect(owner).setVotingWeightOracle(votingWeight.address);

        // voter1 → manager role; voter2 → updateMetadata role
        await dataset.setPermission(voter1.address, true, false);
        await dataset.setPermission(voter2.address, false, true);

        // second arg is dataset address, not a uint
        await votingWeight.setWeight(voter1.address, dataset.address, 100);
        await votingWeight.setWeight(voter2.address, dataset.address, 50);
    });

    // ══════════════════════════════════════════════════════════════════════════
    // setVotingWeightOracle
    // ══════════════════════════════════════════════════════════════════════════
    describe("setVotingWeightOracle", () => {
        it("owner can set the oracle", async () => {
            const fresh = await deployMockVotingWeight();
            await expect(
                manager.connect(owner).setVotingWeightOracle(fresh.address)
            ).to.not.be.reverted;
        });

        it("reverts on zero address", async () => {
            await expect(
                manager.connect(owner).setVotingWeightOracle(ethers.constants.AddressZero)
            ).to.be.revertedWith("invalid address");
        });

        it("reverts when called by non-owner", async () => {
            await expect(
                manager.connect(stranger).setVotingWeightOracle(votingWeight.address)
            ).to.be.reverted;
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // setMaxExpireDuration
    // ══════════════════════════════════════════════════════════════════════════
    describe("setMaxExpireDuration", () => {
        it("owner can update MAX_EXPIRE_DURATION", async () => {
            await manager.connect(owner).setMaxExpireDuration(ONE_DAY);
            expect(await manager.MAX_EXPIRE_DURATION()).to.equal(ONE_DAY);
        });

        it("reverts when set to zero", async () => {
            await expect(
                manager.connect(owner).setMaxExpireDuration(0)
            ).to.be.revertedWith("must be greater than zero");
        });

        it("reverts when called by non-owner", async () => {
            await expect(
                manager.connect(stranger).setMaxExpireDuration(ONE_DAY)
            ).to.be.reverted;
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // createRequest
    // ══════════════════════════════════════════════════════════════════════════
    describe("createRequest", () => {
        it("creates a request and emits RequestCreated with correct args", async () => {
            const tx = await manager.connect(requester).createRequest(defaultParams());
            const receipt = await tx.wait();
            const evt = getEventFromTx(receipt, "RequestCreated");
            assert.ok(evt, "RequestCreated event not emitted");
            expect(evt.args.id).to.equal(1);
            expect(evt.args.datasetAddress).to.equal(dataset.address);
            expect(evt.args.algorithmAddress).to.equal(algorithm.address);
            expect(evt.args.requester).to.equal(requester.address);
        });

        it("increments id on successive calls", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).createRequest(defaultParams());
            const r = await manager.requests(2);
            expect(r.id).to.equal(2);
        });

        it("stores all request fields correctly", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            const r = await manager.requests(1);
            expect(r.requester).to.equal(requester.address);
            expect(r.datasetAddress).to.equal(dataset.address);
            expect(r.algorithmAddress).to.equal(algorithm.address);
            expect(r.reason).to.equal("Update dataset permissions");
            expect(r.status).to.equal(Status.Pending);
        });

        it("appends request id to requestsByDataset", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            expect(await manager.requestsByDataset(dataset.address, 0)).to.equal(1);
        });

        it("handles multiple request types in a single request", async () => {
            const params = defaultParams({
                requestTypes: [RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm],
                data: ["AllowNetworkAccess", "TrustedAlgorithm"],
            });
            const tx = await manager.connect(requester).createRequest(params);
            const receipt = await tx.wait();
            const evt = getEventFromTx(receipt, "RequestCreated");
            expect(evt.args.requestTypes.length).to.equal(2);
            expect(evt.args.data).to.deep.equal(["AllowNetworkAccess", "TrustedAlgorithm"]);
        });

        it("reverts with zero dataset address", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ datasetAddress: ethers.constants.AddressZero })
                )
            ).to.be.revertedWith("invalid dataset address");
        });

        it("reverts with zero algorithm address", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ algorithmAddress: ethers.constants.AddressZero })
                )
            ).to.be.revertedWith("invalid algorithm address");
        });

        it("reverts with empty requestTypes array", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ requestTypes: [], data: [] })
                )
            ).to.be.revertedWith("at least one request type is required");
        });

        it("reverts when requestTypes and data lengths differ", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ requestTypes: [RequestType.AllowNetworkAccess], data: ["a", "b"] })
                )
            ).to.be.revertedWith("request types and data must have the same length");
        });

        it("reverts when expiresIn is zero", async () => {
            await expect(
                manager.connect(requester).createRequest(defaultParams({ expiresIn: 0 }))
            ).to.be.revertedWith("Expiration must be greater than zero");
        });

        it("reverts when expiresIn exceeds MAX_EXPIRE_DURATION", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ expiresIn: THIRTY_DAYS + 1 })
                )
            ).to.be.revertedWith("Expiration exceeds maximum limit");
        });

        it("accepts expiresIn equal to MAX_EXPIRE_DURATION", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({ expiresIn: THIRTY_DAYS })
                )
            ).to.not.be.reverted;
        });

        it("reverts on duplicate request types", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({
                        requestTypes: [RequestType.AllowNetworkAccess, RequestType.AllowNetworkAccess],
                        data: ["a", "b"],
                    })
                )
            ).to.be.revertedWith("duplicate request type");
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // vote
    // ══════════════════════════════════════════════════════════════════════════
    describe("vote", () => {
        beforeEach(async () => {
            await manager.connect(requester).createRequest(defaultParams());
        });

        it("voter with manager role can vote and emits RequestVoted", async () => {
            const tx = await manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "lgtm");
            const receipt = await tx.wait();
            const evt = getEventFromTx(receipt, "RequestVoted");
            assert.ok(evt, "RequestVoted not emitted");
            expect(evt.args.voter).to.equal(voter1.address);
            expect(evt.args.weight).to.equal(100);
            expect(evt.args.inFavourBitmap).to.equal(bitmap(RequestType.AllowNetworkAccess));
        });

        it("voter with updateMetadata role can vote", async () => {
            await expect(
                manager.connect(voter2).vote(1, bitmap(RequestType.AllowNetworkAccess), "")
            ).to.not.be.reverted;
        });

        it("stores the vote with correct fields", async () => {
            await manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "my reason");
            const v = await manager.votes(1, voter1.address);
            expect(v.voter).to.equal(voter1.address);
            expect(v.weight).to.equal(100);
            expect(v.inFavourBitmap).to.equal(bitmap(RequestType.AllowNetworkAccess));
            expect(v.reason).to.equal("my reason");
        });

        it("reverts when caller has no manager or updateMetadata role", async () => {
            await expect(
                manager.connect(stranger).vote(1, bitmap(RequestType.AllowNetworkAccess), "")
            ).to.be.revertedWith("caller not manager");
        });

        it("reverts on double vote", async () => {
            await manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "");
            await expect(
                manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "")
            ).to.be.revertedWith("already voted");
        });

        it("reverts after expiry", async () => {
            await increaseTime(ONE_DAY + 1);
            await expect(
                manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "")
            ).to.be.revertedWith("This request has already expired");
        });

        it("correctly distributes yesWeight and noWeight across subrequests", async () => {
            await manager.connect(requester).createRequest(
                defaultParams({
                    requestTypes: [RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm],
                    data: ["n", "d"],
                })
            );
            // voter1 (100): YES on Name only
            await manager.connect(voter1).vote(2, bitmap(RequestType.AllowNetworkAccess), "");
            // voter2 (50): YES on both
            await manager.connect(voter2).vote(
                2,
                bitmap(RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm),
                ""
            );
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(2);
            const receipt = await tx.wait();
            const apEvt = getEventFromTx(receipt, "RequestApplied");
            // Name: 150 yes vs 0 no → approved; Description: 50 yes vs 100 no → rejected
            expect(apEvt.args.requestTypes.length).to.equal(1);
            expect(apEvt.args.requestTypes[0]).to.equal(RequestType.AllowNetworkAccess);
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // cancelRequest
    // ══════════════════════════════════════════════════════════════════════════
    describe("cancelRequest", () => {
        beforeEach(async () => {
            await manager.connect(requester).createRequest(defaultParams());
        });

        it("requester can cancel and emits RequestCancelled", async () => {
            const tx = await manager.connect(requester).cancelRequest(1);
            const receipt = await tx.wait();
            const evt = getEventFromTx(receipt, "RequestCancelled");
            assert.ok(evt, "RequestCancelled not emitted");
            expect(evt.args.id).to.equal(1);
        });

        it("sets status to Cancelled", async () => {
            await manager.connect(requester).cancelRequest(1);
            const r = await manager.requests(1);
            expect(r.status).to.equal(Status.Cancelled);
        });

        it("sets decidedAt to block.timestamp", async () => {
            const tx = await manager.connect(requester).cancelRequest(1);
            const block = await ethers.provider.getBlock(tx.blockNumber);
            const r = await manager.requests(1);
            expect(r.decidedAt).to.equal(block.timestamp);
        });

        it("reverts when called by non-requester", async () => {
            await expect(
                manager.connect(stranger).cancelRequest(1)
            ).to.be.revertedWith("caller not requester");
        });

        it("reverts when request is already cancelled", async () => {
            await manager.connect(requester).cancelRequest(1);
            await expect(
                manager.connect(requester).cancelRequest(1)
            ).to.be.revertedWith("request in invalid status");
        });

        it("reverts when request is already finalized", async () => {
            await increaseTime(ONE_DAY + 1);
            await manager.finalize(1);
            await expect(
                manager.connect(requester).cancelRequest(1)
            ).to.be.revertedWith("request in invalid status");
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // finalize
    // ══════════════════════════════════════════════════════════════════════════
    describe("finalize", () => {
        it("reverts if voting period has not finished", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await expect(manager.finalize(1)).to.be.revertedWith(
                "voting period not finished yet"
            );
        });

        it("reverts if request is not Pending", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).cancelRequest(1);
            await increaseTime(ONE_DAY + 1);
            await expect(manager.finalize(1)).to.be.revertedWith(
                "request in invalid status"
            );
        });

        it("is callable by anyone — no access control", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await increaseTime(ONE_DAY + 1);
            await expect(manager.connect(stranger).finalize(1)).to.not.be.reverted;
        });

        it("finalizes as Rejected when no votes were cast", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            expect(getEventFromTx(receipt, "RequestVotingFinished").args.status).to.equal(
                Status.Rejected
            );
        });

        it("finalizes as Rejected when noWeight >= yesWeight", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(voter1).vote(1, 0, ""); // bitmap=0 → NO on all
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            expect(getEventFromTx(receipt, "RequestVotingFinished").args.status).to.equal(
                Status.Rejected
            );
        });

        it("finalizes as Approved when all subrequests pass, emits RequestApplied", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(voter1).vote(1, bitmap(defaultParams().requestTypes.at(0)), "");
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            const vtEvt = getEventFromTx(receipt, "RequestVotingFinished");
            const apEvt = getEventFromTx(receipt, "RequestApplied");
            expect(vtEvt.args.status).to.equal(Status.Approved);
            assert.ok(apEvt, "RequestApplied not emitted on Approved");
            expect(apEvt.args.id).to.equal(1);
        });

        it("finalizes as Resolved when only some subrequests pass", async () => {
            await manager.connect(requester).createRequest(
                defaultParams({
                    requestTypes: [RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm],
                    data: ["n", "d"],
                })
            );
            await manager.connect(voter1).vote(1, bitmap(RequestType.AllowNetworkAccess), "");
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            const vtEvt = getEventFromTx(receipt, "RequestVotingFinished");
            const apEvt = getEventFromTx(receipt, "RequestApplied");
            expect(vtEvt.args.status).to.equal(Status.Resolved);
            assert.ok(apEvt, "RequestApplied not emitted on Resolved");
            expect(apEvt.args.requestTypes.length).to.equal(1);
            expect(apEvt.args.requestTypes[0]).to.equal(RequestType.AllowNetworkAccess);
            expect(apEvt.args.data[0]).to.equal("n");
        });

        it("does not emit RequestApplied when Rejected", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            assert.ok(
                !getEventFromTx(receipt, "RequestApplied"),
                "RequestApplied should not be emitted on Rejected"
            );
        });

        it("sets decidedAt to block.timestamp", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const block = await ethers.provider.getBlock(tx.blockNumber);
            const r = await manager.requests(1);
            expect(r.decidedAt).to.equal(block.timestamp);
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // Edge cases
    // ══════════════════════════════════════════════════════════════════════════
    describe("edge cases", () => {
        it("hasNotVoted check: voter can not vote twice", async () => {
            // hasNotVoted checks `votes[requestId][msg.sender].weight == 0`.
            // If getWeight returns 0, the stored vote.weight stays 0 after voting,
            // so the guard passes again on a second call.
            await dataset.setPermission(stranger.address, true, false);
            // stranger has no weight set → getWeight returns 0
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(stranger).vote(1, bitmap(RequestType.TrustedAlgorithm), "first");
            await expect(
                manager.connect(stranger).vote(1, bitmap(RequestType.TrustedAlgorithm), "second")
            ).to.be.reverted;
        });

        it("all three RequestTypes can coexist without triggering duplicate revert", async () => {
            await expect(
                manager.connect(requester).createRequest(
                    defaultParams({
                        requestTypes: [RequestType.TrustedAlgorithm, RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithmPublisher],
                        data: ["n", "d", "a"],
                    })
                )
            ).to.not.be.reverted;
        });

        it("requestsByDataset tracks all requests for the same dataset", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).createRequest(defaultParams());
            expect(await manager.requestsByDataset(dataset.address, 0)).to.equal(1);
            expect(await manager.requestsByDataset(dataset.address, 1)).to.equal(2);
            expect(await manager.requestsByDataset(dataset.address, 2)).to.equal(3);
        });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // Integration: full lifecycle scenarios
    // ══════════════════════════════════════════════════════════════════════════
    describe("integration: full lifecycle", () => {
        it("create → split vote → finalize → Resolved with partial approval", async () => {
            const types = [RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm, RequestType.TrustedAlgorithmPublisher];
            await manager.connect(requester).createRequest(
                defaultParams({ requestTypes: types, data: ["n", "d", "a"] })
            );
            // voter1 (100): YES on Name + Description, NO on Author
            await manager.connect(voter1).vote(
                1,
                bitmap(RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm),
                "partial approve"
            );
            // voter2 (50): YES on all
            await manager.connect(voter2).vote(
                1,
                bitmap(RequestType.AllowNetworkAccess, RequestType.TrustedAlgorithm, RequestType.TrustedAlgorithmPublisher),
                "full approve"
            );
            // Author: 50 yes vs 100 no → rejected
            // Name + Description: 150 yes vs 0 no → approved
            await increaseTime(ONE_DAY + 1);
            const tx = await manager.finalize(1);
            const receipt = await tx.wait();
            expect(getEventFromTx(receipt, "RequestVotingFinished").args.status).to.equal(
                Status.Resolved
            );
            expect(getEventFromTx(receipt, "RequestApplied").args.requestTypes.length).to.equal(2);
        });

        it("create → cancel → finalize reverts", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).cancelRequest(1);
            await increaseTime(ONE_DAY + 1);
            await expect(manager.finalize(1)).to.be.revertedWith("request in invalid status");
        });

        it("finalize twice reverts on second call", async () => {
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(voter1).vote(1, bitmap(RequestType.TrustedAlgorithm), "");
            await increaseTime(ONE_DAY + 1);
            await manager.finalize(1);
            await expect(manager.finalize(1)).to.be.revertedWith("request in invalid status");
        });

        it("requests across different datasets are tracked independently", async () => {
            const dataset2 = await deployMockERC721();
            await manager.connect(requester).createRequest(defaultParams());
            await manager.connect(requester).createRequest(
                defaultParams({ datasetAddress: dataset2.address })
            );
            expect(await manager.requestsByDataset(dataset.address, 0)).to.equal(1);
            expect(await manager.requestsByDataset(dataset2.address, 0)).to.equal(2);
        });
    });
});