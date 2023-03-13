// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import { Test } from "@forge-std/Test.sol";
import "forge-std/Test.sol"; // to get console.log

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";
import { Vault } from "../src/src-default/Vault.sol";
import { IVault } from "../src/src-default/interfaces/IVault.sol";
import { Token } from "../src/src-default/Token.sol";
import { WETH9 } from "../src/src-default/WETH9.sol";
//import { UniswapV2Factory } from "../lib/v2-core/contracts/UniswapV2Factory.sol";
//import { UniswapV2Router01 } from "../lib/v2-periphery/contracts/UniswapV2Router01.sol";

contract VaultTest is Test {
    error Unauthorized();
    error AlreadyInitializedError();
    error NoAssetToWithdrawError();
    error NoRewardsToClaimError();
    error InvalidHintError();
    error InvalidLockPeriodError();

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

    function testVault() external {
        uint256 monthsLocked;
        uint256 hint;
        uint256[] memory depositIds;

        vm.warp(time);

        // Alice tries to claim rewards and withdraw deposit
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(alice);
        vm.expectRevert(NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

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
        vm.expectRevert(NoRewardsToClaimError.selector);
        vault.claimRewards(depositIds);
        vm.expectRevert(NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Bob deposits all his LPtokens for 1 year
        vm.startPrank(bob);
        monthsLocked = 12;
        hint = vault.getInsertPosition(block.timestamp + monthsLocked * SECONDS_IN_30_DAYS);
        LPtoken.approve(address(vault), BOB_INITIAL_LP_BALANCE);
        vault.deposit(BOB_INITIAL_LP_BALANCE, monthsLocked, hint);
        require(LPtoken.balanceOf(bob) == 0, "Failed to assert bob balance after deposit");
        vm.stopPrank();

        // Alice claims her rewards and tries to withdraw before lock period
        vm.startPrank(alice);
        depositIds = vault.getDepositIds(alice);
        vault.claimRewards(depositIds);
        console.log("Month 3. Alice rewards:", rewardToken.balanceOf(alice), "->", 317 * SECONDS_IN_30_DAYS * 3);
        vm.expectRevert(NoAssetToWithdrawError.selector);
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
        vm.expectRevert(NoAssetToWithdrawError.selector);
        vault.withdraw();
        vm.stopPrank();

        // Fast-forward 12 months
        vm.warp(time += 12 * SECONDS_IN_30_DAYS);

        // Bob withdraws deposit and claims rewards
        vm.startPrank(bob);
        vault.withdraw();
        depositIds = vault.getDepositIds(bob);
        vault.claimRewards(depositIds);
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
        vm.stopPrank();

        // Check if withdraws were successful
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
        //vm.deal(bob, BOB_INITIAL_LP_BALANCE);

        vm.startPrank(deployer);

        //  Setup Token contracts.
        Token tokenA = new Token(deployer);
        WETH9 weth = new WETH9();

        // Setup Uniswap V2 contracts
        address factory = deployCode("UniswapV2Factory.sol", abi.encode(address(0)));
        address router = deployCode("UniswapV2Router02.sol", abi.encode(address(factory), address(weth)));
        vm.label(factory, "Factory");
        vm.label(router, "Router");

        //console.log(router);
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

/*    function uniswap() internal{

        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE);
        vm.startPrank(deployer);

        tokenA = new Token();
        weth = new WETH9();
        tokenA.mintRewards(deployer, UNISWAP_INITIAL_TOKEN_RESERVE);

        // Setup Uniswap V2 contracts
        factory = new UniswapV2Factory(address(0));
        router = new UniswapV2Router01(address(factory), address(weth));

        //address exchange = factory.createPair(address(tokenA), address(tokenB));

        // Create pair WETH <-> Token and add liquidity
        tokenA.approve(router, UNISWAP_INITIAL_TOKEN_RESERVE);
        (bool success, ) = router.call{value: UNISWAP_INITIAL_WETH_RESERVE}(
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
        address exchange = factory.getPair(address(tokenA), address(weth));
        //(, bytes memory data) = factory.call(abi.encodeWithSignature("getPair(address,address)", address(token), address(weth)));
        //exchange = abi.decode(data, (address));

        // Sanity check
        (, data) = exchange.call(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 deployerBalance = abi.decode(data, (uint256));
        assertGt(deployerBalance, 0);

        vm.stopPrank();
    }*/
