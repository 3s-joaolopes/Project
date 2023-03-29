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
        selectors[1] = VaultV2Handler.skipTime.selector;
        selectors[2] = VaultV2Handler.withdraw.selector;
        selectors[3] = VaultV2Handler.claimRewards.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
        excludeArtifact("VaultV2");
        excludeArtifact("OFToken");
        excludeArtifact("LZEndpointMock");
        excludeArtifact("VaultV2Replica");
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Deployment Invariants -------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    // Assert that vaults have only been deployed once
    function invariant_onlyDeployedOnce_SkipCI() public view {
        assert(handler.numberOfDeployments() < 2);
    }

    // Assert that actors have been successfully deployed on all chains
    function invariant_successfullyDeployedActors_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        bool deployedActors_;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            if (handler.getNumberOfActorsOnChain(i_) > 0) deployedActors_ = true;
        }
        if (numberOfChains_ > 0) assert(deployedActors_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault-wise Invariants -------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    // Assert that all the vaults (on all the chains) have the same number of shares
    // This isn't always guaranteed to be true, since "withdraw()" and "claimRewards()"
    //      only maintain the deposit list in the source chain
    function conditional_invariant_VaultsInSync_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        uint256 firstVaultshares_;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256 vaultShares_ = handler.getVaultSharesByIndex(i_);
            if (i_ == 0) firstVaultshares_ = vaultShares_;
            else assert(vaultShares_ == firstVaultshares_);
        }
    }

    // This isn't always guaranteed to be true, for the same reasons as in the previous function
    // Assert that the number of shares in the first vault matches the expected shares
    function invariant_correctShares_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            assert(handler.getVaultExpectedSharesByIndex(i_) == handler.getVaultSharesByIndex(i_));
        }
    }

    // Assert that balance of the vaults + actors is the initial asset amount
    function invariant_conservationOfAsset_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory actorAsset_ = handler.getActorsAssetByChainIndex(i_);
            uint256 sumActorAsset_ = Lib.sumOfElements(actorAsset_);
            uint256 initialAsset_ = handler.getInitialAssetByChainIndex(i_);
            uint256 vaultAsset_ = handler.getVaultAssetBalanceByIndex(i_);
            assert(vaultAsset_ + sumActorAsset_ == initialAsset_);
        }
    }

    // Assert that the balance of each vault matches the amount of deposited asset minus withdrawls
    function invariant_correctAsset_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            assert(
                handler.getVaultAssetBalanceByIndex(i_)
                    == handler.getVaultExpectedDepositsByIndex(i_) - handler.getExpectedWithdrawnAssetByChainIndex(i_)
            );
        }
    }

    // Assert that the issuance limit on reward tokens hasn't been crossed
    function invariant_rewardLimit_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        uint256 totalRewards_ = 0;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory actorRewards_ = handler.getActorsRewardsByChainIndex(i_);
            totalRewards_ += Lib.sumOfElements(actorRewards_);
        }
        assert(totalRewards_ <= handler.getMaximumRewardsPossible());
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Actor-wise Invariants -------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    // Assert that the balance of each actor matches its initial asset minus unwithdrawn asset
    function invariant_correctAssetBalances_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory initialAsset_ = handler.getActorsInitialAssetByChainIndex(i_);
            uint256[] memory asset_ = handler.getActorsAssetByChainIndex(i_);
            uint256[] memory unwithdrawnAsset_ = handler.getExpectedActorsAssetByChainIndex(i_);
            assert(Lib.vectorEquals(initialAsset_, Lib.vectorSum(asset_, unwithdrawnAsset_)));
        }
    }

    // Assert that the rewards of each actor match their expected rewards
    function invariant_correctRewards_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory actorRewards_ = handler.getActorsRewardsByChainIndex(i_);
            uint256[] memory actorExpectedRewards_ = handler.getActorsExpectedRewardsByChainIndex(i_);
            assert(Lib.vectorSimilar(actorRewards_, actorExpectedRewards_, 10));
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Logs ------------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    // Log results to console
    function invariant_LogSummary_SkipCI() public view {
        uint256 numberOfChains_ = handler.getNumberOfChains();
        console2.log("Logs------------- chains:", numberOfChains_);
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory actorRewards_ = handler.getActorsRewardsByChainIndex(i_);
            console2.log("Chain: ", i_ + 1, "/", handler.getNumberOfChains());
            console2.log("Vault asset", handler.getVaultAssetBalanceByIndex(i_));
            console2.log("Withdrawn asset", handler.getExpectedWithdrawnAssetByChainIndex(i_));
            console2.log("Claimed rewards", Lib.sumOfElements(actorRewards_));
        }
    }

    // Write results to out.txt file
    function _invariant_WriteSummary_SkipCI() public {
        vm.writeLine("test/invariant/out.txt", "Logs--------");
        uint256 numberOfChains_ = handler.getNumberOfChains();
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256[] memory actorRewards_ = handler.getActorsRewardsByChainIndex(i_);
            vm.writeLine("test/invariant/out.txt", string(abi.encodePacked("Chain: ", vm.toString(i_))));
            vm.writeLine(
                "test/invariant/out.txt",
                string(abi.encodePacked("Asset: ", vm.toString(handler.getVaultAssetBalanceByIndex(i_))))
            );
            vm.writeLine(
                "test/invariant/out.txt",
                string(abi.encodePacked("Withdrawn: ", vm.toString(handler.getExpectedWithdrawnAssetByChainIndex(i_))))
            );
            vm.writeLine(
                "test/invariant/out.txt",
                string(abi.encodePacked("Claimed: ", vm.toString(Lib.sumOfElements(actorRewards_))))
            );
        }
    }
}
