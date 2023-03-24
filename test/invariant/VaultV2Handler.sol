// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { LZEndpointMock } from "@layerZero/mocks/LZEndpointMock.sol";
import { LayerZeroHelper } from "./../utils/LayerZeroHelper.sol";
import { Lib } from "test/utils/Library.sol";

contract VaultV2Handler is Test, LayerZeroHelper {
    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constants -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 constant MIN_VAULTS = 2;
    uint256 constant MAX_VAULTS = 5;
    uint256 constant MAX_DEPOSITORS_PER_VAULT = 6;
    uint256 constant DEPOSITOR_INITIAL_ASSET = 1_000_000 ether;
    uint128 constant MAX_DEPOSIT = 1000 ether;
    uint128 constant MAX_TIME_INTERVAL = 12 * SECONDS_IN_30_DAYS;
    uint256 constant SHARES_SLOT = 101;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Structs ---------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    struct Deposit {
        address depositor;
        uint256 deposit;
        uint256 shares;
        uint256 expireTime;
        bool withdrawn;
    }

    struct Chain_Lz {
        VaultV2 vaultV2;
        IERC20 rewardToken;
        address[] depositors;
        uint256 chainIndex;
    }
    //Deposit[] ghost_deposits;

    struct Random_struct {
        VaultV2 vaultV2;
        IERC20 rewardToken;
        address[] depositors;
        uint256 chainIndex;
        Deposit[] ghost_deposits_random;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Variables -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    uint256 public ghost_amountDeposited;
    uint256 public ghost_amountWithdrawn;
    uint256 public ghost_amountClaimed;
    Chain_Lz[] public chains;
    Random_struct[] public chains_random;

    uint64[4] private _lockPeriods = [6, 12, 24, 48];
    address private _currentActor;
    Chain_Lz private _currentChain;
    Random_struct private _chain_random;

    mapping(uint256 => Deposit[]) public ghost_deposits;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    modifier useChain(uint256 chainSeed_) {
        if (chains.length == 0) _deployOnChains(chainSeed_);
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

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Constructor -----------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    constructor() {
        super.setUp();
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Targeted Functions ----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function deposit(uint256 seed_, uint64 hint_) external useChain(seed_) useActor(seed_) {
        uint128 deposit_ = uint128(Lib.getRandomNumberInRange(MIN_DEPOSIT, MAX_DEPOSIT, seed_));
        uint64 monthsLocked_ = _lockPeriods[(seed_ % _lockPeriods.length)];
        LPtoken.approve(address(_currentChain.vaultV2), deposit_);
        _currentChain.vaultV2.deposit(deposit_, monthsLocked_, hint_);
        _addDepositToList(_currentChain.chainIndex, _currentActor, uint256(deposit_), uint256(monthsLocked_));
    }

    function withdraw(uint256 seed_) external useChain(seed_) useActor(seed_) {
        _currentChain.vaultV2.withdraw();
        _setDepositsAsWithdrawn(_currentChain.chainIndex, _currentActor);
    }

    function claimRewards(uint256 seed_) external useChain(seed_) useActor(seed_) {
        uint64[] memory depositIds_ = _currentChain.vaultV2.getDepositIds(_currentActor);
        _currentChain.vaultV2.claimRewards(depositIds_);
    }

    function skipTime(uint256 seed_) external {
        uint256 timeInterval = Lib.getRandomNumberInRange(0, MAX_TIME_INTERVAL, seed_);
        vm.warp(time += timeInterval);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // View Functions --------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getNumberOfChains() external view returns (uint256 numberOfChains_) {
        numberOfChains_ = chains.length;
    }

    function getVaultSharesByChainIndex(uint256 chainIndex_) external view returns (uint256 totalShares_) {
        address vaultAddr = address(chains[chainIndex_].vaultV2);
        uint256 slotData_ = uint256(vm.load(vaultAddr, bytes32(uint256(SHARES_SLOT))));
        totalShares_ = slotData_ & 0xffffffffffffffffffffffffffffffff;
    }

    function getVaultExpectedShares() external view returns (uint256 totalShares_) {
        uint256 numberOfChains_ = chains.length;
        for (uint256 i_ = 0; i_ < numberOfChains_; i_++) {
            uint256 numberOfDeposits_ = ghost_deposits[i_].length;
            for (uint256 j_ = 0; j_ < numberOfDeposits_; j_++) {
                if (ghost_deposits[i_][j_].withdrawn == false) {
                    totalShares_ += ghost_deposits[i_][j_].shares;
                }
            }
        }
    }

    function getVaultAssetBalanceByChainIndex(uint256 chainIndex_) external view returns (uint256 assetBalance_) {
        address vaultAddr = address(chains[chainIndex_].vaultV2);
        assetBalance_ = getLPTokenBalance(vaultAddr);
    }

    function getVaultUnwithdrawnAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256 unwithdrawnAsset_)
    {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (ghost_deposits[chainIndex_][i_].withdrawn == false) {
                unwithdrawnAsset_ += ghost_deposits[chainIndex_][i_].deposit;
            }
        }
    }

    function getWithdrawnAssetByChainIndex(uint256 chainIndex_) external view returns (uint256 withdrawnAsset_) {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (ghost_deposits[chainIndex_][i_].withdrawn == true) {
                withdrawnAsset_ += ghost_deposits[chainIndex_][i_].deposit;
            }
        }
    }

    function getDepositorsInitialAssetByChainIndex(uint256 chainIndex_) external view returns (uint256 initialAsset_) {
        initialAsset_ = chains[chainIndex_].depositors.length * DEPOSITOR_INITIAL_ASSET;
    }

    function getDepositorsCurrentAssetByChainIndex(uint256 chainIndex_) external view returns (uint256 currentAsset_) { }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Vautlt Simulation Functions ----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _addDepositToList(uint256 chainIndex_, address depositor_, uint256 deposit_, uint256 monthsLocked_)
        internal
    {
        Deposit memory newDeposit;
        newDeposit.depositor = depositor_;
        newDeposit.deposit = deposit_;
        newDeposit.shares = deposit_ * uint128((monthsLocked_ / 6));
        newDeposit.expireTime = block.timestamp + monthsLocked_ * SECONDS_IN_30_DAYS;
        newDeposit.withdrawn = false;
        ghost_deposits[chainIndex_].push(newDeposit);
    }

    function _setDepositsAsWithdrawn(uint256 chainIndex_, address depositor_) internal {
        uint256 listSize_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < listSize_; i_++) {
            if (ghost_deposits[chainIndex_][i_].depositor == depositor_) {
                if (block.timestamp > ghost_deposits[chainIndex_][i_].expireTime) {
                    ghost_deposits[chainIndex_][i_].withdrawn = true;
                }
            }
        }
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Handler Operation Functions ----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _deployOnChains(uint256 seed_) internal {
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
            Chain_Lz memory newChain;
            newChain.vaultV2 = VaultV2(vaultsv2_[i_]);
            newChain.rewardToken = IERC20(rewardTokens_[i_]);
            newChain.chainIndex = i_;
            chains.push(newChain);

            /*chains_random.push(Random_struct({
                vaultV2 : VaultV2(vaultsv2_[i_]),
                rewardToken : IERC20(rewardTokens_[i_]),
                depositors: new address[](0),
                chainIndex : 0,
                ghost_deposits_random : new  Deposit[](0)
            }));

            Random_struct memory a;
            a.ghost_deposits_random = new Deposit[](1);
            a.ghost_deposits_random.push(Deposit({
                depositor: address(0),
                deposit: 1,
                shares: 1,
                expireTime:0,
                withdrawn : false
            }));
            chains_random.push(a);*/
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
        uint256 _currentChainId = seed_ % chains.length;
        chain_ = chains[_currentChainId];
    }

    function _getChain_random(uint256 seed_) internal view returns (Random_struct storage chain_) {
        uint256 _currentChainId = seed_ % chains.length;
        chain_ = chains_random[_currentChainId];
    }

    function _getActor(uint256 seed_) internal view returns (address actor_) {
        uint256 actorSize = _currentChain.depositors.length;
        actor_ = _currentChain.depositors[seed_ % actorSize];
    }
}
