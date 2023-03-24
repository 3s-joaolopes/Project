// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { Token } from "./Token.sol";
import { WETH9 } from "./WETH9.sol";
import { Lib } from "test/utils/Library.sol";

contract VaultFixture is Test {
    uint64 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint128 constant REWARDS_PER_SECOND = 317;
    uint128 constant REWARDS_PER_MONTH = REWARDS_PER_SECOND * SECONDS_IN_30_DAYS;
    uint128 constant MIN_DEPOSIT = 1000;
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

    modifier isDeployer() {
        vm.startPrank(deployer);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE);
        setUpUniswap();

        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        //sanity checks
        assert(Lib.similar(100, 110) == false);
        assert(Lib.similar(110, 100) == false);
        assert(Lib.similar(100, 101) == true);
        assert(Lib.similar(101, 100) == true);
        assert(Lib.similar(100, 100) == true);
    }

    function giveLPtokens(address receiver_, uint256 amount_) public isDeployer {
        uint256 balanceBefore = LPtoken.balanceOf(receiver_);
        LPtoken.transfer(receiver_, amount_);

        //sanity check
        if (receiver_ != deployer) {
            assert(LPtoken.balanceOf(receiver_) - balanceBefore == amount_);
        }
    }

    function getLPTokenBalance(address address_) public view returns (uint256 balance_) {
        balance_ = LPtoken.balanceOf(address_);
    }

    function deposit(address vaultAddr_, address depositor_, uint128 deposit_, uint64 monthsLocked_) public {
        vm.startPrank(depositor_);
        uint256 startingBalance = LPtoken.balanceOf(depositor_);
        uint64 hint_ =
            IVault(vaultAddr_).getInsertPosition(uint64(block.timestamp) + monthsLocked_ * SECONDS_IN_30_DAYS);
        LPtoken.approve(vaultAddr_, deposit_);
        IVault(vaultAddr_).deposit(deposit_, monthsLocked_, hint_);
        assert(LPtoken.balanceOf(depositor_) == startingBalance - deposit_);
        vm.stopPrank();
    }

    function setUpUniswap() internal isDeployer {
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
        assert(success);

        // Get the pair to interact with
        (, bytes memory data) =
            factory.call(abi.encodeWithSignature("getPair(address,address)", address(tokenA), address(weth)));
        LPtoken = IERC20(abi.decode(data, (address)));
        vm.label(address(LPtoken), "LPtoken");
    }
}
