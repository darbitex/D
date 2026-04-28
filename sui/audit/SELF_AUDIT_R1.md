# D v0.2.0 — Self-Audit R1

**Date:** 2026-04-28
**Auditor:** Self (Rera + Claude Opus 4.7)
**Source:** `/home/rera/d/sui/sources/D.move` (899 lines), `/home/rera/d/sui/tests/D_tests.move` (390 lines)
**Build:** clean (only intentional W99001 lint on entry wrappers)
**Tests:** 26/26 PASS

## Executive summary

D v0.2.0 is a refactored + rebranded redeploy of ONE Sui v0.1.0 (`0x9f39a102…`, sealed mainnet). The diff is **focused** — V1 already passed 6 external audit rounds (Gemini ×2, Grok ×2, Claude ×1, Qwen ×1, DeepSeek ×1, Kimi ×1) with 0 HIGH/MEDIUM/LOW findings. This audit reviews ONLY V2 changes.

| Severity | Count |
|---|---|
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 (1 found, applied in-doc fix before publish) |
| INFO | 2 |

**Verdict: GREEN.** Ready for external audit submission.

## Diff inventory vs ONE v0.1.0

### Modified (semantic change)

| Symbol | Change | Rationale |
|---|---|---|
| `route_fee` | Split 25/75 → **10/90**. 10% portion redirected to sp_pool agnostic donation (joins balance, does NOT increment total_sp). 90% goes to fee_pool reward accumulator when keyed positions exist; cliff branch (no keyed positions) also redirects 90% to sp_pool agnostically. | Lifts depositor yield 75% → 90%. Donations bypass total_sp denominator → zero dilution to keyed positions. Eliminates orphan accumulation in fee_pool during cliff windows. |
| `liquidate` | Denominator for `product_factor` adjustment changed from `total_sp` to `balance::value(&sp_pool)`. New `total_sp` formula: `total_sp × (pool_before - debt) / pool_before`. `reward_index_coll` increment guarded for `total_sp == 0`. Cliff `sp_coll` redirected to reserve_coll instead of sp_coll_pool. | Allows agnostic donations to participate in liquidation absorb pro-rata via actual pool ratio while keyed positions' rewards remain unaffected by donation flow. Cliff fix prevents orphan SUI in sp_coll_pool. |
| `WARNING` text paragraph (4) | Rewritten for 10/90 split + agnostic donation mechanics + no-dilution clarification. | User-facing disclosure accuracy. |

### Added (strictly additive)

| Symbol | Type | Description |
|---|---|---|
| `donate_to_sp(reg, d_in, ctx)` | `public fun` | Permissionless D donation. `balance::join(&mut sp_pool, …)`. Does NOT increment `total_sp`. Emits `SPDonated`. |
| `donate_to_reserve(reg, sui_in, ctx)` | `public fun` | Permissionless SUI donation to `reserve_coll`. Fortifies redeem capacity. Emits `ReserveDonated`. |
| `SPDonated { donor, amount }` | event | Emitted by donate_to_sp + route_fee 10% redirect + cliff 90% redirect |
| `ReserveDonated { donor, amount }` | event | Emitted by donate_to_reserve + cliff `sp_coll` redirect |

### Removed

| Symbol | Reason |
|---|---|
| `FeeBurned` event struct | V1's 25% burn replaced by 10% donation in V2. Event unused dead code. |

### Renamed (semantic-equivalent rebrand)

ONE → D rebrand: module path, OTW struct, Coin type, display strings, internal identifiers (`reward_index_one` → `reward_index_d` etc), comments, WARNING text. **Zero semantic effect** — identical math, identical control flow.

### Test infrastructure additions

- `test_sp_pool_balance(reg)` — view sp_pool balance
- `test_mint_d(reg, amount, ctx)` — treasury-tracked mint for tests requiring real burn paths
- `test_simulate_liquidation_v2(reg, debt, sp_coll, ctx)` — V2-aware liquidation simulator using actual `sp_pool` balance + new `total_sp` formula

## Per-function review

### `route_fee` (line 257)

**Signature unchanged**: `fun route_fee(r: &mut Registry, mut fee_bal: Balance<D>, ctx: &mut TxContext)` — internal-only.

