## Stablecoin

1. (Relative Stability) Anchored or Pegged --> $1.00
   1. Chainlink Price feed
   2. Seta function to exchange: ETH & BTC --> $1.00
2. Stability Mechanism (Minting): Algorithmic (Decentralized)
   1. People can only mint stablecoin with enough collateral (coded)
3. Collateral: Exogenous (Crypto)
   1. wETH
   2. wBTC

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
