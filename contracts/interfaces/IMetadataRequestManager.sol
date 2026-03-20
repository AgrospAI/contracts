// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IMetadataRequestManager {

    enum Status {
        Pending,
        Cancelled,
        Approved, // All sub-requests accepted -> Fully applied
        Resolved, // Some sub-request accepted -> Some applied
        Rejected  // All sub-requests rejected -> Fully rejected
    }

    enum RequestType {
        AllowNetworkAccess,
        TrustedAlgorithm,
        TrustedAlgorithmPublisher
    }

    struct SubRequest {
        uint256 id;
        RequestType requestType;
        string data; // Arbitrary data
        uint256 yesWeight;
        uint256 noWeight;
    }

    struct MetadataRequestVote {
        uint256 id;
        address voter;
        uint256 inFavourBitmap;
        string reason;
        uint256 weight;
    }

    struct Request {
        uint256 id;
        address datasetAddress;
        address algorithmAddress;
        address requester;
        SubRequest[] subRequests; // One per request type
        string reason;
        Status status;
        uint256 createdAt;
        uint256 decidedAt;
        uint256 expiresAt;
    }

    event RequestCreated(
        uint256 indexed id,
        address indexed datasetAddress,
        address algorithmAddress,
        address indexed requester,
        RequestType[] requestTypes,
        string[] data,
        string reason,
        uint256 expiresAt
    );
    event RequestVoted(
        uint256 indexed id,
        address indexed voter,
        uint256 inFavourBitmap,
        uint256 weight,
        string data
    );
    event RequestCancelled(uint256 indexed id);
    event RequestVotingFinished(uint256 indexed id, Status status);
    event RequestApplied(uint256 indexed id, RequestType[] requestTypes, string[] data);

    struct RequestCreationParams {
        address datasetAddress;
        address algorithmAddress;
        string reason;
        RequestType[] requestTypes;
        string[] data;
        uint256 expiresIn;
    }

    /**
     * @notice Create a new request for metadata change.
     * 
     * @param params Request creation parameters
     */
    function createRequest(RequestCreationParams calldata params) external returns (uint256);
    
    /**
     * @notice Vote for a change request done in one of the assets owned 
     * 
     * @param requestId Request to addresss
     * @param inFavourBitmap Votes in favour of subrequests
     * @param data Extra data such as the response reason
     */
    function vote(uint256 requestId, uint256 inFavourBitmap, string calldata data) external;
    
    /**
     * @notice Cancel an outgoing request
     * 
     * @param requestId request id to cancel
     */
    function cancelRequest(uint256 requestId) external;
    
    /** 
     * @notice Mark an expired pending request as Approved/Resolved/Rejected depending on votes.
     * 
     * @param requestId request id to finalize
    */
    function finalize(uint256 requestId) external;
    
    /**
     * Set the used voting weight mechanism
     * 
     * @param _votingWeightOracle new voting weight contract
     */
    function setVotingWeightOracle(address _votingWeightOracle) external;
}
