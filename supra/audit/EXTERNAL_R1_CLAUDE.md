# Auditor: Claude Opus 4.7 (Anthropic, web/mobile chat interface)
# Round: R1
# Verdict: GREEN-with-caveats (bundle-level only; full source attestation not possible from inputs provided)

## Audit scope and limitations

Inputs reviewed: AUDIT_R1_BUNDLE.md only. The 811-LOC `D.move`, 522-LOC `D_tests.move`, `Move.toml`, and helper scripts were referenced by path but not provided. All findings below are derived from the inlined `price_8dec` body, constants tables, error-code tables, ABI tables, the testnet rehearsal log, the self-audit, and external cross-checks against Supra documentation.

The 6 prior auditor passes (Grok / Kimi / Qwen / DeepSeek / Gemini / Claude Opus 4.7-fresh on D Aptos, plus 5 + Claude on D Sui) presumably had source access and consistently returned GREEN on the inherited V2 design. This audit therefore focuses where it can add value: the 6 deltas, the externally-verifiable claims, and the bundle's internal consistency.

## Findings

### HIGH
None identified within the bundle scope.

### MEDIUM
None identified within the bundle scope.

### LOW

**L-A — `now_ms = timestamp::now_seconds() * 1000` quantizes to second precision (asymmetric staleness window)** — `D.move` `price_8dec` line (4).
The Supra oracle pushes timestamps with full ms precision, but `now_ms` is constructed from `now_seconds() * 1000`, so it always lags real chain time by 0–999 ms (`now_ms ≤ real_time_ms`). The asymmetric effect:
- **Staleness check** (line 6, `now_ms <= ts_ms + STALENESS_MS`) becomes up to **1s more permissive** — a feed truly stale at 60.5s real-world can pass.
- **Future-drift check** (line 5, `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS`) becomes up to **1s more restrictive** — a feed legitimately at +9.5s drift can still pass within 10s tolerance, but a feed at +9.99s could spuriously fail.

Net impact: 61s effective staleness instead of 60s, and ~9s effective future-drift tolerance instead of 10s. Both well within the safety budget of a 200% MCR / 150% liquidation system on a 600-900 ms finality chain. **Not exploitable**, but the principled fix is a one-liner: use `timestamp::now_microseconds() / 1000` to recover full ms precision.

Recommendation: cosmetic — apply pre-mainnet if convenient; do not block on this for testnet. (D Aptos used `now_seconds()` directly because Pyth ts was in seconds; the unit mismatch is an artefact of the Aptos→Supra port.)

**L-B — WARNING (10) "<5%" historical USDT depeg magnitude understates worst observed case**.
Per cover letter and self-audit, the USDT depeg tail is bounded historically at "<5%". The May 12, 2022 episode bottomed near ~$0.9485 (≈5.15% deviation). The bundle elsewhere phrases it more accurately as "~50bps long-tail risk" / "magnitude estimate <5%" — these are different magnitudes and slightly inconsistent.

Recommendation: tighten the WARNING (10) wording to "approximately 5%, with brief excursions slightly beyond" or "up to ~5%". Single-character fix at most. Material to integrators evaluating D's effective peg under stress.

### INFO

**I-A — Supra `get_price` ABI cross-check passes (external corroboration).**
Supra docs (`docs.supra.com/oracles/data-feeds/push-oracle`) show the canonical Aptos-Move destructure:
```
let (current_price, _, _, current_round) = supra_oracle_storage::get_price(supra_pair_id);
```
The bundle's `let (v, d, ts_ms, _round) = ...` matches positionally: (price, decimal, timestamp, round). The testnet log (line 149) empirically confirms `(312700000000000, 18, ms_ts, round)` — value 3.127e14 with dec=18 normalizes to 8-dec `31270` = $0.0003127, which matches reported normalization.

