// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { VaultStorage } from "./VaultStorage.sol";
import { ILayerZeroEndpoint } from "@layerZero/interfaces/ILayerZeroEndpoint.sol";

contract VaultV2Storage is VaultStorage {
    mapping(uint16 => bytes) internal _trustedRemoteLookup;
    mapping(uint16 => uint16) internal _chainIdList;

    ILayerZeroEndpoint internal _lzEndpoint;
}
