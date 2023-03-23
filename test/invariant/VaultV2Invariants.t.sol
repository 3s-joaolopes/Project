// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Lib } from "test/utils/Library.sol";
import { VaultV2Handler } from "./VaultV2Handler.sol";

contract VaultV2Invariants is Test {

    VaultV2Handler handler;
    function setUp() public { 
        handler = new VaultV2Handler();

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = VaultV2Handler.deposit.selector;
        selectors[1] = VaultV2Handler.withdraw.selector;
        selectors[2] = VaultV2Handler.claimRewards.selector;
        selectors[3] = VaultV2Handler.skipTime.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));

        targetContract(address(handler));
    }

    function invariant_VaultV2() public { 
        assert(true);
    }
}
