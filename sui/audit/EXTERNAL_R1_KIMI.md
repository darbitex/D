# External R1 — Kimi K2.6

**Auditor:** Kimi K2.6 (Moonshot AI)
**Round:** R1
**Date:** 2026-04-28
**Verdict:** GREEN

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none
- INFO-1: Test helper naming clarity — `test_simulate_liquidation` (V1) and `test_simulate_liquidation_v2` (V2) coexist. Consider deprecating/renaming V1 helper in future cleanup. **Status:** non-blocking, accepted as-is (test-only, not on production critical path).

## Math invariant verification — ALL VERIFIED

- new total_sp formula correctness ✓
- reward_index_d denominator strictly keyed ✓
- donation residue sp_pool consistency ✓
- cliff path no orphan ✓
- V1 invariants preserved at modified call sites ✓

## Attack surface — additional vectors considered & rejected

- **E.** Manipulate sp_pool/total_sp ratio to affect future depositors' snapshots → No, snapshots independent of ratio.
- **F.** Repeated small donations grief by keeping pool_before high → No, beneficial (slower product_factor decay).
- **G.** Donation attacker extract value via redeem_from_reserve after donating → No, oracle-priced redemption, donation only adds capacity.

## Optional notes

- Math proof correct and complete.
- Cliff path 90% redirect is defensive improvement vs V1.
- **Suggested**: explicit test for `total_before == 0 && sp_coll > 0` cliff path (reserve_coll redirect). Logic straightforward; deferrable to testnet smoke.

## Recommendation

**Proceed to R2** — No fixes required.
