// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IVotingWeight {

    /**
     * @notice Returns the voting weight for a given voter on a given erc721 asset
     * @param voter The address of the voter
     * @param erc721 The address of the ERC721 asset
     * @return weight The voting weight
     */
    function getWeight(address voter, address erc721) external view returns (uint256 weight);

}