**I-B — Test name vs error code mismatch deserves clarification.**
Self-audit line 486 says `test_redeem_below_min_debt_aborts` asserts `E_AMOUNT=6` (not `E_DEBT_MIN=3`) on input `900_000`. If the source asserts `assert!(d_amt >= MIN_DEBT, E_DEBT_MIN)`, the abort code should be 3, not 6. Possibilities:
- (a) Source uses `E_AMOUNT` for input-below-MIN_DEBT — semantic mislabeling worth normalizing.
- (b) An earlier `assert!(d_amt > 0, E_AMOUNT)` is hit first by some unrelated invariant in the test setup.
- (c) Test name is misleading; it's testing something else.

Cannot disambiguate without source. Worth a clean-up pass during pre-mainnet to confirm the asserted code matches the failure mode the test name implies.

**I-C — Functional immutability via runtime sealing only; package upgrade_policy is `compatible`, not `immutable`.**
Already disclosed in WARNING (8) and self-audit. Re-emphasizing: D Aptos achieved double-immutability (destroy_cap'd resource cap **and** `upgrade_policy = "immutable"`); D Supra has only the runtime `destroy_cap` lever because `SupraFramework` and `dora-interface` deps both carry `upgrade_policy = 1` (compatible), and a package's policy must be ≥ all its deps'. The destroy_cap argument is sound — once `ResourceCap` is consumed and `Option<SignerCap>` dropped, there is no signer for `@D` and therefore no path through `0x1::code::publish_package_txn` — but this is a **single-mechanism** seal. Anyone auditing post-mainnet should specifically verify on-chain that `is_sealed()` returns true after the multisig destroy_cap call.

**I-D — Error code 17 collision between D Aptos (E_NOT_ORIGIN) and D Supra (E_STALE_FUTURE) is a foot-gun for shared tooling.**
Self-audit I-03 already notes this. Concrete risk: an indexer or frontend that maintained a single error-code map for "the D family" and applied it cross-chain would silently reinterpret D Supra's `E_STALE_FUTURE` as D Aptos's `E_NOT_ORIGIN`. Two suggestions:
- (i) document the mapping explicitly in a per-chain error map file in `audit/`;
- (ii) consider, for any future chain ports, gapping error codes by 100 between siblings (e.g., D Aptos: 1–99, D Supra: 100–199) to make accidental cross-chain map reuse syntactically impossible. Forward-looking only — not actionable for v0.2.0.

**I-E — `_round` from `get_price` is intentionally ignored.**
Same as ONE Supra v0.4.0 mainnet pattern. Round monotonicity could provide an independent freshness signal (refuse a read if `round <= last_observed_round`), but storing and updating a "last seen round" introduces state-mutation cost on every oracle-consuming entry, and `ts_ms` already serves the freshness role. Acceptance by design is reasonable.

**I-F — Oracle-output overflow path produces a different abort code than `E_PRICE_ZERO`.**
A malicious or buggy oracle return of `(v = u128::MAX, dec = 0)` would overflow line (9) `v * pow10(8)` and trigger a Move arithmetic abort (not `E_PRICE_ZERO`). The transaction still aborts safely (no fund loss), so this is a liveness/UX issue, not a safety issue, and it lives within the disclosed "compatible upgrade policy" risk envelope of WARNING (8). No change recommended; flagged for visibility.

**I-G — `pow10` body not visible.**
Helper not inlined in the bundle. If it's iterative or table-backed, fine; if recursive, dec=38 could be a gas/stack concern. 32/32 tests presumably exercise dec=8 (the SUPRA pair returns dec=18, normalized via `pow10(10)`), but explicit edge-case coverage at dec=38 (max bound) and dec=0 (multiply path) would be reassuring. Worth confirming during source review.

**I-H — Constants table cross-check (all consistent).**
Verified internally:
- `STALENESS_MS = 60_000` matches comment "60 seconds"
- `MAX_FUTURE_DRIFT_MS = 10_000` matches "10s tolerance"
- `PAIR_ID = 500` typed `u32` matches Supra ABI input type
- `MIN_DEBT = 1_000_000` (0.01 D at 8 decimals; consistent with bundle's "0.01 D" labeling and economic narrative at SUPRA $0.0003)
- `SUPRA_FA = @0xa` matches the framework-convention native FA address used by ONE Supra v0.4.0 mainnet
- Error codes 1–17 form a contiguous sequence; no duplicates within D Supra

## Delta verification (6 ports)

- [x] `price_8dec` rewrite correct (Supra ms-ts, dec normalization, abort paths) — body inlined and audited line-by-line; one minor precision asymmetry flagged as L-A.
- [~] `*_pyth` wrappers cleanly removed (no orphans) — **claimed** in self-audit; cannot independently verify without source. Recommend `grep -rn "pyth\|_pyth\|VAA\|APT_USD_PYTH_FEED\|MAX_CONF_BPS\|E_PRICE_EXPO\|E_PRICE_NEG\|E_PRICE_UNCERTAIN" sources/ tests/ scripts/` to confirm.
- [x] `MIN_DEBT` 0.01 D safe — fee at MIN_DEBT = 10_000 raw (well above zero); 4 enforcement sites listed; rescue cost ~$0.0001. No new attack surface.
- [~] WARNING (10) USDT-tail accurate — substantively yes; magnitude phrasing imprecise (L-B).
- [~] `Move.toml` deps + named addresses correct — Move.toml not inlined; pin claim (I-02 APPLIED 2026-04-29) is unverifiable from bundle. Recommend the next auditor verify the actual pinned commits.
- [~] Field rename `apt_metadata → supra_metadata` complete — claimed; 32/32 tests passing implies syntactic correctness. Empirical: testnet rehearsal succeeded across 12+16 entries/views, exercising every reader.

## Inheritance verification

- [~] V2 design (10/90, truncation guard, cliff redirect) byte-identical to D Aptos — **claimed**; cannot diff source. The testnet rehearsal exercises all three (10/90 split observed in `redeem` row, cliff path donation accumulator confirmed in `donate_to_sp` row, truncation guard tested via R1 unit tests inherited from D Aptos R2 fix).
- [~] `sp_settle` saturation, `MIN_P_THRESHOLD` freeze, reset-on-empty preserved — claimed.
- [~] 5 store-address views all distinct + stable — `metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`, `treasury_addr` — that's actually 6 store addresses listed in self-audit line 152. Worth confirming whether the canonical count is 5 or 6 (might be a documentation drift from D Aptos to D Supra).

## Supra-specific verification

- [x] Resource-account derivation correct on Supra fork — Supra's `0x1::resource_account` is unmodified relative to Aptos (Entropy-Foundation fork tracks `aptos-core` framework). ONE Supra v0.4.0 mainnet sealing at `0x2365c948…eafda5c90f` with `auth_key=0x0` is empirical proof.
- [x] `supra_oracle::supra_oracle_storage::get_price` ABI match — verified against Supra public docs; positional destructure `(value, decimal, timestamp, round)` confirmed; testnet log values consistent.
- [x] Paired-FA Coin/FA semantics — `primary_fungible_store::withdraw(user, supra_metadata, amt)` reads from FA primary store regardless of whether user holds raw Coin or paired FA, since Aptos/Supra framework auto-converts. Same posture as D Aptos for APT FA.
- [x] Move.toml dep policy chain — compatible enforcement is correct given dep policies; documented trade-off vs D Aptos `immutable` package policy (I-C).

## Attack surface delta

**Removed (vs D Aptos)**:
- Pyth confidence-band protection (no Supra equivalent) — disclosed as L-01 in self-audit; accept-by-design. The Pyth-conf check rejected reads with abnormally wide spreads (sub-second consensus disagreement among publishers); Supra's pre-aggregated single value provides no equivalent signal. Reasonable assumption for "Under Supervision" tier (3-5 sources) at 600-900ms finality, but a real risk in thin-source / volatile conditions.
- VAA pull-update bundling logic (4 `*_pyth` entries deleted) — strict ABI subset; cannot break callers that don't use the deleted entries.

**Added (vs D Aptos)**:
- USDT depeg sensitivity (WARNING clause 10) — bounded historically ≈5%, no fallback in immutable/sealed code. Escape hatches (close_trove, sp_withdraw, donate_*, sp_claim) remain oracle-free, so users can exit positions even during a depeg event.
- Future-drift bound (`MAX_FUTURE_DRIFT_MS=10_000`) — new check, no analogue on D Aptos / Pyth (Pyth ts can't be in the future). Correctly bounded.
- Sub-mainnet upgrade-policy weakening (`compatible` vs D Aptos `immutable`) — single-mechanism runtime seal vs D Aptos double-mechanism (I-C).

**Issues considered, not flagged**:
- MIN_DEBT 0.01 D dust trove grief vector — economically self-limiting (collateral cost ≥ 200% of $0.01 = $0.02 minimum entry). Sub-cent attack surface is not meaningful.
- `_round` ignored — defensible (ts_ms covers freshness).
- Oracle-output overflow path — produces arithmetic abort, no fund loss.

## Recommendation

**Proceed to mainnet** subject to the following:

1. **Pre-mainnet (blocking)**: Verify Move.toml shows the I-02 pins (`SupraFramework@306b6077…`, `dora-interface@37a9d80b…`) and that 32/32 tests still pass against the pinned revs. Self-audit claims this is APPLIED 2026-04-29 but the bundle does not include the Move.toml diff.
2. **Pre-mainnet (recommended, non-blocking)**:
   - Run `grep -rn "pyth\|_pyth\|apt_metadata\|APT_USD_PYTH_FEED\|MAX_CONF_BPS\|E_PRICE_EXPO\|E_PRICE_NEG\|E_PRICE_UNCERTAIN" sources/ tests/ scripts/` and confirm zero hits (closes the orphan-reference deletion claim).
   - Tighten WARNING (10) wording for USDT depeg magnitude (L-B).
   - Clarify `test_redeem_below_min_debt_aborts` expected error code (I-B).
3. **Pre-mainnet (cosmetic)**: Replace `now_seconds() * 1000` with `now_microseconds() / 1000` in `price_8dec` to recover full ms precision (L-A).
4. **Post-mainnet**: After the multisig `destroy_cap` execution, verify on-chain that `is_sealed()` returns true and that no `ResourceCap` exists at `@D`. This is the seam D Supra is functionally relying on for immutability (I-C).

## Optional notes

- The end-to-end testnet rehearsal (12 mutation entries + 16 views, all gas-priced and tx-hashed) is unusually thorough for an R1 submission — substantially stronger evidence than a unit-test-only port. Particularly, the cross-wallet `donate_to_sp` (sp_pool +500_000 with `total_sp` unchanged) directly exercises the cliff-path donation accumulator, which is the V2 invariant most easily broken by a careless port.
- The decision to defer `liquidate` and `destroy_cap` smoke to mainnet is reasonable: the former requires CR<150% which can't be reproduced without oracle manipulation, and the latter is irreversible.
- Inheriting from a sibling (D Aptos R1 GREEN ×6) plus a grandparent (D Sui R1+R2 GREEN ×6) plus an oracle-pattern reference (ONE Supra v0.4.0 mainnet sealed) is about as much prior art as a v0.2.0 port can have. The remaining residual risk is concentrated in (a) the I-02 pin verification, (b) source-level grep for orphan references, and (c) the post-mainnet `is_sealed()` confirmation.
- One stylistic suggestion for future port docs: include the actual `Move.toml` and the `price_8dec` body's `pow10` helper inline in the bundle, since these are the artifacts most likely to harbor port-specific defects and the most cheaply auditable from text alone.