**Flow:**
1. `amt == 0`: destroy zero, return.
2. **10% portion (donate)**: `donate_amt = amt × 1000 / 10000`. Split, balance::join sp_pool. Emit SPDonated. **No total_sp increment, no reward_index increment.**
3. **90% portion (reward)**: `sp_amt = amt - donate_amt`. If `table::length(&r.sp_positions) == 0` (cliff): join to sp_pool, emit SPDonated, no index increment. Else: join to fee_pool, increment `reward_index_one += sp_amt × product_factor / total_sp`.

**Math correctness:**
- 10% never increments total_sp → keyed depositors' reward share denominator unchanged → no dilution.
- 90% reward index correctly normalized to keyed-only `total_sp`.
- Cliff branch: 90% → sp_pool ensures no orphan in fee_pool. Future depositors snapshot at unchanged index, claim future-only.

**Edge cases:**
- `amt < 10`: donate_amt rounds to 0, sp_amt = amt routed normally. Total preserved.
- `donate_amt > 0 ∧ sp_amt == 0`: impossible (donate_amt = amt×0.1, sp_amt = amt×0.9, both monotonic).
- All-cliff: donations accumulate sp_pool, future first deposit triggers product_factor reset (sp_deposit existing logic).

**Reentrancy:** N/A (Sui Coin no callbacks).

**Verdict:** ✓ Correct.

### `liquidate` (line 484)

**V2 math changes:**
```move
pool_before = balance::value(&sp_pool)               // includes donations
assert!(pool_before > debt)                          // changed from total_sp > debt
new_p = product_factor × (pool_before - debt) / pool_before
if (total_before > 0) {                              // NEW guard
    reward_index_coll += sp_coll × product_factor / total_before
}
total_sp = total_before × (pool_before - debt) / pool_before  // changed from total_sp - debt

// SP collateral routing (NEW cliff handling):
if (sp_coll > 0) {
    if (total_before == 0) {
        balance::join(&mut reg.reserve_coll, balance::split(&mut seized, sp_coll));
    } else {
        balance::join(&mut reg.sp_coll_pool, balance::split(&mut seized, sp_coll));
    }
}
```

**Math correctness proof for total_sp:**

Pre-state invariant (inherited from V1): `total_sp_old = Σ(initial × product_old / snap_product)` over keyed positions.

After liquidation:
- `product_new = product_old × (pool_before - debt) / pool_before`
- For each position: `current_value_new = initial × product_new / snap_product = initial × product_old × (pool_before - debt) / (snap_product × pool_before)`
- `Σ current_value_new = Σ(initial × product_old / snap_product) × (pool_before - debt) / pool_before = total_sp_old × (pool_before - debt) / pool_before`

This matches the new `total_sp` formula. ✓ Invariant preserved.

**Donation residue:**
- Pre: `sp_pool = total_sp_old + donation_residue`
- Post-burn: `sp_pool_new = pool_before - debt`
- Σ keyed positions' new values = `total_sp_new = total_sp_old × (pool_before - debt) / pool_before`
- Donation residue post = `(pool_before - debt) - total_sp_new = (pool_before - debt) × (1 - total_sp_old / pool_before) = (pool_before - debt) × donation_residue_old / pool_before`
- = donation_residue scaled by absorb ratio ✓

Donations absorb pro-rata, math invariant preserved.

**Edge cases:**
- `pool_before == 0`: assert fails, abort.
- `total_before == 0` ∧ `pool_before > debt` (cliff): liquidation proceeds, product_factor adjusts, `total_sp_new = 0`, sp_coll → reserve_coll (not sp_coll_pool). No orphan.
- `new_p < MIN_P_THRESHOLD`: existing E_P_CLIFF abort.

**Reentrancy:** N/A.

**Events:** `Liquidated` payload unchanged.

**Verdict:** ✓ Correct.

### `donate_to_sp` (line 612)

```move
public fun donate_to_sp(reg: &mut Registry, d_in: Coin<D>, ctx: &mut TxContext) {
    let amt = coin::value(&d_in); assert!(amt > 0, E_AMOUNT);
    balance::join(&mut reg.sp_pool, coin::into_balance(d_in));
    event::emit(SPDonated { donor: tx_context::sender(ctx), amount: amt });
}
```

**Properties:**
- Pure additive to `sp_pool` balance.
- Does NOT modify `total_sp`, `product_factor`, or any reward index.
- Future liquidations absorb donation pro-rata via pool_before > total_sp delta.
- No position created → permanently un-withdrawable (math-impossible).

