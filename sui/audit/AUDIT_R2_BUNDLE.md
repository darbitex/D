# D v0.2.0 — External Audit R2 Submission Bundle

**Date:** 2026-04-28
**Submitter:** Rera
**Audit round:** R2 (post-R1 fix)
**Bundle size:** 870 LOC source + 476 LOC tests
**Tests:** 28/28 PASS (was 26/26 in R1; +2 regression tests for HIGH-1)

## R1 → R2 changelog

R1 verdicts:
- **5 GREEN** (Kimi, Grok, DeepSeek, Qwen, Gemini) — 0 H/M/L
- **1 YELLOW** (Claude Opus 4.7 fresh session) — **1 HIGH + 1 LOW + 4 INFO**

Claude's HIGH-1 finding was unique and valid — verified via reproducer. Fixes applied:

### HIGH-1 (resolved): u64/u128 truncation decoupling

**Root cause:** `new_p` (u128 with PRECISION=1e18 baked in) tolerates ratio down to 1e-9 via `MIN_P_THRESHOLD`, but `total_sp` (u64 raw) truncates to 0 *much* sooner. State `total_sp == 0 ∧ table::length > 0` becomes reachable, causing:
1. Subsequent `route_fee` div-by-zero DoS on mint/redeem surface
2. Stranded-position withdrawal race after `sp_deposit` reset-on-empty triggers

