// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Lib } from "test/utils/Library.sol";
import { VaultV2Handler } from "./VaultV2Handler.sol";
import { console } from "@forge-std/console.sol";

contract VaultV2Invariants is Test {
    VaultV2Handler handler;

    function setUp() public {
        handler = new VaultV2Handler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = VaultV2Handler.deposit.selector;
        //selectors[1] = VaultV2Handler.withdraw.selector;
        //selectors[2] = VaultV2Handler.claimRewards.selector;
        //selectors[3] = VaultV2Handler.skipTime.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    // Assert that all the vaults (on all the chains) have the same number of shares
    function invariant_VaultsInSync() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        uint256 firstVaultshares_;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256 vaultShares_ = handler.getVaultSharesByChainIndex(i_);
            if (i_ == 0) firstVaultshares_ = vaultShares_;
            else assert(vaultShares_ == firstVaultshares_);
        }
    }

    // Assert that the shares on the first vault match the expected shares
    function invariant_correctShares() public view {
        assert(handler.getVaultExpectedShares() == handler.getVaultSharesByChainIndex(0));
    }

    // Assert that the balance of all vaults matches the amount of un-withdrawn asset
    function invariant_correctAsset() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            assert(handler.getVaultAssetBalanceByChainIndex(i_) == handler.getVaultUnwithdrawnAssetByChainIndex(i_));
        }
    }

    // Assert that the asset balance of every vault matches the locked/un-withdrawn deposits
    function invariant_VaultRewards() public {
        console.log("Number of chains: ", handler.getNumberOfChains());
        //vm.writeLine("test/invariant/out.txt", vm.toString(handler.getNumberOfChains()));
    }
}
