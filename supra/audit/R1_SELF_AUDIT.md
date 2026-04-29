# D Supra v0.2.0 — R1 Self-Audit

**Auditor:** Claude Opus 4.7
**Date:** 2026-04-29
**Scope:** Source port from D Aptos v0.2.0 (`/home/rera/d/aptos/sources/D.move`, 866 LOC, 6 prior auditor GREEN) to `/home/rera/d/supra/sources/D.move` (768 LOC).
**Method:** Focus on PORT DELTAS only. Inherited logic (struct shape, fee/SP math, liquidation distribution, redemption/close mechanics, settlement) is unchanged from R1 base; not re-audited here.

## Delta surface enumerated

1. Oracle: Pyth Aptos pull-based → Supra L1 push-based (`supra_oracle_storage::get_price(500)`)
2. Time unit: oracle ts seconds → milliseconds
3. Constant changes: `STALENESS_SECS=60` → `STALENESS_MS=60_000` + `MAX_FUTURE_DRIFT_MS=10_000`
4. Constant change: `MIN_DEBT=10_000_000` (0.1 D) → `1_000_000` (0.01 D)
5. Constants removed: `APT_USD_PYTH_FEED`, `MAX_CONF_BPS`
6. Constants added: `PAIR_ID=500`
7. Error codes removed: `E_PRICE_EXPO=15`, `E_PRICE_NEG=16`, `E_PRICE_UNCERTAIN=19`
8. Error codes renumbered: `E_NOT_ORIGIN 17→15`, `E_CAP_GONE 18→16`, added `E_STALE_FUTURE=17`
9. Entry functions removed: `open_trove_pyth`, `redeem_pyth`, `redeem_from_reserve_pyth`, `liquidate_pyth`
10. Field rename: `Registry.apt_metadata → supra_metadata`
11. Address: `@origin` from Aptos multisig → Supra multisig `0xbefe37923ac…`
12. Imports: `aptos_framework::* → supra_framework::*`, drop `pyth::*`, add `supra_oracle::supra_oracle_storage`
13. WARNING text: replace clauses (6), (8), (9); add new clause (10) USDT-tail; rename APT→SUPRA, Aptos→Supra, Pyth→Supra oracle throughout
14. Move.toml: `Pyth = { local = "deps/pyth" }` → `core = { git = "...dora-interface", subdir = "supra/mainnet/core" }`; AptosFramework→SupraFramework; remove `pyth` named addr

## 1. ABI surface

### Public entries

| Function | Signature | Notes |
|---|---|---|
| `destroy_cap` | `(caller: &signer)` | unchanged |
| `open_trove` | `(user: &signer, coll_amt: u64, debt: u64)` | unchanged |
| `add_collateral` | `(user: &signer, coll_amt: u64)` | unchanged |
| `close_trove` | `(user: &signer)` | unchanged |
| `redeem` | `(user: &signer, d_amt: u64, target: address)` | unchanged |
| `redeem_from_reserve` | `(user: &signer, d_amt: u64)` | unchanged |
| `liquidate` | `(liquidator: &signer, target: address)` | unchanged |
| `sp_deposit` | `(user: &signer, amt: u64)` | unchanged |
| `donate_to_sp` | `(user: &signer, amt: u64)` | unchanged |
| `donate_to_reserve` | `(user: &signer, amt: u64)` | unchanged |
| `sp_withdraw` | `(user: &signer, amt: u64)` | unchanged |
| `sp_claim` | `(user: &signer)` | unchanged |

**Removed**: `*_pyth` quartet (4 entries). No replacement needed — Supra is push-based, base entries call `price_8dec()` directly.

### Public views (12 unchanged)

`read_warning`, `metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`, `treasury_addr`, `price`, `trove_of`, `sp_of`, `totals`, `reserve_balance`, `sp_pool_balance`, `is_sealed`, `close_cost`, `trove_health`.

**ABI verdict:** ✅ Strict subset of D Aptos ABI. Frontend calling base entries works without modification (just stop calling *_pyth variants and stop bundling VAAs).

## 2. Args validation

Reviewed every `assert!` in the entry path:

