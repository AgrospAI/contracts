// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "../interfaces/IVotingWeight.sol";
import "../interfaces/IMetadataRequestManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MetadataRequestManager
 * @notice Tracks metadata change requests that can contain multiple types per request.
 *         Off-chain updates are referenced via IPFS or JSON hashes.
 */
contract MetadataRequestManager is IMetadataRequestManager, Ownable {
    uint256 private _counter;
    uint256 private constant EXPIRE_PERIOD = 1 weeks;
    mapping(uint256 => Request) public requests;
    mapping(address => uint256[]) public requestsByDid;
    mapping(address => uint256[]) public requestsByOwner;

    mapping(uint256 => mapping(address => bool)) public hasVoted;
    IVotingWeight public votingWeightOracle;

    function setVotingWeightOracle(
        address _votingWeightOracle
    ) external onlyOwner {
        require(_votingWeightOracle != address(0), "invalid address");
        votingWeightOracle = IVotingWeight(_votingWeightOracle);
    }

    function createRequest(
        address erc721,
        address did,
        RequestType[] calldata requestTypes,
        string[] calldata data
    ) external returns (uint256) {
        require(requestTypes.length == data.length, "mismatched arrays");
        uint256 id = ++_counter;
        uint256 expiresAt = block.timestamp + EXPIRE_PERIOD;

        Request storage r = requests[id];
        r.id = id;
        r.erc721 = erc721;
        r.did = did;
        r.requester = msg.sender;
        r.status = Status.Pending;
        r.createdAt = block.timestamp;
        r.expiresAt = expiresAt;

        for (uint256 i = 0; i < requestTypes.length; i++) {
            r.subRequests.push(
                SubRequest({
                    requestType: requestTypes[i],
                    data: data[i],
                    yesWeight: 0,
                    noWeight: 0
                })
            );
        }

        requestsByDid[did].push(id);
        requestsByOwner[Ownable(erc721).owner()].push(id);

        emit RequestCreated(
            id,
            erc721,
            did,
            msg.sender,
            requestTypes,
            data,
            expiresAt
        );
        return id;
    }

    function vote(
        uint256 requestId,
        bool[] calldata inFavour
    )
        external
        hasNotVoted(requestId)
        isNotExpired(requestId)
        isOwner(requestId)
    {
        Request storage req = getPendingRequest(requestId);

        require(
            inFavour.length == req.subRequests.length,
            "invalid votes length"
        );

        hasVoted[requestId][msg.sender] = true;

        uint256 weight = votingWeightOracle.getWeight(msg.sender, req.erc721);

        for (uint256 i = 0; i < req.subRequests.length; i++) {
            SubRequest storage sr = req.subRequests[i];
            if (inFavour[i]) {
                sr.yesWeight += weight;
            } else {
                sr.noWeight += weight;
            }
        }

        emit RequestVoted(requestId, msg.sender, inFavour, weight);
    }

    function cancelRequest(uint256 requestId) external isRequester(requestId) {
        Request storage r = getPendingRequest(requestId);

        r.status = Status.Cancelled;
        r.decidedAt = block.timestamp;

        emit RequestCancelled(requestId);
    }

    function finalize(uint256 requestId) external {
        Request storage r = getExpiredPendingRequest(requestId);

        bool isAllApproved = true;
        bool isAnyApproved = false;

        for (uint256 i = 0; i < r.subRequests.length; i++) {
            SubRequest storage sr = r.subRequests[i];
            if (sr.yesWeight <= sr.noWeight) {
                isAllApproved = false;
            } else {
                isAnyApproved = true;
            }
        }

        r.decidedAt = block.timestamp;

        if (!isAnyApproved) {
            r.status = Status.Rejected;
            emit RequestVotingFinished(requestId, r.status);
            return;
        }

        r.status = isAllApproved ? Status.Approved : Status.Resolved;
        emit RequestVotingFinished(requestId, r.status);

        // Build approved subrequests arrays
        uint256 approvedCount = 0;
        for (uint256 i = 0; i < r.subRequests.length; i++) {
            if (r.subRequests[i].yesWeight > r.subRequests[i].noWeight) {
                approvedCount++;
            }
        }

        RequestType[] memory approvedTypes = new RequestType[](approvedCount);
        string[] memory approvedData = new string[](approvedCount);
        uint256 j = 0;
        for (uint256 i = 0; i < r.subRequests.length; i++) {
            if (r.subRequests[i].yesWeight > r.subRequests[i].noWeight) {
                approvedTypes[j] = r.subRequests[i].requestType;
                approvedData[j] = r.subRequests[i].data;
                j++;
            }
        }

        emit RequestApplied(requestId, approvedTypes, approvedData);
    }

    // UTILITIES
    modifier isExpired(uint256 requestId) {
        Request memory request = requests[requestId];
        require(
            block.timestamp >= request.expiresAt,
            "voting period not finished yet"
        );
        _;
    }

    modifier isNotExpired(uint256 requestId) {
        Request memory request = requests[requestId];
        require(
            request.expiresAt >= block.timestamp,
            "This request has already expired"
        );
        _;
    }

    modifier hasNotVoted(uint256 requestId) {
        Request memory request = requests[requestId];
        require(!hasVoted[requestId][msg.sender], "already voted");
        _;
    }

    modifier isNotInState(uint256 requestId, Status status) {
        Request memory request = requests[requestId];
        require(request.status != status, "request in invalid status");
        _;
    }

    modifier isOwner(uint256 requestId) {
        Request memory request = requests[requestId];
        require(
            Ownable(request.erc721).owner() == msg.sender,
            "caller not owner"
        );
        _;
    }

    modifier isRequester(uint256 requestId) {
        Request memory request = requests[requestId];
        require(request.requester == msg.sender, "caller not requester");
        _;
    }

    function getExpiredPendingRequest(
        uint256 requestId
    )
        internal
        view
        isNotInState(requestId, Status.Pending)
        isExpired(requestId)
        returns (Request storage)
    {
        return requests[requestId];
    }

    function getPendingRequest(
        uint256 requestId
    )
        internal
        view
        isNotInState(requestId, Status.Pending)
        returns (Request storage)
    {
        return requests[requestId];
    }
}
