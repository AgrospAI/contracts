// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MetadataRequestManager
 * @notice Tracks metadata change requests that can contain multiple types per request.
 *         Off-chain updates are referenced via IPFS or JSON hashes.
 */
contract MetadataRequestManager {
    enum Status {
        Pending,
        Approved,
        Resolved,
        Rejected,
        Applied,
        Cancelled
    }

    enum RequestType {
        AllowNetworkAccess,
        TrustedAlgorithm,
        TrustedAlgorithmPublisher
    }

    struct SubRequest {
        RequestType requestType;
        string data; // Arbitrary data
        uint256 yesWeight;
        uint256 noWeight;
    }

    struct Request {
        uint256 id;
        address erc721; // Which ERC721 this request belongs to
        address did; // token DID
        address requester;
        SubRequest[] subRequests; // One per request type
        Status status;
        uint256 createdAt;
        uint256 decidedAt;
        uint256 expiresAt;
    }

    uint256 private _counter;
    uint256 private constant EXPIRE_PERIOD = 1 weeks;
    mapping(uint256 => Request) public requests;
    mapping(address => uint256[]) public requestsByDid;
    mapping(address => uint256[]) public requestsByOwner;

    event RequestCreated(
        uint256 id,
        address indexed erc721,
        address did,
        address indexed requester,
        RequestType[] requestTypes,
        string[] data,
        uint256 expiresAt
    );
    event RequestVoted(
        uint256 indexed id,
        address indexed voter,
        bool approved,
        uint256 weight
    );
    event RequestVotingFinished(uint256 indexed id, Status status);
    event RequestApplied(uint256 indexed id);
    event RequestCancelled(uint256 indexed id);

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
        r.status= Status.Pending;
        r.createdAt= block.timestamp;
        r.expiresAt= expiresAt;

        for (uint256 i = 0; i < requestTypes.length; i++) {
            r.subRequests.push(SubRequest({
                requestType: requestTypes[i],
                data: data[i],
                yesWeight: 0,
                noWeight: 0
            }));
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
        uint256 subrequestIndex,
        bool inFavour,
        uint256 weight
    ) external {
        Request storage req = _getPendingRequest(requestId);
        _isOwner(req);
        _isNotExpired(req);

        SubRequest storage sr = req.subRequests[subrequestIndex];
        // TODO: Define voting weight logic
        if (inFavour) {
            sr.yesWeight += weight;
        } else {
            sr.noWeight += weight;
        }

        emit RequestVoted(requestId, msg.sender, inFavour, weight);
    }

    function cancelRequest(uint256 id) external {
        Request storage r = _getPendingRequest(id);
        _isRequester(r);

        r.status = Status.Cancelled;
        r.decidedAt = block.timestamp;

        emit RequestCancelled(id);
    }

    function finalize(uint256 requestId) external {
        Request storage r = _getActivePendingRequest(requestId);

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

        if (isAllApproved) {
            r.status = Status.Approved;
        } else {
            r.status = isAnyApproved ? Status.Resolved : Status.Rejected;
        }

        r.decidedAt = block.timestamp;

        emit RequestVotingFinished(requestId, r.status);
    }

    // TODO: On-chain metadata update
    // function execute(uint256 requestId) external {
    //     Request storage r = requests[requestId];
    //     require(r.status != Status.Rejected, "is a rejected request");
    //     require(r.status != Status.Pending, "request still pending");

        
    //     for (uint256 i = 0; i < r.subRequests.length; i++) {
    //         SubRequest storage sr = r.subRequests[i];
    //         if (sr.requestType == RequestType.AllowNetworkAccess) {

    //         } else if (sr.requestType == RequestType.TrustedAlgorithm) {

    //         } else if (sr.requestType == RequestType.TrustedAlgorithmPublisher) {
                
    //         }
    //     }

    //     r.status = Status.Applied;
    //     emit RequestApplied(requestId);
    // }

    // UTILITIES
    function _isNotExpired(Request storage req) internal view {
        require(
            req.expiresAt >= block.timestamp,
            "This request has already expired"
        );
    }

    function _getActivePendingRequest(uint256 id) internal view returns (Request storage r) {
        r = requests[id];
        require(r.requester != address(0), "request not found");
        require(r.status == Status.Pending, "not pending");
        require(block.timestamp <= r.expiresAt, "request expired");
    }

    function _getPendingRequest(
        uint256 id
    ) internal view returns (Request storage r) {
        r = requests[id];
        require(r.requester != address(0), "request not found");
        require(r.status == Status.Pending, "not pending");
    }

    function _isOwner(Request storage r) internal view {
        require(Ownable(r.erc721).owner() == msg.sender, "caller not owner");
    }

    function _isRequester(Request storage r) internal view {
        require(r.requester == msg.sender, "caller not requester");
    }
}
