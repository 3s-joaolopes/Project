
This project (developed using the Foundry framework) consists on the creation of a vault which stores tokens locked for a certain amount of time and distributes rewards to depositors.

### Vault

- The vault accepts deposits of [Uniswap LP tokens](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2ERC20.sol) and locks them for a period (6, 12, 24 or 48 months)
- Depositors get rewards based on the deposited amount and lock period. These rewards take the form of ERC20 tokens.
- Depositors can claim their rewards at any time and can witdraw their deposit after the lock period is over
    - after the lock period of the LPs, the position stops accruing rewards.
- The vault is under a proxy, so the implemtation can be upgraded at anytime by the creators.

### OFToken

- The token implements the [Layer Zero Omnichain](https://medium.com/layerzero-official/layerzero-an-omnichain-interoperability-protocol-b43d2ae975b6) OFT20 functionality
- Can only be minted by the Vault
- Has a fixed issuance rate of 10^10 tokens per year

### Vault v2

- The vault v2 implements Layer Zero’s functionality: [Omnichain](https://medium.com/layerzero-official/layerzero-an-omnichain-interoperability-protocol-b43d2ae975b6)
    - to distribute the rewards, it uses the tokens deposited in all the Vaults in all chains that implement the Omnichain functionality.
    - it is only possible to withdraw or claim rewards from the same chain where the deposit was made.

### Implementation logic

To accurately and efficiently distribute rewards, the vault allows for 3 core operations: deposit, withdrawal and claiming rewards.

This deposits are stores as a linked list, sorted by the expiration time of every deposit.

A deposit is represented as a struct containing:

- address depositor - addres of the depositor
- uint128 deposit - initial deposit amount
- uint128 shares - number of shares minted (amount deposited x multiplier)
    - this multiplier is equal to (monthsLocked_ / 6)
- uint128 rewardsPerShare - amount of rewards per share at the start of the deposit
- uint64 expireTime - locktime expiration date (in seconds)
- uint64 nextId - pointer to the next entry in the list

Whenever a user makes a **deposit, withdrawal** or **claims rewards,** the vault starts by checking the sorted list for deposits that have expired. 
If an expired deposit is found, the system:
    - updates the rewards per share
    - adds the claimable rewards of the expired deposit to pendingRewards
    - adds the initial deposit to the withdrawableLPtokens so it can be withdrawn
    - burns the corresponding shares (reducing the total number of outstanding shares)
    - removes this element from the deposit list

### Build

Build the contracts:

```sh
$ make build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ make clean
```

### Compile

Compile the contracts:

```sh
$ make build
```

### Test

To run all tests execute the following commad:

```
make tests
```

Alternatively, you can run specific tests as detailed in this [guide](https://book.getfoundry.sh/forge/tests).

# About Us
[Three Sigma](https://threesigma.xyz/) is a venture builder firm focused on blockchain engineering, research, and investment. Our mission is to advance the adoption of blockchain technology and contribute towards the healthy development of the Web3 space.

If you are interested in joining our team, please contact us [here](mailto:info@threesigma.xyz).

---

<p align="center">
  <img src="https://threesigma.xyz/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fthree-sigma-labs-research-capital-white.0f8e8f50.png&w=2048&q=75" width="75%" />
</p>
