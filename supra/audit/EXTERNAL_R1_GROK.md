# Auditor: Grok (xAI) — R1
# Round: R1
# Verdict: GREEN

The D Supra v0.2.0 submission is a clean, well-executed port of the audited D Aptos v0.2.0 (itself GREEN across multiple auditors including prior Claude Opus passes). The 6 intentional deltas are handled correctly with appropriate risk disclosures. No HIGH or MEDIUM findings. The code is ready for mainnet after the already-flagged dep pinning (I-02).

## Findings

### HIGH
None.

### MEDIUM
None.

### LOW
- **L-01: No oracle confidence-band / deviation check** (inherited delta from Pyth → Supra) — Supra's `get_price` returns a single aggregated value without the confidence interval or expo/sign checks present in Pyth. Under thin liquidity or aggregator issues in the "Under Supervision" tier (3-5 sources), wider spreads are possible. This is **accept-by-design** and explicitly disclosed in the updated WARNING clause (8). No practical immutable mitigation exists without introducing fragile hardcoded bounds. Matches the ONE Supra v0.4.0 pattern. No code change needed.

### INFO
- **I-01: Pyth-specific assertions correctly removed** — `E_PRICE_EXPO`, `E_PRICE_NEG`, `E_PRICE_UNCERTAIN`, `MAX_CONF_BPS`, and related logic are gone. Supra uses unsigned `u16` decimal and a pre-aggregated value; the new checks (`v > 0`, `ts_ms > 0`, `dec <= 38`, final `result > 0`) are appropriate.
- **I-02: Framework + dora-interface deps not pinned to commit hashes** (as noted in self-audit) — `rev = "dev"` / `"master"` in Move.toml. Already flagged for pre-mainnet pinning to specific commits (e.g., the ones used in testnet rehearsal). Not blocking for testnet but required before mainnet publish to prevent subtle ABI drift.
- **I-03: Error code renumbering** — Expected and documented; test updates correctly handle the shifts (`E_NOT_ORIGIN=15`, `E_CAP_GONE=16`, new `E_STALE_FUTURE=17`). Frontends/indexers must update abort code mappings for this separate package.
- **I-04: Cosmetic field rename complete** — `apt_metadata` → `supra_metadata` (and all readers) has no semantic impact.
- **I-05: USDT-denominated peg tail risk correctly disclosed** — WARNING clause (10) accurately reflects the choice of direct pair 500 (SUPRA/USDT) over derived USD price. Historical May 2022 USDT depeg to ~$0.95 is factual. Magnitude estimate ("<5%" historically, ~50bps long-tail) is reasonable. "No fallback" is correct.

All other self-audit INFO items (events, ABI subset, etc.) are accurate.

## Delta verification (6 ports)
- **✅ price_8dec rewrite correct** — Tuple destructure `(v, d, ts_ms, _round)` matches Supra `supra_oracle_storage::get_price(u32)` ABI (u128 price, u16 decimals, u64 ts in ms, u64 round). Time math (`now_ms = timestamp::now_seconds() * 1000`; staleness ≤ 60_000 ms; future drift ≤ 10_000 ms) is sound with no realistic u64 overflow. Decimal normalization (`if dec >= 8 then / else *` via `pow10`) is correct for unsigned decimals. Zero-price and post-normalization zero guards present. Future-drift abort uses new `E_STALE_FUTURE`. Matches ONE Supra oracle usage pattern.
- **✅ *_pyth wrappers cleanly removed** — No orphan references in source or tests (confirmed by self-audit + bundle description). Base entries (`open_trove`, `redeem`, etc.) are self-sufficient; Supra push model means no caller-side VAA update needed. Clean ABI subset for frontends/integrators.
- **✅ MIN_DEBT 0.01 D safe** — Lowered from 0.1 D. Math (fees, CR checks, truncation guard, post-conditions) handles the scale (1% fee = 10_000 raw units; rescuer cost remains trivial ~$0.0001). Enforced at all four relevant sites. No overflow or new dust attacks introduced.
- **✅ WARNING (10) USDT-tail accurate** — Yes; design choice, historical fact, and implications correctly stated. Pair 500 chosen for simplicity/immutability over `get_derived_price`.
- **✅ Move.toml deps + named addresses correct** — SupraFramework swap, core git dep with testnet/mainnet subdir, `origin = "_"`, `upgrade_policy = "compatible"` (forced), removal of Pyth. Testnet rehearsal used appropriate core subdir.
- **✅ Field rename apt_metadata→supra_metadata complete** — All readers updated; purely cosmetic.

