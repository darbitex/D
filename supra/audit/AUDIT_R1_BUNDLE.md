# D Supra v0.2.0 — External Audit R1 Submission Bundle

**Date:** 2026-04-29
**Submitter:** Rera (rera@darbitex)
**Audit round:** R1 (first external pass for the Supra port)
**Target chain:** Supra mainnet (Supra testnet rehearsal complete, 12/13 entries + 16/16 views verified)
**Bundle composition:** cover letter + scope + 250-line self-audit + 811-line source + 522-line tests + Move.toml + bootstrap script + testnet rehearsal log

## Cover letter

D Supra v0.2.0 is the **Supra L1 port** of D Aptos v0.2.0 (Aptos mainnet `0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77`, sealed via resource-account + destroy_cap).

### D Aptos v0.2.0 audit history (canonical sibling reference)

R1 closed 2026-04-29 with 6 external auditor passes:
- Grok / Kimi / Qwen / DeepSeek / Gemini — **GREEN R1**
- Claude Opus 4.7 fresh — 0 HIGH / 0 MED / 3 LOW (all test-only or build hygiene) — **GREEN**
- Cumulative: 0 HIGH / 0 MED / 4 LOW / 20 INFO. All findings closed. Source-of-D.move logic UNCHANGED.

D Aptos itself ports D Sui v0.2.0 (Sui mainnet `0x898d83f0…`, sealed via `make_immutable`), which had its own R1 pass:
- 5 auditors GREEN R1 + Claude Opus 4.7 fresh found **HIGH-1 truncation decoupling** → fixed in R2 → R2 GREEN.

### ONE Supra v0.4.0 (sibling chain, oracle pattern reference)

Sealed mainnet at `0x2365c948…eafda5c90f` (auth_key=0x0). Used Supra L1 native oracle `supra_oracle_storage::get_price(500)` SUPRA/USDT. Pattern proven on mainnet 2026-04-24. Oracle module address `0xe3948c9e3a24c51c4006ef2acc44606055117d021158f320062df099c4a94150` (mainnet) governed by Supra Foundation, `upgrade_policy = 1` (compatible). USDT-as-USD assumption with documented depeg tail.

### What this submission inherits vs what it changes

D Supra = **D Aptos v0.2.0 design** (10/90 fee split + agnostic donation + truncation guard + cliff orphan redirect + 5 store address composability views + resource-account + destroy_cap sealing) **with the ONE Supra v0.4.0 oracle pattern**, with **6 intentional deltas**:

1. **Oracle**: Pyth Aptos pull-based (`pyth::get_price_no_older_than` + VAA bundle) → Supra L1 push-based (`supra_oracle_storage::get_price(PAIR_ID=500)` SUPRA/USDT). No VAA, no `*_pyth` wrappers (deleted). Time unit seconds → milliseconds.
2. **Constants**: `STALENESS_SECS=60` → `STALENESS_MS=60_000` + `MAX_FUTURE_DRIFT_MS=10_000`. Removed: `APT_USD_PYTH_FEED`, `MAX_CONF_BPS`. Added: `PAIR_ID: u32 = 500`. `MIN_DEBT 10_000_000` (0.1 D) → `1_000_000` (0.01 D) to match SUPRA's smaller-unit economics ($0.0003 vs APT $5).
3. **Error codes**: removed `E_PRICE_EXPO`, `E_PRICE_NEG`, `E_PRICE_UNCERTAIN` (Pyth-specific). Added `E_STALE_FUTURE = 17`. Renumbered: `E_NOT_ORIGIN 17→15`, `E_CAP_GONE 18→16`.
4. **Entries removed**: `*_pyth` quartet (`open_trove_pyth`, `redeem_pyth`, `redeem_from_reserve_pyth`, `liquidate_pyth`). Supra is push-based; users call base entries directly. **Strict ABI subset of D Aptos** — no new entries, only the 4 *_pyth helpers gone.
5. **Move.toml**: `AptosFramework`→`SupraFramework` (`Entropy-Foundation/aptos-core` fork), removed `Pyth = local`, added `core = git("dora-interface", subdir="supra/mainnet/core")`. `origin = "_"` CLI-fillable for testnet/mainnet portability. `upgrade_policy = "compatible"` (forced by dep policy chain — `feedback_aptos_dep_policy_chain.md`).
6. **WARNING text**: clauses (1)-(7) verbatim with rename APT→SUPRA, Aptos→Supra, Pyth→Supra oracle. Clause (6) Pyth pull-based → Supra push-based. Clause (8) ORACLE DEPENDENCY rewritten for Supra: oracle pkg `upgrade_policy=1` (compatible, NOT cryptographically immutable like Pyth Aptos), pair 500 in "Under Supervision" tier (3-5 sources). **NEW clause (10) USDT-DENOMINATED PEG TAIL**: D peg target = USDT (not USD); under USDT depeg events D's effective USD peg drifts proportionally; pair 500 chosen over `get_derived_price` for immutable simplicity, accepting ~50bps long-tail USDT risk.

Field rename: `Registry.apt_metadata` → `supra_metadata` (cosmetic, all readers updated, no semantic effect).

### Audit scope

**Your task:** review the **6 deltas above** for correctness on Supra L1.

The V1 inheritance, V2 design, and 5-store composability surface inherit D Aptos R1 GREEN (6 auditors) + D Sui R1+R2 GREEN (6 auditors) — **do NOT re-audit those at the algebraic level**. The 13 entries' control flow + struct shapes + `route_fee_fa` math + `liquidate` math + `sp_settle` math + `truncation guard` are byte-identical to D Aptos modulo the `apt_metadata→supra_metadata` field rename and removal of *_pyth wrappers.

