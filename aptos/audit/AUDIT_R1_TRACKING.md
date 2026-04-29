# D Aptos v0.2.0 — Audit R1 Tracking (Consolidated)

**Status:** R1 **CLOSED** 2026-04-29. 6 auditors all GREEN. User decisions: 5 prior auditor findings DECLINED; Claude Opus 4.7 fresh L1/L2/L3 (now ID L-02/L-03/L-04) **APPLIED**. 32/32 tests pass post-apply. Source-of-D.move logic UNCHANGED — fixes are test-only + Move.toml dep pinning.

## Auditor ledger

| Round | Auditor | Verdict | H/M/L/I | File |
|---|---|---|---|---|
| R1 | Grok 4 (xAI) | **GREEN** | 0/0/0/0 + 3 optional | [EXTERNAL_R1_GROK.md](EXTERNAL_R1_GROK.md) |
| R1 | Kimi K2.6 (Moonshot) | **GREEN** | 0/0/0/0 | [EXTERNAL_R1_KIMI.md](EXTERNAL_R1_KIMI.md) |
| R1 | Qwen3.6 | **GREEN** | 0/0/1/3 | [EXTERNAL_R1_QWEN.md](EXTERNAL_R1_QWEN.md) |
| R1 | DeepSeek (self-id Claude 3.5 Haiku) | **GREEN** | 0/0/0/4 | [EXTERNAL_R1_DEEPSEEK.md](EXTERNAL_R1_DEEPSEEK.md) |
| R1 | Gemini | **GREEN** | 0/0/0/2 | [EXTERNAL_R1_GEMINI.md](EXTERNAL_R1_GEMINI.md) |
| R1 | **Claude Opus 4.7 (fresh)** | **GREEN** | 0/0/**3**/8 | [EXTERNAL_R1_CLAUDE.md](EXTERNAL_R1_CLAUDE.md) |

**Cumulative severity (6 auditors):** 0 HIGH / 0 MEDIUM / **4 LOW** / 20 INFO + 7 optional recommendations.

Notable: Claude Opus 4.7 fresh was the auditor that found HIGH-1 truncation decoupling on D Sui R1. On D Aptos R1, **no HIGH/MEDIUM** — the V2 design + truncation guard ported faithfully. 3 substantive LOWs (test gap + dep pinning + event assertion) are infrastructure/test-coverage issues, not source-of-D.move logic bugs.

## Findings register (de-duplicated, raw)

### HIGH
*(none)*

### MEDIUM
*(none)*

### LOW (4)

