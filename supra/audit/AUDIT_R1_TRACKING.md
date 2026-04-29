# D Supra v0.2.0 — Audit R1 Tracking

**Status:** R1 **OPEN** 2026-04-29. Awaiting external auditor responses. Self-audit (Claude Opus 4.7) GREEN with 1 LOW (accepted) + 4 INFO. Pre-audit action item I-02 (dep pinning) **APPLIED**.

## Auditor ledger

| Round | Auditor | Verdict | H/M/L/I | File |
|---|---|---|---|---|
| R1 | Grok (xAI) | **GREEN** | 0/0/1/5 | [EXTERNAL_R1_GROK.md](EXTERNAL_R1_GROK.md) |
| R1 | DeepSeek (deepseek-chat) | **GREEN** | 0/0/0/4 | [EXTERNAL_R1_DEEPSEEK.md](EXTERNAL_R1_DEEPSEEK.md) |
| R1 | Qwen3.6 | **GREEN** | 0/0/1/4 | [EXTERNAL_R1_QWEN.md](EXTERNAL_R1_QWEN.md) |
| R1 | Gemini | **GREEN** | 0/0/1/3 | [EXTERNAL_R1_GEMINI.md](EXTERNAL_R1_GEMINI.md) |
| R1 | **Claude Opus 4.7 fresh (web)** | **GREEN-with-caveats** (bundle-only) | 0/0/2/8 | [EXTERNAL_R1_CLAUDE.md](EXTERNAL_R1_CLAUDE.md) |
| R1 | (pending — Kimi) | — | — | — |
| R1 | Claude Opus 4.7 (self) | **GREEN** | 0/0/1/4 | [R1_SELF_AUDIT.md](R1_SELF_AUDIT.md) (inlined in `AUDIT_R1_BUNDLE.md`) |

**Cumulative severity (so far, 5/5 external + self):** 0 HIGH / 0 MEDIUM / **2 LOW** (L-01 oracle conf-band accept-by-design + L-A new from Claude fresh: ms-precision asymmetry in `now_ms`) / 8 INFO (de-duplicated). Claude fresh added 2 substantive observations: **L-A** (`now_seconds() * 1000` quantizes to second precision; principled fix `now_microseconds() / 1000`) and **L-B** (WARNING (10) magnitude wording: May 2022 USDT bottom was ~$0.9485 = 5.15%, slightly exceeding "<5%" claim).

Auditor lineup target: same composition as D Aptos R1 (Grok / Kimi / Qwen / DeepSeek / Gemini / Claude Opus 4.7 fresh) for cross-sibling consistency. D Supra inherits 6-auditor R1 GREEN from D Aptos at the algebraic level — focus is on the 6 port deltas.

## Findings register (de-duplicated)

### HIGH
*(none)*

### MEDIUM
*(none)*

### LOW

| ID | Title | Reporter | Loc | Claim | Tier | Status |
|---|---|---|---|---|---|---|
| **L-01** | No oracle confidence-band check (Supra exposes none) | Claude self + Grok + Qwen + Gemini + Claude fresh (DeepSeek elevates to INFO) | `D.move price_8dec` | Supra `get_price` returns single aggregated value, no confidence interval. D drops Pyth's `MAX_CONF_BPS=200` check. Looser safety property than D Aptos. | Tier-3 (accept by design) | **ACCEPTED** — disclosed in WARNING (8); pair 500 is 3-5 source "Under Supervision" tier; code mitigation impossible in immutable. **All 6 auditors agree no source change**. |
| **L-A** | `now_ms = timestamp::now_seconds() * 1000` quantizes to second precision (asymmetric staleness window) | Claude Opus 4.7 fresh | `D.move price_8dec` line (4) | `now_ms` lags real chain time 0–999 ms. Net: 61s effective staleness (1s permissive); ~9s effective future-drift (1s restrictive). **Not exploitable** at 200% MCR / 150% liq with 600-900ms finality. Principled fix: `timestamp::now_microseconds() / 1000`. | Tier-2 (cosmetic, pre-mainnet candidate) | **Pending user decision** — applies vs ONE Supra v0.4.0 sibling pattern (which used `now_seconds() * 1000` and is mainnet sealed). |
| **L-B** | WARNING (10) "<5%" understates worst-case USDT depeg (May 2022 bottom = $0.9485 = 5.15%) | Claude Opus 4.7 fresh | `D.move WARNING` clause 10 | Magnitude wording slightly imprecise; recommendation: "approximately 5%, with brief excursions slightly beyond" or "up to ~5%". | Tier-2 (cosmetic wording) | **Pending user decision** — single-string fix in WARNING constant. |

