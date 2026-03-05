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
        RequestType requestType;
        string data; // Arbitrary data
        uint256 yesWeight;
        uint256 noWeight;
    }

    struct Request {
        uint256 id;
        address erc721; // Which ERC721 this request belongs to
        string did; // token DID
        address requester;
        SubRequest[] subRequests; // One per request type
        Status status;
        uint256 createdAt;
        uint256 decidedAt;
        uint256 expiresAt;
    }

    event RequestCreated(
        uint256 id,
        address indexed erc721,
        string did,
        address indexed requester,
        RequestType[] requestTypes,
        string[] data,
        uint256 expiresAt
    );
    event RequestVoted(
        uint256 indexed id,
        address indexed voter,
        bool[] approved,
        uint256 weight  
    );
    event RequestCancelled(uint256 indexed id);
    event RequestVotingFinished(uint256 indexed id, Status status);
    event RequestApplied(uint256 indexed id, RequestType[] requestTypes, string[] data);

    /**
     * @notice Create a new request for change.
     * 
     * @param erc721 asset to change
     * @param did asset identifier
     * @param requestTypes type of request changes
     * @param data additional data for the change request
     */
    function createRequest(address erc721, string memory did, RequestType[] calldata requestTypes, string[] calldata data) external returns (uint256);
    
    /**
     * @notice Vote for a change request done in one of the assets owned 
     * 
     * @param requestId Request to addresss
     * @param inFavour Votes in favour of subrequests
     */
    function vote(uint256 requestId, bool[] calldata inFavour) external;
    
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