Focus your effort on:

1. **Oracle replacement correctness.** New `price_8dec()` body reads Supra oracle (push-based) instead of Pyth (pull-based). Verify: (a) tuple destructure `let (v, d, ts_ms, _round) = supra_oracle_storage::get_price(PAIR_ID)` matches Supra ABI, (b) staleness check semantics — `now_ms = timestamp::now_seconds() * 1000` then `now_ms <= ts_ms + STALENESS_MS` — bound math correct (no overflow at u64 chain time), (c) future-drift clause `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS` correctly rejects future timestamps within 10s tolerance, (d) decimal normalization `if (dec >= 8) v / pow10(dec - 8) else v * pow10(8 - dec)` correct for Supra's `decimal: u16` (positive only, vs Pyth's signed expo), (e) abort on `v == 0` and on `result == 0`.

2. **`*_pyth` wrapper deletion safety.** D Aptos had 4 entry wrappers that bundled VAA updates. D Supra has these strictly deleted (Supra is push-based, no caller-side feed update needed). Verify: (a) no orphan call sites in tests or scripts referencing the deleted wrappers, (b) base entries (`open_trove`, `redeem`, `redeem_from_reserve`, `liquidate`) work standalone on Supra without prior price-feed update tx, (c) frontends/integrators have a clean migration story (just stop bundling VAAs, call base entries directly).

3. **MIN_DEBT lowering 0.1 → 0.01 D.** Verify: (a) no overflow in fee/coll math at this lower scale (1% fee = 10_000 raw at MIN_DEBT; pre-existing math handles this), (b) the original D Aptos rationale (fee-cascade trap at debt==MIN_DEBT) still applies but at 0.01 D scale rescuer needs only ~$0.0001 worth of D — trivial, (c) MIN_DEBT enforced at all 4 sites: `open_impl:280`, `redeem_impl:339`, `redeem_impl:352` (post-condition), `redeem_from_reserve:389`.

4. **WARNING (10) USDT-tail accuracy.** Verify: (a) text accurately reflects design choice (pair 500 = SUPRA/USDT direct, not USD-derived), (b) historical reference May 2022 USDT $0.95 depeg correct, (c) "no fallback" claim correct (`get_derived_price` not used; if USDT depegs, D peg moves with it), (d) magnitude estimate "<5%" historically defensible.

