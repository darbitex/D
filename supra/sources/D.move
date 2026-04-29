/// D — immutable stablecoin on Supra L1
///
/// WARNING: D is an immutable stablecoin contract that depends on
/// Supra's native oracle feed for SUPRA/USDT (pair id 500). If Supra
/// Foundation ever degrades or misrepresents its oracle, D's peg
/// mechanism breaks deterministically - users can wind down via
/// self-close without any external assistance, but new mint/redeem
/// operations become unreliable or frozen. D is immutable = bug is real.
/// Audit this code yourself before interacting.
module D::D {
    use std::option::{Self, Option};
    use std::signer;
    use std::string;
    #[test_only]
    use std::vector;
    use aptos_std::smart_table::{Self, SmartTable};
    use supra_framework::account::SignerCapability;
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, MintRef, BurnRef, Metadata};
    use supra_framework::object::{Self, Object, ExtendRef};
    use supra_framework::primary_fungible_store;
    use supra_framework::resource_account;
    use supra_framework::timestamp;
    use supra_oracle::supra_oracle_storage;

    const MCR_BPS: u128 = 20000;
    const LIQ_THRESHOLD_BPS: u128 = 15000;
    const LIQ_BONUS_BPS: u64 = 1000;
    const LIQ_LIQUIDATOR_BPS: u64 = 2500;
    const LIQ_SP_RESERVE_BPS: u64 = 2500;
    // SP receives (10000 - LIQ_LIQUIDATOR_BPS - LIQ_SP_RESERVE_BPS) = 5000 (50%) as remainder
    const FEE_BPS: u64 = 100;
    const STALENESS_MS: u64 = 60_000;          // 60s — Supra oracle ts is millis
    const MAX_FUTURE_DRIFT_MS: u64 = 10_000;   // 10s tolerance for clock skew
    // 0.01 D entry barrier (8 decimals). Lowered from D-Aptos 0.1 D to match Supra's
    // smaller-unit economics (SUPRA spot ~$0.0004 vs APT ~$5).
    const MIN_DEBT: u64 = 1_000_000;
    const PRECISION: u128 = 1_000_000_000_000_000_000;
    const MIN_P_THRESHOLD: u128 = 1_000_000_000;
    const SUPRA_FA: address = @0xa;
    const PAIR_ID: u32 = 500;                  // SUPRA/USDT, Supra L1 native oracle

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
    const E_NOT_ORIGIN: u64 = 15;
    const E_CAP_GONE: u64 = 16;
    const E_STALE_FUTURE: u64 = 17;

    const WARNING: vector<u8> = b"D is an immutable stablecoin contract on Supra L1 that depends on Supra's native oracle feed for SUPRA/USDT (pair id 500). If Supra Foundation ever degrades or misrepresents its oracle, D's peg mechanism breaks deterministically - users can wind down via self-close without any external assistance, but new mint/redeem operations become unreliable or frozen. D is immutable = bug is real. Audit this code yourself before interacting. KNOWN LIMITATIONS: (1) Stability Pool enters frozen state when product_factor would drop below 1e9 - protocol aborts further liquidations rather than corrupt SP accounting, accepting bad-debt accumulation past the threshold. (2) Sustained large-scale activity over decades may asymptotically exceed u64 bounds on pending SP rewards. (3) Liquidation seized collateral is distributed in priority: liquidator bonus first (nominal 2.5 percent of debt value, being 25 percent of the 10 percent liquidation bonus), then 2.5 percent reserve share (also 25 percent of bonus), then SP absorbs the remainder and the debt burn. At CR roughly 110% to 150% the SP alone covers the collateral shortfall. At CR below ~5% the liquidator may take the entire remaining collateral, reserve and SP receive zero, and SP still absorbs the full debt burn. (4) 10 percent of each mint and redeem fee is redirected to the Stability Pool as an agnostic donation - it joins sp_pool balance but does NOT increment total_sp, so it does not dilute the reward distribution denominator. Donations participate in liquidation absorption pro-rata via the actual sp_pool balance ratio, gradually burning over time. The remaining 90 percent is distributed pro-rata to keyed SP depositors via the fee accumulator when keyed positions exist; during periods with no keyed positions, the 90 percent is also redirected to the SP pool as agnostic donation rather than accruing unclaimable in the accumulator. Real depositors receive their full 90 percent share unaffected by donation flow rate. Total: 1 percent supply-vs-debt gap per fee cycle, fully draining via SP burns over time. Individual debtors still face a 1 percent per-trove shortfall because only 99 percent is minted while 100 percent is needed to close - full protocol wind-down requires secondary-market D for the last debt closure. (5) Self-redemption (redeem against own trove) is allowed and behaves as partial debt repayment plus collateral withdrawal with a 1 percent fee. (6) Supra oracle is push-based on Supra L1 - Supra Foundation pushes feed updates on cadence (typically under 30 seconds for active pairs); D rejects reads older than 60 seconds via STALENESS_MS. Callers do NOT bundle VAAs or refresh prices; they invoke D entries directly. (7) Extreme low-price regimes may cause transient aborts in redeem paths when requested amounts exceed u64 output bounds; use smaller amounts and retry. (8) ORACLE DEPENDENCY (Supra-specific): Supra oracle pkg 0xe3948c9e... is governed by Supra Foundation with upgrade_policy = 1 (compatible, NOT cryptographically immutable). Pair id 500 (SUPRA/USDT) is in the Under Supervision tier (3-5 sources, lower-confidence than top-tier pairs like BTC/USDT). Residual risks: pair id could be remapped or decommissioned via Supra governance, package code could be upgraded silently in compatible-breaking ways, or the feed could become permanently unavailable for any reason. Either case bricks oracle-dependent entries (open_trove, redeem, liquidate, redeem_from_reserve). Oracle-free escape hatches remain fully open: close_trove lets any trove owner reclaim their collateral by burning the full trove debt in D (acquiring the 1 percent close deficit via secondary market if needed); add_collateral lets owners top up existing troves without touching the oracle; sp_deposit, sp_withdraw, donate_to_sp, donate_to_reserve, and sp_claim let SP depositors manage and exit their positions and claim any rewards accumulated before the freeze (donate_to_sp + donate_to_reserve are oracle-free permissionless contributions). Protocol-owned SUPRA held in reserve_coll becomes permanently locked because redeem_from_reserve requires the oracle. No admin override exists; the freeze is final. (9) REDEMPTION vs LIQUIDATION are two separate mechanisms. liquidate is health-gated (requires CR below 150 percent) and applies a penalty bonus to the liquidator, the reserve, and the SP; healthy troves cannot be liquidated by anyone. redeem has no health gate on target and executes a value-neutral swap at oracle spot price - the target's debt decreases by net D while their collateral decreases by net times 1e8 over price SUPRA, so the target retains full value at spot. Redemption is the protocol peg-anchor: when D trades below 1 USDT on secondary market, any holder can burn D supply by redeeming for SUPRA, pushing the peg back up. The target is caller-specified; there is no sorted-by-CR priority, unlike Liquity V1's sorted list - the economic result for the target is identical to Liquity (made whole at spot), only the redemption ordering differs, and ordering is a peg-efficiency optimization rather than a safety property. Borrowers who want guaranteed long-term SUPRA exposure without the possibility of redemption-induced position conversion should not use D troves - use a non-CDP lending protocol instead. Losing optionality under redemption is not the same as losing value: the target is economically indifferent at spot. (10) USDT-DENOMINATED PEG TAIL: D's peg target is USDT, not USD. Pair 500 reports SUPRA/USDT directly; D treats USDT as 1 USD per Supranova/Solido precedent. Under USDT depeg events (e.g., May 2022 when USDT briefly traded near 0.95 USD), D's effective USD peg drifts proportionally - magnitude historically less than 5 percent with quick recovery. Pair 500 was chosen over the derived SUPRA/USD computation (which would multiply pair 500 by an external USDT/USD feed) for immutable simplicity, accepting approximately 50bps long-tail USDT risk. No fallback exists in immutable code; if USDT depegs structurally, D's peg moves with it.";

    struct Trove has store, drop { collateral: u64, debt: u64 }

    struct SP has store, drop {
        initial_balance: u64,
        snapshot_product: u128,
        snapshot_index_d: u128,
        snapshot_index_coll: u128,
    }

    /// Staged between publish and destroy_cap. Origin consumes + drops the cap to seal the package.
    struct ResourceCap has key { cap: Option<SignerCapability> }

    struct Registry has key {
        metadata: Object<Metadata>,
        supra_metadata: Object<Metadata>,
        mint_ref: MintRef,
        burn_ref: BurnRef,
        fee_pool: Object<FungibleStore>,
        fee_extend: ExtendRef,
        sp_pool: Object<FungibleStore>,
        sp_extend: ExtendRef,
        sp_coll_pool: Object<FungibleStore>,
        sp_coll_extend: ExtendRef,
        reserve_coll: Object<FungibleStore>,
        reserve_extend: ExtendRef,
        treasury: Object<FungibleStore>,
        treasury_extend: ExtendRef,
        troves: SmartTable<address, Trove>,
        sp_positions: SmartTable<address, SP>,
        total_debt: u64,
        total_sp: u64,
        product_factor: u128,
        reward_index_d: u128,
        reward_index_coll: u128,
    }

    #[event] struct TroveOpened has drop, store { user: address, new_collateral: u64, new_debt: u64, added_debt: u64 }
    #[event] struct CollateralAdded has drop, store { user: address, amount: u64 }
    #[event] struct TroveClosed has drop, store { user: address, collateral: u64, debt: u64 }
    #[event] struct Redeemed has drop, store { user: address, target: address, d_amt: u64, coll_out: u64 }
    #[event] struct Liquidated has drop, store { liquidator: address, target: address, debt: u64, coll_to_liquidator: u64, coll_to_sp: u64, coll_to_reserve: u64, coll_to_target: u64 }
    #[event] struct SPDeposited has drop, store { user: address, amount: u64 }
    #[event] struct SPDonated has drop, store { donor: address, amount: u64 }
    #[event] struct ReserveDonated has drop, store { donor: address, amount: u64 }
    #[event] struct SPWithdrew has drop, store { user: address, amount: u64 }
    #[event] struct SPClaimed has drop, store { user: address, d_amt: u64, coll_amt: u64 }
    #[event] struct ReserveRedeemed has drop, store { user: address, d_amt: u64, coll_out: u64 }
    #[event] struct CapDestroyed has drop, store { caller: address, timestamp: u64 }
    #[event] struct RewardSaturated has drop, store { user: address, pending_d_truncated: bool, pending_coll_truncated: bool }

    fun init_module(resource: &signer) {
        let cap = resource_account::retrieve_resource_account_cap(resource, @origin);
        move_to(resource, ResourceCap { cap: option::some(cap) });
        init_module_inner(resource, object::address_to_object<Metadata>(SUPRA_FA));
    }

    /// Origin-only. One-shot consume of the staged SignerCapability. After success,
    /// no actor can reconstruct a signer for @D — package is permanently sealed.
    public entry fun destroy_cap(caller: &signer) acquires ResourceCap {
        assert!(signer::address_of(caller) == @origin, E_NOT_ORIGIN);
        assert!(exists<ResourceCap>(@D), E_CAP_GONE);
        let ResourceCap { cap } = move_from<ResourceCap>(@D);
        let _sc = option::destroy_some(cap);
        event::emit(CapDestroyed { caller: signer::address_of(caller), timestamp: timestamp::now_seconds() });
    }

    fun init_module_inner(deployer: &signer, supra_md: Object<Metadata>) {
        let ctor = object::create_named_object(deployer, b"D");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor, option::none(),
            string::utf8(b"D"), string::utf8(b"D"), 8,
            string::utf8(b""), string::utf8(b""),
        );
        let metadata = object::object_from_constructor_ref<Metadata>(&ctor);
        let da = signer::address_of(deployer);
        let fee_ctor = object::create_object(da);
        let sp_ctor = object::create_object(da);
        let sp_coll_ctor = object::create_object(da);
        let reserve_ctor = object::create_object(da);
        let tr_ctor = object::create_object(da);
        move_to(deployer, Registry {
            metadata,
            supra_metadata: supra_md,
            mint_ref: fungible_asset::generate_mint_ref(&ctor),
            burn_ref: fungible_asset::generate_burn_ref(&ctor),
            fee_pool: fungible_asset::create_store(&fee_ctor, metadata),
            fee_extend: object::generate_extend_ref(&fee_ctor),
            sp_pool: fungible_asset::create_store(&sp_ctor, metadata),
            sp_extend: object::generate_extend_ref(&sp_ctor),
            sp_coll_pool: fungible_asset::create_store(&sp_coll_ctor, supra_md),
            sp_coll_extend: object::generate_extend_ref(&sp_coll_ctor),
            reserve_coll: fungible_asset::create_store(&reserve_ctor, supra_md),
            reserve_extend: object::generate_extend_ref(&reserve_ctor),
            treasury: fungible_asset::create_store(&tr_ctor, supra_md),
            treasury_extend: object::generate_extend_ref(&tr_ctor),
            troves: smart_table::new(),
            sp_positions: smart_table::new(),
            total_debt: 0,
            total_sp: 0,
            product_factor: PRECISION,
            reward_index_d: 0,
            reward_index_coll: 0,
        });
    }

    fun price_8dec(): u128 {
        let (v, d, ts_ms, _round) = supra_oracle_storage::get_price(PAIR_ID);
        assert!(v > 0, E_PRICE_ZERO);
        assert!(ts_ms > 0, E_STALE);
        let now_ms = timestamp::now_seconds() * 1000;
        assert!(ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS, E_STALE_FUTURE);
        assert!(now_ms <= ts_ms + STALENESS_MS, E_STALE);
        let dec = (d as u64);
        assert!(dec <= 38, E_EXPO_BOUND);
        let result = if (dec >= 8) v / pow10(dec - 8) else v * pow10(8 - dec);
        assert!(result > 0, E_PRICE_ZERO);
        result
    }

    fun pow10(n: u64): u128 {
        assert!(n <= 38, E_DECIMAL_OVERFLOW);
        let r: u128 = 1;
        while (n > 0) { r = r * 10; n = n - 1; };
        r
    }

    fun route_fee_fa(r: &mut Registry, fa: FungibleAsset, donor: address) {
        let amt = fungible_asset::amount(&fa);
        if (amt == 0) { fungible_asset::destroy_zero(fa); return };
        let donate_amt = (((amt as u128) * 1000) / 10000) as u64;
        if (donate_amt > 0) {
            let donate_portion = fungible_asset::extract(&mut fa, donate_amt);
            fungible_asset::deposit(r.sp_pool, donate_portion);
            event::emit(SPDonated { donor, amount: donate_amt });
        };
        let sp_amt = fungible_asset::amount(&fa);
        if (sp_amt == 0) { fungible_asset::destroy_zero(fa); return };
        if (r.total_sp == 0) {
            // Cliff: no keyed depositors → 90% portion redirected to sp_pool as agnostic
            // donation rather than accruing unclaimable in the fee accumulator.
            fungible_asset::deposit(r.sp_pool, fa);
            event::emit(SPDonated { donor, amount: sp_amt });
        } else {
            fungible_asset::deposit(r.fee_pool, fa);
            r.reward_index_d = r.reward_index_d + (sp_amt as u128) * r.product_factor / (r.total_sp as u128);
        }
    }

    fun sp_settle(r: &mut Registry, u: address) {
        let pos = smart_table::borrow_mut(&mut r.sp_positions, u);
        let snap_p = pos.snapshot_product;
        let snap_i_d = pos.snapshot_index_d;
        let snap_i_coll = pos.snapshot_index_coll;
        let initial = pos.initial_balance;
        if (snap_p == 0 || initial == 0) {
            pos.snapshot_product = r.product_factor;
            pos.snapshot_index_d = r.reward_index_d;
            pos.snapshot_index_coll = r.reward_index_coll;
            return;
        };

        let u64_max: u256 = 18446744073709551615;
        let raw_d = ((r.reward_index_d - snap_i_d) as u256) * (initial as u256) / (snap_p as u256);
        let raw_coll = ((r.reward_index_coll - snap_i_coll) as u256) * (initial as u256) / (snap_p as u256);
        let raw_bal = (initial as u256) * (r.product_factor as u256) / (snap_p as u256);
        // Saturate at u64::MAX rather than abort — prevents permanent SP position lock
        // if decades of fee accrual push pending rewards past u64 bounds. User loses only
        // the astronomical excess above 1.8e19 raw units.
        let d_trunc = raw_d > u64_max;
        let coll_trunc = raw_coll > u64_max;
        let pending_d = (if (d_trunc) u64_max else raw_d) as u64;
        let pending_coll = (if (coll_trunc) u64_max else raw_coll) as u64;
        let new_balance = (if (raw_bal > u64_max) u64_max else raw_bal) as u64;
        if (d_trunc || coll_trunc) {
            event::emit(RewardSaturated { user: u, pending_d_truncated: d_trunc, pending_coll_truncated: coll_trunc });
        };

        pos.initial_balance = new_balance;
        pos.snapshot_product = r.product_factor;
        pos.snapshot_index_d = r.reward_index_d;
        pos.snapshot_index_coll = r.reward_index_coll;

        if (pending_d > 0) {
            let fee_signer = object::generate_signer_for_extending(&r.fee_extend);
            let fa = fungible_asset::withdraw(&fee_signer, r.fee_pool, pending_d);
            primary_fungible_store::deposit(u, fa);
        };
        if (pending_coll > 0) {
            let coll_signer = object::generate_signer_for_extending(&r.sp_coll_extend);
            let fa = fungible_asset::withdraw(&coll_signer, r.sp_coll_pool, pending_coll);
            primary_fungible_store::deposit(u, fa);
        };
        if (pending_d > 0 || pending_coll > 0) {
            event::emit(SPClaimed { user: u, d_amt: pending_d, coll_amt: pending_coll });
        }
    }

    fun open_impl(user_addr: address, fa_coll: FungibleAsset, debt: u64) acquires Registry {
        assert!(debt >= MIN_DEBT, E_DEBT_MIN);
        let coll_amt = fungible_asset::amount(&fa_coll);
        let r = borrow_global_mut<Registry>(@D);
        let price = price_8dec();

        let is_existing = smart_table::contains(&r.troves, user_addr);
        let (prior_coll, prior_debt) = if (is_existing) {
            let t = smart_table::borrow(&r.troves, user_addr);
            (t.collateral, t.debt)
        } else (0, 0);
        let new_coll = prior_coll + coll_amt;
        let new_debt = prior_debt + debt;
        let coll_usd = (new_coll as u128) * price / 100_000_000;
        assert!(coll_usd * 10000 >= MCR_BPS * (new_debt as u128), E_COLLATERAL);

        fungible_asset::deposit(r.treasury, fa_coll);
        let fee = (((debt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let user_fa = fungible_asset::mint(&r.mint_ref, debt - fee);
        let fee_fa = fungible_asset::mint(&r.mint_ref, fee);
        primary_fungible_store::deposit(user_addr, user_fa);
        route_fee_fa(r, fee_fa, user_addr);

        if (is_existing) {
            let t = smart_table::borrow_mut(&mut r.troves, user_addr);
            t.collateral = new_coll;
            t.debt = new_debt;
        } else {
            smart_table::add(&mut r.troves, user_addr, Trove { collateral: new_coll, debt: new_debt });
        };
        r.total_debt = r.total_debt + debt;
        event::emit(TroveOpened { user: user_addr, new_collateral: new_coll, new_debt, added_debt: debt });
    }

    fun add_impl(user_addr: address, fa_coll: FungibleAsset) acquires Registry {
        let amt = fungible_asset::amount(&fa_coll);
        assert!(amt > 0, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, user_addr), E_TROVE);
        fungible_asset::deposit(r.treasury, fa_coll);
        let t = smart_table::borrow_mut(&mut r.troves, user_addr);
        t.collateral = t.collateral + amt;
        event::emit(CollateralAdded { user: user_addr, amount: amt });
    }

    fun close_impl(user: &signer): FungibleAsset acquires Registry {
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, u), E_TROVE);
        let t = smart_table::remove(&mut r.troves, u);
        if (t.debt > 0) {
            fungible_asset::burn(&r.burn_ref, primary_fungible_store::withdraw(user, r.metadata, t.debt));
        };
        r.total_debt = r.total_debt - t.debt;
        event::emit(TroveClosed { user: u, collateral: t.collateral, debt: t.debt });
        let sr = object::generate_signer_for_extending(&r.treasury_extend);
        fungible_asset::withdraw(&sr, r.treasury, t.collateral)
    }

    fun redeem_impl(user: &signer, d_amt: u64, target: address): FungibleAsset acquires Registry {
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, target), E_TARGET);
        let price = price_8dec();
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * 100_000_000 / price) as u64);

        let t = smart_table::borrow_mut(&mut r.troves, target);
        assert!(t.debt >= net, E_TARGET);
        assert!(t.collateral >= coll_out, E_COLLATERAL);
        t.debt = t.debt - net;
        t.collateral = t.collateral - coll_out;
        assert!(t.debt == 0 || t.debt >= MIN_DEBT, E_DEBT_MIN);
        assert!(t.debt == 0 || t.collateral > 0, E_COLLATERAL);

        let user_fa = primary_fungible_store::withdraw(user, r.metadata, d_amt);
        let fee_fa = fungible_asset::extract(&mut user_fa, fee);
        fungible_asset::burn(&r.burn_ref, user_fa);
        let u = signer::address_of(user);
        route_fee_fa(r, fee_fa, u);
        r.total_debt = r.total_debt - net;
        event::emit(Redeemed { user: u, target, d_amt, coll_out });
        let sr = object::generate_signer_for_extending(&r.treasury_extend);
        fungible_asset::withdraw(&sr, r.treasury, coll_out)
    }

    public entry fun open_trove(user: &signer, coll_amt: u64, debt: u64) acquires Registry {
        let supra_md = borrow_global<Registry>(@D).supra_metadata;
        let fa = primary_fungible_store::withdraw(user, supra_md, coll_amt);
        open_impl(signer::address_of(user), fa, debt);
    }

    public entry fun add_collateral(user: &signer, coll_amt: u64) acquires Registry {
        let supra_md = borrow_global<Registry>(@D).supra_metadata;
        let fa = primary_fungible_store::withdraw(user, supra_md, coll_amt);
        add_impl(signer::address_of(user), fa);
    }

    public entry fun close_trove(user: &signer) acquires Registry {
        primary_fungible_store::deposit(signer::address_of(user), close_impl(user));
    }

    public entry fun redeem(user: &signer, d_amt: u64, target: address) acquires Registry {
        primary_fungible_store::deposit(
            signer::address_of(user), redeem_impl(user, d_amt, target)
        );
    }

    public entry fun redeem_from_reserve(user: &signer, d_amt: u64) acquires Registry {
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        let price = price_8dec();
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * 100_000_000 / price) as u64);
        assert!(fungible_asset::balance(r.reserve_coll) >= coll_out, E_INSUFFICIENT_RESERVE);

        // Reserve redemption burns D against protocol-owned collateral. No trove is
        // being closed here, so total_debt (= sum of per-trove debts) is intentionally
        // not decremented. Circulating supply falls while total_debt stays — this widens
        // the supply-vs-debt gap, which is the intended reserve-drain mechanic.
        let user_fa = primary_fungible_store::withdraw(user, r.metadata, d_amt);
        let fee_fa = fungible_asset::extract(&mut user_fa, fee);
        fungible_asset::burn(&r.burn_ref, user_fa);
        let u = signer::address_of(user);
        route_fee_fa(r, fee_fa, u);

        let sr = object::generate_signer_for_extending(&r.reserve_extend);
        let out = fungible_asset::withdraw(&sr, r.reserve_coll, coll_out);
        primary_fungible_store::deposit(u, out);

        event::emit(ReserveRedeemed { user: u, d_amt, coll_out });
    }

    public entry fun liquidate(liquidator: &signer, target: address) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, target), E_TARGET);
        let price = price_8dec();
        let t_ref = smart_table::borrow(&r.troves, target);
        let debt = t_ref.debt;
        let coll = t_ref.collateral;
        let coll_usd = (coll as u128) * price / 100_000_000;

        assert!(coll_usd * 10000 < LIQ_THRESHOLD_BPS * (debt as u128), E_HEALTHY);
        let pool_before = fungible_asset::balance(r.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);

        let total_before = r.total_sp;
        let new_p = r.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        // MIN_P_THRESHOLD only applies to keyed depositors. During cliff (total_before==0)
        // the donations alone absorb absent any rateable share — accept arbitrary p drop.
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        // Truncation guard (HIGH-1, Claude R1 fresh): u64/u128 truncation could decouple
        // total_sp from product_factor, leaving total_sp_new == 0 while keyed positions
        // still in table. Subsequent route_fee divides by total_sp == 0 → permanent DoS.
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);

        let bonus_usd = (debt as u128) * (LIQ_BONUS_BPS as u128) / 10000;
        let liq_share_usd = bonus_usd * (LIQ_LIQUIDATOR_BPS as u128) / 10000;
        let reserve_share_usd = bonus_usd * (LIQ_SP_RESERVE_BPS as u128) / 10000;
        let total_seize_usd = (debt as u128) + bonus_usd;
        let total_seize_u128 = total_seize_usd * 100_000_000 / price;
        let coll_u128 = (coll as u128);
        let total_seize_coll = (if (total_seize_u128 > coll_u128) coll_u128 else total_seize_u128) as u64;
        let liq_u128 = liq_share_usd * 100_000_000 / price;
        let total_seize_coll_u128 = (total_seize_coll as u128);
        let liq_coll = (if (liq_u128 > total_seize_coll_u128) total_seize_coll_u128 else liq_u128) as u64;
        let remaining_u128 = total_seize_coll_u128 - (liq_coll as u128);
        let reserve_u128 = reserve_share_usd * 100_000_000 / price;
        let reserve_coll_amt = (if (reserve_u128 > remaining_u128) remaining_u128 else reserve_u128) as u64;
        let sp_coll = total_seize_coll - liq_coll - reserve_coll_amt;
        let target_remainder = coll - total_seize_coll;

        smart_table::remove(&mut r.troves, target);
        r.total_debt = r.total_debt - debt;

        let sp_signer = object::generate_signer_for_extending(&r.sp_extend);
        let burn_fa = fungible_asset::withdraw(&sp_signer, r.sp_pool, debt);
        fungible_asset::burn(&r.burn_ref, burn_fa);

        if (total_before > 0) {
            r.reward_index_coll = r.reward_index_coll +
                (sp_coll as u128) * r.product_factor / (total_before as u128);
        };
        r.product_factor = new_p;
        r.total_sp = total_sp_new;

        let tr_signer = object::generate_signer_for_extending(&r.treasury_extend);
        let seized = fungible_asset::withdraw(&tr_signer, r.treasury, total_seize_coll);
        let liq_fa = fungible_asset::extract(&mut seized, liq_coll);
        primary_fungible_store::deposit(signer::address_of(liquidator), liq_fa);
        let reserve_fa = fungible_asset::extract(&mut seized, reserve_coll_amt);
        fungible_asset::deposit(r.reserve_coll, reserve_fa);
        if (total_before == 0) {
            // Cliff orphan: no keyed depositors → redirect sp_coll to reserve_coll instead
            // of accruing in sp_coll_pool where it would be unclaimable.
            fungible_asset::deposit(r.reserve_coll, seized);
        } else {
            fungible_asset::deposit(r.sp_coll_pool, seized);
        };

        if (target_remainder > 0) {
            let rem_fa = fungible_asset::withdraw(&tr_signer, r.treasury, target_remainder);
            primary_fungible_store::deposit(target, rem_fa);
        };

        event::emit(Liquidated {
            liquidator: signer::address_of(liquidator),
            target, debt,
            coll_to_liquidator: liq_coll,
            coll_to_sp: sp_coll,
            coll_to_reserve: reserve_coll_amt,
            coll_to_target: target_remainder,
        });
    }

    public entry fun sp_deposit(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.metadata, amt);
        fungible_asset::deposit(r.sp_pool, fa_in);
        // Reset-on-empty: when total_sp has been fully drained (previous cliff-freeze
        // plus all prior depositors withdrew), reset product_factor to full precision
        // so liquidations can resume. No active depositor is harmed — there are none.
        if (r.total_sp == 0) {
            r.product_factor = PRECISION;
        };
        if (smart_table::contains(&r.sp_positions, u)) {
            sp_settle(r, u);
            let p = smart_table::borrow_mut(&mut r.sp_positions, u);
            p.initial_balance = p.initial_balance + amt;
        } else {
            smart_table::add(&mut r.sp_positions, u, SP {
                initial_balance: amt,
                snapshot_product: r.product_factor,
                snapshot_index_d: r.reward_index_d,
                snapshot_index_coll: r.reward_index_coll,
            });
        };
        r.total_sp = r.total_sp + amt;
        event::emit(SPDeposited { user: u, amount: amt });
    }

    /// Permissionless agnostic donation of D into the Stability Pool. Joins sp_pool
    /// balance only — does NOT increment total_sp, so keyed depositors' yield share
    /// is not diluted. Donations participate in liquidation absorption pro-rata via
    /// the actual sp_pool balance ratio, gradually burning over time.
    public entry fun donate_to_sp(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.metadata, amt);
        fungible_asset::deposit(r.sp_pool, fa_in);
        event::emit(SPDonated { donor: u, amount: amt });
    }

    /// Permissionless donation of SUPRA into reserve_coll — fortifies redeem_from_reserve
    /// capacity. No oracle call; works during oracle freeze.
    public entry fun donate_to_reserve(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.supra_metadata, amt);
        fungible_asset::deposit(r.reserve_coll, fa_in);
        event::emit(ReserveDonated { donor: u, amount: amt });
    }

    public entry fun sp_withdraw(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.sp_positions, u), E_SP_BAL);
        sp_settle(r, u);
        let pos = smart_table::borrow_mut(&mut r.sp_positions, u);
        assert!(pos.initial_balance >= amt, E_SP_BAL);
        pos.initial_balance = pos.initial_balance - amt;
        r.total_sp = r.total_sp - amt;
        let empty = pos.initial_balance == 0;
        let sr = object::generate_signer_for_extending(&r.sp_extend);
        primary_fungible_store::deposit(u, fungible_asset::withdraw(&sr, r.sp_pool, amt));
        if (empty) { smart_table::remove(&mut r.sp_positions, u); };
        event::emit(SPWithdrew { user: u, amount: amt });
    }

    public entry fun sp_claim(user: &signer) acquires Registry {
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.sp_positions, u), E_SP_BAL);
        sp_settle(r, u);
    }

    #[view] public fun read_warning(): vector<u8> { WARNING }

    #[view] public fun metadata_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).metadata)
    }

    // FungibleStore addresses — exposed pre-seal so indexers/frontends can subscribe
    // events directly per store and verify on-chain balances without reading Registry.
    // Each address is derived from the deployer GUID counter at init time and is
    // stable for the package lifetime.

    #[view] public fun fee_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).fee_pool)
    }

    #[view] public fun sp_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).sp_pool)
    }

    #[view] public fun sp_coll_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).sp_coll_pool)
    }

    #[view] public fun reserve_coll_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).reserve_coll)
    }

    #[view] public fun treasury_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).treasury)
    }

    #[view] public fun price(): u128 { price_8dec() }

    #[view] public fun trove_of(addr: address): (u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.troves, addr)) {
            let t = smart_table::borrow(&r.troves, addr);
            (t.collateral, t.debt)
        } else (0, 0)
    }

    #[view] public fun sp_of(addr: address): (u64, u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.sp_positions, addr)) {
            let p = smart_table::borrow(&r.sp_positions, addr);
            let eff = ((((p.initial_balance as u256) * (r.product_factor as u256)) / (p.snapshot_product as u256)) as u64);
            let p_d = ((((r.reward_index_d - p.snapshot_index_d) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            let p_coll = ((((r.reward_index_coll - p.snapshot_index_coll) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            (eff, p_d, p_coll)
        } else (0, 0, 0)
    }

    #[view] public fun totals(): (u64, u64, u128, u128, u128) acquires Registry {
        let r = borrow_global<Registry>(@D);
        (r.total_debt, r.total_sp, r.product_factor, r.reward_index_d, r.reward_index_coll)
    }

    #[view] public fun reserve_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).reserve_coll)
    }

    /// Live sp_pool balance. Differs from total_sp by the amount of agnostic donations
    /// that have not yet been absorbed via liquidation.
    #[view] public fun sp_pool_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).sp_pool)
    }

    /// Returns true iff destroy_cap has been called (package permanently sealed).
    #[view] public fun is_sealed(): bool { !exists<ResourceCap>(@D) }

    /// Exact D amount user needs to burn in order to call close_trove on their own trove.
    /// Useful for front-ends to show the secondary-market D deficit pre-close.
    #[view] public fun close_cost(addr: address): u64 acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.troves, addr)) {
            smart_table::borrow(&r.troves, addr).debt
        } else 0
    }

    /// Returns (collateral, debt, cr_bps). cr_bps = 0 if no trove, or if oracle unavailable
    /// (caller must handle that case). Uses price_8dec() so shares its abort semantics on bad oracle.
    #[view] public fun trove_health(addr: address): (u64, u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (!smart_table::contains(&r.troves, addr)) return (0, 0, 0);
        let t = smart_table::borrow(&r.troves, addr);
        if (t.debt == 0) return (t.collateral, 0, 0);
        let price = price_8dec();
        let coll_usd = (t.collateral as u128) * price / 100_000_000;
        let cr_bps = (coll_usd * 10000 / (t.debt as u128)) as u64;
        (t.collateral, t.debt, cr_bps)
    }

    #[test_only]
    public fun init_module_for_test(deployer: &signer, supra_md: Object<Metadata>) {
        init_module_inner(deployer, supra_md);
    }

    #[test_only]
    public fun test_stash_cap_for_test(deployer: &signer) {
        let fake = supra_framework::account::create_test_signer_cap(signer::address_of(deployer));
        move_to(deployer, ResourceCap { cap: option::some(fake) });
    }

    #[test_only]
    public fun test_create_sp_position(addr: address, balance: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        // Mint+deposit D into sp_pool so live and V2-simulator paths see a
        // balance backing the keyed total_sp. V1-style simulators don't read
        // sp_pool, so this is harmless to legacy tests.
        let fa = fungible_asset::mint(&r.mint_ref, balance);
        fungible_asset::deposit(r.sp_pool, fa);
        smart_table::add(&mut r.sp_positions, addr, SP {
            initial_balance: balance,
            snapshot_product: r.product_factor,
            snapshot_index_d: r.reward_index_d,
            snapshot_index_coll: r.reward_index_coll,
        });
        r.total_sp = r.total_sp + balance;
    }

    #[test_only]
    public fun test_donate_sp_raw(amount: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let fa = fungible_asset::mint(&r.mint_ref, amount);
        fungible_asset::deposit(r.sp_pool, fa);
    }

    #[test_only]
    public fun test_route_fee_virtual(amount: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let sp_amt = amount - amount * 1000 / 10000;
        if (sp_amt == 0) return;
        if (r.total_sp == 0) return;
        r.reward_index_d = r.reward_index_d + (sp_amt as u128) * r.product_factor / (r.total_sp as u128);
    }

    /// Exercises the production `route_fee_fa` end-to-end: mints `amount` D, calls
    /// `route_fee_fa` with the supplied donor. Use this for any test that needs to
    /// verify the actual deposit/event paths (vs `test_route_fee_virtual` which only
    /// simulates the keyed-path index update).
    #[test_only]
    public fun test_route_fee_real(donor: address, amount: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let fa = fungible_asset::mint(&r.mint_ref, amount);
        route_fee_fa(r, fa, donor);
    }

    /// Returns (donor, amount) of the most-recently-emitted `SPDonated` event.
    #[test_only]
    public fun test_last_sp_donated(): (address, u64) {
        let events = event::emitted_events<SPDonated>();
        let len = vector::length(&events);
        let e = vector::borrow(&events, len - 1);
        (e.donor, e.amount)
    }

    #[test_only]
    public fun test_sp_donated_count(): u64 {
        vector::length(&event::emitted_events<SPDonated>())
    }

    #[test_only]
    public fun test_sp_pool_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).sp_pool)
    }

    #[test_only]
    public fun test_mint_d(amount: u64): FungibleAsset acquires Registry {
        let r = borrow_global<Registry>(@D);
        fungible_asset::mint(&r.mint_ref, amount)
    }

    #[test_only]
    public fun test_create_trove(addr: address, collateral: u64, debt: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        smart_table::add(&mut r.troves, addr, Trove { collateral, debt });
        r.total_debt = r.total_debt + debt;
    }

    /// V2 simulator using pool_before denominator. Mirrors live `liquidate` math
    /// for the SP-state mutation only (skips collateral seize/distribution).
    #[test_only]
    public fun test_simulate_liquidation_v2(debt: u64, sp_coll_absorbed: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let pool_before = fungible_asset::balance(r.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);
        let total_before = r.total_sp;
        let new_p = r.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);
        let sp_signer = object::generate_signer_for_extending(&r.sp_extend);
        let burn_fa = fungible_asset::withdraw(&sp_signer, r.sp_pool, debt);
        fungible_asset::burn(&r.burn_ref, burn_fa);
        if (total_before > 0) {
            r.reward_index_coll = r.reward_index_coll +
                (sp_coll_absorbed as u128) * r.product_factor / (total_before as u128);
        };
        r.product_factor = new_p;
        r.total_sp = total_sp_new;
    }

    /// Legacy V1 simulator using total_sp denominator. Kept for any V1-style tests that
    /// don't model donation flow. New tests should prefer test_simulate_liquidation_v2.
    #[test_only]
    public fun test_simulate_liquidation(debt: u64, sp_coll_absorbed: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let total_before = r.total_sp;
        assert!(total_before > debt, E_SP_INSUFFICIENT);
        let new_p = r.product_factor * ((total_before - debt) as u128) / (total_before as u128);
        assert!(new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        r.reward_index_coll = r.reward_index_coll +
            (sp_coll_absorbed as u128) * r.product_factor / (total_before as u128);
        r.product_factor = new_p;
        r.total_sp = total_before - debt;
    }

    #[test_only]
    public fun test_set_sp_position(
        addr: address, initial: u64, snap_p: u128, snap_i_d: u128, snap_i_coll: u128
    ) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        if (smart_table::contains(&r.sp_positions, addr)) {
            let p = smart_table::borrow_mut(&mut r.sp_positions, addr);
            p.initial_balance = initial;
            p.snapshot_product = snap_p;
            p.snapshot_index_d = snap_i_d;
            p.snapshot_index_coll = snap_i_coll;
        } else {
            smart_table::add(&mut r.sp_positions, addr, SP {
                initial_balance: initial,
                snapshot_product: snap_p,
                snapshot_index_d: snap_i_d,
                snapshot_index_coll: snap_i_coll,
            });
        };
    }

    #[test_only]
    public fun test_get_sp_snapshots(addr: address): (u64, u128, u128, u128) acquires Registry {
        let r = borrow_global<Registry>(@D);
        let p = smart_table::borrow(&r.sp_positions, addr);
        (p.initial_balance, p.snapshot_product, p.snapshot_index_d, p.snapshot_index_coll)
    }

    #[test_only]
    public fun test_force_reward_indices(d_idx: u128, coll_idx: u128) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        r.reward_index_d = d_idx;
        r.reward_index_coll = coll_idx;
    }

    #[test_only]
    public fun test_call_sp_settle(addr: address) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        sp_settle(r, addr);
    }
}
