// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "@forge-std/Script.sol";

import { Greeter } from "src/Greeter.sol";

/// @dev See the "Solidity Scripting" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/tutorials/solidity-scripting?highlight=scripts#solidity-scripting
contract Deploy is Script {
    function setUp() public {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @dev You can send multiple transactions inside a single script.
    function run() public {
        vm.startBroadcast();

        // deploy contract
        new Greeter("GM");

        vm.stopBroadcast();
    }
}
