# External R1 — Gemini 3 Pro

**Auditor:** Gemini
**Round:** R1
**Date:** 2026-04-28
**Verdict:** GREEN

## Findings

- HIGH: none
- MEDIUM: none
- LOW: none (LOW-1 cliff orphan resolved at line 548 verified correct)
- INFO-1: Rebrand consistency — OTW + identifiers + events thoroughly applied
- INFO-2: Positive externality of donations — protocol-owned buffer reduces depositor liquidation loss without yield dilution

## Math invariant verification — ALL PASS

- new total_sp formula correctness ✓ (proportional pro-rata value reduction post-absorb)
- reward_index_d denominator strictly keyed ✓ (donations don't dilute yield)
- donation residue sp_pool consistency ✓ (naturally consumed via pool_before)
- cliff path no orphan ✓ (90% fees → sp_pool, sp_coll → reserve_coll)
- V1 invariants preserved ✓ (MIN_P_THRESHOLD, reward saturation intact)

## Attack surface

- New surface: donate_to_sp + donate_to_reserve strictly additive sinks. No value extraction or oracle manipulation.
- Modified surface: burn-based fee → donation-based redirect maintains deflationary pressure while improving SP health.
- Considered: front-running open_trove/redeem via donations evaluated, no manipulation possible since oracle-priced.

## Recommendation

**Proceed to R2 / Ready for Mainnet.**

Refactor semantically sound. Math proofs verified.

## Optional notes

WARNING block (clauses 4 + 8) "exceptionally detailed" regarding Pyth oracle risks + supply-vs-debt gap.

---

**Note:** Gemini reviewed pre-fix bundle and did not catch HIGH-1 (truncation decoupling). HIGH-1 was uniquely identified by Claude and fixes have been applied.
