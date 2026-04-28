# External R1 — Claude (Anthropic, Opus 4.7 fresh session)

**Auditor:** Claude (Opus 4.7), fresh session
**Round:** R1
**Date:** 2026-04-28
**Verdict:** YELLOW — HIGH-1 fix required before re-bundle

## Findings

### HIGH-1: u64/u128 truncation decoupling → DoS + stranded-position race — **APPLIED + RESOLVED**

**Location:** D.move route_fee (line 248) + liquidate (lines 484, 516)

**Root cause:**
- `new_p` lives in u128 with PRECISION=1e18 baked in → MIN_P_THRESHOLD tolerates ratio down to 1e-9
- `total_sp` lives in u64 raw units → truncates to 0 long before MIN_P_THRESHOLD trips
- Asymmetric truncation enables state: `total_sp == 0 ∧ table::length > 0 ∧ new_p >= MIN_P_THRESHOLD`

**Reproducer (verified):**
- ALICE position: `initial_balance = 1`, snap_p = PRECISION
- BOB donates 1_000_000_000 raw
- Liquidate debt = 999_999_990:
  - new_p = 1e18 × 10 / 1e9 = 1e10 (passes MIN_P_THRESHOLD)
  - total_sp_new = 1 × 10 / 1e9 = **0** (truncates)
- After: `total_sp = 0` but `table::length = 1`
- Subsequent route_fee: `table::length > 0` → else branch → `× product_factor / 0` → **DIV BY ZERO ABORT**

**Impact:**
1. Sustained DoS on mint/redeem surface (any fee-routing op aborts)
2. Stranded-position withdrawal race (after sp_deposit reset triggers, dust positions resurrect via `initial × PRECISION / snap_p_old`, first-mover-takes-all)
3. **Triggerable organically** — protocol's own 10% fee routing accumulates donation residue over time, can hit truncation on routine liquidation without adversary

**Fixes applied:**

(a) `route_fee` cliff predicate `table::length(&r.sp_positions) == 0` → `r.total_sp == 0` (consistent with liquidate's `total_before == 0` and sp_deposit's reset-on-empty)

(b) `liquidate` adds invariant guard: `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)`. Liquidation aborts before creating bad state.

**Tests added:**
- `test_truncation_orphan_aborts_liquidation` — Claude's reproducer, expects E_P_CLIFF
- `test_route_fee_cliff_redirect_via_total_sp` — verifies fix (a) routes via total_sp predicate

**Verification:** 28/28 tests PASS post-fix.

### LOW-1: MIN_P_THRESHOLD fires unnecessarily during pure-donation cliff — **APPLIED + RESOLVED**

When `total_before == 0`, product_factor has no semantic role (no positions to apply to). Fix: `assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF)`. Cliff-mode liquidations no longer abort needlessly on product_factor decay.

### MEDIUM
None.

### INFO
- INFO-1: donate_to_sp doesn't reset product_factor when total_sp == 0. Documented behavior, donations + nominal sp_deposit pair if needed.
- INFO-2: sp_of view u256→u64 truncation silent (unlike sp_settle which emits RewardSaturated). Cosmetic, defer.
- INFO-3: assertion message inconsistency on E_SP_INSUFFICIENT for `pool_before == debt` case. Cosmetic.
- INFO-4: rebrand verified by inspection.

## Math invariant verification

| Check | Pre-fix | Post-fix |
|---|---|---|
| total_sp formula in ℚ (rationals) | ✓ | ✓ |
| total_sp formula in ℤ (integers) | ✗ truncation decouples | ✓ via guard |
| reward_index_d denominator strictly keyed | ✗ predicate mismatch | ✓ unified predicate |
| donation residue sp_pool consistency | ✓ | ✓ |
| cliff path no orphan | ✗ half-orphan (route_fee broken) | ✓ unified predicates |
| V1 invariants preserved | ✓ | ✓ |

## Attack surface

- HIGH-1 enables sustained DoS at low cost (~1 D donation triggers when total_sp dust)
- Plus stranded-position fund loss via reset-on-empty inflation

## Recommendation

**Apply HIGH-1 fixes (a) + (b) + LOW-1 fix + reproducer tests + cliff-redirect test, then re-bundle as R2.**

Do NOT deploy as bundled. Truncation pathway reachable via routine activity. After fixes, expect clean clearance — bug is localized, patch is small, V2 changes otherwise well-scoped. Architecture survives; integer-arithmetic edges tightened.

## Optional notes

- Self-audit unusually rigorous — discipline-of-formal-methods miss (continuous proof not lifted to integer semantics) rather than sloppy review.
- Suggest registry-level invariant `total_sp == 0 ⟺ all positions dust` as post-state check in tests.
- WARNING text accurate; suggest one-line addition about pro-rata absorb scaling.
- Move 2024.beta `&mut` borrow patterns clean, no borrow-checker findings.

---

**Status post-fix:** 28/28 tests pass. R2 bundle pending Gemini response.
