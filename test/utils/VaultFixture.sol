// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol"; // to get console.log

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { Token } from "./Token.sol";
import { WETH9 } from "./WETH9.sol";

contract VaultFixture is Test {
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint128 constant REWARDS_PER_SECOND = 317;
    uint128 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;
    uint256 constant STARTING_TIME = 1000;

    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 100_000_000 ether;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 100_000_000 ether;

    address public deployer = vm.addr(1000);
    address public alice = vm.addr(1500);
    address public bob = vm.addr(1501);
    address public router;
    address public factory;
    uint256 public time = STARTING_TIME;

    IERC20 public LPtoken;

    function setUp() public virtual {
        setUpUniswap();

        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        //sanity checks
        require(similar(100, 110) == false, "similar failed 1");
        require(similar(110, 100) == false, "similar failed 2");
        require(similar(100, 101) == true, "similar failed 3");
        require(similar(101, 100) == true, "similar failed 4");
        require(similar(100, 100) == true, "similar failed 4");
    }

    function similar(uint256 a, uint256 b) public pure returns (bool result) {
        if (a == 0 || b == 0) revert("Can't compare to 0");
        uint256 dif;
        uint256 smallest;
        dif = (a > b) ? a - b : b - a;
        smallest = (a > b) ? b : a;
        dif *= 100;
        if (dif / smallest < 3) result = true;
        else result = false;
    }

    function giveLPtokens(address receiver_, uint256 amount_) public {
        vm.startPrank(deployer);
        LPtoken.transfer(receiver_, amount_);

        //sanity check
        if (receiver_ != deployer) {
            uint256 balance = LPtoken.balanceOf(receiver_);
            require(balance == amount_, "Failed to give LP tokens");
        }

        vm.stopPrank();
    }

    function deposit(address vaultAddr_, address depositor_, uint128 deposit_, uint64 monthsLocked_) public {
        vm.startPrank(depositor_);
        uint256 startingBalance = LPtoken.balanceOf(depositor_);
        uint64 hint_ =
            IVault(vaultAddr_).getInsertPosition(uint64(block.timestamp) + monthsLocked_ * SECONDS_IN_30_DAYS);
        LPtoken.approve(vaultAddr_, deposit_);
        IVault(vaultAddr_).deposit(deposit_, monthsLocked_, hint_);
        require(
            LPtoken.balanceOf(depositor_) == startingBalance - deposit_, "Failed to assert alice balance after deposit"
        );
        vm.stopPrank();
    }

    function setUpUniswap() internal {
        // Fund  wallet
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE);
        vm.startPrank(deployer);

        //  Setup Token contracts.
        Token tokenA = new Token(deployer);
        WETH9 weth = new WETH9();

        // Setup Uniswap V2 contracts
        factory = deployCode("UniswapV2Factory.sol", abi.encode(address(0)));
        router = deployCode("UniswapV2Router02.sol", abi.encode(address(factory), address(weth)));
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

        vm.stopPrank();
    }
}