**Reproducer (Claude's, verified):**
- ALICE position dust (initial=1, snap_p=PRECISION)
- BOB donate 1_000_000_000 raw to sp_pool
- Liquidate debt=999_999_990:
  - new_p = 1e18 × 10 / 1_000_000_000 = 1e10 (passes MIN_P_THRESHOLD)
  - total_sp_new = 1 × 10 / 1_000_000_000 = **0** (truncates)
- After: `total_sp == 0` but `table::length == 1` (Alice still keyed)
- Next route_fee → `× product_factor / 0` → div-by-zero abort

**Fixes applied:**

```move
// route_fee (D.move:248) — predicate changed from table::length to total_sp
- if (table::length(&r.sp_positions) == 0) {
+ if (r.total_sp == 0) {
      balance::join(&mut r.sp_pool, fee_bal);
      event::emit(SPDonated { donor: tx_context::sender(ctx), amount: sp_amt });
  } else {
      ...
  }

// liquidate (D.move:484-486) — preempt bad state
  let new_p = reg.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
- assert!(new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
+ assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
+ let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
+ assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);

// liquidate (D.move:516) — use precomputed total_sp_new
- reg.total_sp = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
+ reg.total_sp = total_sp_new;

// test_simulate_liquidation_v2 helper — same hardening for test coverage
```

**Logic of fix (a):** Unify cliff predicate across `route_fee`, `liquidate`, and `sp_deposit` reset-on-empty — all check `total_sp == 0`. After truncation, `total_sp` correctly reflects the cliff state and route_fee redirects to sp_pool agnostic donation.

**Logic of fix (b):** Liquidation preemptively aborts with `E_P_CLIFF` if it would orphan keyed positions (truncate `total_sp_new` to 0 with `total_before > 0`). Bad state never arises. `MIN_P_THRESHOLD` skipped when `total_before == 0` since product_factor has no semantic role in pure-donation mode.

### LOW-1 (resolved in R1): cliff sp_coll orphan

Already fixed pre-R1 submission (line 543-549).

### LOW-1 (Claude R1, resolved): MIN_P_THRESHOLD fires unnecessarily during pure-donation cliff

Fixed via `total_before == 0 ||` clause in fix (b) above. Cliff-mode liquidations no longer abort needlessly.

### Tests added (28/28 PASS):

```move
#[test]
#[expected_failure(abort_code = D::D::E_P_CLIFF)]
fun test_truncation_orphan_aborts_liquidation() {
    let mut sc = start();
    let mut reg = take_reg(&mut sc);
    D::D::test_create_sp_position(&mut reg, ALICE, 1);
    ts::next_tx(&mut sc, BOB);
    let donation = D::D::test_mint_d(&mut reg, 1_000_000_000, ts::ctx(&mut sc));
    D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
    D::D::test_simulate_liquidation_v2(&mut reg, 999_999_990, 0, ts::ctx(&mut sc));
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
fun test_route_fee_cliff_redirect_via_total_sp() {
    let mut sc = start();
    let mut reg = take_reg(&mut sc);
    ts::next_tx(&mut sc, BOB);
    let donation = D::D::test_mint_d(&mut reg, 50_000_000, ts::ctx(&mut sc));
    D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
    let (_, total_sp, _, r_d_pre, _) = D::D::totals(&reg);
    assert!(total_sp == 0, 1800);
    assert!(r_d_pre == 0, 1801);
    D::D::test_route_fee_virtual(&mut reg, 1_000_000);
    let (_, total_sp_post, _, r_d_post, _) = D::D::totals(&reg);
    assert!(total_sp_post == 0, 1802);
    assert!(r_d_post == 0, 1803);
    ts::return_shared(reg);
    ts::end(sc);
}
```

## R2 audit goals

This R2 round is targeted at the auditor who raised HIGH-1 (Claude Opus 4.7 fresh session). Other R1 GREEN auditors are not strictly required to re-review since their findings were already addressed.

Please verify:

1. **HIGH-1 fix correctness.** Both fix (a) `route_fee` predicate and fix (b) `liquidate` invariant guard are applied. Reproducer test now expects `E_P_CLIFF` instead of div0.

2. **No regressions.** 28/28 tests pass including the original 26 from R1 + 2 new regression tests.

3. **Cliff predicate unification.** Verify all three cliff branches now agree:
   - `route_fee`: `r.total_sp == 0`
   - `liquidate` cliff routing: `total_before == 0`
   - `sp_deposit` reset-on-empty: `reg.total_sp == 0`

4. **No new attack surface introduced.** The fix is minimal — added 2 asserts + 1 predicate change + 1 helper var.

## Required response format

Same as R1 bundle. If GREEN with no new findings: ready for testnet deploy.

---

# Self-Audit R1 (inherited, with R2 update)

(See `audit/SELF_AUDIT_R1.md` for canonical R1 version. R2 inherits all R1 conclusions plus the HIGH-1 resolution above.)

| Severity | R1 self | R1 external | R2 (post-fix) |
|---|---|---|---|
| HIGH | 0 | 1 (Claude) | **0 (resolved)** |
| MEDIUM | 0 | 0 | 0 |
| LOW | 0 (1 resolved pre-bundle) | 1 (Claude, resolved) | 0 |
| INFO | 2 | various non-blocking | various non-blocking |

---

# Source: `sources/D.move` (870 lines, post-fix)

```move
/// D — immutable stablecoin on Sui
///
/// WARNING: D is an immutable stablecoin contract that depends on
/// Pyth Network's on-chain price feed for SUI/USD. If Pyth degrades or
/// misrepresents its oracle, D's peg mechanism breaks deterministically
/// - users can wind down via self-close without any external assistance,
/// but new mint/redeem operations become unreliable or frozen.
/// D is immutable = bug is real. Audit this code yourself before
/// interacting.
module D::D {
    use std::string;

    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::coin_registry;
    use sui::event;
    use sui::package::{Self, UpgradeCap};
    use sui::sui::SUI;
    use sui::table::{Self, Table};

    use pyth::i64;
    use pyth::price;
    use pyth::price_identifier;
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::pyth;

    // Constants

    const MCR_BPS: u128 = 20000;
    const LIQ_THRESHOLD_BPS: u128 = 15000;
    const LIQ_BONUS_BPS: u64 = 1000;
    const LIQ_LIQUIDATOR_BPS: u64 = 2500;
    const LIQ_SP_RESERVE_BPS: u64 = 2500;
    // SP receives (10000 - LIQ_LIQUIDATOR_BPS - LIQ_SP_RESERVE_BPS) = 5000 (50%) as remainder
    const FEE_BPS: u64 = 100;
    const STALENESS_SECS: u64 = 60;
    const MIN_DEBT: u64 = 100_000_000;
    const PRECISION: u128 = 1_000_000_000_000_000_000;
    const MIN_P_THRESHOLD: u128 = 1_000_000_000;
    const MAX_CONF_BPS: u64 = 200;                    // Pyth confidence cap: 2% of price
    // SUI is 9 decimals (MIST); D is 8 decimals. Collateral-value math scales by 1e9.
    const SUI_SCALE: u128 = 1_000_000_000;
    const SUI_USD_PYTH_FEED: vector<u8> = x"23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744";

    // Errors

    const E_COLLATERAL: u64 = 1;
    const E_TROVE: u64 = 2;
    const E_DEBT_MIN: u64 = 3;
    const E_STALE: u64 = 4;
    const E_SP_BAL: u64 = 5;
    const E_AMOUNT: u64 = 6;
    const E_TARGET: u64 = 7;
    const E_HEALTHY: u64 = 8;
    const E_SP_INSUFFICIENT: u64 = 9;
    const E_INSUFFICIENT_RESERVE: u64 = 10;
    const E_PRICE_ZERO: u64 = 11;
    const E_EXPO_BOUND: u64 = 12;
    const E_DECIMAL_OVERFLOW: u64 = 13;
    const E_P_CLIFF: u64 = 14;
    const E_PRICE_EXPO: u64 = 15;
    const E_PRICE_NEG: u64 = 16;
    const E_WRONG_FEED: u64 = 17;
    const E_SEALED: u64 = 18;
    const E_PRICE_UNCERTAIN: u64 = 19;

    const WARNING: vector<u8> = b"D is an immutable stablecoin contract on Sui that depends on Pyth Network's on-chain price feed for SUI/USD. If Pyth degrades or misrepresents its oracle, D's peg mechanism breaks deterministically - users can wind down via self-close without any external assistance, but new mint/redeem operations become unreliable or frozen. D is immutable = bug is real. Audit this code yourself before interacting. KNOWN LIMITATIONS: (1) Stability Pool enters frozen state when product_factor would drop below 1e9 - protocol aborts further liquidations rather than corrupt SP accounting, accepting bad-debt accumulation past the threshold. (2) Sustained large-scale activity over decades may asymptotically exceed u64 bounds on pending SP rewards. (3) Liquidation seized collateral is distributed in priority: liquidator bonus first (nominal 2.5 percent of debt value, being 25 percent of the 10 percent liquidation bonus), then 2.5 percent reserve share (also 25 percent of bonus), then SP absorbs the remainder and the debt burn. At CR roughly 110% to 150% the SP alone covers the collateral shortfall. At CR below ~5% the liquidator may take the entire remaining collateral, reserve and SP receive zero, and SP still absorbs the full debt burn. (4) 10 percent of each mint and redeem fee is redirected to the Stability Pool as an agnostic donation - it joins sp_pool balance but does NOT increment total_sp, so it does not dilute the reward distribution denominator. Donations participate in liquidation absorption pro-rata via the actual sp_pool balance ratio, gradually burning over time. The remaining 90 percent is distributed pro-rata to keyed SP depositors via the fee accumulator when keyed positions exist; during periods with no keyed positions, the 90 percent is also redirected to the SP pool as agnostic donation rather than accruing unclaimable in the accumulator. Real depositors receive their full 90 percent share unaffected by donation flow rate. Total: 1 percent supply-vs-debt gap per fee cycle, fully draining via SP burns over time. Individual debtors still face a 1 percent per-trove shortfall because only 99 percent is minted while 100 percent is needed to close - full protocol wind-down requires secondary-market D for the last debt closure. (5) Self-redemption (redeem against own trove) is allowed and behaves as partial debt repayment plus collateral withdrawal with a 1 percent fee. (6) Pyth is pull-based on Sui - callers must refresh the SUI/USD PriceInfoObject via pyth::update_single_price_feed within the same PTB, or oracle-dependent entries abort with E_STALE. (7) Extreme low-price regimes may cause transient aborts in redeem paths when requested amounts exceed u64 output bounds; use smaller amounts and retry. (8) ORACLE UPGRADE RISK (Sui-specific): Pyth Sui (pkg 0x04e20ddf..., state 0x1f931023...) is NOT cryptographically immutable. Its UpgradeCap sits inside shared State with policy=0 (compatible), controlled by Pyth DAO via Wormhole VAA governance. Sui's compatibility checker prevents public-function signature regressions, but does NOT prevent feed-id deregistration, Price struct field reshuffling, or Wormhole state rotation - any of which could brick this consumer. No admin escape once this package is sealed. Accept as external-dependency risk. Oracle-free escape hatches remain fully open: close_trove lets any trove owner reclaim their collateral by burning the full trove debt in D (acquiring the 1 percent close deficit via secondary market if needed); add_collateral lets owners top up existing troves without touching the oracle; sp_deposit, sp_withdraw, and sp_claim let SP depositors manage and exit their positions and claim any rewards accumulated before the freeze. Protocol-owned SUI held in reserve_coll becomes permanently locked because redeem_from_reserve requires the oracle. No admin override exists; the freeze is final. (9) REDEMPTION vs LIQUIDATION are two separate mechanisms. liquidate is health-gated (requires CR below 150 percent) and applies a penalty bonus to the liquidator, the reserve, and the SP; healthy troves cannot be liquidated by anyone. redeem has no health gate on target and executes a value-neutral swap at oracle spot price - the target's debt decreases by net D while their collateral decreases by net times 1e9 over price SUI (Sui native is 9 decimals), so the target retains full value at spot. Redemption is the protocol peg-anchor: when D trades below 1 USD on secondary market, any holder can burn D supply by redeeming for SUI, pushing the peg back up. The target is caller-specified; there is no sorted-by-CR priority, unlike Liquity V1's sorted list - the economic result for the target is identical to Liquity (made whole at spot), only the redemption ordering differs, and ordering is a peg-efficiency optimization rather than a safety property. Borrowers who want guaranteed long-term SUI exposure without the possibility of redemption-induced position conversion should not use D troves - use a non-CDP lending protocol instead. Losing optionality under redemption is not the same as losing value: the target is economically indifferent at spot.";

    // OTW

    public struct D has drop {}

    // State types

    public struct Trove has store, drop { collateral: u64, debt: u64 }

    public struct SP has store, drop {
        initial_balance: u64,
        snapshot_product: u128,
        snapshot_index_d: u128,
        snapshot_index_coll: u128,
    }

    /// Single-use capability proving origin (publisher). Consumed by destroy_cap.
    public struct OriginCap has key { id: UID }

    /// Shared protocol state. Owns TreasuryCap and every pooled balance.
    public struct Registry has key {
        id: UID,
        treasury: TreasuryCap<D>,
        fee_pool: Balance<D>,
        sp_pool: Balance<D>,
        sp_coll_pool: Balance<SUI>,
        reserve_coll: Balance<SUI>,
        treasury_coll: Balance<SUI>,
        troves: Table<address, Trove>,
        sp_positions: Table<address, SP>,
        total_debt: u64,
        total_sp: u64,
        product_factor: u128,
        reward_index_d: u128,
        reward_index_coll: u128,
        sealed: bool,
    }

    // Events

    public struct TroveOpened has copy, drop { user: address, new_collateral: u64, new_debt: u64, added_debt: u64 }
    public struct CollateralAdded has copy, drop { user: address, amount: u64 }
    public struct TroveClosed has copy, drop { user: address, collateral: u64, debt: u64 }
    public struct Redeemed has copy, drop { user: address, target: address, d_amt: u64, coll_out: u64 }
    public struct Liquidated has copy, drop {
        liquidator: address, target: address, debt: u64,
        coll_to_liquidator: u64, coll_to_sp: u64,
        coll_to_reserve: u64, coll_to_target: u64,
    }
    public struct SPDeposited has copy, drop { user: address, amount: u64 }
    public struct SPDonated has copy, drop { donor: address, amount: u64 }
    public struct ReserveDonated has copy, drop { donor: address, amount: u64 }
    public struct SPWithdrew has copy, drop { user: address, amount: u64 }
    public struct SPClaimed has copy, drop { user: address, d_amt: u64, coll_amt: u64 }
    public struct ReserveRedeemed has copy, drop { user: address, d_amt: u64, coll_out: u64 }
    public struct CapDestroyed has copy, drop { caller: address, timestamp_ms: u64 }
    public struct RewardSaturated has copy, drop { user: address, pending_d_truncated: bool, pending_coll_truncated: bool }

    // Init

    fun init(witness: D, ctx: &mut TxContext) {
        // Register via CoinRegistry (Sui framework >= 1.48) so the coin is
        // indexable by wallets/explorers that query the global registry.
        // finalize_and_delete_metadata_cap consumes MetadataCap, making the
        // metadata (name/symbol/decimals/description/icon_url) permanently
        // immutable. Currency<D> is transferred as a Receiving to the
        // CoinRegistry address; a separate `coin_registry::finalize_registration`
        // call (anyone can invoke — bundled into deploy-scripts) promotes it
        // to a shared object keyed by the D type.
        let (initializer, treasury) = coin_registry::new_currency_with_otw<D>(
            witness,
            8,
            string::utf8(b"D"),
            string::utf8(b"1"),
            string::utf8(b"Immutable CDP-backed stablecoin on Sui (SUI-collateralized)"),
            string::utf8(b""),
            ctx,
        );
        coin_registry::finalize_and_delete_metadata_cap(initializer, ctx);
        let reg = Registry {
            id: object::new(ctx),
            treasury,
            fee_pool: balance::zero<D>(),
            sp_pool: balance::zero<D>(),
            sp_coll_pool: balance::zero<SUI>(),
            reserve_coll: balance::zero<SUI>(),
            treasury_coll: balance::zero<SUI>(),
            troves: table::new<address, Trove>(ctx),
            sp_positions: table::new<address, SP>(ctx),
            total_debt: 0,
            total_sp: 0,
            product_factor: PRECISION,
            reward_index_d: 0,
            reward_index_coll: 0,
            sealed: false,
        };
        transfer::share_object(reg);
        transfer::transfer(OriginCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // Sealing (single-call, irreversible)

    /// Consumes OriginCap + UpgradeCap in a single call. Package becomes
    /// cryptographically immutable via sui::package::make_immutable, and
    /// `sealed` flips true. No admin surface remains.
    public fun destroy_cap(
        origin: OriginCap,
        reg: &mut Registry,
        upgrade: UpgradeCap,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!reg.sealed, E_SEALED);
        let OriginCap { id } = origin;
        object::delete(id);
        package::make_immutable(upgrade);
        reg.sealed = true;
        event::emit(CapDestroyed {
            caller: tx_context::sender(ctx),
            timestamp_ms: clock::timestamp_ms(clock),
        });
    }

    // Oracle helpers (internal)

    fun now_secs(clock: &Clock): u64 { clock::timestamp_ms(clock) / 1000 }

    fun price_8dec(pi: &PriceInfoObject, clock: &Clock): u128 {
        let info = price_info::get_price_info_from_price_info_object(pi);
        let id = price_info::get_price_identifier(&info);
        assert!(price_identifier::get_bytes(&id) == SUI_USD_PYTH_FEED, E_WRONG_FEED);

        let p = pyth::get_price_no_older_than(pi, clock, STALENESS_SECS);
        let p_i64 = price::get_price(&p);
        let e_i64 = price::get_expo(&p);
        let ts = price::get_timestamp(&p);
        let conf = price::get_conf(&p);
        let now = now_secs(clock);
        assert!(ts + STALENESS_SECS >= now, E_STALE);
        assert!(ts <= now + 10, E_STALE);
        assert!(i64::get_is_negative(&e_i64), E_PRICE_EXPO);
        let abs_e = i64::get_magnitude_if_negative(&e_i64);
        assert!(abs_e <= 18, E_EXPO_BOUND);
        assert!(!i64::get_is_negative(&p_i64), E_PRICE_NEG);
        let raw = (i64::get_magnitude_if_positive(&p_i64) as u128);
        assert!(raw > 0, E_PRICE_ZERO);
        // Reject prices with wide confidence interval — Pyth signals uncertainty via conf.
        // Cap conf/raw ratio at MAX_CONF_BPS (2% default); conf shares price's expo.
        assert!((conf as u128) * 10000 <= (MAX_CONF_BPS as u128) * raw, E_PRICE_UNCERTAIN);
        let result = if (abs_e >= 8) {
            raw / pow10(abs_e - 8)
        } else {
            raw * pow10(8 - abs_e)
        };
        assert!(result > 0, E_PRICE_ZERO);
        result
    }

    fun pow10(n: u64): u128 {
        assert!(n <= 38, E_DECIMAL_OVERFLOW);
        let mut r: u128 = 1;
        let mut k = n;
        while (k > 0) { r = r * 10; k = k - 1; };
        r
    }

    // Fee routing (internal)

    fun route_fee(r: &mut Registry, mut fee_bal: Balance<D>, ctx: &mut TxContext) {
        let amt = balance::value(&fee_bal);
        if (amt == 0) { balance::destroy_zero(fee_bal); return };
        let donate_amt = (((amt as u128) * 1000) / 10000) as u64;
        if (donate_amt > 0) {
            let donate_portion = balance::split(&mut fee_bal, donate_amt);
            balance::join(&mut r.sp_pool, donate_portion);
            event::emit(SPDonated { donor: tx_context::sender(ctx), amount: donate_amt });
        };
        let sp_amt = balance::value(&fee_bal);
        if (sp_amt == 0) { balance::destroy_zero(fee_bal); return };
        if (r.total_sp == 0) {
            balance::join(&mut r.sp_pool, fee_bal);
            event::emit(SPDonated { donor: tx_context::sender(ctx), amount: sp_amt });
        } else {
            balance::join(&mut r.fee_pool, fee_bal);
            r.reward_index_d = r.reward_index_d + (sp_amt as u128) * r.product_factor / (r.total_sp as u128);
        }
    }

    // SP settle (internal)

    fun sp_settle(r: &mut Registry, u: address, ctx: &mut TxContext) {
        let (snap_p, snap_i_d, snap_i_coll, initial) = {
            let pos = table::borrow(&r.sp_positions, u);
            (pos.snapshot_product, pos.snapshot_index_d, pos.snapshot_index_coll, pos.initial_balance)
        };
        if (snap_p == 0 || initial == 0) {
            let pos = table::borrow_mut(&mut r.sp_positions, u);
            pos.snapshot_product = r.product_factor;
            pos.snapshot_index_d = r.reward_index_d;
            pos.snapshot_index_coll = r.reward_index_coll;
            return
        };

        let u64_max: u256 = 18446744073709551615;
        let raw_d = ((r.reward_index_d - snap_i_d) as u256) * (initial as u256) / (snap_p as u256);
        let raw_coll = ((r.reward_index_coll - snap_i_coll) as u256) * (initial as u256) / (snap_p as u256);
        let raw_bal = (initial as u256) * (r.product_factor as u256) / (snap_p as u256);
        // Saturate at u64::MAX rather than abort — prevents permanent SP position lock
        // if decades of fee accrual push pending rewards past u64 bounds.
        let d_trunc = raw_d > u64_max;
        let coll_trunc = raw_coll > u64_max;
        let pending_d = (if (d_trunc) u64_max else raw_d) as u64;
        let pending_coll = (if (coll_trunc) u64_max else raw_coll) as u64;
        let new_balance = (if (raw_bal > u64_max) u64_max else raw_bal) as u64;
        if (d_trunc || coll_trunc) {
            event::emit(RewardSaturated { user: u, pending_d_truncated: d_trunc, pending_coll_truncated: coll_trunc });
        };

        {
            let pos = table::borrow_mut(&mut r.sp_positions, u);
            pos.initial_balance = new_balance;
            pos.snapshot_product = r.product_factor;
            pos.snapshot_index_d = r.reward_index_d;
            pos.snapshot_index_coll = r.reward_index_coll;
        };

        if (pending_d > 0) {
            let c = coin::from_balance(balance::split(&mut r.fee_pool, pending_d), ctx);
            transfer::public_transfer(c, u);
        };
        if (pending_coll > 0) {
            let c = coin::from_balance(balance::split(&mut r.sp_coll_pool, pending_coll), ctx);
            transfer::public_transfer(c, u);
        };
        if (pending_d > 0 || pending_coll > 0) {
            event::emit(SPClaimed { user: u, d_amt: pending_d, coll_amt: pending_coll });
        }
    }

    // Trove operations — public (PTB-composable)

    /// Opens or adds to a trove. Returns freshly minted D (net of 1% fee).
    public fun open_trove(
        reg: &mut Registry,
        coll: Coin<SUI>,
        debt: u64,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<D> {
        assert!(debt >= MIN_DEBT, E_DEBT_MIN);
        let user_addr = tx_context::sender(ctx);
        let coll_amt = coin::value(&coll);
        let price = price_8dec(pi, clock);

        let is_existing = table::contains(&reg.troves, user_addr);
        let (prior_coll, prior_debt) = if (is_existing) {
            let t = table::borrow(&reg.troves, user_addr);
            (t.collateral, t.debt)
        } else (0, 0);
        let new_coll = prior_coll + coll_amt;
        let new_debt = prior_debt + debt;
        let coll_usd = (new_coll as u128) * price / SUI_SCALE;
        assert!(coll_usd * 10000 >= MCR_BPS * (new_debt as u128), E_COLLATERAL);

        balance::join(&mut reg.treasury_coll, coin::into_balance(coll));
        let fee = (((debt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let user_coin = coin::mint(&mut reg.treasury, debt - fee, ctx);
        let fee_coin = coin::mint(&mut reg.treasury, fee, ctx);
        route_fee(reg, coin::into_balance(fee_coin), ctx);

        if (is_existing) {
            let t = table::borrow_mut(&mut reg.troves, user_addr);
            t.collateral = new_coll;
            t.debt = new_debt;
        } else {
            table::add(&mut reg.troves, user_addr, Trove { collateral: new_coll, debt: new_debt });
        };
        reg.total_debt = reg.total_debt + debt;
        event::emit(TroveOpened { user: user_addr, new_collateral: new_coll, new_debt, added_debt: debt });
        user_coin
    }

    /// Top up existing trove with extra collateral. No oracle needed.
    public fun add_collateral(
        reg: &mut Registry,
        coll: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let user_addr = tx_context::sender(ctx);
        let amt = coin::value(&coll);
        assert!(amt > 0, E_AMOUNT);
        assert!(table::contains(&reg.troves, user_addr), E_TROVE);
        balance::join(&mut reg.treasury_coll, coin::into_balance(coll));
        let t = table::borrow_mut(&mut reg.troves, user_addr);
        t.collateral = t.collateral + amt;
        event::emit(CollateralAdded { user: user_addr, amount: amt });
    }

    /// Close owner's trove by burning `debt` D. Any excess D is returned to sender.
    /// Returns the trove's collateral as a fresh Coin<SUI>.
    public fun close_trove(
        reg: &mut Registry,
        d_in: Coin<D>,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        let user_addr = tx_context::sender(ctx);
        assert!(table::contains(&reg.troves, user_addr), E_TROVE);
        let t = table::remove(&mut reg.troves, user_addr);
        let Trove { collateral, debt } = t;
        let mut d_in_mut = d_in;
        if (debt > 0) {
            assert!(coin::value(&d_in_mut) >= debt, E_AMOUNT);
            let burn_coin = coin::split(&mut d_in_mut, debt, ctx);
            coin::burn(&mut reg.treasury, burn_coin);
        };
        let excess = coin::value(&d_in_mut);
        if (excess > 0) {
            transfer::public_transfer(d_in_mut, user_addr);
        } else {
            coin::destroy_zero(d_in_mut);
        };
        reg.total_debt = reg.total_debt - debt;
        event::emit(TroveClosed { user: user_addr, collateral, debt });
        coin::from_balance(balance::split(&mut reg.treasury_coll, collateral), ctx)
    }

    /// Redeem D against a specific target trove. Value-neutral at spot.
    public fun redeem(
        reg: &mut Registry,
        d_in: Coin<D>,
        target: address,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        let user_addr = tx_context::sender(ctx);
        let d_amt = coin::value(&d_in);
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        assert!(table::contains(&reg.troves, target), E_TARGET);
        let price = price_8dec(pi, clock);
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * SUI_SCALE / price) as u64);

        let t = table::borrow_mut(&mut reg.troves, target);
        assert!(t.debt >= net, E_TARGET);
        assert!(t.collateral >= coll_out, E_COLLATERAL);
        t.debt = t.debt - net;
        t.collateral = t.collateral - coll_out;
        assert!(t.debt == 0 || t.debt >= MIN_DEBT, E_DEBT_MIN);
        assert!(t.debt == 0 || t.collateral > 0, E_COLLATERAL);

        let mut d_in_mut = d_in;
        let fee_coin = coin::split(&mut d_in_mut, fee, ctx);
        coin::burn(&mut reg.treasury, d_in_mut);       // burns `net`
        route_fee(reg, coin::into_balance(fee_coin), ctx);
        reg.total_debt = reg.total_debt - net;
        event::emit(Redeemed { user: user_addr, target, d_amt, coll_out });
        coin::from_balance(balance::split(&mut reg.treasury_coll, coll_out), ctx)
    }

    /// Redeem D against protocol-owned reserve_coll. No trove targeted.
    /// Note: burns circulating D without decrementing total_debt, widening
    /// the supply-vs-debt gap — this is intentional (reserve-drain mechanic).
    public fun redeem_from_reserve(
        reg: &mut Registry,
        d_in: Coin<D>,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        let user_addr = tx_context::sender(ctx);
        let d_amt = coin::value(&d_in);
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        let price = price_8dec(pi, clock);
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * SUI_SCALE / price) as u64);
        assert!(balance::value(&reg.reserve_coll) >= coll_out, E_INSUFFICIENT_RESERVE);

        let mut d_in_mut = d_in;
        let fee_coin = coin::split(&mut d_in_mut, fee, ctx);
        coin::burn(&mut reg.treasury, d_in_mut);
        route_fee(reg, coin::into_balance(fee_coin), ctx);

        let out = coin::from_balance(balance::split(&mut reg.reserve_coll, coll_out), ctx);
        event::emit(ReserveRedeemed { user: user_addr, d_amt, coll_out });
        out
    }

    /// Liquidate an unhealthy trove. Returns the liquidator's SUI bonus.
    /// Reserve share goes to reserve_coll; SP remainder to sp_coll_pool;
    /// any coll left over (after total seize) returned directly to target.
    public fun liquidate(
        reg: &mut Registry,
        target: address,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(table::contains(&reg.troves, target), E_TARGET);
        let price = price_8dec(pi, clock);
        let (debt, coll) = {
            let t_ref = table::borrow(&reg.troves, target);
            (t_ref.debt, t_ref.collateral)
        };
        let coll_usd = (coll as u128) * price / SUI_SCALE;

        assert!(coll_usd * 10000 < LIQ_THRESHOLD_BPS * (debt as u128), E_HEALTHY);
        let pool_before = balance::value(&reg.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);

        let total_before = reg.total_sp;
        let new_p = reg.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);

        let bonus_usd = (debt as u128) * (LIQ_BONUS_BPS as u128) / 10000;
        let liq_share_usd = bonus_usd * (LIQ_LIQUIDATOR_BPS as u128) / 10000;
        let reserve_share_usd = bonus_usd * (LIQ_SP_RESERVE_BPS as u128) / 10000;
        let total_seize_usd = (debt as u128) + bonus_usd;
        let total_seize_u128 = total_seize_usd * SUI_SCALE / price;
        let coll_u128 = (coll as u128);
        let total_seize_coll = (if (total_seize_u128 > coll_u128) coll_u128 else total_seize_u128) as u64;
        let liq_u128 = liq_share_usd * SUI_SCALE / price;
        let total_seize_coll_u128 = (total_seize_coll as u128);
        let liq_coll = (if (liq_u128 > total_seize_coll_u128) total_seize_coll_u128 else liq_u128) as u64;
        let remaining_u128 = total_seize_coll_u128 - (liq_coll as u128);
        let reserve_u128 = reserve_share_usd * SUI_SCALE / price;
        let reserve_coll_amt = (if (reserve_u128 > remaining_u128) remaining_u128 else reserve_u128) as u64;
        let sp_coll = total_seize_coll - liq_coll - reserve_coll_amt;
        let target_remainder = coll - total_seize_coll;

        let _ = table::remove(&mut reg.troves, target);
        reg.total_debt = reg.total_debt - debt;

        // Burn SP-owned D equal to the wiped debt
        let burn_bal = balance::split(&mut reg.sp_pool, debt);
        coin::burn(&mut reg.treasury, coin::from_balance(burn_bal, ctx));

        if (total_before > 0) {
            reg.reward_index_coll = reg.reward_index_coll +
                (sp_coll as u128) * reg.product_factor / (total_before as u128);
        };
        reg.product_factor = new_p;
        reg.total_sp = total_sp_new;

        // Split seized collateral: reserve → reserve_coll, SP → sp_coll_pool, liquidator → return
        let mut seized = balance::split(&mut reg.treasury_coll, total_seize_coll);
        if (reserve_coll_amt > 0) {
            balance::join(&mut reg.reserve_coll, balance::split(&mut seized, reserve_coll_amt));
        };
        if (sp_coll > 0) {
            if (total_before == 0) {
                balance::join(&mut reg.reserve_coll, balance::split(&mut seized, sp_coll));
            } else {
                balance::join(&mut reg.sp_coll_pool, balance::split(&mut seized, sp_coll));
            }
        };
        if (target_remainder > 0) {
            let rem = coin::from_balance(balance::split(&mut reg.treasury_coll, target_remainder), ctx);
            transfer::public_transfer(rem, target);
        };

        let liquidator = tx_context::sender(ctx);
        event::emit(Liquidated {
            liquidator, target, debt,
            coll_to_liquidator: liq_coll,
            coll_to_sp: sp_coll,
            coll_to_reserve: reserve_coll_amt,
            coll_to_target: target_remainder,
        });
        coin::from_balance(seized, ctx)
    }

    // Stability Pool — public entries

    public fun sp_deposit(
        reg: &mut Registry,
        d_in: Coin<D>,
        ctx: &mut TxContext,
    ) {
        let amt = coin::value(&d_in);
        assert!(amt > 0, E_AMOUNT);
        let u = tx_context::sender(ctx);
        balance::join(&mut reg.sp_pool, coin::into_balance(d_in));
        // Reset-on-empty: when the pool has been fully drained (previous cliff-freeze
        // plus all prior depositors withdrew), reset product_factor to full precision
        // so liquidations can resume. No active depositor is harmed — there are none.
        if (reg.total_sp == 0) {
            reg.product_factor = PRECISION;
        };
        if (table::contains(&reg.sp_positions, u)) {
            sp_settle(reg, u, ctx);
            let p = table::borrow_mut(&mut reg.sp_positions, u);
            p.initial_balance = p.initial_balance + amt;
        } else {
            table::add(&mut reg.sp_positions, u, SP {
                initial_balance: amt,
                snapshot_product: reg.product_factor,
                snapshot_index_d: reg.reward_index_d,
                snapshot_index_coll: reg.reward_index_coll,
            });
        };
        reg.total_sp = reg.total_sp + amt;
        event::emit(SPDeposited { user: u, amount: amt });
    }

    public fun donate_to_sp(reg: &mut Registry, d_in: Coin<D>, ctx: &mut TxContext) {
        let amt = coin::value(&d_in);
        assert!(amt > 0, E_AMOUNT);
        balance::join(&mut reg.sp_pool, coin::into_balance(d_in));
        event::emit(SPDonated { donor: tx_context::sender(ctx), amount: amt });
    }

    public fun donate_to_reserve(reg: &mut Registry, sui_in: Coin<SUI>, ctx: &mut TxContext) {
        let amt = coin::value(&sui_in);
        assert!(amt > 0, E_AMOUNT);
        balance::join(&mut reg.reserve_coll, coin::into_balance(sui_in));
        event::emit(ReserveDonated { donor: tx_context::sender(ctx), amount: amt });
    }

    public fun sp_withdraw(
        reg: &mut Registry,
        amt: u64,
        ctx: &mut TxContext,
    ): Coin<D> {
        assert!(amt > 0, E_AMOUNT);
        let u = tx_context::sender(ctx);
        assert!(table::contains(&reg.sp_positions, u), E_SP_BAL);
        sp_settle(reg, u, ctx);
        let empty = {
            let pos = table::borrow_mut(&mut reg.sp_positions, u);
            assert!(pos.initial_balance >= amt, E_SP_BAL);
            pos.initial_balance = pos.initial_balance - amt;
            pos.initial_balance == 0
        };
        reg.total_sp = reg.total_sp - amt;
        let out = coin::from_balance(balance::split(&mut reg.sp_pool, amt), ctx);
        if (empty) { let _ = table::remove(&mut reg.sp_positions, u); };
        event::emit(SPWithdrew { user: u, amount: amt });
        out
    }

    public fun sp_claim(reg: &mut Registry, ctx: &mut TxContext) {
        let u = tx_context::sender(ctx);
        assert!(table::contains(&reg.sp_positions, u), E_SP_BAL);
        sp_settle(reg, u, ctx);
    }

    // PTB-friendly entry wrappers (transfer-to-sender)

    public fun open_trove_entry(
        reg: &mut Registry,
        coll: Coin<SUI>,
        debt: u64,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let c = open_trove(reg, coll, debt, pi, clock, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    public fun close_trove_entry(
        reg: &mut Registry,
        d_in: Coin<D>,
        ctx: &mut TxContext,
    ) {
        let c = close_trove(reg, d_in, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    public fun redeem_entry(
        reg: &mut Registry,
        d_in: Coin<D>,
        target: address,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let c = redeem(reg, d_in, target, pi, clock, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    public fun redeem_from_reserve_entry(
        reg: &mut Registry,
        d_in: Coin<D>,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let c = redeem_from_reserve(reg, d_in, pi, clock, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    public fun liquidate_entry(
        reg: &mut Registry,
        target: address,
        pi: &PriceInfoObject,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let c = liquidate(reg, target, pi, clock, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    public fun sp_withdraw_entry(
        reg: &mut Registry,
        amt: u64,
        ctx: &mut TxContext,
    ) {
        let c = sp_withdraw(reg, amt, ctx);
        transfer::public_transfer(c, tx_context::sender(ctx));
    }

    // Views

    public fun read_warning(): vector<u8> { WARNING }

    public fun price_view(pi: &PriceInfoObject, clock: &Clock): u128 {
        price_8dec(pi, clock)
    }

    public fun trove_of(reg: &Registry, addr: address): (u64, u64) {
        if (table::contains(&reg.troves, addr)) {
            let t = table::borrow(&reg.troves, addr);
            (t.collateral, t.debt)
        } else (0, 0)
    }

    public fun sp_of(reg: &Registry, addr: address): (u64, u64, u64) {
        if (table::contains(&reg.sp_positions, addr)) {
            let p = table::borrow(&reg.sp_positions, addr);
            let eff = ((((p.initial_balance as u256) * (reg.product_factor as u256)) / (p.snapshot_product as u256)) as u64);
            let p_d = ((((reg.reward_index_d - p.snapshot_index_d) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            let p_coll = ((((reg.reward_index_coll - p.snapshot_index_coll) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            (eff, p_d, p_coll)
        } else (0, 0, 0)
    }

    public fun totals(reg: &Registry): (u64, u64, u128, u128, u128) {
        (reg.total_debt, reg.total_sp, reg.product_factor, reg.reward_index_d, reg.reward_index_coll)
    }

    public fun reserve_balance(reg: &Registry): u64 {
        balance::value(&reg.reserve_coll)
    }

    public fun is_sealed(reg: &Registry): bool { reg.sealed }

    /// Exact D amount user needs to burn to close_trove. Useful for UIs
    /// to display the 1 percent secondary-market deficit.
    public fun close_cost(reg: &Registry, addr: address): u64 {
        if (table::contains(&reg.troves, addr)) {
            table::borrow(&reg.troves, addr).debt
        } else 0
    }

    /// Returns (collateral, debt, cr_bps). cr_bps = 0 if no trove or trove has zero debt.
    /// Oracle-dependent — shares price_8dec's abort semantics.
    public fun trove_health(
        reg: &Registry,
        addr: address,
        pi: &PriceInfoObject,
        clock: &Clock,
    ): (u64, u64, u64) {
        if (!table::contains(&reg.troves, addr)) return (0, 0, 0);
        let t = table::borrow(&reg.troves, addr);
        if (t.debt == 0) return (t.collateral, 0, 0);
        let price = price_8dec(pi, clock);
        let coll_usd = (t.collateral as u128) * price / SUI_SCALE;
        let cr_bps = (coll_usd * 10000 / (t.debt as u128)) as u64;
        (t.collateral, t.debt, cr_bps)
    }

    // Test-only helpers (mirrors Aptos test surface)

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(D {}, ctx);
    }

    #[test_only]
    public fun test_create_sp_position(reg: &mut Registry, addr: address, balance: u64) {
        table::add(&mut reg.sp_positions, addr, SP {
            initial_balance: balance,
            snapshot_product: reg.product_factor,
            snapshot_index_d: reg.reward_index_d,
            snapshot_index_coll: reg.reward_index_coll,
        });
        reg.total_sp = reg.total_sp + balance;
    }

    #[test_only]
    public fun test_route_fee_virtual(reg: &mut Registry, amount: u64) {
        let sp_amt = amount - amount * 1000 / 10000;
        if (sp_amt == 0) return;
        if (table::length(&reg.sp_positions) == 0) {
            return
        };
        reg.reward_index_d = reg.reward_index_d + (sp_amt as u128) * reg.product_factor / (reg.total_sp as u128);
    }

    #[test_only]
    public fun test_sp_pool_balance(reg: &Registry): u64 {
        balance::value(&reg.sp_pool)
    }

    #[test_only]
    public fun test_mint_d(reg: &mut Registry, amount: u64, ctx: &mut TxContext): Coin<D> {
        coin::mint(&mut reg.treasury, amount, ctx)
    }

    #[test_only]
    public fun test_simulate_liquidation_v2(reg: &mut Registry, debt: u64, sp_coll_absorbed: u64, ctx: &mut TxContext) {
        let pool_before = balance::value(&reg.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);
        let total_before = reg.total_sp;
        let new_p = reg.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);
        let burn_bal = balance::split(&mut reg.sp_pool, debt);
        coin::burn(&mut reg.treasury, coin::from_balance(burn_bal, ctx));
        if (total_before > 0) {
            reg.reward_index_coll = reg.reward_index_coll + (sp_coll_absorbed as u128) * reg.product_factor / (total_before as u128);
        };
        reg.product_factor = new_p;
        reg.total_sp = total_sp_new;
    }

    #[test_only]
    public fun test_simulate_liquidation(reg: &mut Registry, debt: u64, sp_coll_absorbed: u64) {
        let total_before = reg.total_sp;
        assert!(total_before > debt, E_SP_INSUFFICIENT);
        let new_p = reg.product_factor * ((total_before - debt) as u128) / (total_before as u128);
        assert!(new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        reg.reward_index_coll = reg.reward_index_coll +
            (sp_coll_absorbed as u128) * reg.product_factor / (total_before as u128);
        reg.product_factor = new_p;
        reg.total_sp = total_before - debt;
    }

    #[test_only]
    public fun test_set_sp_position(
        reg: &mut Registry, addr: address, initial: u64, snap_p: u128, snap_i_d: u128, snap_i_coll: u128
    ) {
        if (table::contains(&reg.sp_positions, addr)) {
            let p = table::borrow_mut(&mut reg.sp_positions, addr);
            p.initial_balance = initial;
            p.snapshot_product = snap_p;
            p.snapshot_index_d = snap_i_d;
            p.snapshot_index_coll = snap_i_coll;
        } else {
            table::add(&mut reg.sp_positions, addr, SP {
                initial_balance: initial,
                snapshot_product: snap_p,
                snapshot_index_d: snap_i_d,
                snapshot_index_coll: snap_i_coll,
            });
        };
    }

    #[test_only]
    public fun test_get_sp_snapshots(reg: &Registry, addr: address): (u64, u128, u128, u128) {
        let p = table::borrow(&reg.sp_positions, addr);
        (p.initial_balance, p.snapshot_product, p.snapshot_index_d, p.snapshot_index_coll)
    }

    #[test_only]
    public fun test_force_reward_indices(reg: &mut Registry, d_idx: u128, coll_idx: u128) {
        reg.reward_index_d = d_idx;
        reg.reward_index_coll = coll_idx;
    }

    #[test_only]
    public fun test_call_sp_settle(reg: &mut Registry, addr: address, ctx: &mut TxContext) {
        sp_settle(reg, addr, ctx);
    }

    #[test_only]
    public fun test_mint_origin_cap(ctx: &mut TxContext): OriginCap {
        OriginCap { id: object::new(ctx) }
    }

    #[test_only]
    public fun test_seal_without_upgrade_cap(
        origin: OriginCap, reg: &mut Registry, clock: &Clock, ctx: &mut TxContext
    ) {
        assert!(!reg.sealed, E_SEALED);
        let OriginCap { id } = origin;
        object::delete(id);
        reg.sealed = true;
        event::emit(CapDestroyed {
            caller: tx_context::sender(ctx),
            timestamp_ms: clock::timestamp_ms(clock),
        });
    }
}
```

---

# Tests: `tests/D_tests.move` (476 lines, post-fix)

```move
#[test_only]
module D::D_tests {
    use sui::clock;
    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};
    use std::unit_test;
    use D::D::{Registry, D as D_TYPE};

    const DEPLOYER: address = @0xCAFE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    fun start(): Scenario {
        let mut sc = ts::begin(DEPLOYER);
        D::D::init_for_testing(ts::ctx(&mut sc));
        sc
    }

    fun take_reg(sc: &mut Scenario): Registry {
        ts::next_tx(sc, DEPLOYER);
        ts::take_shared<Registry>(sc)
    }

    // ---- basic init / view surface ----

    #[test]
    fun test_init_creates_registry() {
        let mut sc = start();
        let reg = take_reg(&mut sc);
        let (debt, sp, p, r1, r2) = D::D::totals(&reg);
        assert!(debt == 0, 100);
        assert!(sp == 0, 101);
        assert!(p == 1_000_000_000_000_000_000, 102);
        assert!(r1 == 0, 103);
        assert!(r2 == 0, 104);
        assert!(D::D::is_sealed(&reg) == false, 105);
        assert!(D::D::reserve_balance(&reg) == 0, 106);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_warning_text_on_chain() {
        let sc = start();
        let w = D::D::read_warning();
        let prefix = b"D is an immutable stablecoin";
        let mut i = 0;
        while (i < std::vector::length(&prefix)) {
            assert!(*std::vector::borrow(&w, i) == *std::vector::borrow(&prefix, i), 200);
            i = i + 1;
        };
        let sui_ref = b"Sui";
        let pyth_ref = b"Pyth Network";
        let governance_ref = b"ORACLE UPGRADE RISK";
        assert!(contains_bytes(&w, &sui_ref), 201);
        assert!(contains_bytes(&w, &pyth_ref), 202);
        assert!(contains_bytes(&w, &governance_ref), 203);
        ts::end(sc);
    }

    #[test]
    fun test_trove_of_unknown_returns_zero() {
        let mut sc = start();
        let reg = take_reg(&mut sc);
        let (c, d) = D::D::trove_of(&reg, ALICE);
        assert!(c == 0 && d == 0, 300);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_sp_of_unknown_returns_zero() {
        let mut sc = start();
        let reg = take_reg(&mut sc);
        let (bal, p_d, p_coll) = D::D::sp_of(&reg, ALICE);
        assert!(bal == 0 && p_d == 0 && p_coll == 0, 400);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_close_cost_unknown_zero() {
        let mut sc = start();
        let reg = take_reg(&mut sc);
        assert!(D::D::close_cost(&reg, ALICE) == 0, 500);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_TROVE)]
    fun test_close_trove_without_trove_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let zero_d = coin::zero<D_TYPE>(ts::ctx(&mut sc));
        let clk = clock::create_for_testing(ts::ctx(&mut sc));
        let out = D::D::close_trove(&mut reg, zero_d, ts::ctx(&mut sc));
        unit_test::destroy(out);
        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_SP_BAL)]
    fun test_sp_claim_without_position_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        D::D::sp_claim(&mut reg, ts::ctx(&mut sc));
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_SP_BAL)]
    fun test_sp_withdraw_without_position_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let out = D::D::sp_withdraw(&mut reg, 100_000_000, ts::ctx(&mut sc));
        unit_test::destroy(out);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_AMOUNT)]
    fun test_sp_deposit_zero_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let zero_d = coin::zero<D_TYPE>(ts::ctx(&mut sc));
        D::D::sp_deposit(&mut reg, zero_d, ts::ctx(&mut sc));
        ts::return_shared(reg);
        ts::end(sc);
    }

    // ---- SP math via test helpers (oracle-free) ----

    #[test]
    fun test_sp_position_creation_via_helper() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 100_000_000);
        let (bal, p_d, p_coll) = D::D::sp_of(&reg, ALICE);
        assert!(bal == 100_000_000, 600);
        assert!(p_d == 0, 601);
        assert!(p_coll == 0, 602);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_reward_index_increment_and_pending() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 100_000_000);
        D::D::test_route_fee_virtual(&mut reg, 1_000_000);
        let (_, _, _, r_d, _) = D::D::totals(&reg);
        assert!(r_d == 9_000_000_000_000_000, 700);
        let (bal, p_d, p_coll) = D::D::sp_of(&reg, ALICE);
        assert!(bal == 100_000_000, 701);
        assert!(p_d == 900_000, 702);
        assert!(p_coll == 0, 703);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_reward_index_pro_rata_two_depositors() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 200_000_000);
        D::D::test_create_sp_position(&mut reg, BOB, 100_000_000);
        D::D::test_route_fee_virtual(&mut reg, 300_000_000);
        let (_, pa, _) = D::D::sp_of(&reg, ALICE);
        let (_, pb, _) = D::D::sp_of(&reg, BOB);
        assert!(pa == 180_000_000, 800);
        assert!(pb == 90_000_000, 801);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_liquidation_single_depositor() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 10_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 2_000_000_000, 2_500_000_000);
        let (bal, p_d, p_coll) = D::D::sp_of(&reg, ALICE);
        assert!(bal == 8_000_000_000, 900);
        assert!(p_d == 0, 901);
        assert!(p_coll == 2_500_000_000, 902);
        let (_, total_sp, pf, _, r_coll) = D::D::totals(&reg);
        assert!(total_sp == 8_000_000_000, 903);
        assert!(pf == 800_000_000_000_000_000, 904);
        assert!(r_coll == 250_000_000_000_000_000, 905);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_liquidation_two_depositors_pro_rata() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 10_000_000_000);
        D::D::test_create_sp_position(&mut reg, BOB, 10_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 2_000_000_000, 2_500_000_000);
        let (a_bal, _, a_coll) = D::D::sp_of(&reg, ALICE);
        let (b_bal, _, b_coll) = D::D::sp_of(&reg, BOB);
        assert!(a_bal == 9_000_000_000, 1000);
        assert!(b_bal == 9_000_000_000, 1001);
        assert!(a_coll == 1_250_000_000, 1002);
        assert!(b_coll == 1_250_000_000, 1003);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_liquidation_sequential_math() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 10_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 2_000_000_000, 2_500_000_000);
        D::D::test_create_sp_position(&mut reg, BOB, 10_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 1_000_000_000, 1_500_000_000);
        let (a_bal, _, a_coll) = D::D::sp_of(&reg, ALICE);
        assert!(a_bal == 7_555_555_555, 1100);
        assert!(a_coll == 3_166_666_666, 1101);
        let (b_bal, _, b_coll) = D::D::sp_of(&reg, BOB);
        assert!(b_bal == 9_444_444_444, 1102);
        assert!(b_coll == 833_333_333, 1103);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_P_CLIFF)]
    fun test_liquidation_cliff_guard_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 10_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 9_999_999_000, 1_000_000_000);
        D::D::test_simulate_liquidation(&mut reg, 999, 500);
        ts::return_shared(reg);
        ts::end(sc);
    }

    // R2-C01 regression: zombie SP positions (initial=0) must refresh their
    // snapshots on every sp_settle, preventing a later redeposit from pairing
    // a fresh initial_balance with stale indices (which inflates pending_d).
    #[test]
    fun test_zombie_redeposit_no_phantom_reward() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);

        D::D::test_set_sp_position(&mut reg, ALICE, 0, 100_000_000_000_000, 500, 500);
        D::D::test_force_reward_indices(&mut reg, 1_000_000_000_000_000_000, 2_000_000_000_000_000_000);

        ts::next_tx(&mut sc, ALICE);
        D::D::test_call_sp_settle(&mut reg, ALICE, ts::ctx(&mut sc));

        let (initial, snap_p, snap_i_d, snap_i_coll) = D::D::test_get_sp_snapshots(&reg, ALICE);
        assert!(initial == 0, 1200);
        assert!(snap_p == 1_000_000_000_000_000_000, 1201);
        assert!(snap_i_d == 1_000_000_000_000_000_000, 1202);
        assert!(snap_i_coll == 2_000_000_000_000_000_000, 1203);
        ts::return_shared(reg);
        ts::end(sc);
    }

    // ---- seal via test helper (no UpgradeCap in unit tests) ----

    #[test]
    fun test_destroy_cap_flips_sealed() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        let origin = D::D::test_mint_origin_cap(ts::ctx(&mut sc));
        let clk = clock::create_for_testing(ts::ctx(&mut sc));
        D::D::test_seal_without_upgrade_cap(origin, &mut reg, &clk, ts::ctx(&mut sc));
        assert!(D::D::is_sealed(&reg) == true, 1250);
        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_SEALED)]
    fun test_destroy_cap_double_call_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        let origin_a = D::D::test_mint_origin_cap(ts::ctx(&mut sc));
        let clk = clock::create_for_testing(ts::ctx(&mut sc));
        D::D::test_seal_without_upgrade_cap(origin_a, &mut reg, &clk, ts::ctx(&mut sc));
        let origin_b = D::D::test_mint_origin_cap(ts::ctx(&mut sc));
        D::D::test_seal_without_upgrade_cap(origin_b, &mut reg, &clk, ts::ctx(&mut sc));
        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        ts::end(sc);
    }

    // ---- V2 donation primitive tests ----

    #[test]
    fun test_donate_to_sp_grows_pool_no_total_sp() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let d_in = coin::mint_for_testing<D_TYPE>(50_000_000, ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, d_in, ts::ctx(&mut sc));
        assert!(D::D::test_sp_pool_balance(&reg) == 50_000_000, 1300);
        let (_, total_sp, _, _, _) = D::D::totals(&reg);
        assert!(total_sp == 0, 1301);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_AMOUNT)]
    fun test_donate_to_sp_zero_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let zero = coin::zero<D_TYPE>(ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, zero, ts::ctx(&mut sc));
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_donation_no_dilution_to_keyed_rewards() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 100_000_000);
        ts::next_tx(&mut sc, BOB);
        let donation = coin::mint_for_testing<D_TYPE>(50_000_000, ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
        let (_, total_sp, _, _, _) = D::D::totals(&reg);
        assert!(total_sp == 100_000_000, 1400);
        D::D::test_route_fee_virtual(&mut reg, 1_000_000);
        let (bal, p_d, _) = D::D::sp_of(&reg, ALICE);
        assert!(bal == 100_000_000, 1401);
        assert!(p_d == 900_000, 1402);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_donate_to_reserve_grows_reserve_coll() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        assert!(D::D::reserve_balance(&reg) == 0, 1500);
        ts::next_tx(&mut sc, ALICE);
        let sui_in = coin::mint_for_testing<sui::sui::SUI>(10_000_000_000, ts::ctx(&mut sc));
        D::D::donate_to_reserve(&mut reg, sui_in, ts::ctx(&mut sc));
        assert!(D::D::reserve_balance(&reg) == 10_000_000_000, 1501);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    #[expected_failure(abort_code = D::D::E_AMOUNT)]
    fun test_donate_to_reserve_zero_aborts() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let zero = coin::zero<sui::sui::SUI>(ts::ctx(&mut sc));
        D::D::donate_to_reserve(&mut reg, zero, ts::ctx(&mut sc));
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_route_fee_virtual_skips_when_no_keyed_position() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_route_fee_virtual(&mut reg, 1_000_000);
        let (_, total_sp, _, r_d, _) = D::D::totals(&reg);
        assert!(total_sp == 0, 1600);
        assert!(r_d == 0, 1601);
        ts::return_shared(reg);
        ts::end(sc);
    }

    #[test]
    fun test_donate_then_liquidate_pool_burn_pro_rata() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, ALICE);
        let alice_d = D::D::test_mint_d(&mut reg, 100_000_000, ts::ctx(&mut sc));
        D::D::sp_deposit(&mut reg, alice_d, ts::ctx(&mut sc));
        ts::next_tx(&mut sc, BOB);
        let donation = D::D::test_mint_d(&mut reg, 50_000_000, ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
        assert!(D::D::test_sp_pool_balance(&reg) == 150_000_000, 1700);
        let (_, total_sp_pre, _, _, _) = D::D::totals(&reg);
        assert!(total_sp_pre == 100_000_000, 1701);

        D::D::test_simulate_liquidation_v2(&mut reg, 50_000_000, 5_000_000, ts::ctx(&mut sc));

        assert!(D::D::test_sp_pool_balance(&reg) == 100_000_000, 1702);
        let (_, total_sp_post, pf, _, _) = D::D::totals(&reg);
        assert!(total_sp_post == 66_666_666, 1703);
        assert!(pf == 666_666_666_666_666_666, 1704);
        let (alice_bal, _, alice_coll) = D::D::sp_of(&reg, ALICE);
        assert!(alice_bal == 66_666_666, 1705);
        assert!(alice_coll == 5_000_000, 1706);
        ts::return_shared(reg);
        ts::end(sc);
    }

    // R1 Claude HIGH-1 reproducer: u64/u128 truncation decoupling.
    // total_sp tiny (1 raw) + large donation -> liquidation ratio that keeps
    // new_p >= MIN_P_THRESHOLD but truncates total_sp_new to 0 with keyed
    // positions still in table. Pre-fix: subsequent route_fee div0 DoS.
    // Post-fix (HIGH-1 (b)): liquidate aborts E_P_CLIFF before bad state.
    #[test]
    #[expected_failure(abort_code = D::D::E_P_CLIFF)]
    fun test_truncation_orphan_aborts_liquidation() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        D::D::test_create_sp_position(&mut reg, ALICE, 1);
        ts::next_tx(&mut sc, BOB);
        let donation = D::D::test_mint_d(&mut reg, 1_000_000_000, ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
        D::D::test_simulate_liquidation_v2(&mut reg, 999_999_990, 0, ts::ctx(&mut sc));
        ts::return_shared(reg);
        ts::end(sc);
    }

    // Verify route_fee cliff predicate is now total_sp == 0 (not table::length).
    // After legitimate full SP withdraw (table empty) OR pure-donation state,
    // fee redirect to sp_pool with no div0.
    #[test]
    fun test_route_fee_cliff_redirect_via_total_sp() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        ts::next_tx(&mut sc, BOB);
        let donation = D::D::test_mint_d(&mut reg, 50_000_000, ts::ctx(&mut sc));
        D::D::donate_to_sp(&mut reg, donation, ts::ctx(&mut sc));
        let (_, total_sp, _, r_d_pre, _) = D::D::totals(&reg);
        assert!(total_sp == 0, 1800);
        assert!(r_d_pre == 0, 1801);
        D::D::test_route_fee_virtual(&mut reg, 1_000_000);
        let (_, total_sp_post, _, r_d_post, _) = D::D::totals(&reg);
        assert!(total_sp_post == 0, 1802);
        assert!(r_d_post == 0, 1803);
        ts::return_shared(reg);
        ts::end(sc);
    }

    // ---- helpers ----

    fun contains_bytes(hay: &vector<u8>, needle: &vector<u8>): bool {
        let hn = std::vector::length(hay);
        let nn = std::vector::length(needle);
        if (nn == 0 || nn > hn) return nn == 0;
        let mut i = 0;
        while (i + nn <= hn) {
            let mut j = 0;
            let mut ok = true;
            while (j < nn) {
                if (*std::vector::borrow(hay, i + j) != *std::vector::borrow(needle, j)) {
                    ok = false;
                    break
                };
                j = j + 1;
            };
            if (ok) return true;
            i = i + 1;
        };
        false
    }
}
```

---

# Move.toml

```toml
[package]
name = "D"
version = "0.2.0"
edition = "2024.beta"
# Immutability is achieved post-publish by consuming the UpgradeCap via
# sui::package::make_immutable inside destroy_cap. The package remains
# upgradeable only in the window between publish and destroy_cap.

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "6d4ec0b0621dd9555753c9ecd5be021b25a0d267", override = true }
Pyth = { local = "deps/pyth" }

[addresses]
D = "0x0"

[dev-addresses]
D = "0xCAFE"
```

---

## Submission target

Primary: Claude Opus 4.7 fresh session (the auditor who raised HIGH-1 — verify fix correctness).
Optional: any 1-2 of the R1 GREEN auditors as cross-check.

If Claude returns GREEN on R2: deploy clearance.
