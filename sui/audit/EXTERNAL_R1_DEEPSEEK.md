# External R1 — DeepSeek

**Auditor:** DeepSeek (response header labeled "Claude fresh session" but submitted as DeepSeek per user)
**Round:** R1
**Date:** 2026-04-28
**Verdict:** GREEN

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none
- INFO-1: Integer rounding in liquidation math (floor division on `total_sp`/`product_factor`). Same as V1, bounded drift, negligible practical impact.
- INFO-2: Donation events replace FeeBurned (matches self-audit + Grok)
- INFO-3: `total_before == 0` liquidation behavior — burns debt + reduces product_factor even with no keyed positions. Reset-on-empty in `sp_deposit` correctly handles future depositor entry. No issue.

## Math invariant verification — ALL VERIFIED

- new total_sp formula correctness ✓ (proof confirmed, integer truncation consistent across aggregates)
- reward_index_d denominator strictly keyed ✓ (donations don't dilute)
- donation residue sp_pool consistency ✓ (residue scales exactly as proven)
- cliff path no orphan ✓ (route_fee 90% redirect + sp_coll → reserve_coll)
- V1 invariants preserved ✓ (MIN_P_THRESHOLD, u64 saturation, sender-keyed sp_withdraw)

## Attack surface

- New surface: donate_to_sp + donate_to_reserve permissionless gifts. No exploit, only increase pool balances.
- Modified surface: route_fee + liquidate use sp_pool balance vs total_sp. Mathematically sound. No devaluation path; donations always cushion liquidations.
- Self-audit vectors A-D correctly rejected. Additional verification: u64×u64 ≤ u128 in liquidation math (no overflow). total_sp==0 reset in sp_deposit correctly revives drained pool.

## Recommendation

**Proceed directly to deployment. No fixes required. R2 unnecessary.**

## Optional notes

Self-audit math proof rigorous, aligns with code. Bundle well-documented. Test suite covers V2-specific scenarios thoroughly. "Clean additive refactor."
