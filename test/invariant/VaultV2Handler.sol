// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { Lib } from "test/utils/Library.sol";

contract VaultV2Handler is Test, LayerZeroHelper {
    uint256 constant MIN_VAULTS = 2;
    uint256 constant MAX_VAULTS = 5;
    uint256 constant MAX_DEPOSITORS_PER_VAULT = 10;
    uint256 constant DEPOSITOR_INITIAL_ASSET = 1_000_000 ether;
    uint128 constant MAX_DEPOSIT = 1000 ether;
    uint128 constant MAX_TIME_INTERVAL = 12 * SECONDS_IN_30_DAYS;

    // chain id and endpoint not needed here
    struct Chain_Lz {
        VaultV2 vaultV2;
        IERC20 rewardToken;
        address[] depositors;
    }

    uint64[4] private _lockPeriods = [6, 12, 24, 48];
    address private _currentActor;
    Chain_Lz[] private _chains;
    Chain_Lz private _currentChain;

    modifier useChain(uint256 chainSeed_) {
        if (_chains.length == 0) _deployOnChains(chainSeed_);
        _currentChain = _getChain(chainSeed_);
        _;
    }

    modifier useActor(uint256 actorSeed_) {
        if (_currentChain.depositors.length == 0) _deployActors(actorSeed_);
        _currentActor = _getActor(actorSeed_);
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor() { }

    function deposit(uint256 seed_, uint64 hint_) external useChain(seed_) useActor(seed_) {
        uint128 deposit_ = uint128(Lib.getRandomNumberInRange(MIN_DEPOSIT, MAX_DEPOSIT, seed_));
        uint64 monthsLocked_ = _lockPeriods[(seed_ % _lockPeriods.length)];
        LPtoken.approve(address(_currentChain.vaultV2), deposit_);
        _currentChain.vaultV2.deposit(deposit_, monthsLocked_, hint_);
    }

    function withdraw(uint256 seed_) external useChain(seed_) useActor(seed_) {
        _currentChain.vaultV2.withdraw();
    }

    function claimRewards(uint256 seed_) external useChain(seed_) useActor(seed_) {
        uint64[] memory depositIds_ = _currentChain.vaultV2.getDepositIds(_currentActor);
        _currentChain.vaultV2.claimRewards(depositIds_);
    }

    function skipTime(uint256 seed_) external {
        uint256 timeInterval = Lib.getRandomNumberInRange(0, MAX_TIME_INTERVAL, seed_);
        vm.warp(time += timeInterval);
    }

    function _deployOnChains(uint256 seed_) internal isDeployer {
        vm.warp(time);
        uint256 numberOfVaults_ = Lib.getRandomNumberInRange(MIN_VAULTS, MAX_VAULTS, seed_);

        uint16[] memory chainIds_ = new uint16[](numberOfVaults_);
        for (uint256 i = 0; i < numberOfVaults_; i++) {
            chainIds_[i] = uint16(seed_ % type(uint16).max);
            seed_ = seed_ / 7;
        }
        (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_) =
            this.deployBatchOnChain(chainIds_);
        connectVaults(chainIds_, vaultsv2_, endpoints_);

        for (uint256 i = 0; i < numberOfVaults_; i++) {
            _chains[i] = Chain_Lz({
                vaultV2: VaultV2(vaultsv2_[i]),
                rewardToken: IERC20(rewardTokens_[i]),
                depositors: new address[](0)
            });
        }
    }

    function _deployActors(uint256 seed_) internal {
        uint256 numberOfActors_ = Lib.getRandomNumberInRange(1, MAX_DEPOSITORS_PER_VAULT, seed_);
        for (uint256 j = 0; j < numberOfActors_; j++) {
            address depositor_ = address(uint160(seed_ % type(uint160).max));
            if (depositor_ == address(0)) depositor_ = address(1);
            giveLPtokens(depositor_, DEPOSITOR_INITIAL_ASSET);
            _currentChain.depositors.push(depositor_);
            seed_ = seed_ / 3;
        }
    }

    function _getChain(uint256 seed_) internal view returns (Chain_Lz storage chain_) {
        uint256 _currentChainId = seed_ % _chains.length;
        chain_ = _chains[_currentChainId];
    }

    function _getActor(uint256 seed_) internal view returns (address actor_) {
        uint256 actorSize = _currentChain.depositors.length;
        actor_ = _currentChain.depositors[seed_ % actorSize];
    }
}