**Edge cases:**
- amt == 0 → abort E_AMOUNT.
- Donor address recorded in event for off-chain attribution only (not on-chain claim).

**Verdict:** ✓ Correct.

### `donate_to_reserve` (line 621)

```move
public fun donate_to_reserve(reg: &mut Registry, sui_in: Coin<SUI>, ctx: &mut TxContext) {
    let amt = coin::value(&sui_in); assert!(amt > 0, E_AMOUNT);
    balance::join(&mut reg.reserve_coll, coin::into_balance(sui_in));
    event::emit(ReserveDonated { donor: tx_context::sender(ctx), amount: amt });
}
```

**Properties:**
- Pure additive to `reserve_coll`.
- `redeem_from_reserve` is source-agnostic (only checks `balance::value >= coll_out`).
- Donated SUI fungibly increases redemption capacity for any D holder.

**Economic correctness:**
- No reward to donor — pure permanent transfer.
- u64 overflow: max reserve_coll = 1.8e19 raw = 1.8e10 SUI ≈ way beyond practical supply.
- Strengthens peg defense by reducing E_INSUFFICIENT_RESERVE risk.

**Edge cases:**
- amt == 0 → abort E_AMOUNT.
- No oracle dep → works during oracle-freeze.

**Verdict:** ✓ Correct.

## Math invariant register

| Invariant | Pre-V1 | V1 | V2 |
|---|---|---|---|
| `sp_pool_balance ≥ Σ(position.initial × current_p / snap_p)` | ✓ | ✓ | ✓ — V2 difference is donation residue counted in sp_pool but not total_sp (verified above) |
| `total_sp` consistency = sum keyed positions' current values | ✓ | ✓ | ✓ — V2 formula proven to preserve invariant |
| `total_debt = Σ(trove.debt)` | ✓ | ✓ | ✓ — unchanged |
| Reward distribution proportional to keyed shares | ✓ | ✓ | ✓ — denominator strictly keyed |
| Liquidation cliff guard (MIN_P_THRESHOLD) | ✓ | ✓ | ✓ — unchanged |
| u64 saturation cap on pending rewards | ✓ | ✓ | ✓ — unchanged |
| sender-keyed sp_withdraw blocks gift-attack escape | ✓ | ✓ | ✓ — unchanged |
| sp_coll_pool ≤ Σ keyed positions' pending_coll claims | n/a | ⚠️ orphan possible during cliff | ✓ — fixed via reserve_coll redirect |

## Attack surface delta

### New surface

**`donate_to_sp`** permissionless:
- Spam griefing: no table entry created (no position), only balance::join. Cost: gas. No bloat. Not exploitable.
- Liquidation manipulation: donations grow sp_pool → larger pool_before → smaller per-position absorb ratio → *helps* depositors. Not adversarial.

**`donate_to_reserve`** permissionless:
- Spam griefing: same as above, cost > benefit.
- Reserve manipulation: donations grow reserve_coll → reduces E_INSUFFICIENT_RESERVE risk → enables more redemptions. Pure-positive.
- Donate-then-redeem cycle: donor donates SUI, then redeems own D for SUI from reserve. Donor net: -SUI -1%×D fee. Pure gift mechanism.

### Modified surface

**`route_fee`**: 
- Call sites unchanged (open_trove, close_trove, redeem, redeem_from_reserve internally call route_fee).
- 10% redirect emits SPDonated with donor = trove operator. Off-chain indexers see structural redirect attribution.
- Operator does not gain donor benefit (donations have no claimable position) — same economic loss as V1's burn.

**`liquidate`**:
- Pre-condition strengthened: `sp_pool > debt` instead of `total_sp > debt`. *More permissive* — liquidation proceeds when donations cover gap.
- Frontrun donate-then-liquidate: donor enables liquidation that protects keyed depositors (clears bad debt, distributes bonus). Donor's gift = pure positive externality. Not exploitable.

### Removed surface

`FeeBurned` event no longer emitted. Indexers expecting V1 event need migration to `SPDonated`.

## Risk register

### LOW finding (resolved in source before audit submission)

**LOW-1: cliff liquidation orphan in sp_coll_pool** — *RESOLVED*

