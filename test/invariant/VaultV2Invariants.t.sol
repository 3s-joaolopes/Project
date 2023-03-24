// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Lib } from "test/utils/Library.sol";
import { VaultV2Handler } from "./VaultV2Handler.sol";
import { console2 } from "@forge-std/console2.sol";

contract VaultV2Invariants is Test {
    VaultV2Handler handler;

    function setUp() public {
        handler = new VaultV2Handler();

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = VaultV2Handler.deposit.selector;
        selectors[1] = VaultV2Handler.withdraw.selector;
        selectors[2] = VaultV2Handler.claimRewards.selector;
        selectors[3] = VaultV2Handler.skipTime.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
        excludeArtifact("VaultV2");
        excludeArtifact("OFToken");
        excludeArtifact("LZEndpointMock");
    }

    // Assert that vaults have only been deployed once
    function invariant_onlyDeployedOnce_SkipCI() public view {
        assert(handler.numberOfDeployments() < 2);
    }

    // Assert that actors have been successfully deployed on all chains
    function invariant_successfullyDeployedActors_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        bool deployedActors_;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            if (handler.getNumberOfDepositorsOnChain(i_) > 0) deployedActors_ = true;
        }
        if (numberOfChains_ > 0) assert(deployedActors_);
    }

    // Assert that all the vaults (on all the chains) have the same number of shares
    function invariant_VaultsInSync_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        uint256 firstVaultshares_;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256 vaultShares_ = handler.getVaultSharesByIndex(i_);
            if (i_ == 0) firstVaultshares_ = vaultShares_;
            else assert(vaultShares_ == firstVaultshares_);
        }
    }

    // Assert that the shares on the first vault match the expected shares
    function invariant_correctShares_SkipCI() public view {
        if (handler.getNumberOfChains() > 0) {
            assert(handler.getVaultExpectedShares() == handler.getVaultSharesByIndex(0));
        }
    }

    // Assert that balance of the vaults + depositors is the initial asset amount
    function invariant_conservationOfAsset_SkipCI() public {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory depositorAsset_ = handler.getDepositorsAssetByChainIndex(i_);
            uint256 sumDepositorAsset_ = Lib.sumOfElements(depositorAsset_);
            uint256 initialAsset_ = handler.getInitialAssetByChainIndex(i_);
            uint256 vaultAsset_ = handler.getVaultAssetBalanceByIndex(i_);
            assert(vaultAsset_ + sumDepositorAsset_ == initialAsset_);
        }
    }

    // Assert that the balance of all vaults matches the amount of expected un-withdrawn asset
    function invariant_correctAsset_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            assert(handler.getVaultAssetBalanceByIndex(i_) == handler.getVaultExpectedUnwithdrawnAssetByIndex(i_));
        }
    }

    // Log results
    function invariant_LogSummary_SkipCI() public {
        console2.log("Logs-------------");
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            console2.log("Chain: ", i_ + 1, "/", handler.getNumberOfChains());
            console2.log("Vault asset", handler.getVaultAssetBalanceByIndex(i_));
            console2.log("Withdrawn asset", handler.getWithdrawnAssetByChainIndex(i_));
        }
        //vm.writeLine("test/invariant/out.txt", vm.toString(handler.getNumberOfChains()));
    }

    // Ask handler to log results
    function invariant_HandlerLogSummary_SkipCI() public {
        handler.handlerLog();
    }
}
