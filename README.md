# Limit Order Bot Vyper for Uniswap V3

## Dependencies

[Brownie](https://github.com/eth-brownie/brownie)

[Ganache](https://github.com/trufflesuite/ganache)

## Add account

```sh
brownie accounts new deployer_account
```

## Deploy on mainnet
Create `scripts/deploy_*.py` and Compass-EVM contract address.
### - Uniswap V3 Limit order bot
```sh
brownie run scripts/deploy_uniswap_v3.py --network mainnet
```

## Read-Only functions

### compass

| Key        | Type    | Description                                |
| ---------- | ------- | ------------------------------------------ |
| **Return** | address | Returns compass-evm smart contract address |

### admin

| Key        | Type    | Description              |
| ---------- | ------- | ------------------------ |
| **Return** | address | Returns an admin address |

### deposits

| Key        | Type    | Description                           |
| ---------- | ------- | ------------------------------------- |
| *arg0*     | uint256 | Deposit Id to get Deposit information |
| **Return** | Deposit | Deposit information                   |


## State-Changing functions

### deposit

Deposit a token with its amount with an expected token address and amount. This is run by users.

| Key     | Type    | Description                             |
| ------- | ------- | --------------------------------------- |
| token0  | address | Deposit token address                   |
| amount  | uint256 | Deposit token amount                    |
| token1  | address | Expected token address                  |
| fee     | uint24  | Deposit pool on Uniswap V3              |
| to_tick | int24   | Uniswap V3 tick of expected token price |

### cancel

Cancels an order.

| Key     | Type    | Description                           |
| ------- | ------- | ------------------------------------- |
| tokenId | uint256 | Uniswap V3 liquidity NFT Id to cancel |

### multiple_cancel

Cancels multiple orders.

| Key      | Type      | Description                                  |
| -------- | --------- | -------------------------------------------- |
| tokenIds | uint256[] | Uniswap V3 liquidity NFT Ids array to cancel |

### withdraw

Swap and send the token to the depositor.

| Key     | Type    | Description                                                   |
| ------- | ------- | ------------------------------------------------------------- |
| tokenId | uint256 | Uniswap V3 liquidity NFT Id to swap and send to the depositor |

### multiple_withdraw

Swap and send multiple tokens to the depositor.

| Key      | Type      | Description                                                       |
| -------- | --------- | ----------------------------------------------------------------- |
| tokenIds | uint256[] | Uniswap V3 liquidity NFT Ids array to swap and send to depositors |

### update_admin

Update admin address.

| Key       | Type    | Description       |
| --------- | ------- | ----------------- |
| new_admin | address | New admin address |

### update_compass

Update Compass-EVM address.

| Key         | Type    | Description             |
| ----------- | ------- | ----------------------- |
| new_compass | address | New compass-evm address |

## Struct

### Deposit

| Key       | Type    | Description                       |
| --------- | ------- | --------------------------------- |
| pool      | address | Uniswap V3 liquidity pool address |
| token0    | address | Token address to trade            |
| token1    | address | Token address to receive          |
| from_tick | int24   | Uniswap V3 tick on deposit price  |
| to_tick   | int24   | Uniswap V3 tick on expected price |
| depositor | address | Depositor address                 |
| token_id  | uint256 | Uniswap V3 liquidity NFT token Id |
