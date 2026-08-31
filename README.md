# Katana Vault Bridge — Bug-Bounty Fuzzing

[Katana Immunefi scope](https://immunefi.com/bug-bounty/katana/scope/) · [Upstream protocol](https://github.com/agglayer/vault-bridge)

Portfolio extract of the Foundry tests I ran against the vault/bridge flow.

- Stateful: 5 flows, 19 invariants.
- Stateless: 11 fuzz tests.
- Local mocks only.
- No vulnerability details are published here. Confirmed findings are reported privately and published only after a fix and disclosure approval.

Results recorded before extracting the portfolio files:

```text
Stateful:  24 passed, 0 failed
Stateless: 11 passed, 0 failed
```

Exact test names, flows and formulas: [`PORTFOLIO_CASE_STUDY.md`](PORTFOLIO_CASE_STUDY.md)