| Check | Location | Status |
|---|---|---|
| `debt >= MIN_DEBT` (open) | open_impl:280 | ✓ enforces 0.01 D minimum |
| `coll_usd * 10000 >= MCR_BPS * debt` | open_impl:293 | ✓ 200% MCR enforced via 8-dec price |
| `amt > 0` (sp_deposit, donate_*, sp_withdraw, add_collateral) | various | ✓ no-op rejection |
| `d_amt >= MIN_DEBT` (redeem, redeem_from_reserve) | 339, 389 | ✓ same floor as open |
| `t.debt == 0 || t.debt >= MIN_DEBT` post-redeem | 352 | ✓ post-condition |
| `t.debt == 0 || t.collateral > 0` post-redeem | 353 | ✓ no zombie troves |
| `coll_usd * 10000 < LIQ_THRESHOLD_BPS * debt` (liq) | 423 | ✓ 150% threshold gate |
| `pool_before > debt` (liq) | 425 | ✓ SP must cover debt strictly |
| `total_before == 0 \|\| new_p >= MIN_P_THRESHOLD` (liq) | 431 | ✓ cliff path skip; keyed path P-cliff |
| `total_before == 0 \|\| total_sp_new > 0` (liq) | 436 | ✓ truncation guard (R1 HIGH-1) |
| `signer::address_of(caller) == @origin` (destroy_cap) | 122 | ✓ origin-only |
| `exists<ResourceCap>(@D)` (destroy_cap) | 123 | ✓ one-shot guard |

**Args verdict:** ✅ All asserts inherited from D Aptos R1; no new args introduced.

## 3. Math integrity

### 3.1 Oracle math (price_8dec) — CRITICAL DELTA

```move
fun price_8dec(): u128 {
    let (v, d, ts_ms, _round) = supra_oracle_storage::get_price(PAIR_ID);  // (1)
    assert!(v > 0, E_PRICE_ZERO);                                          // (2)
    assert!(ts_ms > 0, E_STALE);                                           // (3)
    let now_ms = timestamp::now_seconds() * 1000;                          // (4)
    assert!(ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS, E_STALE_FUTURE);        // (5)
    assert!(now_ms <= ts_ms + STALENESS_MS, E_STALE);                      // (6)
    let dec = (d as u64);                                                  // (7)
    assert!(dec <= 38, E_EXPO_BOUND);                                      // (8)
    let result = if (dec >= 8) v / pow10(dec - 8) else v * pow10(8 - dec); // (9)
    assert!(result > 0, E_PRICE_ZERO);                                     // (10)
    result
}
```

**Line-by-line:**

(1) `get_price` returns `(u128 v, u16 d, u64 ts_ms, u64 round)`. Pattern lifted from ONE Supra v0.4.0 `/home/rera/one/supra/sources/ONE.move:154-163` (proven mainnet).

(2) `v > 0` rejects zero-price. Supra returns 0 only if pair is absent or feed expired internally; either way unsafe.

(3) `ts_ms > 0` rejects unset feed. Defensive.

(4) `timestamp::now_seconds() * 1000` converts framework time to ms-aligned. **Overflow check**: `u64::MAX / 1000 ≈ 1.84e16 secs`, well above any plausible chain time. Safe.

(5) `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS` rejects future-drift > 10s. Tolerates clock skew in the validator timestamping the feed push. Aborts with `E_STALE_FUTURE=17` (new code).

(6) `now_ms <= ts_ms + STALENESS_MS` rejects reads >60s old. **OVERFLOW CHECK**: `ts_ms + 60_000` — can overflow u64 only if `ts_ms > u64::MAX - 60_000 ≈ 1.84e19`. Implausible (current ms time ~1.78e12). Safe.

(7) `dec` cast u16 → u64 always lossless.

(8) `dec <= 38` bounds pow10 below u128 overflow point (10^38 = u128 max range).

(9) Decimal normalization: at SUPRA $0.0004 with dec=18, `v ≈ 4e14`, normalizing to 8 dec means dividing by 10^10. `result ≈ 4e4`. Result fits u128 trivially.
   - Edge: `dec=8` → result = v unchanged
   - Edge: `dec=0` → result = v * 10^8
   - Edge: `dec=38` → result = v / 10^30. If v < 10^30, result == 0, caught by (10).

(10) `result > 0` final guard against degenerate normalization.

**Comparison with D Aptos `price_8dec`:**

D Aptos asserts: `i64::get_is_negative(&e_i64)` (Pyth expo always negative), `abs_e <= 18`, `!i64::get_is_negative(&p_i64)` (positive price), `(conf * 10000) <= MAX_CONF_BPS * raw` (Pyth conf cap).

D Supra **drops** the conf cap because Supra returns a single pre-aggregated value (no confidence interval exposed). This is a **looser** safety property than Pyth's conf-bounded reads.

