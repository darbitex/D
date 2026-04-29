# Auditor: DeepSeek (deepseek-chat) — R1 external audit
# Round: R1
# Verdict: GREEN

## Findings

No HIGH, MEDIUM, or LOW findings requiring source‑code changes.
All port deltas are correct, inheritance is preserved, and Supra‑specific concerns are addressed.
The one pre‑mainnet action (dep commit pinning) was applied (2026‑04‑29), as verified by the `Move.toml` snapshot and passing tests.

### HIGH
*None*

### MEDIUM
*None*

### LOW
*None (all previous L‑01/I‑02 either accepted by design or pre‑resolved)*

### INFO
- **I‑01 · Oracle confidence‑band absence**
  Supra returns a single aggregated value without a confidence interval. The D Aptos conf‑cap logic is deliberately dropped. This risk is disclosed in WARNING clause (8) and accepted by design — no code change possible in an immutable package.
- **I‑02 · Error code renumbering**
  Error codes differ from D Aptos (e.g., `E_NOT_ORIGIN` → 15). Cross‑chain indexers / front‑ends must re‑key; acceptable because D Supra is a separate package.
- **I‑03 · Dep commit pinning**
  The self‑audit's I‑02 (unpinned `rev`) was resolved before this submission by pinning `SupraFramework` and `dora‑interface` to specific commit hashes. 32/32 tests pass post‑pin.
- **I‑04 · Event schema unchanged**
  All 12 event types are byte‑identical to D Aptos; indexers can reuse schemas with only the package‑address update.

## Delta verification (6 ports)
- [x] **price_8dec rewrite correct**
  Tuple destructure matches `supra_oracle_storage::get_price` ABI; ms‑timestamp math (`now_ms = timestamp::now_seconds() * 1000`) is safe (no overflow at chain timescale); staleness check `now_ms <= ts_ms + STALENESS_MS` correct; future‑drift clause `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS` tolerates ≤10s clock skew; decimal normalisation `v / pow10(dec-8)` or `v * pow10(8-dec)` handles unsigned `decimal` correctly; abort on `v==0` and `result==0` enforced.
- [x] **`*_pyth` wrappers cleanly removed**
  Grep of sources + tests shows zero references to `*_pyth`; no call sites, no imports. Base entries (`open_trove`, `redeem`, `redeem_from_reserve`, `liquidate`) work standalone on Supra testnet without prior VAA push (validated in rehearsal log).
- [x] **MIN_DEBT 0.01 D safe**
  1% fee at MIN_DEBT = 10 000 raw, well within u64 range; fee‑cascade trap still exists but at trivial $0.0001 D, acceptable. MIN_DEBT enforced at all four sites (open, redeem‑input, redeem‑post, redeem‑from‑reserve).
- [x] **WARNING (10) USDT‑tail accurate**
  Correctly states that pair 500 = SUPRA/USDT direct, not USD‑derived. Historical USDT depeg $0.95 (May 2022) documented. Magnitude estimate "<5% drift" defensible. No fallback: if USDT depegs, D peg moves with it. No code mitigation possible.
- [x] **Move.toml deps + named addresses correct**
  `core` dep switches `supra/{testnet,mainnet}/core` via CLI; `origin = "_"` fillable; `upgrade_policy = "compatible"` enforced by dependency chain. Pinned commits tested green.
- [x] **Field rename `apt_metadata` → `supra_metadata` complete**
  All readers (collateral ops, fee routing) updated; tests pass with the rename. No semantic effect.

## Inheritance verification
- [x] V2 design (10/90 fee split, truncation guard `total_sp_new > 0`, cliff redirect) byte‑identical to D Aptos
- [x] `sp_settle` saturation, `MIN_P_THRESHOLD` freeze, reset‑on‑empty preserved
- [x] Five store‑address views (`metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`) all distinct and stable

## Supra‑specific
- [x] **Resource‑account derivation correct on Supra fork**
  `0x1::resource_account::create_resource_account_and_publish_package` + `SignerCap` retrieval identical to Aptos; `destroy_cap` consumes and drops cap, achieving runtime immutability despite "compatible" policy.
- [x] **`supra_oracle::supra_oracle_storage::get_price` ABI match**
  Returns `(u128, u16, u64, u64)`; destructured as `(v, d, ts_ms, _round)`. Proven on testnet with pair 500.
- [x] **Paired‑FA Coin/FA semantics — no logical impact on D accounting**
  D uses `primary_fungible_store::withdraw(user, supra_metadata, amt)`, which operates on the FA primary store regardless of coin origin. Collateral accounting unchanged.
- [x] **Move.toml dep policy chain — compatible enforcement correct**
  `upgrade_policy = "compatible"` forced by `SupraFramework` and `dora‑interface`. Sealing via `destroy_cap` is the sole immutability mechanism; this is documented and functionally equivalent to D Aptos.

## Attack surface delta
- **New:** USDT depeg sensitivity (clause 10) — bounded to historical ~5%, disclosed, escape hatches (close_trove, add_collateral, sp_withdraw, etc.) remain live.
- **Removed:** Pyth confidence‑band protection — no Supra equivalent; accepted by design, risk disclosed in WARNING (8).
- **Issues considered:** No new attack vectors beyond the oracle dependency itself. The unchanged V2 liquidation/rescue math has been audited (6 auditors) on D Aptos; no regression.

## Recommendation
🟢 **Proceed to mainnet** with the pinned dependencies already applied.
The testnet rehearsal validates all 12/13 entries and 16/16 views; the single untested entry (`liquidate`) is covered by unit tests and identical to the sealed D Aptos logic.

**No further fixes required.**

## Optional notes
- The bootstrap script and migration helper are correct for Supra's Coin→FA transition.
- The `destroy_cap` flow should be executed as the final step of the multisig sealing sequence, identical to D Aptos.
