// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../interfaces/IVotingWeight.sol";

contract VotingWeight is IVotingWeight {
    function getWeight(
        address voter,
        address erc721
    ) external view override returns (uint256 weight) {
        return 1;
    }
}