### INFO

| ID | Title | Reporter(s) | Loc | Status |
|---|---|---|---|---|
| **I-01** | Pyth-specific asserts correctly omitted (negative-expo, positive-price) | Claude self + Grok + DeepSeek + Qwen | `D.move price_8dec` | NOTED — Supra `decimal: u16` is unsigned, so the dropped Pyth assertions are not applicable; `dec <= 38` + `result > 0` sufficient. |
| **I-02** | `SupraFramework` rev = "dev" + `dora-interface` rev = "master" (moving branches) | Claude self + Grok + DeepSeek + Qwen + Gemini | `Move.toml` | **APPLIED 2026-04-29**: SupraFramework pinned to `306b60776be2ba382e35e327a7812233ae7acb13`, dora-interface pinned to `37a9d80bd076a5f4d81163952068bb4e27518d5b`. 32/32 tests still PASS post-pin. Gemini explicitly verified from bundle notes. |
| **I-03** | Error codes renumbered between D Aptos and D Supra | Claude self + Grok + DeepSeek + Qwen + Gemini | `D.move` | DOCUMENTED — backwards incompatibility between sibling chains is acceptable since D Supra is separate package not an upgrade. Indexer/frontend re-keying required. |
| **I-04** | Event schema identical to D Aptos / cosmetic field rename complete | Claude self + Grok + DeepSeek + Qwen | `D.move` events + Registry | NOTED — indexer schema reusable with just package address swap. `apt_metadata`→`supra_metadata` rename has no semantic impact (4 readers updated). |
| **I-05** | USDT-denominated peg tail risk correctly disclosed (WARNING clause 10 accuracy) | Grok | `D.move WARNING` | NOTED — Grok confirms historical reference (May 2022 USDT $0.95 depeg) factual, magnitude estimate (<5% historically, ~50bps long-tail) reasonable, "no fallback" correct, design choice (pair 500 direct vs derived) defensible. |
| **I-06** | 10s `MAX_FUTURE_DRIFT_MS` tolerance characterization | Gemini | `D.move price_8dec` | NOTED — generous for L1 clock skew but perfectly safe; prevents aggressive timestamp spoofing while resilient to minor desyncs. |
| **I-07** | Functional immutability via runtime sealing only (single-mechanism vs D Aptos double-mechanism) | Claude fresh | `Move.toml` + `D.move` | NOTED — D Aptos achieved double-immutability (destroy_cap + Move.toml `immutable`); D Supra only has runtime destroy_cap because deps force `compatible`. Argument is sound (no signer for @D post-destroy_cap = no path through `code::publish_package_txn`), but worth post-mainnet `is_sealed()` verification. |
| **I-08** | Error code 17 collision with D Aptos (E_NOT_ORIGIN vs E_STALE_FUTURE) | Claude fresh | `D.move` errors | NOTED — risk of cross-chain indexer/frontend confusion. Recommend per-chain error map file. Forward-looking suggestion: gap error codes by 100 between siblings for future ports. |
| **I-09** | `_round` from `get_price` intentionally ignored | Claude fresh | `D.move price_8dec` | NOTED — same as ONE Supra v0.4.0 mainnet pattern. Round monotonicity could provide independent freshness signal but adds state-mutation cost. ts_ms covers freshness role. |
| **I-10** | Oracle-output overflow path produces arithmetic abort (not E_PRICE_ZERO) | Claude fresh | `D.move price_8dec` line 9 | NOTED — `(v=u128::MAX, dec=0)` would overflow `v * pow10(8)` and trigger Move arithmetic abort. Tx aborts safely (no fund loss); liveness/UX issue, not safety. |
| **I-11** | `pow10` helper edge-case test coverage (dec=38 max bound, dec=0 multiply path) | Claude fresh | `D.move pow10` | NOTED — testnet exercises dec=18 (SUPRA pair). Explicit dec=0 + dec=38 coverage would be reassuring; existing `assert!(n <= 38, E_DECIMAL_OVERFLOW)` provides bound check. |
| **I-12** | `test_redeem_below_min_debt_aborts` asserts E_AMOUNT not E_DEBT_MIN | Claude fresh | tests + source | NOTED — verified: source `redeem_impl` asserts `assert!(d_amt >= MIN_DEBT, E_AMOUNT)`. Test/source agree numerically (code 6). Inherited from D Aptos. Semantic-clarity mislabeling (E_DEBT_MIN exists at code 3 but redeem path uses E_AMOUNT for below-min-debt). Not a bug; future cleanup candidate. |

