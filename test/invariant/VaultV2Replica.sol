// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VaultV2Replica {
    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constants -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 constant REWARD_PRECISION = 1 ether;
    uint256 constant REWARDS_PER_SECOND = 317 * REWARD_PRECISION;
    uint256 constant SECONDS_IN_30_DAYS = 2_592_000;

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

    struct HistoryElement {
        uint256 time;
        uint256 shares;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Variables -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 private _lastHistoryIndex;
    HistoryElement[] private _shareHistory;
    Deposit[] private _ghost_deposits;
    // Mapping: chain index -> depositor -> ExpectedRewards * REWARD_PRECISION
    mapping(uint256 => mapping(address => uint256)) private _ghost_expectedRewards;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constructor -----------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    constructor() { }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault External Functions -------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function addDeposit(uint256 chainIndex_, address depositor_, uint256 deposit_, uint256 monthsLocked_, uint256 time_)
        external
    {
        // Create deposit
        uint256 expireTime_ = time_ + monthsLocked_ * SECONDS_IN_30_DAYS;
        uint256 shares_ = deposit_ * (monthsLocked_ / 6);
        Deposit memory newDeposit_ = Deposit({
            chainIndex: chainIndex_,
            depositor: depositor_,
            deposit: deposit_,
            shares: shares_,
            depositTime: time_,
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
        _updateShareHistory(time_);
        uint256 latestShares_ = 0;
        if (_shareHistory.length > 0) {
            latestShares_ = _shareHistory[_shareHistory.length - 1].shares;
        }
        _shareHistory.push(HistoryElement(time_, latestShares_ + shares_));
    }

    function addWithdrawl(uint256 chainIndex_, address depositor_, uint256 time_) external {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                if (_ghost_deposits[i_].depositor == depositor_) {
                    if (time_ > _ghost_deposits[i_].expireTime) {
                        _ghost_deposits[i_].withdrawn = true;
                    }
                }
            }
        }
    }

    function addRewards(uint256 chainIndex_, address depositor_, uint256 time_) external {
        _updateShareHistory(time_);
        _ghost_expectedRewards[chainIndex_][depositor_] = _getExpectedRewards(depositor_, time_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // View Functions --------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getExpectedShares(uint256 time_) public view returns (uint256 totalShares_) {
        for (uint256 i_ = 0; i_ < _ghost_deposits.length; i_++) {
            if (_ghost_deposits[i_].depositTime <= time_ && time_ < _ghost_deposits[i_].expireTime) {
                totalShares_ += _ghost_deposits[i_].shares;
            }
        }
    }

    function getExpectedDepositsInChain(uint256 chainIndex_) public view returns (uint256 depositedAsset_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                depositedAsset_ += _ghost_deposits[i_].deposit;
            }
        }
    }

    function getExpectedWithdrawnAssetInChain(uint256 chainIndex_) public view returns (uint256 withdrawnAsset_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].chainIndex == chainIndex_) {
                if (_ghost_deposits[i_].withdrawn == true) {
                    withdrawnAsset_ += _ghost_deposits[i_].deposit;
                }
            }
        }
    }

    function getExpectedActorAssetInChain(uint256 chainIndex_, address actor_)
        external
        view
        returns (uint256 actorAsset_)
    {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 j_ = 0; j_ < numberOfDeposits_; j_++) {
            if (_ghost_deposits[j_].chainIndex == chainIndex_) {
                if (_ghost_deposits[j_].depositor == actor_) {
                    if (_ghost_deposits[j_].withdrawn == false) {
                        actorAsset_ += _ghost_deposits[j_].deposit;
                    }
                }
            }
        }
    }

    function getActorsExpectedRewardsInChain(uint256 chainIndex_, address actor_)
        external
        view
        returns (uint256 actorExpectedRewards_)
    {
        actorExpectedRewards_ = _ghost_expectedRewards[chainIndex_][actor_] / REWARD_PRECISION;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault Logic Internal Functions ----------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    /// @dev Extremely gas ineficient. Just an alternative to the optimized logic used in the vault
    function _updateShareHistory(uint256 time_) internal {
        if (_shareHistory.length == 0) return;
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = _lastHistoryIndex; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].expireTime <= time_) {
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
    function _getExpectedRewards(address depositor_, uint256 time_) internal view returns (uint256 expectedRewards_) {
        uint256 numberOfDeposits_ = _ghost_deposits.length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (_ghost_deposits[i_].depositor == depositor_) {
                uint256 depositTime_ = _ghost_deposits[i_].depositTime;
                uint256 expireTime_ = _ghost_deposits[i_].expireTime;
                uint256 shares_ = _ghost_deposits[i_].shares;
                uint256 historySize_ = _shareHistory.length;
                if (historySize_ > 1) {
                    for (uint256 j_ = 1; j_ < historySize_; j_++) {
                        if (depositTime_ <= _shareHistory[j_ - 1].time && _shareHistory[j_].time <= expireTime_) {
                            uint256 timeInterval_ = _shareHistory[j_].time - _shareHistory[j_ - 1].time;
                            uint256 rewardIncrement =
                                timeInterval_ * REWARDS_PER_SECOND * shares_ / _shareHistory[j_ - 1].shares;
                            expectedRewards_ += rewardIncrement;
                        }
                    }
                }
                if (_shareHistory[historySize_ - 1].time < expireTime_) {
                    uint256 timeInterval_ = time_ - _shareHistory[historySize_ - 1].time;
                    uint256 rewardIncrement =
                        timeInterval_ * REWARDS_PER_SECOND * shares_ / _shareHistory[historySize_ - 1].shares;
                    expectedRewards_ += rewardIncrement;
                }
            }
        }
    }
}
