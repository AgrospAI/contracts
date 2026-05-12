// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '../interfaces/IVotingWeight.sol';
import '../interfaces/IERC721Template.sol';
import '../interfaces/IMetadataRequestManager.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title MetadataRequestManager
 * @notice Tracks metadata change requests that can contain multiple types per request.
 *         Off-chain updates are referenced via IPFS or JSON hashes.
 */
contract MetadataRequestManager is IMetadataRequestManager, Ownable {
  uint256 private _counter;
  uint256 private _subRequestCounter;
  uint256 private _voteCounter;

  mapping(uint256 => Request) public requests;
  mapping(address => uint256[]) public requestsByDataset;

  uint256 public MAX_EXPIRE_DURATION = 30 days;

  mapping(uint256 => mapping(address => MetadataRequestVote)) public votes;
  IVotingWeight public votingWeightOracle;

  function setVotingWeightOracle(
    address _votingWeightOracle
  ) external onlyOwner {
    require(_votingWeightOracle != address(0), 'invalid address');
    votingWeightOracle = IVotingWeight(_votingWeightOracle);
  }

  function setMaxExpireDuration(uint256 _maxExpireDuration) external onlyOwner {
    require(_maxExpireDuration > 0, 'must be greater than zero');
    MAX_EXPIRE_DURATION = _maxExpireDuration;
  }

  function createRequest(
    RequestCreationParams calldata params
  )
    external
    override
    checkUniqueRequestTypes(params.requestTypes)
    returns (uint256)
  {
    require(params.datasetAddress != address(0), 'invalid dataset address');
    require(params.algorithmAddress != address(0), 'invalid algorithm address');
    require(params.requestTypes.length > 0, 'at least one request type is required');
    require(params.requestTypes.length == params.data.length, 'request types and data must have the same length');
    require(params.expiresIn <= MAX_EXPIRE_DURATION, "Expiration exceeds maximum limit");
    require(params.expiresIn > 0, "Expiration must be greater than zero");

    uint256 id = ++_counter;

    Request storage r = requests[id];
    r.id = id;
    r.datasetAddress = params.datasetAddress;
    r.algorithmAddress = params.algorithmAddress;
    r.reason = params.reason;

    r.requester = msg.sender;
    r.status = Status.Pending;
    r.createdAt = block.timestamp;
    r.expiresAt = block.timestamp + params.expiresIn;

    for (uint256 i = 0; i < params.requestTypes.length; i++) {
      r.subRequests.push(
        SubRequest({
          id: ++_subRequestCounter,
          requestType: params.requestTypes[i],
          data: params.data[i],
          yesWeight: 0,
          noWeight: 0
        })
      );
    }

    emit RequestCreated(
      r.id,
      r.datasetAddress,
      r.algorithmAddress,
      r.requester,
      params.requestTypes,
      params.data,
      params.reason,
      r.expiresAt
    );

    requestsByDataset[r.datasetAddress].push(r.id);
    return r.id;
  }

  function vote(
    uint256 requestId,
    uint256 inFavourBitmap,
    string calldata data
  )
    external
    override
    hasNotVoted(requestId)
    isNotExpired(requestId)
    isOwner(requestId)
  {
    Request storage req = getPendingRequest(requestId);

    uint256 weight = votingWeightOracle.getWeight(
      msg.sender,
      req.datasetAddress
    );

    _storeVote(requestId, inFavourBitmap, data, weight);
    _addWeight(req, inFavourBitmap, weight);

    emit RequestVoted(requestId, msg.sender, inFavourBitmap, weight, data);
  }

  function _storeVote(
    uint256 requestId,
    uint256 inFavourBitmap,
    string calldata data,
    uint256 weight
  ) internal {
    MetadataRequestVote storage requestVote = votes[requestId][msg.sender];
    requestVote.id = ++_voteCounter;
    requestVote.voter = msg.sender;
    requestVote.inFavourBitmap = inFavourBitmap;
    requestVote.reason = data;
    requestVote.weight = weight;
  }

  function _addWeight(
    Request storage request,
    uint256 inFavourBitmap,
    uint256 weight
  ) internal {
    for (uint256 i = 0; i < request.subRequests.length; i++) {
      SubRequest storage sr = request.subRequests[i];
      bool isYes = ((inFavourBitmap >> uint256(sr.requestType)) & 1) == 1;

      if (isYes) {
        sr.yesWeight += weight;
      } else {
        sr.noWeight += weight;
      }
    }
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
      request.expiresAt <= block.timestamp,
      'voting period not finished yet'
    );
    _;
  }

  modifier isNotExpired(uint256 requestId) {
    Request memory request = requests[requestId];
    require(
      request.expiresAt >= block.timestamp,
      'This request has already expired'
    );
    _;
  }

  modifier hasNotVoted(uint256 requestId) {
    Request memory request = requests[requestId];
    require(votes[requestId][msg.sender].weight == 0, 'already voted');
    _;
  }

  modifier isInState(uint256 requestId, Status status) {
    Request memory request = requests[requestId];
    require(request.status == status, 'request in invalid status');
    _;
  }

  modifier isOwner(uint256 requestId) {
    Request memory request = requests[requestId];
    IERC721Template.Roles memory roles = IERC721Template(request.datasetAddress)
      .getPermissions(msg.sender);
    require(roles.manager || roles.updateMetadata, 'caller not manager');
    _;
  }

  modifier isRequester(uint256 requestId) {
    Request memory request = requests[requestId];
    require(request.requester == msg.sender, 'caller not requester');
    _;
  }

  modifier sameLength(
    RequestType[] calldata requestTypes,
    string[] calldata data
  ) {
    require(requestTypes.length == data.length, 'mismatched arrays');
    _;
  }

  modifier checkUniqueRequestTypes(RequestType[] calldata requestTypes) {
    uint256 bitmap = 0;
    for (uint256 i = 0; i < requestTypes.length; i++) {
      uint256 bit = 1 << uint256(requestTypes[i]);
      require((bitmap & bit) == 0, 'duplicate request type');
      bitmap |= bit;
    }
    _;
  }

  function getExpiredPendingRequest(
    uint256 requestId
  )
    internal
    view
    isInState(requestId, Status.Pending)
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
    isInState(requestId, Status.Pending)
    returns (Request storage)
  {
    return requests[requestId];
  }
}