**FINDING L-01 (LOW)**: D Supra has no protection against wide-spread oracle readings. If Supra Foundation's median aggregator behaves erratically (e.g., 20% deviation from true market under thin-source conditions), D will accept the value. Mitigation: pair_id 500 is a well-watched pair; "Under Supervision" tier means 3-5 sources. WARNING clause (8) discloses this risk explicitly. **No code change recommended** — adding a custom band check would require hardcoded bounds that are themselves sensitive to long-term price moves and immutable. Accept by design.

**FINDING I-01 (INFO)**: Supra `decimal: u16` is unsigned, so `dec <= 38` plus `result > 0` is sufficient. The Pyth-specific assertions (negative-expo, positive-price) are correctly omitted as not applicable.

### 3.2 Trove + SP + liq math — UNCHANGED

`open_impl`, `redeem_impl`, `liquidate`, `sp_settle`, `route_fee_fa` byte-identical to D Aptos modulo field rename `apt_metadata→supra_metadata`. Inherits 6-auditor R1 GREEN.

### 3.3 MIN_DEBT change

D Aptos: `10_000_000` (0.1 D). D Supra: `1_000_000` (0.01 D).

Implications:
- Lower entry barrier — more trove dust possible
- Fee-cascade trap edge: at debt = MIN_DEBT, attempting partial redeem against this trove leaves residual debt < MIN_DEBT, aborting with `E_DEBT_MIN`. User must redeem the FULL debt (close-equivalent) or leave alone. **Mitigation**: redeem_impl line 352 enforces `t.debt == 0 || t.debt >= MIN_DEBT` post-condition. Same constraint as D Aptos. Just at a different absolute scale.
- MIN_DEBT enforced at:
  - open: line 280 ✓
  - redeem (input): line 339 ✓
  - redeem (post): line 352 ✓
  - redeem_from_reserve (input): line 389 ✓

**Verdict:** No new attack surface. Lower MIN_DEBT just shifts the dust threshold proportionally.

## 4. Reentrancy

Move's resource semantics + lack of dynamic dispatch eliminates classical reentrancy. Cross-module calls only into:
- `supra_oracle_storage::get_price` — view-only, returns tuple, no state mutation in oracle ↔ D direction
- `primary_fungible_store::*` — Aptos framework, audited
- `fungible_asset::*` — Aptos framework, audited
- `smart_table::*` — Aptos framework, audited
- `event::emit` — pure side-effect

**No external code is given a callback path into D state.** All mutations on `Registry` happen between `borrow_global_mut` and the function return; Move's borrow checker guarantees no aliasing within that window.

**Reentrancy verdict:** ✅ Same posture as D Aptos. No new external interactions.

## 5. Edges

### 5.1 Oracle freeze

- If `get_price(500)` aborts (pair removed/decommissioned), every oracle-consuming entry aborts. Escape hatches (close_trove, add_collateral, sp_deposit, sp_withdraw, donate_*, sp_claim) remain. `redeem_from_reserve` becomes blocked → reserve_coll permanently locked. Documented in WARNING clause (8). **Same as D Aptos behavior under Pyth freeze.**

### 5.2 USDT depeg

- pair 500 reports SUPRA/USDT directly. If USDT trades $0.95, oracle returns SUPRA value in 0.95-USD-equivalent units. D treats this as $1.00. Effective peg drift ~5%. Documented in WARNING clause (10). **Accept by design; no fallback in immutable code.**

### 5.3 Stale-but-not-future ts edge

- If `ts_ms` is exactly equal to `now_ms - STALENESS_MS`: passes (assertion is `<=`). Correct boundary semantics.
- If `ts_ms == now_ms`: passes both assertions trivially.
- If `ts_ms == now_ms + MAX_FUTURE_DRIFT_MS`: passes future-drift check (line 5).

### 5.4 Bootstrap trove edge

- Bootstrap = 500 SUPRA → 0.01 D. CR @ SUPRA $0.0004: `(500 * 0.0004) / 0.01 = $0.20 / $0.01 = 20.0x = 2000% bps`. **Well above 200% MCR**. ✓

### 5.5 sp_pool donation absorption during cliff

- During `total_sp == 0`, route_fee_fa redirects 90% portion to sp_pool as donation (line 222). Cliff path skip in liquidate (line 431) accepts arbitrary p drop. Same as D Aptos. Accumulated donations absorb future small liquidations.

### 5.6 Self-redeem (target == caller)

- Allowed by design (clause (5)). Behaves as partial debt repay + collateral withdraw with 1% fee. Inherits D Aptos behavior.

## 6. Interactions

### 6.1 Supra oracle dep

