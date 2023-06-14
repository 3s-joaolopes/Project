// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { VaultV2Replica } from "./VaultV2Replica.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { Lib } from "test/utils/Library.sol";
import { console2 } from "@forge-std/console2.sol";

contract VaultV2Handler is Test, LayerZeroHelper {
    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constants -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 constant STARTING_TIME = 1000;
    uint256 constant REWARDS_PER_SECOND = 317;
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;
    uint256 constant MIN_VAULTS = 2;
    uint256 constant MAX_VAULTS = 4;
    uint256 constant MIN_ACTORS_PER_VAULT = 1;
    uint256 constant MAX_ACTORS_PER_VAULT = 3;
    uint256 constant ACTOR_INITIAL_ASSET = 1_000_000 ether;
    uint256 constant MIN_DEPOSIT = 1000;
    uint256 constant MAX_DEPOSIT = 10 ether;
    uint256 constant MIN_TIME_INTERVAL = 7 days;
    uint256 constant MAX_TIME_INTERVAL = 12 * SECONDS_IN_30_DAYS;
    uint256 constant SHARES_STORAGE_SLOT = 101;
    uint256 constant LAST_TIME_STORAGE_SLOT = 102;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Structs ---------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    struct Chain_Lz {
        VaultV2 vaultV2;
        IERC20 rewardToken;
        address[] actors;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Variables -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 public numberOfDeployments;

    address private _currentActor;
    uint256 private _time = STARTING_TIME;
    uint256 private _chainIndex;
    uint64[4] private _lockPeriods = [6, 12, 24, 48];
    Chain_Lz[] private _chains;

    mapping(address => bool) private _invalidActorAdresses;

    VaultV2Replica private _vaultReplica;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    modifier useTime() {
        vm.warp(_time);
        _;
    }

    modifier useChain(uint256 chainSeed_) {
        if (_chains.length == 0) _deployOnChains(chainSeed_);
        _chainIndex = _getChainIndex(chainSeed_);
        _;
    }

    modifier useActor(uint256 actorSeed_) {
        vm.stopPrank();
        if (_chains[_chainIndex].actors.length == 0) _deployActors(actorSeed_);
        _currentActor = _getActor(actorSeed_);
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constructor -----------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    constructor() {
        super.setUp();
        _vaultReplica = new VaultV2Replica();

        _invalidActorAdresses[deployer] = true;
        _invalidActorAdresses[address(_vaultReplica)] = true;
        _invalidActorAdresses[address(LPtoken)] = true;
        _invalidActorAdresses[address(this)] = true;
        _invalidActorAdresses[address(0)] = true;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Targeted Functions ----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function deposit(uint256 seed_, uint64 hint_) external useTime useChain(seed_) useActor(seed_) {
        uint128 deposit_ = uint128(Lib.getRandomNumberInRange(MIN_DEPOSIT, MAX_DEPOSIT, seed_));
        uint64 monthsLocked_ = _lockPeriods[(seed_ % _lockPeriods.length)];
        LPtoken.approve(address(_chains[_chainIndex].vaultV2), deposit_);
        _chains[_chainIndex].vaultV2.deposit(deposit_, monthsLocked_, hint_);
        _vaultReplica.addDeposit(_chainIndex, _currentActor, uint256(deposit_), uint256(monthsLocked_), _time);
    }

    function withdraw(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        _chains[_chainIndex].vaultV2.withdraw();
        _vaultReplica.addWithdrawl(_chainIndex, _currentActor, _time);
    }

    function claimRewards(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        uint64[] memory depositIds_ = _chains[_chainIndex].vaultV2.getDepositIds(_currentActor);
        _chains[_chainIndex].vaultV2.claimRewards(depositIds_);
        _vaultReplica.addRewards(_chainIndex, _currentActor, _time);
    }

    function skipTime(uint256 seed_) external {
        uint256 timeInterval = Lib.getRandomNumberInRange(MIN_TIME_INTERVAL, MAX_TIME_INTERVAL, seed_);
        vm.warp(_time += timeInterval);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault-wise View Functions ---------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getNumberOfChains() public view returns (uint256 numberOfChains_) {
        numberOfChains_ = _chains.length;
    }

    function getNumberOfActorsOnChain(uint256 chainIndex_) public view returns (uint256 numberOfActors_) {
        numberOfActors_ = _chains[chainIndex_].actors.length;
    }

    function getVaultSharesByIndex(uint256 chainIndex_) public view returns (uint256 totalShares_) {
        address vaultAddr = address(_chains[chainIndex_].vaultV2);
        uint256 slotData_ = uint256(vm.load(vaultAddr, bytes32(uint256(SHARES_STORAGE_SLOT))));
        totalShares_ = slotData_ & 0xffffffffffffffffffffffffffffffff;
    }

    function getVaultExpectedSharesByIndex(uint256 chainIndex_) public view returns (uint256 totalShares_) {
        address vaultAddr = address(_chains[chainIndex_].vaultV2);
        uint256 slotData_ = uint256(vm.load(vaultAddr, bytes32(uint256(LAST_TIME_STORAGE_SLOT))));
        uint256 lastUpdateTime_ = slotData_ & 0xffffffffffffffff;

        totalShares_ = _vaultReplica.getExpectedShares(lastUpdateTime_);
    }

    function getVaultAssetBalanceByIndex(uint256 chainIndex_) public view returns (uint256 assetBalance_) {
        address vaultAddr = address(_chains[chainIndex_].vaultV2);
        assetBalance_ = getLPTokenBalance(vaultAddr);
    }

    function getVaultExpectedDepositsByIndex(uint256 chainIndex_) public view returns (uint256 depositedAsset_) {
        depositedAsset_ = _vaultReplica.getExpectedDepositsInChain(chainIndex_);
    }

    function getExpectedWithdrawnAssetByChainIndex(uint256 chainIndex_) public view returns (uint256 withdrawnAsset_) {
        withdrawnAsset_ = _vaultReplica.getExpectedWithdrawnAssetInChain(chainIndex_);
    }

    function getInitialAssetByChainIndex(uint256 chainIndex_) public view returns (uint256 initialAsset_) {
        initialAsset_ = _chains[chainIndex_].actors.length * ACTOR_INITIAL_ASSET;
    }

    function getMaximumRewardsPossible() public view returns (uint256 maxRewards_) {
        maxRewards_ = (_time - STARTING_TIME) * REWARDS_PER_SECOND;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Actor-wise View Functions ---------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getActorsInitialAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory initialAsset_)
    {
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        initialAsset_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            initialAsset_[i_] = ACTOR_INITIAL_ASSET;
        }
    }

    function getActorsAssetByChainIndex(uint256 chainIndex_) external view returns (uint256[] memory actorAsset_) {
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        actorAsset_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            actorAsset_[i_] = getLPTokenBalance(_chains[chainIndex_].actors[i_]);
        }
    }

    function getExpectedActorsAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory actorAsset_)
    {
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        actorAsset_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            actorAsset_[i_] = _vaultReplica.getExpectedActorAssetInChain(chainIndex_, _chains[chainIndex_].actors[i_]);
        }
    }

    function getActorsRewardsByChainIndex(uint256 chainIndex_) external view returns (uint256[] memory actorRewards_) {
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        actorRewards_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            address actor_ = _chains[chainIndex_].actors[i_];
            actorRewards_[i_] = _chains[chainIndex_].rewardToken.balanceOf(actor_);
        }
    }

    function getActorsExpectedRewardsByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory actorExpectedRewards_)
    {
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        actorExpectedRewards_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            address actor_ = _chains[chainIndex_].actors[i_];
            actorExpectedRewards_[i_] = _vaultReplica.getActorsExpectedRewardsInChain(chainIndex_, actor_);
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Handler Operation Functions ----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _deployOnChains(uint256 seed_) internal {
        vm.stopPrank();
        numberOfDeployments++;
        uint256 numberOfChains_ = Lib.getRandomNumberInRange(MIN_VAULTS, MAX_VAULTS, seed_);

        uint16[] memory chainIds_ = new uint16[](numberOfChains_);
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            chainIds_[i_] = uint16(seed_ % type(uint16).max);
            seed_ = seed_ / 7;
        }
        (address[] memory vaultsv2_, address[] memory endpoints_, address[] memory rewardTokens_) =
            this.deployBatchOnChain(chainIds_);
        connectVaults(chainIds_, vaultsv2_, endpoints_);

        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            _invalidActorAdresses[vaultsv2_[i_]] = true;
            _invalidActorAdresses[endpoints_[i_]] = true;
            _invalidActorAdresses[rewardTokens_[i_]] = true;

            Chain_Lz memory newChain;
            newChain.vaultV2 = VaultV2(vaultsv2_[i_]);
            newChain.rewardToken = IERC20(rewardTokens_[i_]);
            _chains.push(newChain);
        }
    }

    function _deployActors(uint256 seed_) internal {
        uint256 numberOfActors_ = Lib.getRandomNumberInRange(MIN_ACTORS_PER_VAULT, MAX_ACTORS_PER_VAULT, seed_);
        for (uint256 j = 0; j < numberOfActors_; j++) {
            address actor_ = address(uint160(seed_ % type(uint160).max));
            if (_invalidActorAdresses[actor_]) actor_ = address(1);
            giveLPtokens(actor_, ACTOR_INITIAL_ASSET);
            _chains[_chainIndex].actors.push(actor_);
            seed_ = seed_ / 3;
        }
        assert(Lib.repeatedEntries(_chains[_chainIndex].actors) == false);
    }

    function _getChainIndex(uint256 seed_) internal view returns (uint256 chainIndex_) {
        chainIndex_ = seed_ % _chains.length;
    }

    function _getActor(uint256 seed_) internal view returns (address actor_) {
        uint256 actorsSize_ = _chains[_chainIndex].actors.length;
        actor_ = _chains[_chainIndex].actors[seed_ % actorsSize_];
    }
}
