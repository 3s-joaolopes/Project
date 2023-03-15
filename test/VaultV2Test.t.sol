// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol"; // to get console.log

import { VaultFixture } from "./utils/VaultFixture.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

import { OFT } from "src/src-default/OFT.sol";

contract VaultV2Test is Test, VaultFixture { }
