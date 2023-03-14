// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import { Test } from "@forge-std/Test.sol";
import "forge-std/Test.sol"; // to get console.log

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";
import { Vault } from "../src/src-default/Vault.sol";
import { IVault } from "../src/src-default/interfaces/IVault.sol";
import { Token } from "../src/src-default/Token.sol";
import { WETH9 } from "./WETH9.sol";

contract VaultTest is Test {
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 100 ether;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 100 ether;
    uint256 public constant ALICE_INITIAL_LP_BALANCE = 1000;
    uint256 public constant BOB_INITIAL_LP_BALANCE = 2000;

    uint256 public time = 1000;

    address public deployer = vm.addr(1000);
    address public alice = vm.addr(1500);
    address public bob = vm.addr(1501);

    IERC20 private LPtoken;
    Token private rewardToken;
    Vault private vault;

    function setUp() external {
        setUpUniswap();

        vault = new Vault();
        vault.initialize(address(LPtoken));
        rewardToken = vault.rewardToken();
    }

    function testVault_AlreadyInitialized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.AlreadyInitializedError.selector);
        vault.initialize(address(0));
        vm.stopPrank();
    }

    function testVault_Unauthorized() external {
        vm.startPrank(alice);
        vm.expectRevert(IVault.Unauthorized.selector);
        vault.upgrade(address(0));
        vm.stopPrank();
    }

    function testVault_NoDeposit() external {
        // Alice tries to claim rewards and withdraw deposit without depositing
        vm.startPrank(alice);
        uint256[] memory depositIds = vault.getDepositIds(alice);
        vm.expectRevert(IVault.NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();
    }

    function testVault_InsuficientDepositAmount() external {
        vm.startPrank(alice);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vm.expectRevert(IVault.InsuficientDepositAmountError.selector);
        vault.deposit(1, 6, 100);
        vm.stopPrank();
    }

    function testVault_InvalidLockPeriod() external {
        // Alice tries to make a deposit locked for 10 months
        vm.startPrank(alice);
        uint256 monthsLocked = 10;
        uint256 hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vm.expectRevert(IVault.InvalidLockPeriodError.selector);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        vm.stopPrank();
    }

    function testVault_Scenario1() external {
        uint256 monthsLocked;
        uint256 hint;
        uint256[] memory depositIds;

        vm.warp(time);

        // Alice deposits all her LPtokens for 6 months
        vm.startPrank(alice);
        monthsLocked = 6;
        hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), ALICE_INITIAL_LP_BALANCE);
        vault.deposit(ALICE_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(alice) == 0, "Failed to assert alice balance after deposit");
        vm.stopPrank();

        // Fast-forward 3 months
        vm.warp(time += 3 * SECONDS_IN_30_DAYS);

        // Bob tries to claim rewards and withdraw deposit
        vm.startPrank(bob);
        depositIds = vault.getDepositIds(bob);
        vm.expectRevert(IVault.NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Bob deposits all his LPtokens for 1 year using invalid hint
        vm.startPrank(bob);
        monthsLocked = 12;
        LPtoken.approve(address(vault), BOB_INITIAL_LP_BALANCE);
        vault.deposit(BOB_INITIAL_LP_BALANCE, monthsLocked, 100);
        require(LPtoken.balanceOf(bob) == 0, "Failed to assert bob balance after deposit");
        vm.stopPrank();

        // Alice claims her rewards and tries to withdraw before lock period
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        console.log("Month 3. Alice rewards:", rewardToken.balanceOf(alice), "->", 317 * SECONDS_IN_30_DAYS * 3);
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Fast-forward 5 months
        vm.warp(time += 5 * SECONDS_IN_30_DAYS);

        // Alice withdraws her deposit and claims her rewards
        vm.startPrank(alice);
        vault.withdraw();
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        console.log(
            "Month 8. Alice rewards:",
            rewardToken.balanceOf(alice),
            "->",
            317 * SECONDS_IN_30_DAYS * 3 + 317 * SECONDS_IN_30_DAYS * 3 / 5
        );
        vm.stopPrank();

        // Bob claims rewards and tries to withdraw deposit
        vm.startPrank(bob);
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        console.log(
            "Month 8. Bob rewards:",
            rewardToken.balanceOf(bob),
            "->",
            317 * SECONDS_IN_30_DAYS * 3 * 4 / 5 + 317 * SECONDS_IN_30_DAYS * 2
        );
        vm.expectRevert(IVault.NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Alice tries to claim bob's rewards
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(bob);
        vm.expectRevert(IVault.InvalidHintError.selector);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Bob withdraws deposit and claims rewards
        vm.startPrank(bob);
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
        vm.stopPrank();

        // Print reward token balances
        console.log(
            "Month 20. Alice rewards:",
            rewardToken.balanceOf(alice),
            "->",
            317 * SECONDS_IN_30_DAYS * 3 + 317 * SECONDS_IN_30_DAYS * 3 / 5
        );
        console.log(
            "Month 20. Bob rewards:",
            rewardToken.balanceOf(bob),
            "->",
            317 * SECONDS_IN_30_DAYS * 3 * 4 / 5 + 317 * SECONDS_IN_30_DAYS * 9
        );
        console.log(
            "Total rewards:",
            rewardToken.balanceOf(alice) + rewardToken.balanceOf(bob),
            "->",
            317 * SECONDS_IN_30_DAYS * 15
        );

        // Check if withdrawls were successful
        uint256 balance = LPtoken.balanceOf(alice);
        require(balance == ALICE_INITIAL_LP_BALANCE, "Failed to assert alice's balance");

        balance = LPtoken.balanceOf(bob);
        require(balance == BOB_INITIAL_LP_BALANCE, "Failed to assert bob's balance");
    }

    function setUpUniswap() internal {
        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        // Fund  wallets
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE);
        vm.deal(alice, ALICE_INITIAL_LP_BALANCE);

        vm.startPrank(deployer);

        //  Setup Token contracts.
        Token tokenA = new Token(deployer);
        WETH9 weth = new WETH9();

        // Setup Uniswap V2 contracts
        address factory = deployCode("UniswapV2Factory.sol", abi.encode(address(0)));
        address router = deployCode("UniswapV2Router02.sol", abi.encode(address(factory), address(weth)));
        vm.label(factory, "Factory");
        vm.label(router, "Router");

        // Create pair WETH <-> Token and add liquidity
        tokenA.mintRewards(deployer, UNISWAP_INITIAL_TOKEN_RESERVE);
        tokenA.approve(router, UNISWAP_INITIAL_TOKEN_RESERVE);
        (bool success,) = router.call{ value: UNISWAP_INITIAL_WETH_RESERVE }(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                address(tokenA),
                UNISWAP_INITIAL_TOKEN_RESERVE,
                0,
                0,
                deployer,
                block.timestamp * 2
            )
        );
        require(success);

        // Get the pair to interact with
        (, bytes memory data) =
            factory.call(abi.encodeWithSignature("getPair(address,address)", address(tokenA), address(weth)));
        LPtoken = IERC20(abi.decode(data, (address)));
        vm.label(address(LPtoken), "LPtoken");

        LPtoken.transfer(bob, BOB_INITIAL_LP_BALANCE);

        tokenA.mintRewards(alice, ALICE_INITIAL_LP_BALANCE);
        vm.stopPrank();

        vm.startPrank(alice);
        tokenA.approve(router, ALICE_INITIAL_LP_BALANCE);
        (success,) = router.call{ value: ALICE_INITIAL_LP_BALANCE }(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                address(tokenA),
                ALICE_INITIAL_LP_BALANCE,
                0,
                0,
                alice,
                block.timestamp * 2
            )
        );
        require(success);
        vm.stopPrank();

        //sanity checks
        uint256 balance = LPtoken.balanceOf(alice);
        require(balance == ALICE_INITIAL_LP_BALANCE, "Failed to assert alice initial balance");
        //console.log("alice balance:", balance);

        balance = LPtoken.balanceOf(bob);
        require(balance == BOB_INITIAL_LP_BALANCE, "Failed to assert bob initial balance");
        //console.log("bob balance:", balance);
    }
}
