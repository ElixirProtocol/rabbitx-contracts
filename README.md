<img align="right" width="150" height="150" top="100" style="border-radius:99%" src="https://i.imgur.com/H5aZQMA.jpg">

# Elixir <> RabbitX Contracts • [![CI](https://github.com/ElixirProtocol/rabbitx-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/ElixirProtocol/rabbitx-contracts/actions/workflows/test.yml)

## Background

This project contains the smart contracts for the Elixir Protocol integration on top of Rabbitx.

See the [documentation](docs/docs.md), the [Elixir Protocol documentation](https://docs.elixir.finance/), and the [RabbitX documentation](https://docs.rabbitx.io/) for more information.

## Deployments

<table>
</table>

## Documentation

You can find the technical documentation and references of the smart contracts [here](docs/docs.md). 

## Usage

You will need a copy of [Foundry](https://github.com/foundry-rs/foundry) installed before proceeding. See the [installation guide](https://github.com/foundry-rs/foundry#installation) for details.

To build the contracts:

```sh
git clone https://github.com/ElixirProtocol/rabbitx-contracts.git
cd rabbitx-contracts
forge install
forge build
```

### Run Tests

In order to run unit tests, run:

```sh
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="deep" forge test
```

### Run Slither

After [installing Slither](https://github.com/crytic/slither#how-to-install), run:

```sh
slither src/
```

### Check coverage

To check the test coverage, run:

```sh
forge coverage
```

### Update Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

### Deploy Contracts

In order to deploy the contracts, set the relevant constants in the respective chain script, and run the following command(s):

```sh
forge script script/deploy/DeploySepolia.s.sol:DeploySepolia -vvvv --fork-url RPC --broadcast --slow
```