- Module: `supra_oracle::supra_oracle_storage` at `0xe3948c9e3a24c51c4006ef2acc44606055117d021158f320062df099c4a94150`
- Function read: `get_price(u32) -> (u128, u16, u64, u64)`
- Pkg upgrade_policy: 1 (compatible, NOT immutable). Supra Foundation can upgrade silently.
- Tier: pair 500 = "Under Supervision" (3-5 sources)
- **All risks disclosed in WARNING clause (8). No code mitigation possible in immutable.**

### 6.2 SUPRA FA at @0xa

- Native SUPRA fungible asset metadata at `0xa`. Same address as APT FA on Aptos (Move framework convention). Verified live during ONE Supra v0.4.0 deploy.

### 6.3 SupraFramework dep

- Source `git://Entropy-Foundation/aptos-core.git` `subdir aptos-move/framework/supra-framework` `rev dev`
- **FINDING I-02 (INFO)**: `rev = "dev"` is not pinned to a commit hash. ONE Supra v0.4.0 used same. Risk: framework upgrade between local compile and mainnet publish could introduce subtle ABI drift.
- **Recommend**: pin `rev` to a specific commit before mainnet publish (per `feedback_third_party_move_dep_crosscheck.md`).

### 6.4 dora-interface dep

- `git://Entropy-Foundation/dora-interface.git` `subdir supra/mainnet/core` `rev master`
- Same pinning concern as 6.3.

## 7. Errors

### 7.1 Renumbering safety

D Supra error codes:
```
E_COLLATERAL=1
E_TROVE=2
E_DEBT_MIN=3
E_STALE=4
E_SP_BAL=5
E_AMOUNT=6
E_TARGET=7
E_HEALTHY=8
E_SP_INSUFFICIENT=9
E_INSUFFICIENT_RESERVE=10
E_PRICE_ZERO=11
E_EXPO_BOUND=12
E_DECIMAL_OVERFLOW=13
E_P_CLIFF=14
E_NOT_ORIGIN=15  (was 17 in D Aptos)
E_CAP_GONE=16    (was 18 in D Aptos)
E_STALE_FUTURE=17 (new)
```

Removed: `E_PRICE_EXPO=15`, `E_PRICE_NEG=16`, `E_PRICE_UNCERTAIN=19` (Pyth-specific).

**FINDING I-03 (INFO)**: Tools/indexers/frontends parsing abort codes from D Aptos must be re-keyed for D Supra. Backwards incompatibility between sibling chains is acceptable since D Supra is a separate package, not an upgrade of D Aptos.

### 7.2 Test coverage of error paths

`D_tests.move` updated with new code numbers (15, 16) for destroy_cap tests. `E_AMOUNT=6` test still asserted for redeem-below-min via 900_000 raw input. **32/32 PASS verifies error wiring.**

## 8. Events

12 event types unchanged from D Aptos:
- `TroveOpened`, `CollateralAdded`, `TroveClosed`, `Redeemed`, `Liquidated`, `SPDeposited`, `SPDonated`, `ReserveDonated`, `SPWithdrew`, `SPClaimed`, `ReserveRedeemed`, `CapDestroyed`, `RewardSaturated`

**FINDING I-04 (INFO)**: Event field types and names are identical between D Aptos and D Supra. Indexer schema can be reused with just the package address swap.

## Findings summary

| ID | Severity | Title | Status |
|---|---|---|---|
| L-01 | LOW | No oracle confidence-band check (Supra exposes none) | ACCEPTED — disclosed in WARNING (8); code mitigation impossible in immutable |
| I-01 | INFO | Pyth-specific asserts correctly omitted | NOTED |
| I-02 | INFO | SupraFramework dep `rev = "dev"` unpinned | **PRE-MAINNET ACTION**: pin to commit hash |
| I-03 | INFO | Error codes renumbered between D Aptos and D Supra | DOCUMENTED |
| I-04 | INFO | Event schema identical to D Aptos | NOTED |

**No HIGH, MEDIUM, or LOW findings require source-code changes before testnet deploy.**

**Pre-mainnet action item**: pin SupraFramework + dora-interface dep `rev`s to specific commit hashes (I-02). Not blocking for testnet.

## Verdict

🟢 **GREEN — testnet deploy approved.**

D Supra v0.2.0 source is a faithful port of D Aptos v0.2.0 with:
- All structural logic byte-identical (modulo field rename)
- Oracle replacement validated against ONE Supra v0.4.0 mainnet pattern
- Compile + test (32/32) green with placeholder address
- All porting deltas reviewed and either accept-by-design or documented

Pre-mainnet R2 audit recommended after testnet smoke (1-2 day soak test on Supra testnet, validate oracle integration on real chain), before re-publishing to mainnet via multisig.
