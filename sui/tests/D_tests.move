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

    // R2 INFO-2: meaningful test for fix (a) — construct synthetic divergent state
    // total_sp == 0 ∧ table::length > 0. Pre-fix: route_fee else-branch div0.
    // Post-fix: total_sp predicate routes via cliff branch correctly.
    // (test_set_sp_position adds to position table without incrementing total_sp,
    // so this constructs the truncation-orphan state synthetically.)
    #[test]
    fun test_route_fee_predicate_divergent_state_uses_total_sp() {
        let mut sc = start();
        let mut reg = take_reg(&mut sc);
        // Synthetic divergent state: table::length=1, total_sp=0
        D::D::test_set_sp_position(&mut reg, ALICE, 1, 1_000_000_000_000_000_000, 0, 0);
        let (_, total_sp_pre, _, r_d_pre, _) = D::D::totals(&reg);
        assert!(total_sp_pre == 0, 1900);
        assert!(r_d_pre == 0, 1901);
        // Pre-fix: would div0 in else branch (table::length != 0 → reward_index update with /0)
        // Post-fix: cliff redirect via total_sp == 0 → no reward_index update
        D::D::test_route_fee_virtual(&mut reg, 1_000_000);
        let (_, total_sp_post, _, r_d_post, _) = D::D::totals(&reg);
        assert!(total_sp_post == 0, 1902);
        assert!(r_d_post == 0, 1903);
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
