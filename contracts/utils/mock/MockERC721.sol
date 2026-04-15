// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

contract MockERC721 {
  struct Roles {
      bool manager;
      bool deployERC20;
      bool updateMetadata;
      bool store;
    }

  mapping(address => Roles) public permissions;
  
  function setPermission(
    address user,
    bool manager,
    bool updateMetadata
  ) external {
    permissions[user] = Roles(manager, false, updateMetadata, false);
  }
  
  function getPermissions(address user) external view returns (Roles memory) {
    return permissions[user];
  }
}
