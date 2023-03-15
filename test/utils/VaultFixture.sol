// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol"; // to get console.log

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { Token } from "src/src-default/Token.sol";
import { WETH9 } from "./WETH9.sol";

contract VaultFixture is Test {
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint256 constant REWARDS_PER_SECOND = 317;
    uint256 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;

    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 100 ether;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 100 ether;
    uint256 public constant ALICE_INITIAL_LP_BALANCE = 1000;
    uint256 public constant BOB_INITIAL_LP_BALANCE = 2000;

    IERC20 public LPtoken;
    Token public rewardToken;
    Vault public vault;

    address public deployer = vm.addr(1000);
    address public alice = vm.addr(1500);
    address public bob = vm.addr(1501);
    uint256 public time = 1000;

    function setUp() public virtual {
        setUpUniswap();

        //sanity checks
        require(similar(100, 110) == false, "similar failed 1");
        require(similar(110, 100) == false, "similar failed 2");
        require(similar(100, 101) == true, "similar failed 3");
        require(similar(100, 101) == true, "similar failed 4");
    }

    function similar(uint256 a, uint256 b) public pure returns (bool result) {
        if (a == 0 || b == 0) revert("Can't compare to 0");
        uint256 dif;
        uint256 smallest;
        dif = (a > b) ? a - b : b - a;
        smallest = (a > b) ? b : a;
        dif *= 100;
        if (dif / smallest < 2) result = true;
        else result = false;
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
