# Katana Vault Bridge — Mathematical Invariants

[Katana Immunefi scope](https://immunefi.com/bug-bounty/katana/scope/) · [Upstream protocol](https://github.com/agglayer/vault-bridge)

The five stateful flows execute 256 generated actions and evaluate the formulas below after every action. This is a public test extract; it does not disclose vulnerability details.

## 1. Native converter / bridge

File: `test/invariant/KatanaVaultBridgeStatefulInvariant.t.sol`  
Test: `testFuzz_statefulConvertDeconvert(uint256)`

Notation: $B_t$ = converter backing, $U_t(x)$ = underlying balance, $S_t$ = custom-token supply, $T_t(x)$ = custom-token balance, $C$ = converter, $H$ = handler.

- Technical — `invariant_nativeBackingMatchesTokenBalance`

  $$B_t = U_t(C)$$

- Technical — `invariant_converterNeverHoldsLessThanBacking`

  $$U_t(C) \ge B_t$$

- Technical — `invariant_handlerBalanceIsBoundedBySupply`

  $$T_t(H) \le S_t$$

- Technical — `invariant_maxDeconvertCannotExceedBalance`

  $$\operatorname{maxDeconvert}_t(H) \le T_t(H)$$

- Business — `invariant_customSupplyMatchesBacking`

  $$S_t = B_t$$

- Business — `invariant_oneToOneConversion`

  $$B_t = S_t$$

## 2. Vault bridge token

File: `test/invariant/VaultBridgeTokenStatefulInvariant.t.sol`  
Test: `testFuzz_statefulVaultFlow(uint256)`

Notation: $R_t$ = reserved assets, $A_t$ = total assets, $S_t$ = total vault shares, $V_t(x)$ = share balance, $H$ = handler, $Q$ = recipient.

- Technical — `invariant_reserveBounded`

  $$R_t \le A_t$$

- Technical — `invariant_handlerBalanceBounded`

  $$V_t(H) \le S_t$$

- Business — `invariant_assetsCoverSupply`

  $$A_t \ge S_t$$

- Business — `invariant_supplyConserved`

  $$S_t = V_t(H) + V_t(Q)$$

## 3. Custom token

File: `test/invariant/CustomTokenStatefulInvariant.t.sol`  
Test: `testFuzz_statefulCustomTokenFlow(uint256)`

Notation: $S_t$ = total supply, $a_t$ and $b_t$ = balances of actors A and B, $S_0$ = seeded supply.

- Technical + business — `invariant_supplyConserved`

  $$S_t = a_t + b_t$$

- Technical — `invariant_actorBalancesBounded`

  $$\forall x \in \{a,b\}: \; x_t \le S_t$$

- Business — `invariant_supplyStable`

  $$S_t = S_0$$

## 4. Migration manager

File: `test/invariant/MigrationManagerStatefulInvariant.t.sol`  
Test: `testFuzz_statefulMigrationFlow(uint256)`

Notation: $P_t$ = configured `(vbToken, underlyingToken)` pair, $G_t$ = configured bridge, $L$ = `NETWORK_ID_L2`.

- Technical — `invariant_configurationIsStable`

  $$P_t(L,\mathrm{nativeConverter}) = P_0(L,\mathrm{nativeConverter})$$

- Technical — `invariant_bridgeOnlyDispatchesConfiguredPair`

  $$G_t = G_0$$

- Business — `invariant_completedMessagesUseConfiguredNetwork`

  $$\mathrm{completeCalls}_t > 0 \Rightarrow \mathrm{lastOriginNetwork}_t = L$$

## 5. Agglayer custom token

File: `test/invariant/GenericCustomTokenAgglayerStatefulInvariant.t.sol`  
Test: `testFuzz_statefulAgglayerTokenFlow(uint256)`

Notation: $S_t$ = token supply, $h_t$ and $q_t$ = handler/recipient balances, $G_t$ = bridge, $N_t$ = native converter.

- Technical — `invariant_authoritiesRemainConfigured`

  $$(G_t,N_t) = (G_0,N_0)$$

- Technical — `invariant_balancesBoundedBySupply`

  $$\forall x \in \{h,q\}: \; x_t \le S_t$$

- Business — `invariant_supplyConserved`

  $$S_t = h_t + q_t$$

**Stateful total: 5 flow tests and 19 public invariant functions.**

## Stateless fuzz tests

File: `test/fuzz/GenericVaultBridgeTokenFuzz.t.sol`

Tests:

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

Properties:

- Minimum deposit: $0 < d < D_{min} \Rightarrow$ exact deposit reverts; non-exact returns $d$.
- Maximum deposit: $d > D_{max} \Rightarrow$ exact deposit reverts; non-exact returns $d-D_{max}$.
- Slippage limit: $m = \left\lfloor d(1-\sigma)\right\rfloor$ and `mintedShares` must satisfy

  $$\mathrm{mintedShares} \ge m$$

- Excess slippage: `mintedShares < m` reverts in exact mode and returns all $d$ in non-exact mode.
- Withdrawal: $s_{burned} \le d + \left\lfloor 0.01d\right\rfloor$; otherwise exact withdrawal reverts.
- Reserve percentage: $0 \le p \le 10^{18} \Rightarrow \mathrm{storedPercentage}=p$.

**Stateless total: 11 fuzz tests.**

## Recorded results

```text
Stateful:  24 passed, 0 failed
Stateless: 11 passed, 0 failed
```

Private findings are reported through bug-bounty channels and published only after a fix and responsible disclosure.