## Inheritance verification
- **✅ V2 design byte-identical to D Aptos** (modulo rename + oracle delta) — 10/90 fee split, truncation guard (`total_before == 0 || total_sp_new > 0`), cliff orphan redirect, `MIN_P_THRESHOLD=1e9` freeze, `sp_settle` saturation handling, self-redeem allowance, reset-on-empty, etc., preserved.
- **✅ 5 store-address views distinct + stable** — `metadata_addr`, `fee_pool_addr`, etc., unchanged in behavior.
- **✅ sp_settle saturation, MIN_P_THRESHOLD, truncation guard, etc.** — All inherited correctly; HIGH-1 from Aptos R1 remains protected.

## Supra-specific
- **✅ Resource-account derivation & sealing correct** — `0x1::resource_account` + `destroy_cap` pattern ports identically from D Aptos (Supra fork preserves the same modules). Runtime sealing (ResourceCap removal + Option<SignerCap> drop) prevents future `publish_package_txn` against `@D`. Equivalent to D Aptos despite `compatible` policy (functional immutability via runtime).
- **✅ supra_oracle::supra_oracle_storage::get_price ABI match** — Confirmed via Supra docs and ONE Supra reference: returns `(u128, u16, u64, u64)`. Testnet rehearsal + price normalization validated end-to-end.
- **✅ Paired-FA Coin/FA semantics — no logical impact** — SUPRA at `@0xa` uses primary fungible store. `primary_fungible_store::withdraw` (and framework paths) works regardless of Coin/FA origin. D's accounting unaffected. Matches Supra FA framework.
- **✅ Move.toml dep policy chain** — `compatible` enforcement is correct and documented.

## Attack surface delta
- **New**: USDT depeg sensitivity (disclosed; bounded historically; escape via non-oracle entries like `close_trove`/`add_collateral` remains). Oracle freeze risk same as prior Pyth case (reserve lock possible; documented).
- **Removed**: Pyth VAA bundling + conf-band protection (accept-by-design; Supra push model simplifies UX).
- **Considered**: No reentrancy (Move borrow checker + view-only oracle). No new entry points. Lower MIN_DEBT dust handled by existing post-conditions. Stale/future ts math safe. Bootstrap CR well above MCR at current oracle price. Testnet rehearsal (12/13 entries + 16/16 views) + 32/32 tests confirm no regressions. Liquidate math identical to audited D Aptos (deferred mainnet smoke reasonable).

## Recommendation
**Proceed to mainnet** after applying the non-blocking I-02 dep pinning (pin SupraFramework and dora-interface to the exact commits used in testnet rehearsal, e.g., the hashes already noted). The package is a faithful, lower-risk port with strong inheritance from multiple GREEN audits. Sealing flow (resource-account + destroy_cap via multisig) and oracle integration are solid.

## Optional notes
- Testnet rehearsal log looks excellent — real oracle smoke, fee splits, cliff path, keyed rewards, structural 1% gap, and FA handling all validated.
- WARNING text updates are comprehensive and user-protective.
- Overall quality of the port (self-audit depth, test updates, rehearsal) is high. Minor cosmetic renames and error renumbering handled cleanly.

This submission maintains the security posture of its audited siblings while correctly adapting to Supra L1's native push oracle and FA conventions. **GREEN R1**.
