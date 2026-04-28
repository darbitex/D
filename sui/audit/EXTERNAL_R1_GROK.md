# External R1 — Grok 4 (xAI)

**Auditor:** Grok (xAI)
**Round:** R1
**Date:** 2026-04-28
**Verdict:** GREEN

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none
- INFO-1: Indexer migration FeeBurned → SPDonated (matches self-audit INFO-1)
- INFO-2: Donation u64 ceiling at ~180 trillion D, practically unreachable (matches self-audit INFO-2)

## Math invariant verification — ALL VERIFIED

- new total_sp formula correctness ✓ (proof in self-audit "correct and clean")
- reward_index_d denominator strictly keyed ✓ (cliff fallback to sp_pool agnostic donation correct)
- donation residue sp_pool consistency ✓ (preserves no-dilution property)
- cliff path no orphan ✓ (route_fee 90% redirect + liquidate sp_coll → reserve_coll)
- V1 invariants preserved at modified call sites ✓ (total_debt, product_factor monotonicity, MIN_P_THRESHOLD, u64 saturation, sender-keyed sp_withdraw, MCR, redemption — all untouched)

## Attack surface

**New surface (donate_to_sp / donate_to_reserve):**
- Pure permissionless gift semantics
- donate_to_sp: increases sp_pool without inflating total_sp → strictly benefits keyed depositors
- donate_to_reserve: pure SUI gift, strengthens redemption capacity, no downside
- Self-audit vectors A-D valid and correctly rejected. **No new vectors found.**

**Modified surface (route_fee + liquidate):**
- 25/75 → 10/90 split + agnostic donation = clear improvement for SP yield
- product_factor denominator change (total_sp → balance::value(&sp_pool)) = minimal correct change for donation semantics
- No new reentrancy/overflow/underflow risks
- Cliff paths consistently route to sp_pool/reserve_coll — no orphan/stuck funds

**Additional vectors considered:**
- u64 overflow via spam donations: ~180T D required, saturation + cliff guards limit damage
- Frontrun sp_deposit with donation: no material effect (donation only helps absorption)
- Interaction with redeem_from_reserve: only beneficial

## Optional notes

- WARNING paragraph is "exceptionally thorough and honest — one of the best I've seen in a production immutable contract." Recommend keep verbatim.
- Suggest adding small test case for multiple sequential donations + liquidations + claims (mostly covered).
- "Code remains remarkably compact and readable for what it does (866 LOC core)."

## Recommendation

**Proceed to R2** (or directly to mainnet if all R1 GREEN with no MEDIUM+).

V2 diff is clean, well-reasoned, mathematically sound. Donation mechanics achieve stated goal (no dilution + gradual burn) without regressions. Cliff orphan fix is elegant and complete.

**Verdict: GREEN — Ready for deployment after parallel auditor feedback.**
