# D v0.2.0 — Audit Tracking

**Status:** AUDIT PHASE CLOSED. R1 (6 auditors) + R2 (Claude verification) complete. HIGH-1 + LOW-1 resolved. 29/29 tests pass. Ready for testnet deploy.

## R2 ledger

| Round | Auditor | Date | Verdict | Notes |
|---|---|---|---|---|
| R2 | Claude Opus 4.7 (fresh session) | 2026-04-28 | **GREEN** | HIGH-1 fixes verified correct + complete. INFO-1 (test helper predicate) + INFO-2 (synthetic divergent state test) applied post-R2. INFO-3 (dust-SP griefing) documented, deferred. "R1→R2 turnaround exemplary, cleanest patch cycle expected on real audit." `EXTERNAL_R2_CLAUDE.md` |


## Audit ledger

| Round | Auditor | Date | Verdict | Findings | Notes |
|---|---|---|---|---|---|
| R1 | Kimi K2.6 | 2026-04-28 | **GREEN** | 0H/0M/0L/1I + vectors E/F/G rejected | Math proof verified. Cliff sp_coll test deferable. `EXTERNAL_R1_KIMI.md` |
| R1 | Grok 4 | 2026-04-28 | **GREEN** | 0H/0M/0L/2I (match self-audit) | "Math proof correct and clean". WARNING praised. 866 LOC "remarkably compact". `EXTERNAL_R1_GROK.md` |
| R1 | DeepSeek | 2026-04-28 | **GREEN** | 0H/0M/0L/3I (rounding drift, indexer, total_sp==0 reset) | "Proceed directly to deployment. R2 unnecessary." `EXTERNAL_R1_DEEPSEEK.md` |
| R1 | Qwen3.6 | 2026-04-28 | **GREEN** | 0H/0M/0L/2I + vectors E/F rejected | Math algebra verified. Operational notes (event timestamp, doc sync). `EXTERNAL_R1_QWEN.md` |
| R1 | Claude Opus 4.7 (fresh session) | 2026-04-28 | **YELLOW** | **1 HIGH** + 1 LOW + 4 INFO | Found u64/u128 truncation decoupling DoS — fixes applied + reproducer test added. 28/28 pass post-fix. `EXTERNAL_R1_CLAUDE.md` |
| R1 | Gemini 3 Pro | 2026-04-28 | **GREEN** | 0H/0M/0L/2I | "Proceed to R2 / Ready for Mainnet". Reviewed pre-fix bundle, did not catch HIGH-1. `EXTERNAL_R1_GEMINI.md` |

## Self-audit reference

- `audit/SELF_AUDIT_R1.md` — 0 HIGH / 0 MED / 0 LOW (1 LOW resolved in source) / 2 INFO. Verdict GREEN.

## Submission bundle

- `audit/AUDIT_R1_BUNDLE.md` — 1558 lines, 66.7 KB. Self-contained with cover letter + self-audit + source + tests + Move.toml inline.

## Findings register (cumulative)

### HIGH
(none yet)

### MEDIUM
(none yet)

### LOW
- LOW-1: cliff liquidation orphan in sp_coll_pool — **RESOLVED in source pre-submission** (line 543-549). Detected during self-audit.

### INFO (cumulative across self-audit + 3 R1 auditors)
- INFO-1: Indexer migration FeeBurned → SPDonated. (self-audit, Grok, DeepSeek). Mitigation: post-deploy guide.
- INFO-2: Donation u64 ceiling at ~180 trillion D. (self-audit, Grok, DeepSeek-acknowledged). Practically unreachable.
- INFO-3 (Kimi): Test helper naming clarity (`test_simulate_liquidation` vs `_v2`). Non-blocking, accepted.
- INFO-4 (Kimi attack vectors E/F/G): considered & rejected.
- INFO-5 (DeepSeek): Integer rounding drift in liquidation math, bounded, same as V1.
- INFO-6 (DeepSeek): `total_before == 0` liquidation correctly handled by reset-on-empty in `sp_deposit`.

## Decision log

| Date | Decision | Reason |
|---|---|---|
| 2026-04-28 | Spec locked: agnostic donation + 10/90 split + cliff redirects | Result of design discussion: zero dilution to keyed depositors, no orphan paths |
| 2026-04-28 | Skip flash mint inclusion in V2 | Scope creep; external flash via Suilend/Scallop sufficient for atomic arb |
| 2026-04-28 | Defer multi-oracle redundancy to V3 | Scope creep; ship sealed v2 minimal, document oracle risk in WARNING |
| 2026-04-28 | Rebrand ONE → D (full) | User decision; folder + file + identifiers + WARNING text |
| 2026-04-28 | Cliff sp_coll → reserve_coll redirect | Self-audit LOW-1 fix; consistent with V2 cliff routing pattern |

## Resume keywords

- "lanjut D R1 submit" — actually send bundle to auditors
- "lanjut D R1 process" — process incoming auditor responses
- "lanjut D testnet deploy" — proceed past audit to testnet
