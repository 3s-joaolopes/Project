// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vault } from "src/src-default/Vault.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { Token } from "./Token.sol";
import { WETH9 } from "./WETH9.sol";

contract UniswapHelper is Test {
    uint256 private constant UNISWAP_INITIAL_TOKEN_RESERVE = 100_000_000 ether;
    uint256 private constant UNISWAP_INITIAL_WETH_RESERVE = 100_000_000 ether;

    address public deployer = vm.addr(1000);
    address public router;
    address public factory;

    IERC20 public LPtoken;

    modifier isDeployer() {
        vm.startPrank(deployer);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        vm.label(deployer, "Deployer");
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE);
        setUpUniswap();
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
