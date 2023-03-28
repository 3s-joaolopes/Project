// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { Lib } from "test/utils/Library.sol";
import { console2 } from "@forge-std/console2.sol";

contract VaultV2Handler is Test, LayerZeroHelper {
    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constants -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 constant MIN_VAULTS = 2;
    uint256 constant MAX_VAULTS = 4;
    uint256 constant MIN_ACTORS_PER_VAULT = 1;
    uint256 constant MAX_ACTORS_PER_VAULT = 3;
    uint256 constant ACTOR_INITIAL_ASSET = 1_000_000 ether;
    uint128 constant MAX_DEPOSIT = 10 ether;
    uint128 constant MAX_TIME_INTERVAL = 12 * SECONDS_IN_30_DAYS;
    uint256 constant SHARES_STORAGE_SLOT = 101;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Structs ---------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    struct Deposit {
        uint256 chainIndex;
        address depositor;
        uint256 deposit;
        uint256 shares;
        uint256 depositTime;
        uint256 expireTime;
        bool withdrawn;
    }

    struct Chain_Lz {
        VaultV2 vaultV2;
        IERC20 rewardToken;
        address[] actors;
    }

    struct HistoryElement {
        uint256 time;
        uint256 shares;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Variables -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 public numberOfDeployments;

    address private _currentActor;
    uint256 private _chainIndex;
    uint256 private _lastHistoryIndex;
    uint256 _lastRewardsTime;
    uint64[4] private _lockPeriods = [6, 12, 24, 48];

    Chain_Lz[] private _chains;
    HistoryElement[] private _shareHistory;
    Deposit[] private _ghost_deposits;

    mapping(address => bool) private _invalidActorAdresses;
    mapping(uint256 => mapping(address => uint256)) private _ghost_expectedRewards;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    modifier useTime() {
        //vm.warp(time);
        _;
    }

    modifier useChain(uint256 chainSeed_) {
        if (_chains.length == 0) _deployOnChains(chainSeed_);
        _chainIndex = _getChainIndex(chainSeed_);
        _;
    }

    modifier useActor(uint256 actorSeed_) {
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
        _invalidActorAdresses[address(LPtoken)] = true;
        _invalidActorAdresses[address(this)] = true;
        _invalidActorAdresses[address(0)] = true;
    }

    function handlerLog() external view {
        console2.log("Logs-------------");
        uint256 numberOfChains_ = _chains.length;
        console2.log("Chains: ", numberOfChains_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Targeted Functions ----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function deposit(uint256 seed_, uint64 hint_) external useTime useChain(seed_) useActor(seed_) {
        uint128 deposit_ = uint128(Lib.getRandomNumberInRange(MIN_DEPOSIT, MAX_DEPOSIT, seed_));
        uint64 monthsLocked_ = _lockPeriods[(seed_ % _lockPeriods.length)];
        LPtoken.approve(address(_chains[_chainIndex].vaultV2), deposit_);
        _chains[_chainIndex].vaultV2.deposit(deposit_, monthsLocked_, hint_);
        _addDepositToList(_chainIndex, _currentActor, uint256(deposit_), uint256(monthsLocked_));
    }

    function withdraw(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        _chains[_chainIndex].vaultV2.withdraw();
        _setDepositAsWithdrawn(_chainIndex, _currentActor);
    }

    function claimRewards(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        uint64[] memory depositIds_ = _chains[_chainIndex].vaultV2.getDepositIds(_currentActor);
        _chains[_chainIndex].vaultV2.claimRewards(depositIds_);
        _addRewardsClaimedToList(_chainIndex, _currentActor);
    }

    function skipTime(uint256 seed_) external {
        uint256 timeInterval = Lib.getRandomNumberInRange(0, MAX_TIME_INTERVAL, seed_);
        vm.warp(time += timeInterval);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault-wise View Functions ---------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getNumberOfChains() external view returns (uint256 numberOfChains_) {
        numberOfChains_ = _chains.length;
    }

    function getNumberOfActorsOnChain(uint256 chainIndex_) external view returns (uint256 numberOfActors_) {
        numberOfActors_ = _chains[chainIndex_].actors.length;
    }

    function getVaultSharesByIndex(uint256 chainIndex_) external view returns (uint256 totalShares_) {
        address vaultAddr = address(_chains[chainIndex_].vaultV2);
        uint256 slotData_ = uint256(vm.load(vaultAddr, bytes32(uint256(SHARES_STORAGE_SLOT))));
        totalShares_ = slotData_ & 0xffffffffffffffffffffffffffffffff;
    }

    function getVaultExpectedShares() external view returns (uint256 totalShares_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].withdrawn == false) {
                totalShares_ += _ghost_deposits[i_].shares;
            }
        }
    }

    function getVaultAssetBalanceByIndex(uint256 chainIndex_) external view returns (uint256 assetBalance_) {
        address vaultAddr = address(_chains[chainIndex_].vaultV2);
        assetBalance_ = getLPTokenBalance(vaultAddr);
    }

    function getVaultExpectedDepositsByIndex(uint256 chainIndex_) external view returns (uint256 depositedAsset_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                depositedAsset_ += _ghost_deposits[i_].deposit;
            }
        }
    }

    function getExpectedWithdrawnAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256 withdrawnAsset_)
    {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                if (_ghost_deposits[i_].withdrawn == true) {
                    withdrawnAsset_ += _ghost_deposits[i_].deposit;
                }
            }
        }
    }

    function getInitialAssetByChainIndex(uint256 chainIndex_) external view returns (uint256 initialAsset_) {
        initialAsset_ = _chains[chainIndex_].actors.length * ACTOR_INITIAL_ASSET;
    }

    function getMaximumRewardsPossible() external view returns (uint256 maxRewards_) {
        maxRewards_ = (time - STARTING_TIME) * REWARDS_PER_SECOND;
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

    function getActorsUnwithdrawnAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory actorDeposits_)
    {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        uint256 numberOfActors_ = _chains[chainIndex_].actors.length;
        actorDeposits_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            for (uint256 j_ = 0; j_ < numberOfDeposits_; j_++) {
                if (_ghost_deposits[j_].chainIndex == chainIndex_) {
                    if (_ghost_deposits[j_].depositor == _chains[chainIndex_].actors[i_]) {
                        if (_ghost_deposits[j_].withdrawn == false) {
                            actorDeposits_[i_] += _ghost_deposits[j_].deposit;
                        }
                    }
                }
            }
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
            actorExpectedRewards_[i_] = _ghost_expectedRewards[chainIndex_][actor_];
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Vault Simulation Functions -----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _addDepositToList(uint256 chainIndex_, address depositor_, uint256 deposit_, uint256 monthsLocked_)
        internal
    {
        // Create deposit
        uint256 expireTime_ = time + monthsLocked_ * SECONDS_IN_30_DAYS;
        uint256 shares_ = deposit_ * (monthsLocked_ / 6);
        Deposit memory newDeposit_ = Deposit({
            chainIndex: chainIndex_,
            depositor: depositor_,
            deposit: deposit_,
            shares: shares_,
            depositTime: time,
            expireTime: expireTime_,
            withdrawn: false
        });

        // Add deposit to list (ordered by expire time)
        bool placed_ = false;
        for (uint256 i_ = 0; i_ < _ghost_deposits.length; i_++) {
            if (!placed_ && _ghost_deposits[i_].expireTime > expireTime_) {
                _ghost_deposits.push(newDeposit_);
                placed_ = true;
            }
            if (placed_ == true) {
                Deposit memory currentDeposit = _ghost_deposits[i_];
                _ghost_deposits[i_] = _ghost_deposits[_ghost_deposits.length - 1];
                _ghost_deposits[_ghost_deposits.length - 1] = currentDeposit;
            }
        }
        if (!placed_) _ghost_deposits.push(newDeposit_);

        // Update share history and include new deposit
        _updateShareHistory();
        uint256 latestShares_ = 0;
        if (_shareHistory.length > 0) {
            latestShares_ = _shareHistory[_shareHistory.length - 1].shares;
        }
        _shareHistory.push(HistoryElement(time, latestShares_ + shares_));
    }

    function _setDepositAsWithdrawn(uint256 chainIndex_, address depositor_) internal {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                if (_ghost_deposits[i_].depositor == depositor_) {
                    if (time > _ghost_deposits[i_].expireTime) {
                        _ghost_deposits[i_].withdrawn = true;
                    }
                }
            }
        }
    }

    function _addRewardsClaimedToList(uint256 chainIndex_, address depositor_) internal {
        _updateShareHistory();
        _ghost_expectedRewards[chainIndex_][depositor_] = _getExpectedRewards(depositor_);
    }

    /// @dev Extremely gas ineficient. Just an alternative to the optimized logic used in the vault
    function _updateShareHistory() internal {
        if (_shareHistory.length == 0) return;
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = _lastHistoryIndex; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].expireTime <= time) {
                uint256 latestShares_ = _shareHistory[_shareHistory.length - 1].shares;
                _shareHistory.push(
                    HistoryElement(_ghost_deposits[i_].expireTime, latestShares_ - _ghost_deposits[i_].shares)
                );
                _lastHistoryIndex++;
            } else {
                break;
            }
        }
    }

    /// @dev Extremely gas ineficient. Just an alternative to the optimized logic used in the vault
    function _getExpectedRewards(address depositor_) internal view returns (uint256 expectedRewards_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].depositor == depositor_) {
                uint256 depositTime_ = _ghost_deposits[i_].depositTime;
                uint256 expireTime_ = _ghost_deposits[i_].expireTime;
                uint256 shares_ = _ghost_deposits[i_].shares;
                uint256 historySize_ = _shareHistory.length;
                for (uint256 j_ = 1; j_ < historySize_; j_++) {
                    if (depositTime_ <= _shareHistory[j_ - 1].time && _shareHistory[j_].time <= expireTime_) {
                        uint256 timeInterval_ = _shareHistory[j_].time - _shareHistory[j_ - 1].time;
                        expectedRewards_ +=
                            (timeInterval_ * REWARDS_PER_SECOND / _shareHistory[j_ - 1].shares) * shares_;
                    }
                }
                if (_shareHistory[historySize_ - 1].time < expireTime_) {
                    uint256 timeInterval_ = expireTime_ - _shareHistory[historySize_ - 1].time;
                    expectedRewards_ +=
                        (timeInterval_ * REWARDS_PER_SECOND / _shareHistory[historySize_ - 1].shares) * shares_;
                }
            }
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Handler Operation Functions ----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _deployOnChains(uint256 seed_) internal {
        numberOfDeployments++;
        vm.warp(time);
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

/*
    /// @dev Extremely gas ineficient. Just an alternative to the optimized logic used in the vault
    function _updateShareHistory(){
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        bool changes_ = true;
        while(changes_ == true){
            uint256 listSize_ = shareHistory.length;
            uint256 lastUpdateTime_ = shareHistory[listSize_-1].time;
            uint256 timeAux_ = type(uint256).max;
            uint256 sharesAux_ = 0;
            changes = false;
            for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
                if(_ghost_deposits[i_].expiretime > lastUpdateTime_ && _ghost_deposits[i_].expiretime <= time){
                    changes_ = true;
                    if(_ghost_deposits[i_].expiretime < timeAux_){
                        timeAux_ = _ghost_deposits[i_].expiretime;
                        sharesAux_ = _ghost_deposits[i_].shares;
                    }
                }
            }
            uint256 latestShares_ = shareHistory[shareHistory.length-1].shares;
            shareHistory.push(HistoryElement(timeAux_, latestShares_ - sharesAux_));
        }
    }

    /// @dev Extremely gas ineficient. Just an alternative to the optimized logic used in the vault
    function _getExpectedRewards(address depositor_) internal returns (uint256 expectedRewards_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if(_ghost_deposits[i_].depositor == depositor_){
                uint256 depositTime_ = _ghost_deposits[i_].depositTime;
                uint256 expireTime_ = _ghost_deposits[i_].expireTime;
                uint256 shares_ = _ghost_deposits[i_].shares;
                uint256 historySize_ = shareHistory.length;
                for (uint256 j_ = 0; j_ < historySize_; j_++) {
                    if(depositTime_ < shareHistory[j_].time && shareHistory[j_].time <= expireTime_){
                        int256 timeInterval_ = shareHistory[j_].time - shareHistory[j_-1].time ;
                        expectedRewards_+= (timeInterval_ * REWARDS_PER_SECOND / shareHistory[j_-1].shares) * shares_;
                    }
                }
                if(shareHistory[historySize_-1].time < expireTime_){
                    int256 timeInterval_ = expireTime_ - shareHistory[historySize_-1].time ;
                    expectedRewards_+= (timeInterval_ * REWARDS_PER_SECOND / shareHistory[historySize_-1].shares) * shares_;
                }
            }
        }
     }*/
