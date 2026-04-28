# External R2 — Claude (Anthropic, Opus 4.7 fresh session)

**Auditor:** Claude (Opus 4.7), fresh session
**Round:** R2 (post-R1-fix verification)
**Date:** 2026-04-28
**Verdict:** **GREEN** — HIGH-1 fixes correct and complete. Ready for testnet deploy.

## Summary

Both fix (a) `route_fee` predicate change and fix (b) `liquidate` truncation guard applied correctly. R1 LOW-1 elegantly folded into the same `total_before == 0 ||` clause. Cliff predicates across `route_fee`, `liquidate`, and `sp_deposit` reset-on-empty now agree.

No new HIGH/MEDIUM. 3 INFO items relate to test hygiene + residual griefing window (judged unexploitable).

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none
- INFO-1: `test_route_fee_virtual` helper still uses `table::length` predicate (not mirrored to production). Trivial fix.
- INFO-2: `test_route_fee_cliff_redirect_via_total_sp` doesn't actually distinguish predicates (state has both total_sp=0 ∧ table::length=0). Need synthetic divergent state to truly exercise fix (a).
- INFO-3: Residual dust-SP griefing window — analyzed and judged unexploitable. Documentation-only.

## Math invariant verification — ALL PASS POST-FIX

- new total_sp formula correctness in ℤ ✓ (truncation-orphan path closed by fix (b), continuous-math proof now lifts cleanly to integers)
- reward_index_d denominator strictly keyed ✓ (predicate aligned)
- donation residue sp_pool consistency ✓ (unchanged)
- cliff path no orphan ✓ (all three branches semantically equivalent post-fix)
- V1 invariants preserved ✓ (MIN_P_THRESHOLD active when total_before > 0, u64 saturation, sender-keyed sp_withdraw)

## Attack surface

- Fix delta strictly narrows accepted inputs (more aborts via E_P_CLIFF in narrow truncation cases). No new accepted state.
- Vectors A-D (R1) still rejected.
- E (residual dust-SP griefing): unexploitable for profit, defendable cheaply by any user via sp_deposit.
- F (does fix (b) introduce new DoS?): only in narrow cases that also trigger MIN_P_THRESHOLD or are easily resolved. Architecturally consistent.

## Recommendation

**Proceed to testnet deploy.**

Before mainnet, optionally tighten:
- Apply INFO-1 (one-line test helper fix) — APPLIED post-R2
- Apply INFO-2 (synthetic divergent state test) — APPLIED post-R2
- Consider INFO-3 documentation note in WARNING — defer

None gating. Contract as-bundled safe to deploy testnet. R1 HIGH fully resolved at source; test-side gaps were hygiene.

## Optional notes

- "R1 → R2 turnaround is exemplary: cleanest patch cycle I'd expect on a real audit."
- After fix (b), registry-level invariant `total_sp == 0 ⟺ table::length(&sp_positions) == 0` is load-bearing across multiple call sites. Consider lightweight inv_check helper in tests.
- donate_to_sp doesn't reset product_factor in cliff (R1 INFO-1, unchanged). Acceptable design — no MIN_P_THRESHOLD floor when total_before == 0, sp_deposit cleanly resets.
- Move.toml unchanged; build/dependency surface inherited from R1.

---

**Status post-R2:** 29/29 tests pass (INFO-1 + INFO-2 applied). HIGH-1 + LOW-1 closed. Audit phase CLOSED. Ready for testnet deploy.
