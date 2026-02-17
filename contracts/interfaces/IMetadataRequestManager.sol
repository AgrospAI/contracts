// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IMetadataRequestManager {
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

    function createRequest(
        address erc721,
        address did,
        RequestType[] calldata requestTypes,
        string[] calldata data
    ) external returns (uint256 id);

    function vote(
        uint256 requestId,
        uint256 subrequestIndex,
        bool inFavour,
        uint256 weight
    ) external;

    function cancelRequest(uint256 id) external;

    function finalize(uint256 requestId) external;
}
