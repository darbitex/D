# Auditor: Gemini
# Round: R1
# Verdict: GREEN

## Findings

### HIGH
- None found. Core SP, fee, and liquidation math remains byte-identical to the previously audited and proven D Aptos mainnet deployment.

### MEDIUM
- None found.

### LOW
- [LOW-1: Missing Oracle Confidence Band] — Supra's native push oracle (`supra_oracle_storage::get_price`) does not expose a confidence interval or spread metric, unlike Pyth. Consequently, D Supra cannot natively reject wide-spread or highly uncertain readings during extreme volatility.
  - *Location*: `D.move: price_8dec()`
  - *Impact*: In the event of extreme thin-liquidity events on the SUPRA/USDT pair, a momentary price spike from the oracle could trigger unwarranted liquidations.
  - *Recommendation*: As noted in the self-audit, this is a limitation of the chosen oracle architecture and cannot be mitigated in immutable code without introducing hardcoded, brittle bounds. Accept by design, and rely on the "Under Supervision" tier (3-5 sources) of Pair 500. WARNING clause (8) sufficiently discloses this risk.

### INFO
- [INFO-1: 10s Future Drift Tolerance] — The `MAX_FUTURE_DRIFT_MS` is set to 10 seconds. This is generous for L1 clock skew but perfectly safe. It prevents aggressive timestamp spoofing from a malicious validator while remaining resilient to minor network desyncs.
- [INFO-2: Dependency Pinning Verified] — The self-audit noted the necessity of pinning `SupraFramework` and `dora-interface` to specific commits. I can confirm from the bundle notes that this was applied on 2026-04-29.
- [INFO-3: Ecosystem Tooling Breakage] — The removal of Pyth-specific error codes and the addition of `E_STALE_FUTURE=17` shifts the abort code numbering (`E_NOT_ORIGIN` to 15, `E_CAP_GONE` to 16). Ensure any off-chain monitoring bots, indexers, or UI error-parsing libraries are updated for the D Supra deployment.

## Delta verification (6 ports)
- [x] price_8dec rewrite correct (Supra ms-ts, dec normalization, abort paths logic is sound and overflow-safe)
- [x] *_pyth wrappers cleanly removed (no orphans, base entries securely function standalone)
- [x] MIN_DEBT 0.01 D safe (no overflow, fee math intact at smaller scales)
- [x] WARNING (10) USDT-tail accurate
- [x] Move.toml deps + named addresses correct (compatible upgrade policy acknowledged)
- [x] Field rename apt_metadata→supra_metadata complete

## Inheritance verification
- [x] V2 design (10/90, truncation guard, cliff redirect) byte-identical to D Aptos
- [x] sp_settle saturation, MIN_P_THRESHOLD freeze, reset-on-empty preserved
- [x] 5 store-address views all distinct + stable

## Supra-specific
- [x] Resource-account derivation correct on Supra fork (relies on identical `0x1::resource_account` layout)
- [x] supra_oracle::supra_oracle_storage::get_price ABI match (matches ONE Supra v0.4.0 pattern)
- [x] Paired-FA Coin/FA semantics — no logical impact on D accounting (Aptos FA framework abstraction handles this natively)
- [x] Move.toml dep policy chain — compatible enforcement correct

## Attack surface delta
- New: USDT depeg sensitivity (clause 10) — magnitude bound + escape paths. Acceptably documented. If USDT drops, D's effective dollar value drops symmetrically.
- Removed: Pyth conf-band protection (no Supra equivalent) — Accept-by-design analysis confirmed (see LOW-1).
- Issues considered: Timestamp overflow in `price_8dec` (framework time * 1000). Validated that `u64::MAX` limit is orders of magnitude beyond any plausible chain time, neutralizing overflow risks.

## Recommendation
- Proceed to mainnet. The port is structurally sound, economically viable at the new `MIN_DEBT` threshold, and safely integrates the Supra push-oracle pattern.
