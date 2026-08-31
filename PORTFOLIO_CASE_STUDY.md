# Katana Vault Bridge — Bug-Bounty Fuzzing Portfolio

[Katana Immunefi bug-bounty scope](https://immunefi.com/bug-bounty/katana/scope/) · [Source protocol](https://github.com/agglayer/vault-bridge)

This repository shows what I tested: real Foundry stateful/stateless fuzz tests and the invariants checked. It does **not** publish vulnerability details or claim a finding.

Confirmed findings are reported privately through the relevant bug-bounty platform. A public write-up is released only after the fix and responsible-disclosure approval.

## Stateful tests and invariants

### `test/invariant/KatanaVaultBridgeStatefulInvariant.t.sol`

Test: `testFuzz_statefulConvertDeconvert(uint256)`

Flow: `convert → deconvert → round-trip → invalid → interleaved → bridge-out → extreme`

- Technical: `invariant_nativeBackingMatchesTokenBalance` — `backing = balanceOf(converter)`
- Technical: `invariant_converterNeverHoldsLessThanBacking` — `tokenBalance(converter) ≥ backing`
- Technical: `invariant_handlerBalanceIsBoundedBySupply` — `balance(handler) ≤ totalSupply`
- Technical: `invariant_maxDeconvertCannotExceedBalance` — `maxDeconvert(handler) ≤ balance(handler)`
- Business: `invariant_customSupplyMatchesBacking` — `totalSupply(customToken) = backing`
- Business: `invariant_oneToOneConversion` — `customTokenSupply = secondaryBacking`

### `test/invariant/VaultBridgeTokenStatefulInvariant.t.sol`

Test: `testFuzz_statefulVaultFlow(uint256)`

Flow: `deposit → mint → redeem → withdraw → round-trip → transfer → invalid → extreme`

- Technical: `invariant_reserveBounded` — `reservedAssets ≤ totalAssets`
- Technical: `invariant_handlerBalanceBounded` — `balance(handler) ≤ totalSupply`
- Business: `invariant_assetsCoverSupply` — `totalAssets ≥ totalSupply`
- Business: `invariant_supplyConserved` — `totalSupply = balance(handler) + balance(recipient)`

### `test/invariant/CustomTokenStatefulInvariant.t.sol`

Test: `testFuzz_statefulCustomTokenFlow(uint256)`

Flow: `transfer → approve/transferFrom → reverse → round-trip → invalid → extreme`

- Technical + business: `invariant_supplyConserved` — `totalSupply = balance(actorA) + balance(actorB)`
- Technical: `invariant_actorBalancesBounded` — `balance(actorA), balance(actorB) ≤ totalSupply`
- Business: `invariant_supplyStable` — `totalSupply = INITIAL_SUPPLY`

### `test/invariant/MigrationManagerStatefulInvariant.t.sol`

Test: `testFuzz_statefulMigrationFlow(uint256)`

Flow: `complete message → wrap gas → invalid origin → invalid network → malformed → extreme`

- Technical: `invariant_configurationIsStable` — configured `(vbToken, underlyingToken)` is unchanged
- Technical: `invariant_bridgeOnlyDispatchesConfiguredPair` — `agglayerBridge = configuredBridge`
- Business: `invariant_completedMessagesUseConfiguredNetwork` — `originNetwork = NETWORK_ID_L2`

### `test/invariant/GenericCustomTokenAgglayerStatefulInvariant.t.sol`

Test: `testFuzz_statefulAgglayerTokenFlow(uint256)`

Flow: `bridge mint → native mint → transfer → bridge burn → native burn → round-trip → duplicate/invalid → extreme`

- Technical: `invariant_authoritiesRemainConfigured` — bridge and native-converter addresses are fixed
- Technical: `invariant_balancesBoundedBySupply` — each tracked balance `≤ totalSupply`
- Business: `invariant_supplyConserved` — `totalSupply = balance(handler) + balance(recipient)`

**Stateful total: 5 flow tests, 19 public invariant functions.**

## Stateless tests

File: `test/fuzz/GenericVaultBridgeTokenFuzz.t.sol`

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

Property: `actualShares ≥ assets × (1 − allowedSlippage)`.

**Stateless total: 11 fuzz tests.**

## Verified local results

```text
Stateful: 24 passed, 0 failed
Stateless: 11 passed, 0 failed
```

These are local-mock results, not a guarantee that the live protocol is bug-free.
