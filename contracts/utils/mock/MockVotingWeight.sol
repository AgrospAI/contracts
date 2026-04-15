// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '../../interfaces/IVotingWeight.sol';

contract MockVotingWeight is IVotingWeight {
  mapping(address => mapping(address => uint256)) public weights;

  function setWeight(
    address voter,
    address erc721,
    uint256 weight
  ) external override {
    weights[voter][erc721] = weight;
  }

  function getWeight(
    address voter,
    address erc721
  ) external view override returns (uint256) {
    uint256 w = weights[voter][erc721];
    return w != 0 ? w : 1;
  }
}
