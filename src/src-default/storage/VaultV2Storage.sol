// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { VaultStorage } from "./VaultStorage.sol";

contract VaultV2Storage is VaultStorage {
    mapping(uint16 => bytes) internal _trustedRemoteLookup; // The address of the vaults on other chains
    mapping(uint16 => uint16) internal _chainIdList; // The list of chain ids that hold vaults
}
