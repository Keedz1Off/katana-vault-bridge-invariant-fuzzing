# Katana Vault Bridge — Bug-Bounty Fuzzing Portfolio

[![Immunefi scope](https://img.shields.io/badge/Immunefi-Katana%20scope-7b61ff)](https://immunefi.com/bug-bounty/katana/scope/)

Foundry tests for the Katana Vault Bridge flow. This public repository shows what I tested and the invariants I checked; it does not disclose private vulnerability details.

## Disclosure policy

Confirmed findings are reported privately through the applicable bug-bounty platform. A public write-up is published only after the fix and responsible-disclosure approval. A passing local test is not a claim that the live protocol is bug-free.

## What is included

- **Stateful fuzzing:** 5 handler flows, 19 public invariants, and checks after every generated action.
- **Stateless fuzzing:** 11 boundary tests for deposits, withdrawals, slippage and reserve limits.
- **Technical invariants:** balances, supply bounds, permissions and configuration.
- **Business invariants:** backing/supply equality, conservation, 1:1 conversion and valid message origin.
- Local mocks only; no live-chain execution or private keys.

The exact test names, flows, formulas and results are in [`PORTFOLIO_CASE_STUDY.md`](PORTFOLIO_CASE_STUDY.md).

## Results recorded here

```text
Stateful suites:  24 passed, 0 failed
Stateless suite:  11 passed, 0 failed
```

## Run locally

```bash
export PATH="$HOME/.foundry/bin:$PATH"

# Stateful handlers and invariants
forge test --match-path 'test/invariant/*.t.sol' --fuzz-runs 1000 -v --summary

# Stateless boundary tests
forge test --match-path 'test/fuzz/*.t.sol' --fuzz-runs 10000 -v --summary
```

## Links

- [Katana Immunefi scope](https://immunefi.com/bug-bounty/katana/scope/)
- [Upstream Vault Bridge source](https://github.com/agglayer/vault-bridge)
- [Portfolio case study](PORTFOLIO_CASE_STUDY.md)
