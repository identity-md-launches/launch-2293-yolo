# Yolo (YOLO)

Yolo is an immutable, fixed-supply ERC-20 token. Its constructor mints the entire
supply to the immediate deployer in one mint operation.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/Yolo.sol:Yolo` |
| Constructor arguments | None (`[]`) |
| Name | `Yolo` |
| Symbol | `YOLO` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Initial recipient | Constructor `msg.sender` |
| Target chain | Ethereum, chain ID `1` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

`INITIAL_SUPPLY` is the named constant for the supply in base units. Metadata
and supply are fixed by the code; no deployment parameters or outside services
need to be configured.

## Behavior and assumptions

The implementation extends the vendored OpenZeppelin ERC-20 without modifying
its transfer or allowance logic. Transfers move the exact specified amount:
there are no taxes, fees, rebases, transfer limits, exemptions or callbacks.
Successful transfers and approvals return `true`; invalid operations revert
with ERC-6093 custom errors.

Zero-value transfers are permitted and emit `Transfer`. Transfers to the zero
address and approvals to the zero address revert. Self-transfers preserve the
balance and still require sufficient funds. `approve` replaces the existing
allowance; zero revokes it. `transferFrom` spends finite allowances, including
when sending tokens back to their holder. A maximum `uint256` allowance stays
unchanged when spent. Failed operations roll back both balances and allowances.
Explicit approvals emit `Approval`; allowance spending does not emit a new
`Approval` event in the vendored implementation.

There is no owner, privileged role, mint function, burn function, pause,
blacklist, seizure, proxy, upgrade path, initializer or rescue function.
The inherited mint and burn helpers are internal; only the constructor calls
the mint helper. No function can change total supply after construction.
The token does not call external contracts.

## Deployment and operational responsibilities

Build from this repository root. The deployable artifact is
`out/Yolo.sol/Yolo.json`; it contains creation bytecode with no external library
linking requirements. Use the creation bytecode without appended constructor
arguments. The constructor needs no ETH and makes no external calls.

During an IdentityMD custom-token launch, the deploying factory receives all
`10^27` base units, because it is `msg.sender`. The transaction initiator does
not receive them directly. A direct deployment would instead mint to its direct
deployer. The token grants neither deployer any special rights after minting.

The launch infrastructure is responsible for distribution and liquidity. The
specified allocation is 10% to the launch distributor, 50% to liquidity, and
40% to the requester's remainder recipient. These transfers are performed by
the factory, not by this token's constructor. No application contracts are
required. The separate manifest step supplies the launch configuration;
this project does not include `launch.json` or broadcast transactions.

After launch, there are no owner settings or maintenance calls. The launch
operator should verify the deployed source with the pinned build settings,
confirm the metadata and total supply, and check the constructor mint and
subsequent distribution events. Distribution and pool admission remain the
launch infrastructure's responsibility.

Holders control their balances and allowances. They should grant only needed
allowances and revoke unused ones. Replacing a nonzero allowance has the usual
ERC-20 transaction-ordering risk: a spender may spend the old approval before
the replacement confirms. Revoke and confirm before granting a new amount
when appropriate. Avoid sending tokens to this token contract or to a
recipient that cannot return them: there is no recovery authority. Ordinary
ETH payments revert, and forcibly sent ETH cannot be recovered.

## Build and verification

Install Foundry and make Solidity `0.8.26` available in its compiler cache.
All Solidity dependencies are present as ordinary source files under `lib/`;
no package installation, RPC, environment secrets or network access is needed
to build or test once the compiler is installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2a53d6cb7bc898ee5c7cac318542d0bb3287c60f082439a4b6232b5ffa99504e forge test
forge fmt --check
```

The test suite covers metadata, the single constructor mint and its event,
direct/factory/CREATE2 deployment, exact distribution and claim transfers,
transfer events, zero/full/self transfers, finite/infinite/revoked approvals,
unauthorized spending, insufficient funds, invalid addresses, rollback on
failure, rejected administrative calls and deployment bytecode constraints.
Fuzz tests cover amounts, recipients and allowance boundaries. Stateful
invariants compare balances and allowances to an independent ledger across
random sequences of transfers, approvals and delegated transfers.

The default test settings are 512 runs per fuzz test and 128 sequences of
64 calls per invariant. Tests use local fixtures, require no runtime
configuration and do not read or modify environment variables.

Local validation passed with Solidity `0.8.26`: `forge build`, `forge test`
with the seed above, and `forge fmt --check`. All 35 unit/fuzz tests passed;
both stateful invariants passed across 8,192 handler calls. The compiled
runtime is 1,752 bytes, with no library links. All 36 vendored files matched
their recorded SHA-256 digests.

Source review checked supply reachability, allowance authorization and failure
rollback, zero-address handling, event behavior, and the absence of external
calls or privileged entry points. Slither and Mythril were not run.

The distribution test checks token accounting using local actors; it does not
simulate a Uniswap pool. The supplied protected launch tests depend on the
separate launch harness, manifest-derived environment and Uniswap dependencies;
that full integration is performed by the launch verifier. Local results are
not a substitute for that integration or independent security review.

## Dependencies and licensing

Production code uses the ERC-20 dependency closure from
[OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2),
commit `dbb6104ce834628e473d2173bbc9d47f81a9eec3`, under its MIT license.
Tests use the source tree of
[forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7),
commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505`, under its MIT/Apache-2.0
licenses. The upstream license files are included beside each dependency.

`dependencies.lock.json` records the versions, commits and SHA-256 digest of
every vendored file. Dependencies are unmodified source files, not submodules.
Project-authored Solidity files are MIT licensed; see `LICENSE`.