## Pending user decisions

Two new substantive findings from Claude Opus 4.7 fresh (web session, bundle-only audit). Both Tier-2 cosmetic, not blocking testnet:

**L-A — Replace `now_seconds() * 1000` with `now_microseconds() / 1000` in `price_8dec`.**
- **Cost:** 1 line in D.move. Re-test 32/32.
- **Risk:** None functional. Diverges from ONE Supra v0.4.0 sealed mainnet pattern (which used the same `now_seconds() * 1000`).
- **Benefit:** Recovers ms precision in staleness/future-drift checks (asymmetric drift up to 1s eliminated).
- **Trade-off:** correctness ↑ vs sibling-pattern symmetry ↓. Auditor explicit: "Not exploitable", "do not block on this for testnet".
- **Recommend:** Apply (cleaner; ONE Supra v0.4.0 was sealed before this audit refinement was surfaced).

**L-B — Tighten WARNING (10) USDT depeg magnitude wording.**
- **Cost:** Single-string edit in WARNING constant.
- **Risk:** None.
- **Benefit:** Material to integrators; current "<5%" understates May 2022 USDT bottom (~$0.9485 = 5.15%).
- **Recommend:** Apply (trivial, more accurate).

**Combined cost: 2 small edits + 1 retest. Estimated 5 minutes. Both are pre-mainnet quality polish, not blocking.**

## Cross-auditor consensus (target)

Goals to verify across auditors:
- ✓ Oracle replacement correct (price_8dec body)
- ✓ Time unit ms conversion correct
- ✓ Decimal normalization correct for Supra `decimal: u16` unsigned
- ✓ Future-drift bound `MAX_FUTURE_DRIFT_MS` correct
- ✓ `*_pyth` wrapper deletion clean (no orphans)
- ✓ MIN_DEBT 0.01 D scale safe (no overflow, fee math intact)
- ✓ WARNING (10) USDT-tail accurate
- ✓ Move.toml deps + named addresses correct
- ✓ Field rename apt_metadata→supra_metadata complete
- ✓ V2 design (10/90 split, truncation guard, cliff redirect) byte-identical to D Aptos
- ✓ 5 store-address views all distinct + stable
- ✓ Resource-account derivation correct on Supra fork
- ✓ Move.toml `compatible` policy enforcement correct (dep policy chain)

## Cross-sibling reference

D Aptos R1 closed 2026-04-29 with 6/6 GREEN. Findings:
- 0 HIGH, 0 MED, 4 LOW (test-only + dep pinning), 20 INFO
- L-02/L-03/L-04 from Claude Opus 4.7 fresh applied (test-only + Move.toml dep pin)
- 5 prior auditor findings declined per user

D Supra port retains identical V2 design + V1 inheritance. The only logic change is the oracle replacement (price_8dec body) — see L-01 + I-01 above.

## Status

- **Source-of-D.move logic:** 768 LOC (deliverable to auditors). 32/32 tests PASS.
- **Self-audit:** GREEN. 1 LOW (accepted), 4 INFO. No pre-audit changes recommended.
- **Testnet rehearsal:** 12/13 entries + 16/16 views verified end-to-end. Source unchanged from submission state.
- **R1 phase:** **OPEN** 2026-04-29. Awaiting auditor responses.
- **Mainnet deploy plan:** prepared at `D_SUPRA_PORT_PLAN.md`, scripts ready in `deploy-scripts/`. Ready to execute on user GO + auditor sign-off + dep pinning.