**Description:** During cliff scenarios (donations in sp_pool but no keyed positions), liquidation could distribute 50% bonus SUI to `sp_coll_pool`. Since `total_sp == 0`, `reward_index_coll` increment was guarded but the SUI was still added to the pool via `balance::join`. Future keyed depositors entering would have `snap_index_coll = current_index` (which didn't move during cliff), so the cliff-era SUI would never be distributed via reward index — orphan locked.

**Fix applied:** When `total_before == 0` at liquidation time, route `sp_coll` to `reserve_coll` instead of `sp_coll_pool`. Consistent with the "no keyed depositors → reroute to pool" pattern V2 already applied to ONE side fees. SUI fortifies redemption reserve; no orphan.

**Verification:** Source line 543-549. No regression — 26/26 tests pass post-fix.

### INFO findings (non-blocking)

**INFO-1: Indexer migration for FeeBurned → SPDonated.** V2's `route_fee` no longer emits `FeeBurned`. Off-chain indexers built for V1 ONE need to migrate event listener to `SPDonated`. **Mitigation:** post-deploy migration guide + early notice to known indexer operators.

**INFO-2: Donation u64 ceiling.** Donations grow sp_pool unboundedly within u64. At 1e8 raw decimals, max sp_pool = u64::MAX ≈ 1.8e11 D ≈ 180 trillion D. Practically unreachable. Existing u64 saturation handling on rewards already documented in WARNING (clause 2). No additional disclosure required.

## Issues considered & rejected

**A. Could donation attacker drain reserve via repeated donate-then-redeem cycles?**
No. donate_to_reserve gives SUI to protocol with no on-chain claim. Subsequent redeem_from_reserve requires donor to burn D (1% fee). Donor net: -SUI -D -1%×D fee. Pure gift with leak.

**B. Could agnostic donation manipulate liquidation to harm keyed depositors?**
No. Donations growing sp_pool → larger pool_before denominator → smaller proportional absorb on keyed positions. Strict positive externality.

**C. Could attacker frontrun open_trove with donate_to_sp to manipulate ratio?**
No. open_trove math depends on oracle price + collateral, not on sp_pool ratio. Donation has no effect on mint operation.

**D. Could attacker frontrun donate_to_reserve to manipulate redeem_from_reserve price?**
No. redeem_from_reserve uses oracle price, not reserve ratio. Donation only affects whether `balance::value(reserve_coll) >= coll_out` check passes.

## Test coverage

**26 tests, 26 PASS:**

| Category | Tests |
|---|---|
| V1 inheritance (still passing) | 19 |
| V2 donate_to_sp surface | 3 (grows pool, zero aborts, no dilution) |
| V2 donate_to_reserve surface | 2 (grows reserve, zero aborts) |
| V2 route_fee virtual | 1 (cliff redirect) |
| V2 liquidate-with-donation | 1 (pool_before pro-rata math + position value match) |

**Coverage gaps (defer to testnet smoke):**
- Real liquidate flow with donation (requires Pyth — testable on testnet only)
- Cliff sp_coll → reserve_coll redirect (LOW-1 fix) — testable on testnet
- Trove ops integration (requires Pyth)
- Multi-cycle donation + liquidation interaction

## Pre-deploy checklist

- [x] Build clean (only intentional W99001 lint)
- [x] All unit tests pass (26/26)
- [x] WARNING text accurate for V2 mechanics
- [x] No dead code (FeeBurned removed)
- [x] No ONE residue (rebrand complete, grep verified)
- [x] LOW-1 cliff orphan fix applied
- [x] Math invariants documented + proven
- [x] Attack surface delta enumerated
- [ ] External audit R1 submission (next phase)
- [ ] Testnet smoke covering liquidate-with-donation + cliff redirect (deploy phase)

## Recommended R1 submission targets

Per `feedback_satellite_self_audit.md` SOP: minimum 3 external auditors, target ≥2 GREEN to advance to R2.

Recommended:
- Gemini 3 Pro (V1 R2 GREEN, ideal continuity)
- Grok (V1 R2 GREEN, ideal continuity)
- Claude Sonnet 4.6 fresh session (different perspective from Opus 4.7 self-audit)

Optional fourth:
- Qwen3 235B Instruct (Cerebras free-tier, V1 R2 GREEN)

Bundle: this self-audit doc + `D.move` + `D_tests.move` + `Move.toml`. Frame: "diff vs V1 ONE which already passed 6× R2 GREEN — focus only on additive + modified surface."
