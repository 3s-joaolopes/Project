// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";
import { VaultFixture } from "./utils/VaultFixture.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { OFToken } from "src/src-default/OFToken.sol";

contract VaultV2Test is Test, VaultFixture {
    address public lzEndpoint;

    function setUp() public override {
        super.setUp();

        lzEndpoint = address(0);
    }

    function testOFToken_transfer() external {
        OFToken token = new OFToken(alice, "Token", "TKN", lzEndpoint);

        vm.startPrank(bob);
        vm.expectRevert(OFToken.Unauthorized.selector);
        token.mintRewards(alice, 10);
        vm.stopPrank();

        vm.startPrank(alice);
        token.mintRewards(alice, 10);
        require(token.balanceOf(alice) == 10, "Failed to setup OFToken");
        token.transfer(bob, 10);
        require(token.balanceOf(bob) == 10, "Failed to setup OFToken");
        vm.stopPrank();
    }
}