5. **No regression vs D Aptos R1 GREEN.** Especially: (a) cliff `product_factor` freeze (`MIN_P_THRESHOLD=1e9`), (b) u64 saturation in `sp_settle`, (c) HIGH-1 truncation guard at `D.move:417` (line moved due to deletes; verify it's still `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)`), (d) cliff orphan redirect at liquidate, (e) reset-on-empty in `sp_deposit`, (f) self-redemption allowed (clause 5), (g) 5 store-address views all distinct + stable, (h) close_cost view, trove_health view, sp_pool_balance view.

6. **Sealing equivalence.** Resource-account + destroy_cap pattern from D Aptos ports identically to Supra (Supra fork = Aptos same `0x1::resource_account` + `0x1::account` modules). After `destroy_cap`: `ResourceCap` resource removed, `Option<SignerCap>` consumed and dropped, `is_sealed()=true`. No actor can reconstruct a signer for `@D` ⇒ no actor can call `0x1::code::publish_package_txn` against `@D`. Verify the assertion that the runtime sealing is equivalent (NOT package-policy-level) since `Move.toml upgrade_policy="compatible"` (forced by dep policy chain).

7. **Supra-specific gotchas.** `transferSupraCoin` SDK + `0x1::supra_account::transfer` route via FA (paired-FA), not raw Coin. Verify there's no logical impact on D's accounting: D's collateral path (`primary_fungible_store::withdraw(user, supra_metadata, amt)` in `open_trove`) reads from FA primary store regardless of Coin/FA origin. Standard Aptos FA framework semantics.

## V2 diff summary (vs D Aptos)

### Modified

| Symbol | D Aptos | D Supra |
|---|---|---|
| `price_8dec` body | Pyth pull-based (4 reads, 6 asserts incl. expo sign + conf cap) | Supra push-based (4 reads, 6 asserts; no expo sign — Supra `decimal: u16` unsigned; no conf — Supra returns single aggregated value) |
| `STALENESS_SECS` constant (`60`) | seconds-based | renamed `STALENESS_MS` (`60_000`) + new `MAX_FUTURE_DRIFT_MS` (`10_000`) |
| `MIN_DEBT` constant | `10_000_000` (0.1 D) | `1_000_000` (0.01 D) |
| `Registry.apt_metadata` field | `apt_metadata: Object<Metadata>` | `supra_metadata: Object<Metadata>` (cosmetic rename, 4 readers updated) |
| WARNING clauses (6), (8), (9) | Pyth/APT/Aptos lexicon | Supra/SUPRA/Supra-oracle lexicon |
| WARNING — new clause (10) | absent | USDT-DENOMINATED PEG TAIL (~50bps long-tail risk disclosure) |
| Module path imports | `aptos_framework::*` + `pyth::*` | `supra_framework::*` + `supra_oracle::supra_oracle_storage` |
| Error code numbering | `E_PRICE_EXPO=15, E_PRICE_NEG=16, E_NOT_ORIGIN=17, E_CAP_GONE=18, E_PRICE_UNCERTAIN=19` | `E_NOT_ORIGIN=15, E_CAP_GONE=16, E_STALE_FUTURE=17` (renumbered + dropped 3, added 1) |

### Removed

| Symbol | Reason |
|---|---|
| `open_trove_pyth` entry | Supra push-based, no VAA bundle needed |
| `redeem_pyth` entry | Same |
| `redeem_from_reserve_pyth` entry | Same |
| `liquidate_pyth` entry | Same |
| `APT_USD_PYTH_FEED: vector<u8>` const | Pyth-specific feed identifier |
| `MAX_CONF_BPS: u64` const | Pyth-specific conf cap (Supra exposes none) |
| `E_PRICE_EXPO`, `E_PRICE_NEG`, `E_PRICE_UNCERTAIN` errors | Pyth-specific assertions |
| `pyth::*` imports (4 modules) | Pyth dep dropped |

### Added

| Symbol | Purpose |
|---|---|
| `STALENESS_MS: u64 = 60_000` | Supra ts is millis |
| `MAX_FUTURE_DRIFT_MS: u64 = 10_000` | Tolerate validator clock skew |
| `PAIR_ID: u32 = 500` | SUPRA/USDT Supra L1 native oracle pair |
| `SUPRA_FA: address = @0xa` | Supra native FA (renamed from `APT_FA`, same value @0xa) |
| `E_STALE_FUTURE: u64 = 17` | New abort code for future-drift bound |
| WARNING clause (10) | USDT-tail risk disclosure |
| `supra_oracle::supra_oracle_storage` import | Supra oracle storage module |

### Renamed (semantic-equivalent)

`apt_metadata`→`supra_metadata` field. Comments + WARNING text rewrites APT→SUPRA, Pyth→Supra oracle, Aptos→Supra. Zero semantic effect — identical math, identical control flow, identical struct shape.

## Build status

```
$ cd /home/rera/d/supra
$ aptos move compile --named-addresses D=0x12...,origin=0x12... --skip-fetch-latest-git-deps
[only ///-comment warnings, cosmetic — same as D Aptos which sealed cleanly]
{ "Result": "Success" }

$ aptos move test --named-addresses D=0x12... --skip-fetch-latest-git-deps
32/32 PASS
```

Test coverage: same 32 tests as D Aptos R1 (after L-02/L-04 applied), with mechanical sed-style renames (`aptos_framework→supra_framework`, `MOCK_APT_HOST→MOCK_SUPRA_HOST`, `apt_md→supra_md`, `b"APT"→b"SUPRA"`, `b"Aptos Coin"→b"Supra Coin"`, `b"Pyth Network"→b"Supra"`) plus 3 abort-code patches:
- `test_destroy_cap_non_origin_aborts`: `abort_code = 17` → `15` (E_NOT_ORIGIN renumbered)
- `test_destroy_cap_double_call_aborts`: `abort_code = 18` → `16` (E_CAP_GONE renumbered)
- `test_redeem_below_min_debt_aborts`: input `9_900_000` → `900_000` (because old MIN_DEBT was 10M, new is 1M; need value strictly < 1M)

All 32 tests pass against the new error codes + new MIN_DEBT scale + Supra framework dep.

## Testnet rehearsal log (Supra TESTNET, full oracle smoke)

Unlike D Aptos testnet (Pyth feed-id mismatch forced oracle-free smoke), **Supra testnet has a working SUPRA/USDT pair 500** at oracle pkg `0x5615001f63d3223f194498787647bb6f8d37b8d1e6773c00dcdd894079e56190`. Full oracle path validated end-to-end. (Move.toml `core` dep subdir flipped to `supra/testnet/core`; will revert to `supra/mainnet/core` for mainnet.)

| Step | Tx hash | Result |
|---|---|---|
| Publish (resource-account, seed=`b"D"`) | `0x3f605f1d9c4e1fa2a0267e65ef4a3f6f847d63eff60a97a36e4532dec5cf13e2` | Pkg at `0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c`, gas 18283 |
| Bootstrap (Coin→FA + open_trove 500 SUPRA / 0.01 D) | `0xe93801b16e54274ad94e8fde679baf100eeb117cd74101af6c4f0debeb29a163` | Trove created, CR 1563.5%, gas 587 |
| W2 open_trove (500 SUPRA / 0.025 D) | `0x30f55fda4c05c5a3f179d3f3a2f7db9e0d18d4938167068c6bddb72d6ddef421` | gas 581 |
| W1 add_collateral (500 SUPRA) | `0xecf64b947836fe8211e518b04ec29f2375c93a3754a2bab2c40681e2708604b6` | gas 15 |
| W2 redeem (0.0202 D, target W1) | `0x4abf80afff7c488b992d0b803cbda5e913c49acdb97bfcdb375b54b377545b60` | gas 25, fee 10/90 split observed |
| W1 sp_deposit (0.02 D) | `0x4386e3f7822d71afcdddc13f9b86ac0328cbffb234762afacd9cea31195994e5` | gas 53, total_sp 0 → 2_000_000 |
| W1 donate_to_sp (0.005 D) | `0xa00f5aa37c16bd2a3435a14bb74e033d8ed8e592794fbd39f42b0db60cf14bf6` | gas 13, sp_pool +500_000, total_sp unchanged ✓ |
| W1 donate_to_reserve (100 SUPRA) | `0xa4ec16951e16894c01cd245c2c7145a10b125ecc12709b87b18ad936188fd185` | gas 14, reserve 0 → 100 SUPRA |
| W1 redeem_from_reserve (0.01 D) | `0x08314789fc6b4e192c92b44ac04f4b8c13e34e727b0aac7c43918643074b0402` | gas 25, reserve 100 → 68.42 SUPRA, total_debt unchanged ✓ |
| W1 redeem self (0.01 D, target W1) | `0x5f3ad4b5494c13423243ecf6f9e2d8ec37253a9aaa4c05b2d4dfdcd7b96af41c` | gas 26, reward_index_d updated (keyed path) |
| W1 sp_claim | `0xfca5cec888bd8fdee2e3140fd1d9371b5ba7d1991aaa9aa7b26e4aa4700dd471` | gas 15, claimed 18000 raw (0.00018 D from fee accumulator) |
| W1 sp_withdraw (0.01 D) | `0xf397517e87a46d7e7a5d48507d06c5e75759c11966e7d4993c69ffd47733ff04` | gas 15, total_sp 2_000_000 → 1_000_000 |
| Funder→W1 D top-up (0.0055 D) | `0xb87dc3fee83f27482f987ec4173fa46e45db916633fb59816cfad0f677383283` | gas 10, covers structural 1% supply gap |
| W1 close_trove | `0xb8239e2ef1f343d2ab4cb28c3593e2e6fe65aa95d4288f33b75eadab47e387eb` | gas 19, trove deleted, full 2404 SUPRA collateral returned |

**Validated end-to-end on Supra testnet:**
- Resource-account publish via `0x1::resource_account::create_resource_account_and_publish_package` (D's `init_module` retrieves SignerCap from `@origin = creator`)
- Move.toml `D = "_"` + `origin = "_"` substitution path (CLI fills both at compile time)
- Real Supra oracle integration — `get_price(500)` returns `(312700000000000, 18, ms_ts, round)`, normalized to 8-dec `31270` (= $0.0003127 USDT/SUPRA)
- Staleness window 60s — 0 reverts during ~25 sequential txs over ~10 min span
- 12 of 13 oracle/state-mutation entries (publish, open_trove×3, add_collateral, redeem×2, redeem_from_reserve, sp_deposit, donate_to_sp, donate_to_reserve, sp_claim, sp_withdraw, close_trove)
- 16 of 16 view fns (`metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`, `treasury_addr`, `read_warning`, `price`, `totals`, `trove_of`, `sp_of`, `close_cost`, `trove_health`, `reserve_balance`, `sp_pool_balance`, `is_sealed`)
- All V2 invariants exercised:
  - 10/90 fee split (10% donation → sp_pool, 90% via reward_index_d to keyed)
  - Cliff path (`total_sp == 0` routes 100% to sp_pool donation cumulative)
  - Keyed reward distribution (W1 received 0.00018 D from 2 fee cycles after sp_deposit)
  - `redeem_from_reserve` does NOT decrement `total_debt` (verified: total_debt stable through operation)
  - `add_collateral` oracle-free (works without VAA push, no oracle call in path)
  - `donate_to_sp` + `donate_to_reserve` oracle-free
  - MIN_DEBT 0.01 D enforced (E_AMOUNT abort verified for input < 1_000_000)
- Sealing flow verified: ResourceCap exists pre-destroy_cap, view `is_sealed()` returns false; mainnet flow will exercise destroy_cap.
- Cross-wallet D top-up + close_trove: verified the structural 1% supply-vs-debt gap (clause 4 of WARNING) plays out as documented — debtor needs external D source for the 1% deficit; close_trove logic itself is correct (FA withdraw aborts in `0x1::fungible_asset` only when balance insufficient, NOT in D logic).

**Not validated on testnet (deferred to mainnet smoke):**
- `liquidate` — requires CR < 150% which can't be reproduced on testnet without oracle manipulation. Math is unit-tested + identical to D Aptos sealed mainnet. Confidence high.
- `destroy_cap` — testnet pkg left with ResourceCap intact for further smoke. Mainnet flow will call destroy_cap as part of multisig sealing sequence.

## Audit goals

Please verify (focused on the 6 deltas + Supra-specific concerns):

1. **Oracle replacement correctness** (price_8dec body rewrite). Compare against ONE Supra v0.4.0 sealed mainnet oracle reader pattern at `/home/rera/one/supra/sources/ONE.move:154-163` (proven). Verify ts unit math, decimal normalization, abort paths.

2. **`*_pyth` wrapper deletion completeness**. Grep source + tests for any orphan reference. Confirm base entries are self-sufficient on Supra (no implicit assumption of prior price feed update).

3. **MIN_DEBT 0.01 D safety**. Lower than D Aptos 0.1 D. At SUPRA $0.0003, 0.01 D ≈ $0.01 USDT debt; CR 200% ⇒ ~50 SUPRA min collateral. No new attack surface (math handles smaller scale; fee at 0.01 D = 10_000 raw, well above zero).

4. **WARNING (10) USDT-tail correctness**. Disclosure accuracy.

5. **No regression vs D Aptos R1 GREEN**. Cross-reference D Aptos R1 findings (none HIGH/MED) — confirm same posture on Supra port.

6. **Sealing equivalence**. resource_account + destroy_cap proven on D Aptos; same module path on Supra fork (`0x1::resource_account`); confirm seam holds.

7. **Supra dep policy chain**. Move.toml `upgrade_policy = "compatible"` is forced by deps (SupraFramework + dora-interface both compatible). Functional immutability via runtime sealing only. Documented in Move.toml comment.

8. **Pre-mainnet action items** flagged in self-audit:
- I-02: pin `SupraFramework` `rev = "dev"` + `core` `rev = "master"` to commit hashes — **APPLIED 2026-04-29**. Pinned to SupraFramework `306b60776be2ba382e35e327a7812233ae7acb13` + dora-interface `37a9d80bd076a5f4d81163952068bb4e27518d5b`. 32/32 tests PASS post-pin.

## Required response format

```markdown
# Auditor: [name + model + version]
# Round: R1
# Verdict: GREEN / YELLOW / RED

## Findings

### HIGH
- [HIGH-1: brief title] — description, location (file:line), impact, recommendation

### MEDIUM
- ...

### LOW
- ...

### INFO
- ...

## Delta verification (6 ports)
- [ ] price_8dec rewrite correct (Supra ms-ts, dec normalization, abort paths)
- [ ] *_pyth wrappers cleanly removed (no orphans)
- [ ] MIN_DEBT 0.01 D safe (no overflow, fee math intact)
- [ ] WARNING (10) USDT-tail accurate
- [ ] Move.toml deps + named addresses correct
- [ ] Field rename apt_metadata→supra_metadata complete

## Inheritance verification
- [ ] V2 design (10/90, truncation guard, cliff redirect) byte-identical to D Aptos
- [ ] sp_settle saturation, MIN_P_THRESHOLD freeze, reset-on-empty preserved
- [ ] 5 store-address views all distinct + stable

## Supra-specific
- [ ] Resource-account derivation correct on Supra fork
- [ ] supra_oracle::supra_oracle_storage::get_price ABI match
- [ ] Paired-FA Coin/FA semantics — no logical impact on D accounting
- [ ] Move.toml dep policy chain — compatible enforcement correct

## Attack surface delta
- New: USDT depeg sensitivity (clause 10) — magnitude bound + escape paths
- Removed: Pyth conf-band protection (no Supra equivalent) — accept-by-design analysis
- Issues considered: [list any not covered in self-audit]

## Recommendation
- Proceed to mainnet / Apply fixes for X / Reject

## Optional notes
```

---

# Self-Audit R1 (canonical, inlined for self-contained submission)

# D Supra v0.2.0 — R1 Self-Audit

**Auditor:** Claude Opus 4.7
**Date:** 2026-04-29
**Scope:** Source port from D Aptos v0.2.0 (`/home/rera/d/aptos/sources/D.move`, 866 LOC, 6 prior auditor GREEN) to `/home/rera/d/supra/sources/D.move` (811 LOC).
**Method:** Focus on PORT DELTAS only. Inherited logic (struct shape, fee/SP math, liquidation distribution, redemption/close mechanics, settlement) is unchanged from R1 base; not re-audited here.

## Delta surface enumerated

1. Oracle: Pyth Aptos pull-based → Supra L1 push-based (`supra_oracle_storage::get_price(500)`)
2. Time unit: oracle ts seconds → milliseconds
3. Constant changes: `STALENESS_SECS=60` → `STALENESS_MS=60_000` + `MAX_FUTURE_DRIFT_MS=10_000`
4. Constant change: `MIN_DEBT=10_000_000` (0.1 D) → `1_000_000` (0.01 D)
5. Constants removed: `APT_USD_PYTH_FEED`, `MAX_CONF_BPS`
6. Constants added: `PAIR_ID=500`
7. Error codes removed: `E_PRICE_EXPO=15`, `E_PRICE_NEG=16`, `E_PRICE_UNCERTAIN=19`
8. Error codes renumbered: `E_NOT_ORIGIN 17→15`, `E_CAP_GONE 18→16`, added `E_STALE_FUTURE=17`
9. Entry functions removed: `open_trove_pyth`, `redeem_pyth`, `redeem_from_reserve_pyth`, `liquidate_pyth`
10. Field rename: `Registry.apt_metadata → supra_metadata`
11. Address: `@origin` from Aptos multisig → Supra multisig `0xbefe37923ac…` (or CLI-fillable)
12. Imports: `aptos_framework::* → supra_framework::*`, drop `pyth::*`, add `supra_oracle::supra_oracle_storage`
13. WARNING text: replace clauses (6), (8), (9); add new clause (10) USDT-tail; rename APT→SUPRA, Aptos→Supra, Pyth→Supra oracle throughout
14. Move.toml: `Pyth = { local = "deps/pyth" }` → `core = { git = "...dora-interface", subdir = "supra/{testnet|mainnet}/core" }`; AptosFramework→SupraFramework; remove `pyth` named addr

## 1. ABI surface

### Public entries

| Function | Signature | Notes |
|---|---|---|
| `destroy_cap` | `(caller: &signer)` | unchanged |
| `open_trove` | `(user: &signer, coll_amt: u64, debt: u64)` | unchanged |
| `add_collateral` | `(user: &signer, coll_amt: u64)` | unchanged |
| `close_trove` | `(user: &signer)` | unchanged |
| `redeem` | `(user: &signer, d_amt: u64, target: address)` | unchanged |
| `redeem_from_reserve` | `(user: &signer, d_amt: u64)` | unchanged |
| `liquidate` | `(liquidator: &signer, target: address)` | unchanged |
| `sp_deposit` | `(user: &signer, amt: u64)` | unchanged |
| `donate_to_sp` | `(user: &signer, amt: u64)` | unchanged |
| `donate_to_reserve` | `(user: &signer, amt: u64)` | unchanged |
| `sp_withdraw` | `(user: &signer, amt: u64)` | unchanged |
| `sp_claim` | `(user: &signer)` | unchanged |

**Removed**: `*_pyth` quartet (4 entries). No replacement needed — Supra is push-based, base entries call `price_8dec()` directly.

### Public views (12 unchanged)

`read_warning`, `metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`, `treasury_addr`, `price`, `trove_of`, `sp_of`, `totals`, `reserve_balance`, `sp_pool_balance`, `is_sealed`, `close_cost`, `trove_health`.

**ABI verdict:** ✅ Strict subset of D Aptos ABI. Frontend calling base entries works without modification (just stop calling *_pyth variants and stop bundling VAAs).

## 2. Args validation

Reviewed every `assert!` in the entry path:

| Check | Location | Status |
|---|---|---|
| `debt >= MIN_DEBT` (open) | open_impl | ✓ enforces 0.01 D minimum |
| `coll_usd * 10000 >= MCR_BPS * debt` | open_impl | ✓ 200% MCR enforced via 8-dec price |
| `amt > 0` (sp_deposit, donate_*, sp_withdraw, add_collateral) | various | ✓ no-op rejection |
| `d_amt >= MIN_DEBT` (redeem, redeem_from_reserve) | both | ✓ same floor as open |
| `t.debt == 0 || t.debt >= MIN_DEBT` post-redeem | redeem_impl | ✓ post-condition |
| `t.debt == 0 || t.collateral > 0` post-redeem | redeem_impl | ✓ no zombie troves |
| `coll_usd * 10000 < LIQ_THRESHOLD_BPS * debt` (liq) | liquidate | ✓ 150% threshold gate |
| `pool_before > debt` (liq) | liquidate | ✓ SP must cover debt strictly |
| `total_before == 0 \|\| new_p >= MIN_P_THRESHOLD` (liq) | liquidate | ✓ cliff path skip; keyed path P-cliff |
| `total_before == 0 \|\| total_sp_new > 0` (liq) | liquidate | ✓ truncation guard (R1 HIGH-1) |
| `signer::address_of(caller) == @origin` (destroy_cap) | destroy_cap | ✓ origin-only |
| `exists<ResourceCap>(@D)` (destroy_cap) | destroy_cap | ✓ one-shot guard |

**Args verdict:** ✅ All asserts inherited from D Aptos R1; no new args introduced.

## 3. Math integrity

### 3.1 Oracle math (price_8dec) — CRITICAL DELTA

```move
fun price_8dec(): u128 {
    let (v, d, ts_ms, _round) = supra_oracle_storage::get_price(PAIR_ID);  // (1)
    assert!(v > 0, E_PRICE_ZERO);                                          // (2)
    assert!(ts_ms > 0, E_STALE);                                           // (3)
    let now_ms = timestamp::now_seconds() * 1000;                          // (4)
    assert!(ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS, E_STALE_FUTURE);        // (5)
    assert!(now_ms <= ts_ms + STALENESS_MS, E_STALE);                      // (6)
    let dec = (d as u64);                                                  // (7)
    assert!(dec <= 38, E_EXPO_BOUND);                                      // (8)
    let result = if (dec >= 8) v / pow10(dec - 8) else v * pow10(8 - dec); // (9)
    assert!(result > 0, E_PRICE_ZERO);                                     // (10)
    result
}
```

**Line-by-line:**

(1) `get_price` returns `(u128 v, u16 d, u64 ts_ms, u64 round)`. Pattern lifted from ONE Supra v0.4.0 `/home/rera/one/supra/sources/ONE.move:154-163` (proven mainnet).

(2) `v > 0` rejects zero-price. Supra returns 0 only if pair is absent or feed expired internally; either way unsafe.

(3) `ts_ms > 0` rejects unset feed. Defensive.

(4) `timestamp::now_seconds() * 1000` converts framework time to ms-aligned. **Overflow check**: `u64::MAX / 1000 ≈ 1.84e16 secs`, well above any plausible chain time. Safe.

(5) `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS` rejects future-drift > 10s. Tolerates clock skew in the validator timestamping the feed push. Aborts with `E_STALE_FUTURE=17` (new code).

(6) `now_ms <= ts_ms + STALENESS_MS` rejects reads >60s old. **OVERFLOW CHECK**: `ts_ms + 60_000` — can overflow u64 only if `ts_ms > u64::MAX - 60_000 ≈ 1.84e19`. Implausible (current ms time ~1.78e12). Safe.

(7) `dec` cast u16 → u64 always lossless.

(8) `dec <= 38` bounds pow10 below u128 overflow point (10^38 = u128 max range).

(9) Decimal normalization: at SUPRA $0.0004 with dec=18, `v ≈ 4e14`, normalizing to 8 dec means dividing by 10^10. `result ≈ 4e4`. Result fits u128 trivially.
   - Edge: `dec=8` → result = v unchanged
   - Edge: `dec=0` → result = v * 10^8
   - Edge: `dec=38` → result = v / 10^30. If v < 10^30, result == 0, caught by (10).

(10) `result > 0` final guard against degenerate normalization.

**Comparison with D Aptos `price_8dec`:**

D Aptos asserts: `i64::get_is_negative(&e_i64)` (Pyth expo always negative), `abs_e <= 18`, `!i64::get_is_negative(&p_i64)` (positive price), `(conf * 10000) <= MAX_CONF_BPS * raw` (Pyth conf cap).

D Supra **drops** the conf cap because Supra returns a single pre-aggregated value (no confidence interval exposed). This is a **looser** safety property than Pyth's conf-bounded reads.

**FINDING L-01 (LOW)**: D Supra has no protection against wide-spread oracle readings. If Supra Foundation's median aggregator behaves erratically (e.g., 20% deviation from true market under thin-source conditions), D will accept the value. Mitigation: pair_id 500 is a well-watched pair; "Under Supervision" tier means 3-5 sources. WARNING clause (8) discloses this risk explicitly. **No code change recommended** — adding a custom band check would require hardcoded bounds that are themselves sensitive to long-term price moves and immutable. Accept by design.

**FINDING I-01 (INFO)**: Supra `decimal: u16` is unsigned, so `dec <= 38` plus `result > 0` is sufficient. The Pyth-specific assertions (negative-expo, positive-price) are correctly omitted as not applicable.

### 3.2 Trove + SP + liq math — UNCHANGED

`open_impl`, `redeem_impl`, `liquidate`, `sp_settle`, `route_fee_fa` byte-identical to D Aptos modulo field rename `apt_metadata→supra_metadata`. Inherits 6-auditor R1 GREEN.

### 3.3 MIN_DEBT change

D Aptos: `10_000_000` (0.1 D). D Supra: `1_000_000` (0.01 D).

Implications:
- Lower entry barrier — more trove dust possible
- Fee-cascade trap edge: at debt = MIN_DEBT, attempting partial redeem against this trove leaves residual debt < MIN_DEBT, aborting with `E_DEBT_MIN`. User must redeem the FULL debt (close-equivalent) or leave alone. **Mitigation**: redeem_impl post-condition enforces `t.debt == 0 || t.debt >= MIN_DEBT`. Same constraint as D Aptos. Just at a different absolute scale.
- MIN_DEBT enforced at:
  - open: ✓
  - redeem (input): ✓
  - redeem (post): ✓
  - redeem_from_reserve (input): ✓

**Verdict:** No new attack surface. Lower MIN_DEBT just shifts the dust threshold proportionally.

## 4. Reentrancy

Move's resource semantics + lack of dynamic dispatch eliminates classical reentrancy. Cross-module calls only into:
- `supra_oracle_storage::get_price` — view-only, returns tuple, no state mutation in oracle ↔ D direction
- `primary_fungible_store::*` — Aptos framework, audited
- `fungible_asset::*` — Aptos framework, audited
- `smart_table::*` — Aptos framework, audited
- `event::emit` — pure side-effect

**No external code is given a callback path into D state.** All mutations on `Registry` happen between `borrow_global_mut` and the function return; Move's borrow checker guarantees no aliasing within that window.

**Reentrancy verdict:** ✅ Same posture as D Aptos. No new external interactions.

## 5. Edges

### 5.1 Oracle freeze

If `get_price(500)` aborts (pair removed/decommissioned), every oracle-consuming entry aborts. Escape hatches (close_trove, add_collateral, sp_deposit, sp_withdraw, donate_*, sp_claim) remain. `redeem_from_reserve` becomes blocked → reserve_coll permanently locked. Documented in WARNING clause (8). **Same as D Aptos behavior under Pyth freeze.**

### 5.2 USDT depeg

pair 500 reports SUPRA/USDT directly. If USDT trades $0.95, oracle returns SUPRA value in 0.95-USD-equivalent units. D treats this as $1.00. Effective peg drift ~5%. Documented in WARNING clause (10). **Accept by design; no fallback in immutable code.**

### 5.3 Stale-but-not-future ts edge

- If `ts_ms` is exactly equal to `now_ms - STALENESS_MS`: passes (assertion is `<=`). Correct boundary semantics.
- If `ts_ms == now_ms`: passes both assertions trivially.
- If `ts_ms == now_ms + MAX_FUTURE_DRIFT_MS`: passes future-drift check.

### 5.4 Bootstrap trove edge

Bootstrap = 500 SUPRA → 0.01 D. CR @ SUPRA $0.0004: `(500 * 0.0004) / 0.01 = $0.20 / $0.01 = 20.0x = 2000% bps`. **Well above 200% MCR**. ✓ (Validated on testnet at oracle price $0.0003127.)

### 5.5 sp_pool donation absorption during cliff

During `total_sp == 0`, route_fee_fa redirects 90% portion to sp_pool as donation. Cliff path skip in liquidate accepts arbitrary p drop. Same as D Aptos. Accumulated donations absorb future small liquidations.

### 5.6 Self-redeem (target == caller)

Allowed by design (clause 5). Behaves as partial debt repay + collateral withdraw with 1% fee. Inherits D Aptos behavior. **Validated on testnet** (W1 self-redeem 0.01 D successful).

## 6. Interactions

### 6.1 Supra oracle dep

- Module: `supra_oracle::supra_oracle_storage` at `0xe3948c9e3a24c51c4006ef2acc44606055117d021158f320062df099c4a94150` (mainnet) / `0x5615001f63d3223f194498787647bb6f8d37b8d1e6773c00dcdd894079e56190` (testnet)
- Function read: `get_price(u32) -> (u128, u16, u64, u64)`
- Pkg upgrade_policy: 1 (compatible, NOT immutable). Supra Foundation can upgrade silently.
- Tier: pair 500 = "Under Supervision" (3-5 sources)
- **All risks disclosed in WARNING clause (8). No code mitigation possible in immutable.**

### 6.2 SUPRA FA at @0xa

Native SUPRA fungible asset metadata at `0xa`. Same address as APT FA on Aptos (Move framework convention). Verified live during ONE Supra v0.4.0 deploy + D Supra testnet smoke.

### 6.3 SupraFramework dep

- Source `git://Entropy-Foundation/aptos-core.git` `subdir aptos-move/framework/supra-framework` `rev dev`
- **FINDING I-02 (INFO)**: `rev = "dev"` is not pinned to a commit hash. ONE Supra v0.4.0 used same. Risk: framework upgrade between local compile and mainnet publish could introduce subtle ABI drift.
- **Recommend**: pin `rev` to a specific commit before mainnet publish (per `feedback_third_party_move_dep_crosscheck.md`).

### 6.4 dora-interface dep

`git://Entropy-Foundation/dora-interface.git` `subdir supra/{testnet|mainnet}/core` `rev master`. Same pinning concern as 6.3.

## 7. Errors

### 7.1 Renumbering safety

D Supra error codes:
```
E_COLLATERAL=1
E_TROVE=2
E_DEBT_MIN=3
E_STALE=4
E_SP_BAL=5
E_AMOUNT=6
E_TARGET=7
E_HEALTHY=8
E_SP_INSUFFICIENT=9
E_INSUFFICIENT_RESERVE=10
E_PRICE_ZERO=11
E_EXPO_BOUND=12
E_DECIMAL_OVERFLOW=13
E_P_CLIFF=14
E_NOT_ORIGIN=15  (was 17 in D Aptos)
E_CAP_GONE=16    (was 18 in D Aptos)
E_STALE_FUTURE=17 (new)
```

Removed: `E_PRICE_EXPO=15`, `E_PRICE_NEG=16`, `E_PRICE_UNCERTAIN=19` (Pyth-specific).

**FINDING I-03 (INFO)**: Tools/indexers/frontends parsing abort codes from D Aptos must be re-keyed for D Supra. Backwards incompatibility between sibling chains is acceptable since D Supra is a separate package, not an upgrade of D Aptos.

### 7.2 Test coverage of error paths

`D_tests.move` updated with new code numbers (15, 16) for destroy_cap tests. `E_AMOUNT=6` test still asserted for redeem-below-min via 900_000 raw input. **32/32 PASS verifies error wiring.**

## 8. Events

12 event types unchanged from D Aptos:
- `TroveOpened`, `CollateralAdded`, `TroveClosed`, `Redeemed`, `Liquidated`, `SPDeposited`, `SPDonated`, `ReserveDonated`, `SPWithdrew`, `SPClaimed`, `ReserveRedeemed`, `CapDestroyed`, `RewardSaturated`

**FINDING I-04 (INFO)**: Event field types and names are identical between D Aptos and D Supra. Indexer schema can be reused with just the package address swap.

## Findings summary

| ID | Severity | Title | Status |
|---|---|---|---|
| L-01 | LOW | No oracle confidence-band check (Supra exposes none) | ACCEPTED — disclosed in WARNING (8); code mitigation impossible in immutable |
| I-01 | INFO | Pyth-specific asserts correctly omitted | NOTED |
| I-02 | INFO | SupraFramework + dora-interface deps `rev` unpinned | **PRE-MAINNET ACTION**: pin to commit hashes |
| I-03 | INFO | Error codes renumbered between D Aptos and D Supra | DOCUMENTED |
| I-04 | INFO | Event schema identical to D Aptos | NOTED |

**No HIGH, MEDIUM, or LOW findings require source-code changes before testnet deploy.**

**Pre-mainnet action item**: pin SupraFramework + dora-interface dep `rev`s to specific commit hashes (I-02). Not blocking for testnet (already deployed + validated).

## Verdict

🟢 **GREEN — testnet deploy approved + executed; mainnet deploy pending dep-pin + multisig script port.**

D Supra v0.2.0 source is a faithful port of D Aptos v0.2.0 with:
- All structural logic byte-identical (modulo field rename)
- Oracle replacement validated against ONE Supra v0.4.0 mainnet pattern
- Compile + 32/32 tests + 12/13 testnet entry smoke + 16/16 view smoke green
- All porting deltas reviewed and either accept-by-design or documented

---

# Source attachments (paths, not inlined)

- **Source:** `/home/rera/d/supra/sources/D.move` (811 LOC)
- **Tests:** `/home/rera/d/supra/tests/D_tests.move` (522 LOC, 32/32 PASS)
- **Move.toml:** `/home/rera/d/supra/Move.toml` (testnet variant currently; will revert to mainnet `core` subdir before mainnet)
- **Bootstrap script:** `/home/rera/d/supra/scripts/bootstrap.move` (Coin→FA conversion + open_trove)
- **Migrate helper script:** `/home/rera/d/supra/scripts/migrate_coin_to_fa.move`
- **Port plan doc:** `/home/rera/d/supra/D_SUPRA_PORT_PLAN.md` (line-by-line diff D Aptos → D Supra, multisig + sealing flow)
- **Self-audit (canonical):** `/home/rera/d/supra/audit/R1_SELF_AUDIT.md` (also inlined above)
- **Sibling references:**
  - D Aptos source: `/home/rera/d/aptos/sources/D.move` (mainnet sealed)
  - D Aptos R1 audit bundle: `/home/rera/d/aptos/audit/AUDIT_R1_BUNDLE.md` (6 auditor GREEN)
  - ONE Supra source: `/home/rera/one/supra/sources/ONE.move` (mainnet sealed, oracle pattern reference)