| ID | Title | Reporter(s) | Loc | Claim | Tier | Status |
|---|---|---|---|---|---|---|
| **L-01** (Qwen) | Integer division precision loss in `donate_amt` calc | Qwen | `D.move route_fee_fa` | `donate_amt = (amt * 1000) / 10000` integer division loses ≤1 raw unit. Doc-only recommendation. | Tier-2 (cosmetic) | **DECLINED** (user 2026-04-29) |
| **L-02** (Claude L1) | `test_route_fee_cliff_path_pure_donation` doesn't exercise production cliff | Claude | `D_tests.move` | Test uses `test_route_fee_virtual` which short-circuits at `total_sp==0`. Production cliff path in `route_fee_fa` (real `if (r.total_sp == 0) { deposit(sp_pool); emit SPDonated }`) has NO Aptos-port unit test. | Tier-2 (test coverage gap) | **APPLIED** — added `test_route_fee_real(donor, amount)` + `test_last_sp_donated()` + `test_sp_donated_count()` helpers in D.move; rewrote cliff test to exercise real route_fee_fa, asserts pool grows by full amount + r_d unchanged + 2 SPDonated events emitted; bonus added `test_route_fee_keyed_path_real` |
| **L-03** (Claude L2) | `AptosFramework` rev = "mainnet" (moving branch) | Claude | `Move.toml` | Non-reproducible builds. Different commits resolved on different days. | Tier-2 (build hygiene) | **APPLIED** — pinned to `e0f33de9783f2ceaa30e5f2b004d3b39812c4f06` (aptos-core mainnet HEAD as of 2026-04-29) |
| **L-04** (Claude L3) | `donor` field on `SPDonated` event not asserted in any test | Claude | tests/D_tests.move | V2 delta (audit goal #3) covered by code review only. | Tier-2 (test coverage gap) | **APPLIED** — added `test_donate_to_sp_emits_donor` test using `test_last_sp_donated()` helper; asserts donor field == signer-derived address |

### INFO (20)

Grouped by category for de-dup:

**Doc/changelog drift** (Claude I1, I2): test count discrepancy 30/30 vs 29 vs claim of 31; LOC 839 vs 760; truncation guard line `:498` stale. Reconcile bundle docs. **Status: cosmetic.**

**Inherited from V1/D Sui sealed** (DeepSeek I4, Claude I3 + I4):
- `(total_before * (pool_before-debt))` u128 product approaches u128::MAX at u64::MAX inputs (theoretical, not reached at realistic scales).
- `total_sp` vs Σ `pos.initial_balance` drift up to (N-1) raw units per liquidation. ~$1e-9 at MIN_DEBT scale. No exploit. Carried from V1 + D Sui (14 audit passes did not flag).
- `reward_index_d` u128 overflow in pathological sustained `total_sp=1` scenario. Documented as WARNING (2). No action needed.

**Operational / pre-deploy hygiene** (DeepSeek I3, I5; Claude I5, I6):
- Pin Pyth dep to git rev for mainnet (already in pre-deploy checklist).
- `bootstrap.move` Move script uses `coin::withdraw<AptosCoin>` — fails for FA-only wallets. Recommend `pyth::update_price_feeds_with_funder`.
- `bootstrap.js` doesn't validate Hermes response shape — could throw confusingly on outage.

**Design-acknowledged** (DeepSeek I1, I2; Qwen I1, I2; Gemini I1, I2; Claude I8):
- MIN_DEBT lowering = conscious design.
- Testnet rehearsal scope = oracle-free per Pyth feed-id mismatch.
- Pyth feed deregistration = WARNING (8), inherent to immutability.
- u64 saturation in sp_settle = WARNING (2).
- Primary store auto-create gas variance = standard Aptos.
- 2 SPDonated events from cliff = indexer note.

**Cosmetic** (Claude I7): WARNING (3) "below ~5%" should be ~2.5% for reserve-zero case. SP-zero correct at <5%. Cosmetic text drift, protocol behaves correctly.

### Optional recommendations (7)

| ID | Title | Reporter(s) | Status |
|---|---|---|---|
| **O-01** | Run Claude Opus 4.7 fresh as additional reviewer | Grok | **DONE** (now in ledger) |
| **O-02** | Mainnet smoke: full open_trove_pyth → fee → sp_claim → liquidate_pyth | Grok | Already in `MAINNET_DEPLOY_PLAN.md` Step 5 |
| **O-03** | Consider `sp_pool_donation_balance()` view | Grok | Derived as `sp_pool_balance() − total_sp`; not adding |
| **O-04** | Document integer division behavior at route_fee_fa | Qwen, Gemini | Same as L-01 declined |
| **O-05** | Standardize mainnet derivation seeds + verify Pyth feed IDs | Gemini | In pre-deploy checklist |
| **O-06** | Submit to fresh Claude Opus 4.7 + 4 more auditors | Qwen | **DONE** (Claude in ledger) |
| **O-07** | Update Darbitex SPA `/one` → D module | Qwen | Separate task `lanjut D aptos frontend` |

## Cross-auditor consensus

All 6 auditors agree on V2 design correctness:
- ✓ `route_fee_fa` 10/90 split correct
- ✓ `liquidate` `pool_before` denominator correct
- ✓ Truncation guard placement correct
- ✓ Cliff orphan redirect correct
- ✓ MIN_DEBT lowering safe
- ✓ Donor threading correct (3 call sites; verified by Claude line-by-line)
- ✓ FA framework usage correct
- ✓ Resource-account derivation correct
- ✓ View fns correct (5 store addresses + sp_pool_balance)
- ✓ Sealing equivalence to D Sui `make_immutable`
- ✓ No reentrancy surface

**Zero divergence on the V2 design correctness across all 6 auditors.**

Claude additionally verified attack-surface enumerations beyond self-audit:
- Self-donation gambit (strictly worse than keyed SP) — ruled out
- Donation-during-liquidation race — cannot make healthy trove liquidatable
- Pyth VAA replay — Pyth-side enforced
- All u128 overflow paths bounded at realistic scales

## Decision (2026-04-29)

User decision on **5 prior auditors' findings**: **"skip semua fix, tidak perlu" / "decline semua fix"** — all DECLINED, source unchanged.

Claude Opus 4.7 fresh now in. Three substantive LOWs (L-02, L-03, L-04) await user decision. None are Tier-1 safety bugs; per `feedback_auditor_rec_signoff.md` policy, propose + wait.

### Pending user decision (3 items)

**L-02 — Add real-cliff-path unit test for `route_fee_fa`.**
- **Cost:** ~30 lines new test + 1 new test_only helper in D.move (`test_route_fee_real(amt: u64)` that mints D, calls `route_fee_fa(donor=test_addr)` directly, asserts sp_pool grew + reward_index_d unchanged at cliff).
- **Risk:** None — pure test-only addition, doesn't touch production code.
- **Benefit:** Closes the only meaningful test-coverage gap on V2-specific surface; verifies production cliff path on Aptos toolchain (currently only validated by inheritance from D Sui sealed mainnet + code review).
- **Recommend:** Apply (test-only, zero source risk, closes Claude's most substantive finding).

**L-03 — Pin AptosFramework to commit hash.**
- **Cost:** 1 line in `Move.toml`. Lookup current `mainnet` HEAD commit, replace `rev = "mainnet"` with `rev = "<hash>"`.
- **Risk:** None.
- **Benefit:** Reproducible builds for future audit re-runs / forensics.
- **Recommend:** Apply (trivial, build hygiene).

**L-04 — Add donor-field event assertion test.**
- **Cost:** ~15 lines new test using `event::emitted_events<SPDonated>()`.
- **Risk:** None — pure test-only addition.
- **Benefit:** Closes the audit-goal-#3 gap (donor threading was explicitly asked, currently only code-reviewed).
- **Recommend:** Apply (cheap, closes loop).

### My take on aggregate

All 3 items are **test/build infrastructure improvements**, not D.move logic fixes. They wouldn't change the audit verdict. The cost is trivial (~50 lines test code + 1 Move.toml line). They strengthen confidence for future audit re-runs and forensics. But they're not strictly required for mainnet — the inherited D Sui audit chain + code review covers the mechanical behavior.

If user wants strict adherence to "skip all fixes" → all 3 stay as RAW/DECLINED, mainnet proceeds as-is. Source unchanged.

If user wants to apply just the cheapest highest-value subset → L-02 + L-04 (the two test additions, ~50 lines, zero source risk). L-03 trivial too.

If user wants comprehensive → all 3 applied + reconcile I1-I2 doc drift + I7 WARNING (3) cosmetic.

**Awaiting user instruction.**

## Status

- **Source-of-D.move logic:** UNCHANGED from pre-audit submission (Claude fixes are test-only + Move.toml dep pinning).
- **D.move test_only additions:** `test_route_fee_real`, `test_last_sp_donated`, `test_sp_donated_count` (3 helpers, no production-path effect).
- **D_tests.move:** 32 tests (was 30). New: `test_route_fee_keyed_path_real`, `test_donate_to_sp_emits_donor`. Replaced: `test_route_fee_cliff_path_pure_donation` body (now exercises real route_fee_fa).
- **Move.toml:** AptosFramework pinned to commit `e0f33de9783f2ceaa30e5f2b004d3b39812c4f06`.
- **Test result:** 32/32 PASS.
- **R1 phase:** **CLOSED 2026-04-29.** 6 auditors GREEN, all decisions made.
- **Mainnet deploy plan:** prepared at `audit/MAINNET_DEPLOY_PLAN.md`, scripts ready in `deploy-scripts/`. Ready to execute on user GO.
