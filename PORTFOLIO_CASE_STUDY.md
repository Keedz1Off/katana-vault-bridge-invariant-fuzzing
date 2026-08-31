# Katana Vault Bridge — Invariant Fuzzing

> Portfolio case study. Tests run against local mocks; no production vulnerability is claimed.

![Stateful versus stateless fuzzing](docs/assets/stateful-vs-stateless.png)

This repository contains the actual tests and invariants used for the Katana vault/bridge flow. There are two layers:

- **Stateful:** a handler executes a sequence of actions and checks invariants after each action.
- **Stateless:** each fuzz case starts from a fresh fixture and checks one boundary or operation.

## Stateful suites

### `test/invariant/KatanaVaultBridgeStatefulInvariant.t.sol`

Test: `testFuzz_statefulConvertDeconvert(uint256)`.

Flow: `convert → deconvert → round-trip → invalid input → interleaved conversion → bridge-out → extreme`.

Actions: `actionConvert`, `actionDeconvert`, `actionRoundTrip`, `actionInvalidInputs`, `actionInterleaved`, `actionBridgeOut`, `actionExtreme`.

Invariants:

- Technical — `invariant_nativeBackingMatchesTokenBalance`: `backing = balanceOf(converter)`.
- Technical — `invariant_converterNeverHoldsLessThanBacking`: `tokenBalance(converter) ≥ backing`.
- Technical — `invariant_handlerBalanceIsBoundedBySupply`: `balance(handler) ≤ totalSupply`.
- Technical — `invariant_maxDeconvertCannotExceedBalance`: `maxDeconvert(handler) ≤ balance(handler)`.
- Business — `invariant_customSupplyMatchesBacking`: `totalSupply(customToken) = backing`.
- Business — `invariant_oneToOneConversion`: `customTokenSupply = secondaryBacking`.

### `test/invariant/VaultBridgeTokenStatefulInvariant.t.sol`

Test: `testFuzz_statefulVaultFlow(uint256)`.

Flow: `deposit → mint → redeem → withdraw → round-trip → transfer → invalid → extreme`.

Actions: `actionDeposit`, `actionMint`, `actionRedeem`, `actionWithdraw`, `actionRoundTrip`, `actionTransfer`, `actionInvalid`, `actionExtreme`.

Invariants:

- Technical — `invariant_reserveBounded`: `reservedAssets ≤ totalAssets`.
- Technical — `invariant_handlerBalanceBounded`: `balance(handler) ≤ totalSupply`.
- Business — `invariant_assetsCoverSupply`: `totalAssets ≥ totalSupply`.
- Business — `invariant_supplyConserved`: `totalSupply = balance(handler) + balance(recipient)`.

### `test/invariant/CustomTokenStatefulInvariant.t.sol`

Test: `testFuzz_statefulCustomTokenFlow(uint256)`.

Flow: `transfer → approve/transferFrom → reverse transfer → round-trip → invalid → extreme`.

Actions: transfer, allowance/pull, reverse transfer, round-trip, invalid and extreme-value actions.

Invariants:

- Technical + Business — `invariant_supplyConserved`: `totalSupply = balance(actorA) + balance(actorB)`.
- Technical — `invariant_actorBalancesBounded`: `balance(actorA), balance(actorB) ≤ totalSupply`.
- Business — `invariant_supplyStable`: `totalSupply = INITIAL_SUPPLY`.

### `test/invariant/MigrationManagerStatefulInvariant.t.sol`

Test: `testFuzz_statefulMigrationFlow(uint256)`.

Flow: `complete message → wrap gas → invalid origin → invalid network → malformed message → extreme`.

Invariants:

- Technical — `invariant_configurationIsStable`: configured `(vbToken, underlyingToken)` never changes.
- Technical — `invariant_bridgeOnlyDispatchesConfiguredPair`: `agglayerBridge = configuredBridge`.
- Business — `invariant_completedMessagesUseConfiguredNetwork`: completed messages use `originNetwork = NETWORK_ID_L2`.

### `test/invariant/GenericCustomTokenAgglayerStatefulInvariant.t.sol`

Test: `testFuzz_statefulAgglayerTokenFlow(uint256)`.

Flow: `bridge mint → native mint → transfer → bridge burn → native burn → round-trip → already-minted/zero-address → extreme → invalid`.

Invariants:

- Technical — `invariant_authoritiesRemainConfigured`: bridge and native-converter addresses remain fixed.
- Technical — `invariant_balancesBoundedBySupply`: each tracked balance `≤ totalSupply`.
- Business — `invariant_supplyConserved`: `totalSupply = balance(handler) + balance(recipient)`.

Together these five suites contain **5 stateful flow tests and 19 invariant functions**.

## Stateless fuzz suite

File: `test/fuzz/GenericVaultBridgeTokenFuzz.t.sol`

Exact tests:

1. `testFuzz_depositIntoYieldVault_minimumDepositNotMetAndDoNotIgnoreMinimumDeposit_revert`
2. `testFuzz_depositIntoYieldVault_minimumDepositNotMet_nonExact`
3. `testFuzz_depositIntoYieldVault_exceedsMaxDeposit_revert`
4. `testFuzz_depositIntoYieldVault_exceedsMaxDeposit_nonExact`
5. `testFuzz_depositIntoYieldVault_slippageFailure_revert`
6. `testFuzz_depositIntoYieldVault_slippageFailure_nonExact`
7. `testFuzz_depositIntoYieldVault_success`
8. `testFuzz_depositIntoYieldVault_successNoSlippage`
9. `testFuzz_withdrawFromYieldVault_revert`
10. `testFuzz_withdrawFromYieldVault`
11. `testFuzz_setMinimumReservePercentage`

Main slippage property:

```text
actualShares ≥ assets × (1 − allowedSlippage)
```

The exact branch must revert on a violated bound and preserve balances. The non-exact branch returns the unprocessed amount.

Additional unit-level fuzz tests are in:

- `test/unit/primary-chain/VaultBridgeTokenTest.t.sol`
- `test/unit/primary-chain/MigrationManagerTest.t.sol`
- `test/unit/secondary-chain/CustomTokenTest.t.sol`
- `test/unit/secondary-chain/agglayer/GenericCustomTokenAgglayer.t.sol`
- `test/unit/secondary-chain/layerzero/NonDefaultMintBurnOftAdapter.t.sol`

## Results from this working tree

```text
Stateful: test/invariant/*.t.sol, --fuzz-runs 20  → 24 passed, 0 failed
Stateless: test/fuzz/*.t.sol, --fuzz-runs 1000   → 11 passed, 0 failed
```

These are local smoke results, not proof that the protocol is bug-free.

## Reproduce

```bash
export PATH="$HOME/.foundry/bin:$PATH"

# Stateful handlers and invariants
forge test --match-path 'test/invariant/*.t.sol' --fuzz-runs 1000 -v --summary

# Stateless boundary tests
forge test --match-path 'test/fuzz/*.t.sol' --fuzz-runs 10000 -v --summary
```
