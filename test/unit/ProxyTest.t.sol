// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { UUPSProxy } from "src/src-default/UUPSProxy.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { UniswapHelper } from "./../utils/UniswapHelper.sol";
import { Vault } from "src/src-default/Vault.sol";
import { VaultTest } from "./VaultTest.t.sol";
import { OFToken } from "src/src-default/OFToken.sol";
import { Lib } from "test/utils/Library.sol";

contract ProxyTest is Test, UniswapHelper {
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint128 constant REWARDS_PER_SECOND = 317;
    uint128 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;
    uint128 constant MIN_DEPOSIT = 1000;
    uint256 constant STARTING_TIME = 1000;

    uint256 public time = STARTING_TIME;
    uint256 public constant ALICE_INITIAL_LP_BALANCE = 1 ether;
    uint256 public constant BOB_INITIAL_LP_BALANCE = 2 ether;

    address public alice = vm.addr(1500);
    address public bob = vm.addr(1501);

    OFToken public rewardToken;
    Vault public vault;

    function setUp() public override {
        super.setUp();

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        giveLPtokens(alice, ALICE_INITIAL_LP_BALANCE);
        giveLPtokens(bob, BOB_INITIAL_LP_BALANCE);

        Vault vaultImplementation = new Vault();
        bytes memory initializeData =
            abi.encodeWithSignature("initialize(address,address)", address(LPtoken), address(0));
        vm.startPrank(deployer);
        vault = Vault(address(new UUPSProxy(address(vaultImplementation), initializeData)));
        vm.stopPrank();
        rewardToken = vault.rewardToken();
    }

    function testProxy_Unauthorized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.UnauthorizedError.selector);
        vault.upgradeTo(address(0));
        vm.stopPrank();
    }

    function testVault_AlreadyInitialized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(0), address(0));
        vm.stopPrank();
    }

    function testProxy_Upgrade() external {
        Vault vaultImplementationUpgrade = new Vault();
        vm.startPrank(deployer);
        vault.upgradeTo(address(vaultImplementationUpgrade));
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(LPtoken), address(0));
        vm.stopPrank();
    }

    function testProxy_Deposit() external {
        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        uint64 monthsLocked = 6;
        uint64 hint = vault.getInsertPosition(uint64(block.timestamp) + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(uint128(ALICE_INITIAL_LP_BALANCE), uint64(monthsLocked), uint64(hint));
        assert(LPtoken.balanceOf(alice) == 0);

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vault.withdraw();
        uint64[] memory depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        uint128 expectedValue = REWARDS_PER_MONTH * 6;
        assert(Lib.similar(rewardToken.balanceOf(alice), uint256(expectedValue)));
        vm.stopPrank();
    }
}
