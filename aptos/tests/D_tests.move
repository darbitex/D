#[test_only]
module D::D_tests {
    use std::option;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use D::D;

    const MOCK_APT_HOST: address = @0xABCD;

    fun setup(deployer: &signer): Object<Metadata> {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@aptos_framework)
        );
        let apt_signer = account::create_signer_for_test(MOCK_APT_HOST);
        let ctor = object::create_named_object(&apt_signer, b"APT");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor, option::none(),
            string::utf8(b"Aptos Coin"), string::utf8(b"APT"), 8,
            string::utf8(b""), string::utf8(b""),
        );
        let apt_md = object::object_from_constructor_ref<Metadata>(&ctor);
        D::init_module_for_test(deployer, apt_md);
        apt_md
    }

    #[test(deployer = @D)]
    fun test_init_creates_registry(deployer: &signer) {
        setup(deployer);
        let (debt, sp, p, r1, r2) = D::totals();
        assert!(debt == 0, 100);
        assert!(sp == 0, 101);
        assert!(p == 1_000_000_000_000_000_000, 102);
        assert!(r1 == 0, 103);
        assert!(r2 == 0, 104);
    }

    #[test(deployer = @D)]
    fun test_warning_text_on_chain(deployer: &signer) {
        setup(deployer);
        let w = D::read_warning();
        let prefix = b"D is an immutable stablecoin";
        let i = 0;
        while (i < vector::length(&prefix)) {
            assert!(*vector::borrow(&w, i) == *vector::borrow(&prefix, i), 200);
            i = i + 1;
        };
        let pyth_ref = b"Pyth Network";
        assert!(contains_bytes(&w, &pyth_ref), 201);
        // V2-specific: confirm WARNING (4) reflects 10/90 + agnostic donation language.
        let agnostic_ref = b"agnostic donation";
        assert!(contains_bytes(&w, &agnostic_ref), 202);
        let split_ref = b"10 percent of each mint and redeem fee";
        assert!(contains_bytes(&w, &split_ref), 203);
    }

    #[test(deployer = @D)]
    fun test_trove_of_unknown_returns_zero(deployer: &signer) {
        setup(deployer);
        let (c, d) = D::trove_of(@0xA11CE);
        assert!(c == 0 && d == 0, 300);
    }

    #[test(deployer = @D)]
    fun test_sp_of_unknown_returns_zero(deployer: &signer) {
        setup(deployer);
        let (bal, p_d, p_coll) = D::sp_of(@0xA11CE);
        assert!(bal == 0 && p_d == 0 && p_coll == 0, 400);
    }

    #[test(deployer = @D)]
    fun test_metadata_addr_stable(deployer: &signer) {
        setup(deployer);
        assert!(D::metadata_addr() == D::metadata_addr(), 500);
    }

    /// Composability surface: each FungibleStore exposes its own object address.
    /// Indexers can subscribe events per-store; frontend can verify balances.
    /// All five addresses must be distinct AND stable across calls.
    #[test(deployer = @D)]
    fun test_store_addresses_distinct_and_stable(deployer: &signer) {
        setup(deployer);
        let m = D::metadata_addr();
        let f = D::fee_pool_addr();
        let s = D::sp_pool_addr();
        let sc = D::sp_coll_pool_addr();
        let rc = D::reserve_coll_addr();
        let t = D::treasury_addr();

        // Stability: same call returns same address
        assert!(f == D::fee_pool_addr(), 510);
        assert!(s == D::sp_pool_addr(), 511);
        assert!(sc == D::sp_coll_pool_addr(), 512);
        assert!(rc == D::reserve_coll_addr(), 513);
        assert!(t == D::treasury_addr(), 514);

        // Distinctness: all six addresses (metadata + 5 stores) must differ
        assert!(m != f && m != s && m != sc && m != rc && m != t, 520);
        assert!(f != s && f != sc && f != rc && f != t, 521);
        assert!(s != sc && s != rc && s != t, 522);
        assert!(sc != rc && sc != t, 523);
        assert!(rc != t, 524);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 2, location = D::D)]
    fun test_close_trove_without_trove_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::close_trove(user);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 5, location = D::D)]
    fun test_sp_claim_without_position_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_claim(user);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 5, location = D::D)]
    fun test_sp_withdraw_without_position_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_withdraw(user, 100_000_000);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_sp_deposit_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_deposit(user, 0);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_donate_to_sp_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::donate_to_sp(user, 0);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_donate_to_reserve_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::donate_to_reserve(user, 0);
    }

    #[test(deployer = @D)]
    fun test_sp_position_creation_via_helper(deployer: &signer) {
        setup(deployer);
        let u = @0xBEEF;
        D::test_create_sp_position(u, 100_000_000);
        let (bal, p_d, p_coll) = D::sp_of(u);
        assert!(bal == 100_000_000, 600);
        assert!(p_d == 0, 601);
        assert!(p_coll == 0, 602);
    }

    /// V2 split: 10% donation / 90% accumulator. Replaces V1's 25/75 expected values.
    /// amount=1_000_000 → donate=100_000 (sp_pool), sp_amt=900_000 (accumulator).
    /// reward_index_d delta = 900_000 * 1e18 / 100_000_000 = 9e15.
    /// pending_d for keyed depositor = 9e15 * 1e8 / 1e18 = 900_000.
    #[test(deployer = @D)]
    fun test_reward_index_increment_and_pending(deployer: &signer) {
        setup(deployer);
        let u = @0xBEEF;
        D::test_create_sp_position(u, 100_000_000);
        D::test_route_fee_virtual(1_000_000);
        let (_, _, _, r_d, _) = D::totals();
        assert!(r_d == 9_000_000_000_000_000, 700);
        let (bal, p_d, p_coll) = D::sp_of(u);
        assert!(bal == 100_000_000, 701);
        assert!(p_d == 900_000, 702);
        assert!(p_coll == 0, 703);
    }

    /// V2 pro-rata: amount=300M → donate=30M (skipped in virtual helper), sp_amt=270M.
    /// reward_index_d delta = 270M * 1e18 / 300M = 9e17.
    /// AAAA (200M): p_d = 9e17 * 200M / 1e18 = 180_000_000.
    /// BBBB (100M): p_d = 9e17 * 100M / 1e18 = 90_000_000.
    #[test(deployer = @D)]
    fun test_reward_index_pro_rata_two_depositors(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 200_000_000);
        D::test_create_sp_position(@0xBBBB, 100_000_000);
        D::test_route_fee_virtual(300_000_000);
        let (_, pa, _) = D::sp_of(@0xAAAA);
        let (_, pb, _) = D::sp_of(@0xBBBB);
        assert!(pa == 180_000_000, 800);
        assert!(pb == 90_000_000, 801);
    }

    #[test(deployer = @D)]
    fun test_liquidation_single_depositor(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        let (bal, p_d, p_coll) = D::sp_of(@0xAAAA);
        assert!(bal == 8_000_000_000, 900);
        assert!(p_d == 0, 901);
        assert!(p_coll == 2_500_000_000, 902);
        let (_, total_sp, pf, _, r_coll) = D::totals();
        assert!(total_sp == 8_000_000_000, 903);
        assert!(pf == 800_000_000_000_000_000, 904);
        assert!(r_coll == 250_000_000_000_000_000, 905);
    }

    #[test(deployer = @D)]
    fun test_liquidation_two_depositors_pro_rata(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_create_sp_position(@0xBBBB, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        let (a_bal, _, a_coll) = D::sp_of(@0xAAAA);
        let (b_bal, _, b_coll) = D::sp_of(@0xBBBB);
        assert!(a_bal == 9_000_000_000, 1000);
        assert!(b_bal == 9_000_000_000, 1001);
        assert!(a_coll == 1_250_000_000, 1002);
        assert!(b_coll == 1_250_000_000, 1003);
    }

    #[test(deployer = @D)]
    fun test_liquidation_sequential_math(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        D::test_create_sp_position(@0xBBBB, 10_000_000_000);
        D::test_simulate_liquidation(1_000_000_000, 1_500_000_000);
        let (a_bal, _, a_coll) = D::sp_of(@0xAAAA);
        assert!(a_bal == 7_555_555_555, 1100);
        assert!(a_coll == 3_166_666_666, 1101);
        let (b_bal, _, b_coll) = D::sp_of(@0xBBBB);
        assert!(b_bal == 9_444_444_444, 1102);
        assert!(b_coll == 833_333_333, 1103);
    }

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 14, location = D::D)]
    fun test_liquidation_cliff_guard_aborts(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(9_999_999_000, 1_000_000_000);
        D::test_simulate_liquidation(999, 500);
    }

    // V2 — agnostic donation invariants

    /// donate_to_sp grows sp_pool balance but does NOT increment total_sp,
    /// so reward distribution to keyed depositors is unaffected by donation rate.
    #[test(deployer = @D)]
    fun test_donate_to_sp_no_dilution(deployer: &signer) {
        setup(deployer);
        let alice = @0xA11CE;
        D::test_create_sp_position(alice, 100_000_000);
        // Mint D for a fresh donor and donate it
        let donor = @0xD0;
        let donor_signer = account::create_signer_for_test(donor);
        let fa = D::test_mint_d(50_000_000);
        primary_fungible_store::deposit(donor, fa);
        D::donate_to_sp(&donor_signer, 50_000_000);
        // total_sp unchanged, sp_pool grew
        let (_, total_sp_after, _, _, _) = D::totals();
        assert!(total_sp_after == 100_000_000, 1200);
        let pool = D::sp_pool_balance();
        assert!(pool == 150_000_000, 1201);
        // Reward index didn't change either (donation bypasses fee accumulator)
        let (_, _, _, r_d_after, _) = D::totals();
        assert!(r_d_after == 0, 1202);
        // Now route a fee → keyed depositor still gets full 90% share
        D::test_route_fee_virtual(1_000_000);
        let (_, p_d, _) = D::sp_of(alice);
        assert!(p_d == 900_000, 1203);
    }

    /// V2 cliff path: when total_sp == 0, production `route_fee_fa` redirects BOTH
    /// the 10% donate portion AND the 90% accumulator portion to sp_pool as agnostic
    /// donations (rather than accruing in fee_pool where they'd be unclaimable).
    /// Uses test_route_fee_real to exercise the actual entry path (per Claude R1 L-02
    /// — earlier version with test_route_fee_virtual short-circuited and proved nothing).
    #[test(deployer = @D)]
    fun test_route_fee_cliff_path_pure_donation(deployer: &signer) {
        setup(deployer);
        // Pre-state: pure cliff, no keyed depositors, no donations
        let (_, total_sp_before, _, r_d_before, _) = D::totals();
        assert!(total_sp_before == 0, 1400);
        assert!(r_d_before == 0, 1401);
        let pool_before = D::test_sp_pool_balance();
        assert!(pool_before == 0, 1402);

        // Route 1_000_000 raw fee through production route_fee_fa
        D::test_route_fee_real(@0xCAFE, 1_000_000);

        // Cliff: all 1_000_000 lands in sp_pool (10% extracted to donate, 90% redirected
        // to sp_pool because total_sp==0 instead of fee_pool)
        let pool_after = D::test_sp_pool_balance();
        assert!(pool_after == 1_000_000, 1403);

        // total_sp unchanged (donations never increment it)
        let (_, total_sp_after, _, r_d_after, _) = D::totals();
        assert!(total_sp_after == 0, 1404);

        // reward_index_d unchanged at cliff (no keyed depositor to accumulate against)
        assert!(r_d_after == 0, 1405);

        // Two SPDonated events emitted: 10% portion (100_000) then 90% portion (900_000)
        assert!(D::test_sp_donated_count() == 2, 1406);
        // Last emission = 90% cliff portion
        let (last_donor, last_amt) = D::test_last_sp_donated();
        assert!(last_donor == @0xCAFE, 1407);
        assert!(last_amt == 900_000, 1408);
    }

    /// V2 keyed path: when total_sp > 0, route_fee_fa puts 10% to sp_pool donation
    /// and 90% to fee_pool (accumulator). reward_index_d updates pro-rata.
    #[test(deployer = @D)]
    fun test_route_fee_keyed_path_real(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 100_000_000);
        let pool_before = D::test_sp_pool_balance();  // 1e8 from keyed deposit

        D::test_route_fee_real(@0xCAFE, 1_000_000);

        // sp_pool grew by exactly 100_000 (only the 10% donate portion)
        let pool_after = D::test_sp_pool_balance();
        assert!(pool_after - pool_before == 100_000, 1450);

        // reward_index_d updated by 90% portion
        let (_, _, _, r_d, _) = D::totals();
        assert!(r_d == 9_000_000_000_000_000, 1451);  // 900_000 * 1e18 / 1e8

        // Single SPDonated event from the 10% donate
        assert!(D::test_sp_donated_count() == 1, 1452);
        let (donor, amt) = D::test_last_sp_donated();
        assert!(donor == @0xCAFE, 1453);
        assert!(amt == 100_000, 1454);
    }

    /// L-04: Donor field on SPDonated event reflects actual transaction sender.
    #[test(deployer = @D, donor = @0xC0DE)]
    fun test_donate_to_sp_emits_donor(deployer: &signer, donor: &signer) {
        setup(deployer);
        let donor_addr = std::signer::address_of(donor);
        let fa = D::test_mint_d(50_000_000);
        primary_fungible_store::deposit(donor_addr, fa);

        D::donate_to_sp(donor, 50_000_000);

        // Last (only) SPDonated event must reflect donor's signer-derived address
        let (e_donor, e_amt) = D::test_last_sp_donated();
        assert!(e_donor == donor_addr, 1900);
        assert!(e_amt == 50_000_000, 1901);
    }

    /// HIGH-1 reproducer (Claude Opus 4.7 fresh R1): u64/u128 truncation could decouple
    /// total_sp_new from product_factor. Setup: pool_before = 1e9, total_before = 1e8,
    /// debt = 999_999_999. Then new_p = 1e18 * 1 / 1e9 = 1e9 (= MIN_P_THRESHOLD, passes
    /// cliff guard). total_sp_new = 1e8 * 1 / 1e9 = 0 via integer truncation. Without
    /// the truncation guard, subsequent route_fee divides by total_sp == 0 → permanent
    /// DoS. Guard `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` catches it.
    #[test(deployer = @D)]
    #[expected_failure(abort_code = 14, location = D::D)]
    fun test_truncation_decoupling_aborts(deployer: &signer) {
        setup(deployer);
        // Keyed depositor with 1e8 D
        D::test_create_sp_position(@0xAAAA, 100_000_000);
        // Donate 9e8 D agnostically → sp_pool = 1e9, total_sp still 1e8
        D::test_donate_sp_raw(900_000_000);
        // Liquidate 999_999_999 → pool_before=1e9, new_p=1e9 (MIN_P_THRESHOLD ok),
        // total_sp_new = 1e8 * 1 / 1e9 = 0 → truncation guard aborts E_P_CLIFF.
        D::test_simulate_liquidation_v2(999_999_999, 0);
    }

    /// V2 cliff handling: liquidation when total_before == 0 (pure-donation pool)
    /// must succeed without aborting on MIN_P_THRESHOLD or truncation guard, since
    /// no keyed depositor exists to be harmed by p drop.
    #[test(deployer = @D)]
    fun test_min_p_threshold_skipped_at_cliff(deployer: &signer) {
        setup(deployer);
        // Pure donation pool: 1e10 D, total_sp == 0
        D::test_donate_sp_raw(10_000_000_000);
        // Liquidate 9_999_999_999 → pool_before=1e10, would-be new_p = 1e18 * 1 / 1e10 = 1e8
        // (well below MIN_P_THRESHOLD 1e9), but total_before==0 so cliff guard skipped.
        D::test_simulate_liquidation_v2(9_999_999_999, 0);
        let (_, total_sp, pf, _, _) = D::totals();
        assert!(total_sp == 0, 1500);
        assert!(pf == 100_000_000, 1501); // 1e8 — below MIN_P but accepted at cliff
    }

    /// Confirms V2 simulator math matches V1 simulator when no donations exist
    /// (pool_before == total_sp). Acts as cross-check between the two helpers.
    #[test(deployer = @D)]
    fun test_v1_v2_simulator_parity_no_donation(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation_v2(2_000_000_000, 2_500_000_000);
        let (bal, _, p_coll) = D::sp_of(@0xAAAA);
        // Same expected as V1 single-depositor test
        assert!(bal == 8_000_000_000, 1600);
        assert!(p_coll == 2_500_000_000, 1601);
        let (_, total_sp, pf, _, _) = D::totals();
        assert!(total_sp == 8_000_000_000, 1602);
        assert!(pf == 800_000_000_000_000_000, 1603);
    }

    /// V2 reset-on-empty: after pool fully drains via cliff liquidations, a new
    /// sp_deposit must reset product_factor to PRECISION so subsequent liquidations
    /// can resume.
    #[test(deployer = @D, depositor = @0xDEAD)]
    fun test_sp_deposit_resets_product_factor_when_empty(deployer: &signer, depositor: &signer) {
        setup(deployer);
        // Drive product_factor below PRECISION via simulated liquidation
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 0);
        let (_, _, pf_mid, _, _) = D::totals();
        assert!(pf_mid < 1_000_000_000_000_000_000, 1700);
        // Withdraw AAAA fully so total_sp returns to 0
        // (Use raw simulator-friendly path: drain via test_set_sp_position to 0 then remove)
        // Simpler: simulate aggressive liq that brings total_sp to 0 via formula
        // For this test just use sp_deposit which sees total_sp == 0 if we manually clear it.
        let r_clear_addr = @0xAAAA;
        let _ = r_clear_addr;
        // Direct path: AAAA withdraws via the entry. Need real D balance.
        let alice_signer = account::create_signer_for_test(@0xAAAA);
        D::sp_withdraw(&alice_signer, 8_000_000_000);
        let (_, total_sp, _, _, _) = D::totals();
        assert!(total_sp == 0, 1701);
        // Now depositor mints+deposits — should reset product_factor
        let fa = D::test_mint_d(1_000_000_000);
        primary_fungible_store::deposit(@0xDEAD, fa);
        D::sp_deposit(depositor, 1_000_000_000);
        let (_, _, pf_after, _, _) = D::totals();
        assert!(pf_after == 1_000_000_000_000_000_000, 1702);
    }

    // --- destroy_cap / ResourceCap tests ---

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 17, location = D::D)]
    fun test_destroy_cap_non_origin_aborts(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let attacker = account::create_signer_for_test(@0xBEEF);
        D::destroy_cap(&attacker);
    }

    #[test(deployer = @D)]
    fun test_destroy_cap_consumes_resource(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let origin = account::create_signer_for_test(@origin);
        D::destroy_cap(&origin);
    }

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 18, location = D::D)]
    fun test_destroy_cap_double_call_aborts(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let origin = account::create_signer_for_test(@origin);
        D::destroy_cap(&origin);
        D::destroy_cap(&origin);
    }

    fun contains_bytes(hay: &vector<u8>, needle: &vector<u8>): bool {
        let hn = vector::length(hay);
        let nn = vector::length(needle);
        if (nn == 0 || nn > hn) return nn == 0;
        let i = 0;
        while (i + nn <= hn) {
            let j = 0;
            let ok = true;
            while (j < nn) {
                if (*vector::borrow(hay, i + j) != *vector::borrow(needle, j)) {
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

    // R2-C01 regression: zombie positions (initial=0) must have their snapshots
    // refreshed on every sp_settle call, not left stale. Otherwise a later
    // redeposit pairs a fresh initial_balance with a stale snap_product /
    // snap_index_d pair, inflating the next pending_d by Δindex / stale_P.
    #[test(deployer = @D)]
    fun test_zombie_redeposit_no_phantom_reward(deployer: &signer) {
        setup(deployer);
        let alice = @0xA11CE;

        // Seed a zombie: initial=0, stale snap_p far below current P,
        // stale snap_i_d / snap_i_coll far below current reward indices.
        D::test_set_sp_position(alice, 0, 100_000_000_000_000, 500, 500);
        D::test_force_reward_indices(1_000_000_000_000_000_000, 2_000_000_000_000_000_000);

        D::test_call_sp_settle(alice);

        // Fix validation: snaps must be refreshed to current registry state
        // so a subsequent redeposit cannot inherit the stale pre-zombie diff.
        let (initial, snap_p, snap_i_d, snap_i_coll) = D::test_get_sp_snapshots(alice);
        assert!(initial == 0, 1800);
        assert!(snap_p == 1_000_000_000_000_000_000, 1801);
        assert!(snap_i_d == 1_000_000_000_000_000_000, 1802);
        assert!(snap_i_coll == 2_000_000_000_000_000_000, 1803);
    }

    /// MIN_DEBT was lowered to 0.1 D (10_000_000 raw, 8 dec) in V2 to avoid the
    /// fee-cascade trap that strands ONE Aptos troves at debt == MIN_DEBT.
    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_redeem_below_min_debt_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        // 0.099 D = 9_900_000 < MIN_DEBT (10_000_000)
        D::redeem(user, 9_900_000, @0xBEEF);
    }
}
