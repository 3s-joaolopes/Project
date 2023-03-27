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
        address depositor;
        uint256 deposit;
        uint256 shares;
        uint256 expireTime;
        bool withdrawn;
    }

    struct Withdrawl {
        uint256 chainIndex;
        uint256 claimedRewards;
        uint256 expectedRewards;
    }

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
    uint256 private _chainIndex;
    uint64[4] private _lockPeriods = [6, 12, 24, 48];
    Chain_Lz[] private chains;

    mapping(address => bool) private _invalidActorAdresses;
    mapping(uint256 => Deposit[]) private ghost_deposits;
    mapping(address => Withdrawl[]) private ghost_withdrawls;

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers -------------------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    modifier useTime() {
        vm.warp(time);
        _;
    }

    modifier useChain(uint256 chainSeed_) {
        if (chains.length == 0) _deployOnChains(chainSeed_);
        _chainIndex = _getChainIndex(chainSeed_);
        _;
    }

    modifier useActor(uint256 actorSeed_) {
        if (chains[_chainIndex].actors.length == 0) _deployActors(actorSeed_);
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
        uint256 numberOfChains_ = chains.length;
        console2.log("Chains: ", numberOfChains_);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Targeted Functions ----------------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function deposit(uint256 seed_, uint64 hint_) external useTime useChain(seed_) useActor(seed_) {
        uint128 deposit_ = uint128(Lib.getRandomNumberInRange(MIN_DEPOSIT, MAX_DEPOSIT, seed_));
        uint64 monthsLocked_ = _lockPeriods[(seed_ % _lockPeriods.length)];
        LPtoken.approve(address(chains[_chainIndex].vaultV2), deposit_);
        chains[_chainIndex].vaultV2.deposit(deposit_, monthsLocked_, hint_);
        _addDepositToList(_chainIndex, _currentActor, uint256(deposit_), uint256(monthsLocked_));
    }

    function withdraw(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        chains[_chainIndex].vaultV2.withdraw();
        _setDepositAsWithdrawn(_chainIndex, _currentActor);
    }

    function claimRewards(uint256 seed_) external useTime useChain(seed_) useActor(seed_) {
        uint64[] memory depositIds_ = chains[_chainIndex].vaultV2.getDepositIds(_currentActor);
        chains[_chainIndex].vaultV2.claimRewards(depositIds_);
        _addRewardsClaimedToList(_chainIndex, _currentActor, 0);
    }

    function skipTime(uint256 seed_) external {
        uint256 timeInterval = Lib.getRandomNumberInRange(0, MAX_TIME_INTERVAL, seed_);
        vm.warp(time += timeInterval);
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Vault-wise View Functions ---------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function getNumberOfChains() external view returns (uint256 numberOfChains_) {
        numberOfChains_ = chains.length;
    }

    function getNumberOfActorsOnChain(uint256 chainIndex_) external view returns (uint256 numberOfActors_) {
        numberOfActors_ = chains[chainIndex_].actors.length;
    }

    function getVaultSharesByIndex(uint256 chainIndex_) external view returns (uint256 totalShares_) {
        address vaultAddr = address(chains[chainIndex_].vaultV2);
        uint256 slotData_ = uint256(vm.load(vaultAddr, bytes32(uint256(SHARES_STORAGE_SLOT))));
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

    function getVaultAssetBalanceByIndex(uint256 chainIndex_) external view returns (uint256 assetBalance_) {
        address vaultAddr = address(chains[chainIndex_].vaultV2);
        assetBalance_ = getLPTokenBalance(vaultAddr);
    }

    /*function getVaultExpectedUnwithdrawnAssetByIndex(uint256 chainIndex_)
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
    }*/

    function getVaultExpectedDepositsByIndex(uint256 chainIndex_) external view returns (uint256 depositedAsset_) {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            depositedAsset_ += ghost_deposits[chainIndex_][i_].deposit;
        }
    }

    function getVaultExpectedWithdrawlsByIndex(uint256 chainIndex_) external view returns (uint256 withdrawnAsset_) {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (ghost_deposits[chainIndex_][i_].withdrawn == true) {
                withdrawnAsset_ += ghost_deposits[chainIndex_][i_].deposit;
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

    function getInitialAssetByChainIndex(uint256 chainIndex_) external view returns (uint256 initialAsset_) {
        initialAsset_ = chains[chainIndex_].actors.length * ACTOR_INITIAL_ASSET;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Actor-wise View Functions ---------------------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//
    function getActorsInitialAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory initialAsset_)
    {
        uint256 numberOfActors_ = chains[chainIndex_].actors.length;
        initialAsset_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            initialAsset_[i_] = ACTOR_INITIAL_ASSET;
        }
    }

    function getActorsAssetByChainIndex(uint256 chainIndex_) external view returns (uint256[] memory actorAsset_) {
        uint256 numberOfActors_ = chains[chainIndex_].actors.length;
        actorAsset_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            actorAsset_[i_] = getLPTokenBalance(chains[chainIndex_].actors[i_]);
        }
    }

    function getActorsUnwithdrawnAssetByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory actorDeposits_)
    {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        uint256 numberOfActors_ = chains[chainIndex_].actors.length;
        actorDeposits_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            for (uint256 j_ = 0; j_ < numberOfDeposits_; j_++) {
                if (ghost_deposits[chainIndex_][j_].depositor == chains[chainIndex_].actors[i_]) {
                    if (ghost_deposits[chainIndex_][j_].withdrawn == false) {
                        actorDeposits_[i_] += ghost_deposits[chainIndex_][j_].deposit;
                    }
                }
            }
        }
    }

    function getActorsRewardsByChainIndex(uint256 chainIndex_) external view returns (uint256[] memory actorRewards_) {
        uint256 numberOfActors_ = chains[chainIndex_].actors.length;
        actorRewards_ = new uint256[](numberOfActors_);
        for (uint256 i_ = 0; i_ < numberOfActors_; i_++) {
            address actor_ = chains[chainIndex_].actors[i_];
            actorRewards_[i_] = chains[chainIndex_].rewardToken.balanceOf(actor_);
        }
    }

    function getActorsExpectedRewardsByChainIndex(uint256 chainIndex_)
        external
        view
        returns (uint256[] memory actorExpectedRewards_)
    {
        uint256 numberOfActors_ = chains[chainIndex_].actors.length;
    }

    //------------------------------------------------------------------------------------------------------------------------------------//
    // Internal Vault Simulation Functions -----------------------------------------------------------------------------------------------//
    //------------------------------------------------------------------------------------------------------------------------------------//

    function _addDepositToList(uint256 chainIndex_, address depositor_, uint256 deposit_, uint256 monthsLocked_)
        internal
    {
        Deposit memory newDeposit;
        newDeposit.depositor = depositor_;
        newDeposit.deposit = deposit_;
        newDeposit.shares = deposit_ * (monthsLocked_ / 6);
        newDeposit.expireTime = block.timestamp + monthsLocked_ * SECONDS_IN_30_DAYS;
        newDeposit.withdrawn = false;
        ghost_deposits[chainIndex_].push(newDeposit);
    }

    function _setDepositAsWithdrawn(uint256 chainIndex_, address depositor_) internal {
        uint256 numberOfDeposits_ = ghost_deposits[chainIndex_].length;
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            if (ghost_deposits[chainIndex_][i_].depositor == depositor_) {
                if (block.timestamp > ghost_deposits[chainIndex_][i_].expireTime) {
                    ghost_deposits[chainIndex_][i_].withdrawn = true;
                }
            }
        }
    }

    function _addRewardsClaimedToList(uint256 chainIndex_, address depositor_, uint256 claimedRewards_) internal {
        Withdrawl memory newWithdrawl;
        newWithdrawl.chainIndex = chainIndex_;
        newWithdrawl.claimedRewards = claimedRewards_;
        newWithdrawl.expectedRewards = _getExpectedRewards(depositor_);
        ghost_withdrawls[depositor_].push(newWithdrawl);
    }

    function _getExpectedRewards(address depositor_) internal returns (uint256 expectedRewards_) { }

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
            chains.push(newChain);

            /*chains_random.push(Random_struct({
                vaultV2 : VaultV2(vaultsv2_[i_]),
                rewardToken : IERC20(rewardTokens_[i_]),
                actors: new address[](0),
                ghost_deposits_random : new  Deposit[](0)
            }));

            Random_struct memory a;
            a.ghost_deposits_random = new Deposit[](1);
            a.ghost_deposits_random.push(Deposit({
                actor: address(0),
                deposit: 1,
                shares: 1,
                expireTime:0,
                withdrawn : false
            }));
            chains_random.push(a);*/
        }
    }

    function _deployActors(uint256 seed_) internal {
        uint256 numberOfActors_ = Lib.getRandomNumberInRange(MIN_ACTORS_PER_VAULT, MAX_ACTORS_PER_VAULT, seed_);
        for (uint256 j = 0; j < numberOfActors_; j++) {
            address actor_ = address(uint160(seed_ % type(uint160).max));
            if (_invalidActorAdresses[actor_]) actor_ = address(1);
            giveLPtokens(actor_, ACTOR_INITIAL_ASSET);
            chains[_chainIndex].actors.push(actor_);
            seed_ = seed_ / 3;
        }
        assert(Lib.repeatedEntries(chains[_chainIndex].actors) == false);
    }

    function _getChainIndex(uint256 seed_) internal view returns (uint256 chainIndex_) {
        chainIndex_ = seed_ % chains.length;
    }

    function _getActor(uint256 seed_) internal view returns (address actor_) {
        uint256 actorsSize_ = chains[_chainIndex].actors.length;
        actor_ = chains[_chainIndex].actors[seed_ % actorsSize_];
    }
}
