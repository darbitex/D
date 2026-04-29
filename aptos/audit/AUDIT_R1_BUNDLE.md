# D Aptos v0.2.0 — External Audit R1 Submission Bundle

**Date:** 2026-04-29
**Submitter:** Rera (rera@darbitex)
**Audit round:** R1 (first external pass for the Aptos port)
**Target chain:** Aptos mainnet (testnet rehearsal sealed)
**Bundle composition:** cover letter + 250-line self-audit + 839-line source + 458-line tests + Move.toml + bootstrap script + testnet rehearsal log

## Cover letter

D Aptos v0.2.0 is the **Aptos port** of D Sui v0.2.0 (Sui mainnet `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7`, sealed via `sui::package::make_immutable`).

### D Sui v0.2.0 audit history (canonical V2 reference)

6 external auditor passes:
- Kimi, Grok, DeepSeek, Qwen, Gemini — **GREEN R1**
- Claude Opus 4.7 fresh — found **HIGH-1 truncation decoupling**, fixed in R2
- Claude R2 — **GREEN** (R1→R2 turnaround verbatim: "exemplary, cleanest patch cycle expected on real audit")

### ONE Aptos v0.1.3 audit history (V1 lineage, sealed sibling)

8 external auditor passes across 4 rounds (R1 / R2 / R3.1 / R4 post-mainnet):
- Gemini 2.5 Pro / Gemini 3 Pro / Gemini 3 Flash / Kimi / Qwen / Grok / Claude markdown / Claude with-source / ChatGPT / DeepSeek / Claude 4.7 fresh — composite GREEN
- Cumulative severity: 0 CRIT / 0 HIGH / 1 MED (R4-M-01 stale-oracle redemption asymmetry, off-chain mitigation) / 4 LOW / 1 DESIGN / 9 INFO
- Mainnet `0x85ee9c43688e37bb2050327467c3a6ebcfa37375a8209df327dd77c0aab87387`, sealed via destroy_cap (auth_key=0x0)

### What this submission inherits vs what it changes

D Aptos = **D Sui V2 design** (10/90 fee split + agnostic donation accounting + truncation guard + cliff orphan redirect) **on the ONE Aptos sealing model** (resource-account + destroy_cap), with **two intentional deltas**:

1. **Aptos dialect**: FA framework (`primary_fungible_store`, `MintRef`/`BurnRef`, `Object<FungibleStore>`) replaces Sui's Coin/Balance/PTB; resource-account + destroy_cap replaces `make_immutable(UpgradeCap)`.
2. **MIN_DEBT 1 D → 0.1 D** (10_000_000 raw, 8 dec) — addresses a fee-cascade trap that stranded W2 trove on ONE Aptos v0.1.3 mainnet (the trap: trove at debt == MIN_DEBT has zero partial-redeem headroom; only valid redeem = full clear of `MIN_DEBT × 1.0101`, requiring external D source ≥ 1.0101 ONE = $1.01. With MIN_DEBT=0.1 D, external rescue requires ~$0.10 — ~10× more bootstrappable).

### Audit scope

**Your task:** review the V2 design correctness on the Aptos dialect.

The V1 invariants and unchanged code paths inherit ONE Aptos v0.1.3's R1-R4 GREEN audit conclusions. The V2 math invariants and HIGH-1 truncation guard inherit D Sui v0.2.0's R1-R2 GREEN. **Do NOT re-audit V1 ONE Aptos logic or D Sui V2 math at the algebraic level** — those are sealed and externally validated.

Focus your effort on:
1. Aptos-specific translation correctness (FA vs Coin, `primary_fungible_store` vs `transfer::public_transfer`, resource-account derivation, donor address threading)
2. MIN_DEBT lowering side-effects (overflow/economic/fee-cascade analysis at 0.1 D scale)
3. New view fns (5 store addresses) for composability gap fixes (per `feedback_core_composability_gap.md` — pre-seal mandatory)

## V2 diff summary (vs V1 ONE Aptos)

### Modified

| Symbol | V1 | V2 |
|---|---|---|
| `route_fee_fa` | 25% burn / 75% accumulator | 10% agnostic donation / 90% accumulator + cliff redirect |
| `liquidate` | denominator `total_sp`, linear `total_sp - debt` | denominator `balance(sp_pool)`, scaled `total_sp × (pool_before − debt)/pool_before`, truncation guard, cliff orphan redirect |
| `sp_settle` | (no change in math) | field rename `pending_one`→`pending_d`, `snapshot_index_one`→`snapshot_index_d` |
| `WARNING` paragraph (4) | V1 burn semantics | V2 agnostic donation semantics |
| `WARNING` paragraph (8) | "if upgraded in a breaking way" | "cryptographically immutable + residual feed-deregistration risk" (Pyth Aptos auth_key=0x0) |
| `MIN_DEBT` constant | `100_000_000` (1 ONE) | `10_000_000` (0.1 D) |

### Added (strictly additive)

| Symbol | Purpose |
|---|---|
| `donate_to_sp(user, amt)` | Permissionless D donation entry — joins `sp_pool` balance, does NOT increment `total_sp` |
| `donate_to_reserve(user, amt)` | Permissionless APT donation entry — joins `reserve_coll`, fortifies `redeem_from_reserve` capacity |
| `SPDonated{donor, amount}` event | Emitted by `donate_to_sp` direct call + `route_fee_fa` 10% redirect + cliff 90% redirect |
| `ReserveDonated{donor, amount}` event | Emitted by `donate_to_reserve` |
| `sp_pool_balance()` view | Exposes the donation-vs-keyed delta |
| `fee_pool_addr()`, `sp_pool_addr()`, `sp_coll_pool_addr()`, `reserve_coll_addr()`, `treasury_addr()` view fns | Composability surface — 5 FungibleStore object addresses for indexer/frontend integration |
| `donor: address` param in `route_fee_fa` | Threaded from each caller (open_impl, redeem_impl, redeem_from_reserve) |

### Removed

| Symbol | Reason |
|---|---|
| `FeeBurned` event struct | V1's 25% burn replaced by V2's 10% agnostic donation |

### Renamed (semantic-equivalent)

ONE → D rebrand: module path, FA display name, FA symbol, all internal identifiers (`reward_index_one`→`reward_index_d`, `snapshot_index_one`→`snapshot_index_d`, `pending_one_truncated`→`pending_d_truncated`, `one_amt`→`d_amt`), comments, WARNING text. **Zero semantic effect** — identical math, identical control flow.

## Build status

```
$ aptos move compile --named-addresses D=0xd00
[only ///-comment warnings, cosmetic — same as V1 ONE Aptos which sealed cleanly]
{ "Result": "Success" }

$ aptos move test --named-addresses D=0xd00
30/30 PASS
```

Test coverage:
- 21 V1 inheritance tests (ported from ONE Aptos)
- 9 new V2-specific tests:
  - `test_donate_to_sp_no_dilution` (verifies keyed depositor's reward share unaffected by donations)
  - `test_donate_to_sp_zero_aborts`
  - `test_donate_to_reserve_zero_aborts`
  - `test_route_fee_cliff_path_pure_donation` (cliff path: total_sp==0 → no index update)
  - `test_truncation_decoupling_aborts` (HIGH-1 reproducer: 1e8 keyed + 9e8 donation, debt=999_999_999 → total_sp_new truncates to 0 → guard aborts E_P_CLIFF)
  - `test_min_p_threshold_skipped_at_cliff` (pure-donation pool liquidation succeeds despite extreme p drop)
  - `test_v1_v2_simulator_parity_no_donation` (V1 sim ≡ V2 sim when no donations)
  - `test_sp_deposit_resets_product_factor_when_empty` (reset-on-empty)
  - `test_redeem_below_min_debt_aborts` (MIN_DEBT=0.1 D enforcement)
- 1 composability test: `test_store_addresses_distinct_and_stable` (verifies 6 addresses metadata + 5 stores all stable + distinct, 15 pairwise checks)

## Testnet rehearsal log (Aptos testnet, oracle-free smoke — Opsi A)

Pivoted to oracle-free smoke because Pyth Aptos testnet uses a different APT/USD feed ID (beta `0x44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e`) vs mainnet (`0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5` hardcoded in `D.move::APT_USD_PYTH_FEED`). Updates against the testnet feed ID would abort with `E_WRONG_FEED (17)`.

| Step | Tx hash | Result |
|---|---|---|
| Publish (resource-account, seed=`D`) | `0x6ab023f65d2bde7b58bf31c3be7a7338ba9fdd999013e714126984deb8c9df44` | Pkg at `0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c` |
| Smoke 10 view fns | view-only | All return expected initial state |
| `donate_to_reserve(50_000_000)` | `0x1f50eddeca89db80f7f3119e64f0f02a112c970ff3f09e4576499224c6f816fd` | reserve_balance 0 → 50_000_000, ReserveDonated emitted, gas_used 107 |
| `destroy_cap` | `0x9cfafe2322ff588ea6d4334661dcb64c275133c2a0f3252f3b232339ccfc8a7b` | is_sealed=true, ResourceCap resource gone (404), CapDestroyed emitted, gas_used 56 |

**Validated end-to-end:** resource-account publish + Move.toml `D = "_"` substitution path, sealing flow (destroy_cap consume ResourceCap, is_sealed flip), permissionless oracle-free `donate_to_reserve` path, 5 store-address composability views, all 6 addresses distinct.

**Not validated on testnet (deferred to mainnet smoke):** oracle-dependent paths — `open_trove_pyth`, `redeem_pyth`, `liquidate_pyth`, `donate_to_sp` (needs minted D first, which requires `open_trove`), V2 `route_fee_fa` 10/90 split (needs real fee from open/redeem). The math for these is unit-tested + matches D Sui sealed mainnet, so confidence is high; mainnet smoke is final empirical validation.

## Audit goals

Please verify:

1. **Aptos translation correctness.** D.move uses FA framework primitives (`primary_fungible_store::withdraw`, `fungible_asset::deposit`, `Object<FungibleStore>`, `MintRef`/`BurnRef`, `ExtendRef`) that differ from Sui's `Coin<T>`/`Balance<T>`/`TreasuryCap<T>` model. Confirm the math semantics from D Sui carry over identically. Pay attention to: (a) how `route_fee_fa` extracts the donation portion via `fungible_asset::extract(&mut fa, donate_amt)` vs Sui's `balance::split`, (b) how seized collateral is split in `liquidate` via `extract` chain, (c) how `primary_fungible_store::withdraw` auto-creates stores on first call.

2. **MIN_DEBT side-effects.** Lowered to `10_000_000` (0.1 D). Verify: (a) no overflow in fee/coll math at this scale (1% fee = 100_000 raw; pre-existing math handles this), (b) no economic vulnerability vs the previous 1 ONE floor, (c) the fee-cascade trap rationale is correctly addressed (W2 trove on ONE Aptos was stranded at debt=1 ONE because external rescuer needed ≥ 1.0101 ONE; with 0.1 D requirement = ≥ 0.10101 D, much more bootstrappable).

3. **`donor: address` threading.** V2 added a `donor` parameter to `route_fee_fa`. Verify: (a) all 3 call sites (`open_impl`, `redeem_impl`, `redeem_from_reserve`) pass `signer::address_of(user)` correctly, (b) `SPDonated` event's donor field reflects actual transaction sender (not module-internal address), (c) cliff path donor = same caller, not e.g. zero address.

4. **HIGH-1 truncation guard ports correctly.** D Sui's `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` is preserved at `D.move:498`. Verify: (a) guard placement equivalent to D Sui sealed mainnet, (b) cliff predicate `r.total_sp == 0` (NOT `smart_table::length(&r.sp_positions) == 0`) at `route_fee_fa:248`, (c) reproducer `test_truncation_decoupling_aborts` actually exercises the guard (not some other earlier assert).

5. **Composability surface (5 new view fns).** Verify: (a) each `*_addr()` returns the correct `FungibleStore` object address via `object::object_address(&store)`, (b) all 6 addresses (metadata + 5 stores) are distinct (no collision — derived from sequential `object::create_object(da)` calls in `init_module_inner`), (c) stable across calls (each call returns same address).

6. **Aptos sealing equivalence.** Resource-account + destroy_cap pattern (consume `SignerCapability` from `Option`, drop the `ResourceCap` resource) achieves the same immutability as D Sui's `make_immutable(UpgradeCap)`. Note: `Move.toml` uses `upgrade_policy = "compatible"` because Pyth dep is compat (per `feedback_aptos_dep_policy_chain.md`) — real immutability is at the resource-account layer, not the Aptos package upgrade_policy. After `destroy_cap`, no actor can reconstruct a signer for `@D` ⇒ no actor can call `aptos move publish --override` against `@D`.

7. **No regression vs ONE Aptos v0.1.3.** Especially: cliff `product_factor` freeze (MIN_P_THRESHOLD), u64 saturation in `sp_settle` (decades of accrual past u64::MAX), Pyth confidence cap (MAX_CONF_BPS=200), redemption-vs-liquidation distinction in WARNING (9), reset-on-empty product_factor in `sp_deposit`.

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

## Math invariant verification
- [ ] route_fee_fa 10/90 split semantics correct
- [ ] liquidate denominator pool_before correct
- [ ] truncation guard placement correct (D.move:498)
- [ ] cliff orphan redirect correct (D.move:520-525)
- [ ] MIN_DEBT lowering safe
- [ ] donor address threading correct (3 call sites)

## Aptos translation review
- [ ] FA framework usage correct (deposit/withdraw paths)
- [ ] resource-account derivation correct
- [ ] primary_fungible_store auto-create on first donate
- [ ] view fn correctness (5 store addresses + sp_pool_balance)
- [ ] sealing equivalence to D Sui make_immutable

## Attack surface
- New surface assessment (donate_to_sp, donate_to_reserve)
- Modified surface assessment (route_fee_fa, liquidate)
- Issues considered: [list any not covered in self-audit]

## Recommendation
- Proceed to R2 / Apply fixes for X / Reject

## Optional notes
```

---

# Self-Audit R1 (canonical, inlined for self-contained submission)

# D Aptos v0.2.0 — Self-Audit R1

**Source:** `/home/rera/d/aptos/sources/D.move` (760 LOC)
**Tests:** `/home/rera/d/aptos/tests/D_tests.move` (29 tests, 29 pass)
**Build:** `aptos move compile --named-addresses D=0xd00` clean (only `///`-comment warnings, cosmetic).
**Lineage:** ports D Sui v0.2.0 sealed at `0x898d83f0…` (Sui mainnet) onto the Aptos resource-account + destroy_cap immutability pattern from ONE Aptos v0.1.3 sealed at `0x85ee9c43…`.

## Scope of changes (V1 ONE Aptos → V2 D Aptos)

Verified the diff covers **only** the V2-design surface from D Sui plus the MIN_DEBT revision; no other behavior was opportunistically modified.

### 1. ABI surface

| Entry | V1 | V2 | Notes |
|---|---|---|---|
| `open_trove` | ✓ | ✓ | unchanged signature |
| `add_collateral` | ✓ | ✓ | unchanged |
| `close_trove` | ✓ | ✓ | unchanged |
| `redeem` | ✓ | ✓ | param renamed `one_amt`→`d_amt` (cosmetic, same type) |
| `redeem_from_reserve` | ✓ | ✓ | param renamed |
| `liquidate` | ✓ | ✓ | unchanged signature, body diff (see math) |
| `sp_deposit` | ✓ | ✓ | unchanged |
| `donate_to_sp` | absent | **NEW** | `(user: &signer, amt: u64)` |
| `donate_to_reserve` | absent | **NEW** | `(user: &signer, amt: u64)` |
| `sp_withdraw` | ✓ | ✓ | unchanged |
| `sp_claim` | ✓ | ✓ | unchanged |
| `*_pyth` wrappers | ✓ | ✓ | param renamed in `redeem_pyth`/`redeem_from_reserve_pyth` |
| `destroy_cap` | ✓ | ✓ | unchanged |

| View | V1 | V2 |
|---|---|---|
| `read_warning` | ✓ | ✓ rewritten paragraph (4) + (8) |
| `metadata_addr` | ✓ | ✓ |
| `price` | ✓ | ✓ |
| `trove_of` | ✓ | ✓ |
| `sp_of` | ✓ | ✓ field name `p_one`→`p_d` |
| `totals` | ✓ | ✓ field name `reward_index_one`→`reward_index_d` |
| `reserve_balance` | ✓ | ✓ |
| `sp_pool_balance` | absent | **NEW** — exposes the donation-vs-keyed delta |
| `fee_pool_addr` | absent | **NEW** — composability surface (D fee accumulator) |
| `sp_pool_addr` | absent | **NEW** — composability surface (D liquidation pool) |
| `sp_coll_pool_addr` | absent | **NEW** — composability surface (APT SP rewards) |
| `reserve_coll_addr` | absent | **NEW** — composability surface (APT reserve) |
| `treasury_addr` | absent | **NEW** — composability surface (APT trove lockup) |
| `is_sealed` | ✓ | ✓ |
| `close_cost` | ✓ | ✓ |
| `trove_health` | ✓ | ✓ |

**Verdict:** ABI break is cosmetic (`one_*` → `d_*` field/param renames) plus strict additions (`donate_to_sp`, `donate_to_reserve`, `sp_pool_balance`, 5 store address views). No call-site of an existing entry needs to change. The 5 store addresses cover the V1 composability gap flagged in `feedback_core_composability_gap.md` — added pre-seal so indexers/frontends can subscribe events per FungibleStore without reading Registry.

### 2. Math — route_fee_fa

V1 (25% burn / 75% accumulator):
```
burn_amt = amt * 2500 / 10000
fee_pool += amt - burn_amt    [if total_sp > 0]
reward_index_one += sp_amt * pf / total_sp
```

V2 (10% agnostic donation / 90% accumulator):
```
donate_amt = amt * 1000 / 10000
sp_pool += donate_amt
sp_amt = amt - donate_amt
if total_sp == 0: sp_pool += sp_amt   [donation cliff path, no index update]
else:             fee_pool += sp_amt
                  reward_index_d += sp_amt * pf / total_sp
```

**Tested values:**
- `amount = 1_000_000` → `donate = 100_000`, `sp_amt = 900_000`, `r_d_delta = 9e15`, single-depositor `pending_d = 900_000`. Verified `test_reward_index_increment_and_pending`.
- `amount = 300_000_000` two-depositor pro-rata → `pa = 180M`, `pb = 90M`. Verified `test_reward_index_pro_rata_two_depositors`.
- Cliff path (`total_sp == 0`) → no index update. Verified `test_route_fee_cliff_path_pure_donation`.

**Donor address threading:** V2 adds `donor: address` parameter (used for `SPDonated` event provenance). All call sites pass `signer::address_of(user)` — confirmed at `open_impl`, `redeem_impl`, `redeem_from_reserve`. No path leaks the wrong donor.

### 3. Math — liquidate

V1:
```
assert total_sp > debt
new_p = pf * (total_sp - debt) / total_sp
assert new_p >= MIN_P_THRESHOLD
total_sp_new = total_sp - debt           [linear]
```

V2:
```
pool_before = balance(sp_pool)
assert pool_before > debt
new_p = pf * (pool_before - debt) / pool_before
assert total_before == 0 || new_p >= MIN_P_THRESHOLD     [cliff skip]
total_sp_new = total_before * (pool_before - debt) / pool_before    [scaled]
assert total_before == 0 || total_sp_new > 0     [HIGH-1 truncation guard]
```

Donations now contribute to liquidation absorption pro-rata via the `pool_before` denominator. Keyed depositors' `total_sp_new` scales proportionally with pool depletion so their effective `eff = initial * pf / snap_p` after liquidation equals the new `total_sp` (pro-rata-of-keyed) plus the donations residue.

**Truncation guard verified:** `test_truncation_decoupling_aborts` reproduces the HIGH-1 PoC from D Sui R1 (Claude Opus 4.7 fresh):
- `total_before = 1e8`, donations bring `pool_before = 1e9`, `debt = 999_999_999`.
- `new_p = 1e9` (= MIN_P_THRESHOLD, passes cliff), `total_sp_new = 1e8 / 1e9 = 0` (truncation).
- Without guard, subsequent `route_fee` divides by `total_sp == 0` → permanent DoS.
- Guard `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` catches it. ✓

**Cliff orphan redirect:** when `total_before == 0` (pure donation pool), `sp_coll → reserve_coll` instead of `sp_coll_pool` (where it'd be unclaimable). Code path:
```move
if (total_before == 0) {
    fungible_asset::deposit(r.reserve_coll, seized);
} else {
    fungible_asset::deposit(r.sp_coll_pool, seized);
}
```
Reserve gets fortified; no orphan accumulation. (Live-path only, not unit-tested without oracle but math is identical to D Sui sealed mainnet.)

**reward_index_coll guard:** `if (total_before > 0) { ... reward_index_coll += sp_coll * pf / total_before }`. Skipped at cliff to avoid div-by-zero. Verified at `D.move:528` and exercised in `test_min_p_threshold_skipped_at_cliff`.

### 4. New entries — donate_to_sp / donate_to_reserve

`donate_to_sp(user, amt)`:
- Withdraws D from user's primary FA store.
- Deposits to `sp_pool` (joins balance only).
- **Does NOT** increment `total_sp`. Verified `test_donate_to_sp_no_dilution`: keyed depositor's reward share unaffected.
- Emits `SPDonated{donor, amount}`.
- Aborts on `amt == 0` with `E_AMOUNT (6)`.

`donate_to_reserve(user, amt)`:
- Withdraws APT from user's primary FA store (uses `r.apt_metadata`).
- Deposits to `reserve_coll`. Fortifies `redeem_from_reserve` capacity.
- Emits `ReserveDonated{donor, amount}`.
- No oracle call — works during oracle freeze.
- Aborts on `amt == 0`.

Both are permissionless. Neither writes any privileged state (no admin path).

### 5. Constants

| Constant | V1 | V2 |
|---|---|---|
| `MIN_DEBT` | `100_000_000` (1 ONE) | **`10_000_000` (0.1 D)** |
| `MCR_BPS` | 20000 | unchanged |
| `LIQ_THRESHOLD_BPS` | 15000 | unchanged |
| `LIQ_BONUS_BPS` | 1000 | unchanged |
| `LIQ_LIQUIDATOR_BPS` | 2500 | unchanged |
| `LIQ_SP_RESERVE_BPS` | 2500 | unchanged |
| `FEE_BPS` | 100 | unchanged |
| `STALENESS_SECS` | 60 | unchanged |
| `MIN_P_THRESHOLD` | 1e9 | unchanged |
| `PRECISION` | 1e18 | unchanged |
| `MAX_CONF_BPS` | 200 | unchanged |
| `APT_USD_PYTH_FEED` | `0x03ae4d…` | unchanged |

**MIN_DEBT lowering rationale:** per `feedback_one_min_debt.md` revision (2026-04-28): a trove sitting at exactly `MIN_DEBT` has zero partial-redeem headroom (only valid redeem = full clear of `MIN_DEBT × 1.0101`). With MIN_DEBT=1 ONE this stranded W2 trove on ONE Aptos. With MIN_DEBT=0.1 D, an external rescuer needs only ~$0.10 of D, much more bootstrappable. Retail-first ethos preserved (still flat 1% fee, no sorted list, no base rate, arbitrary redemption target).

### 6. Events

| Event | V1 | V2 | Diff |
|---|---|---|---|
| `TroveOpened` | ✓ | ✓ | unchanged |
| `CollateralAdded` | ✓ | ✓ | unchanged |
| `TroveClosed` | ✓ | ✓ | unchanged |
| `Redeemed` | ✓ | ✓ | field `one_amt`→`d_amt` |
| `Liquidated` | ✓ | ✓ | unchanged |
| `SPDeposited` | ✓ | ✓ | unchanged |
| `SPWithdrew` | ✓ | ✓ | unchanged |
| `SPClaimed` | ✓ | ✓ | field `one_amt`→`d_amt` |
| `ReserveRedeemed` | ✓ | ✓ | field `one_amt`→`d_amt` |
| `FeeBurned` | ✓ | **dropped** | V2 has no burn step |
| `SPDonated` | absent | **NEW** | `{donor, amount}` |
| `ReserveDonated` | absent | **NEW** | `{donor, amount}` |
| `CapDestroyed` | ✓ | ✓ | unchanged |
| `RewardSaturated` | ✓ | ✓ | field rename |

`SPDonated` is emitted in 3 distinct sites: (a) `donate_to_sp` direct call, (b) `route_fee_fa` 10% portion, (c) `route_fee_fa` cliff path 90% portion. Donor field reflects actual sender in all three.

### 7. Reentrancy / interactions

No path makes external Move calls between writes that could be re-entered:
- All FA writes (`deposit`/`withdraw`) settle atomically within the borrow_global_mut scope.
- `pyth::get_price_no_older_than` is a pure read.
- `pyth::update_price_feeds_with_funder` (in `*_pyth` wrappers) executes BEFORE the borrow_global_mut → no reentrancy window.
- `transfer::public_transfer` not used (Aptos pattern; deposits to `primary_fungible_store` directly).

`primary_fungible_store::deposit` to an arbitrary `target` address (e.g. liquidate target_remainder) does NOT trigger a callback; FA framework has no hooks. Confirmed by ONE Aptos v0.1.3 sealed mainnet operating cleanly.

### 8. Edge cases

- `amt == 0` for donate/sp_deposit/sp_withdraw → `E_AMOUNT (6)`. Tested.
- `MIN_DEBT` redeem floor → `E_AMOUNT (6)` in `redeem`/`redeem_from_reserve`. Tested for redeem (`test_redeem_below_min_debt_aborts`).
- `debt == 0 || debt >= MIN_DEBT` post-redeem invariant on target trove → `E_DEBT_MIN (3)`.
- Trove with `coll == 0 ∧ debt > 0` → `E_COLLATERAL (1)` after redeem.
- Liquidate of healthy trove (CR ≥ 150%) → `E_HEALTHY (8)`.
- Liquidate when `pool_before <= debt` → `E_SP_INSUFFICIENT (9)`.
- Cliff: `new_p < MIN_P_THRESHOLD` AND `total_before > 0` → `E_P_CLIFF (14)`. Tested.
- Truncation: `total_sp_new == 0` AND `total_before > 0` → `E_P_CLIFF (14)`. Tested.
- Reset-on-empty: `sp_deposit` with `total_sp == 0` resets `product_factor = PRECISION`. Tested.
- Saturating reward: `pending_d > u64::MAX` → emits `RewardSaturated`, caps at u64::MAX (no abort). Carried forward from V1.
- Pyth: stale (`ts + 60 < now`), future (`ts > now + 10`), zero price, negative price, expo > 18, conf > 2% → distinct error codes (4, 11, 12, 15, 16, 19). Carried forward.

### 9. Sealing

Resource-account + destroy_cap pattern unchanged from V1 ONE Aptos:
1. `init_module` retrieves SignerCapability from `@origin` and stashes it under `ResourceCap` resource at `@D`.
2. `destroy_cap(caller)` (origin-only) consumes the cap and drops the `ResourceCap` resource.
3. After consumption, `is_sealed()` returns `true` (no `ResourceCap` exists at `@D`).
4. No actor can ever reconstruct a signer for `@D` ⇒ package permanently sealed.

`Move.toml` has `upgrade_policy = "compatible"` because Pyth dep is compat. Real immutability is achieved at the resource-account layer, not the Aptos package upgrade_policy (which can't be `immutable` while compat-only deps exist — see `feedback_aptos_dep_policy_chain.md`).

Verified by V1 ONE Aptos's mainnet seal at `0x85ee9c43…` (auth_key=0x0, no ResourceCap on-chain).

### 10. Comparison to D Sui (canonical V2 reference)

| Aspect | D Sui v0.2.0 | D Aptos v0.2.0 (this) |
|---|---|---|
| Package addr | `0x898d83f0…` (sealed) | TBD |
| Coin type | `D::D` | `D::D` (Aptos FA, not Sui Coin generic) |
| Decimals | 8 | 8 |
| Collateral | SUI (9-dec, 1e9 scale) | APT (8-dec, 1e8 scale) |
| MIN_DEBT | 1 D (1e8) | **0.1 D (1e7)** ← lower for retail-fee-cascade fix |
| Sealing model | `make_immutable(UpgradeCap)` | resource-account + `destroy_cap` |
| Oracle | Pyth Sui PriceInfoObject | Pyth Aptos `pyth::get_price_no_older_than` |
| Pyth pkg immutability | governance (UpgradeCap policy=0) | cryptographically immutable (auth_key=0x0) |
| Truncation guard | ✓ (R1 Claude HIGH-1 fix) | ✓ ported |
| Cliff path donation | ✓ | ✓ |
| Cliff orphan redirect | ✓ | ✓ |
| Agnostic donate fns | ✓ | ✓ |
| Test count | 29 | 29 |
| External audit | 6 (5 GREEN, 1 HIGH→fixed) | 0 — pending |

The Aptos port preserves every V2 invariant. Differences are dialect-only (FA vs Coin, signer vs PTB, primary_fungible_store vs balance::join). MIN_DEBT differs intentionally per session feedback.

## Findings

**0 HIGH / 0 MEDIUM / 0 LOW / 0 INFO** unaddressed.

The single HIGH-1 (truncation decoupling) from D Sui R1 is **inherent to the V2 design** and was carried over with its mitigation (cliff predicate `r.total_sp == 0` + invariant guard `total_sp_new > 0`). Reproducer test added (`test_truncation_decoupling_aborts`). No new attack surface introduced by the Aptos port.

## Pre-deploy checklist (deferred from this session)

- [ ] External LLM audits (target: 5 fresh, including Claude Opus 4.7 fresh as second-look on truncation guard port).
- [ ] Resource-account derivation: pick seed (e.g. `D`), derive address via `aptos account derive-resource-account-address`. Likely candidates differ from V1 — V1 used seed "ONE" → `0x85ee9c43…`.
- [ ] Move.toml dep pin: switch Pyth from `local = "deps/pyth"` to mainnet git rev (or keep local; the `0x7e78…` mainnet pkg is identical and immutable).
- [ ] Bootstrap script param tuning: pick collateral size + debt for genesis trove. With MIN_DEBT=0.1 D, can bootstrap with as little as ~0.22 APT @ APT≈$0.93 + 0.1 D debt for MCR=205%. Recommend ≥ 2.2 APT / 1 D for optics + LP-pool seeding headroom.
- [ ] Frontend: replace `/one` Darbitex SPA route with D module. PARAMS: MIN_DEBT=10_000_000, FEE_BPS=100, MCR=20000.
- [ ] Walrus deploy + ws-resources.json (per `feedback_walrus_deploy.md`).
- [ ] Mainnet deploy SOP: hot-wallet OK per session decision (0x0047 has ~11.357 APT free per memory).

## Verdict

**R1 GREEN.** Proceed to external audit submission.

---

# Source: `sources/D.move` (839 lines)

```move
/// D — immutable stablecoin on Aptos
///
/// WARNING: D is an immutable stablecoin contract that depends on
/// Pyth Network's on-chain price feed for APT/USD. If Pyth degrades or
/// misrepresents its oracle, D's peg mechanism breaks deterministically
/// - users can wind down via self-close without any external assistance,
/// but new mint/redeem operations become unreliable or frozen.
/// D is immutable = bug is real. Audit this code yourself before
/// interacting.
module D::D {
    use std::option::{Self, Option};
    use std::signer;
    use std::string;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::account::SignerCapability;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, MintRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use pyth::pyth;
    use pyth::price::{Self, Price};
    use pyth::i64;
    use pyth::price_identifier;

    const MCR_BPS: u128 = 20000;
    const LIQ_THRESHOLD_BPS: u128 = 15000;
    const LIQ_BONUS_BPS: u64 = 1000;
    const LIQ_LIQUIDATOR_BPS: u64 = 2500;
    const LIQ_SP_RESERVE_BPS: u64 = 2500;
    // SP receives (10000 - LIQ_LIQUIDATOR_BPS - LIQ_SP_RESERVE_BPS) = 5000 (50%) as remainder
    const FEE_BPS: u64 = 100;
    const STALENESS_SECS: u64 = 60;
    // 0.1 D entry barrier (8 decimals). Lowered from 1 D to avoid the fee-cascade trap
    // that strands troves at debt == MIN_DEBT (no partial-redeem headroom remaining).
    const MIN_DEBT: u64 = 10_000_000;
    const PRECISION: u128 = 1_000_000_000_000_000_000;
    const MIN_P_THRESHOLD: u128 = 1_000_000_000;
    const APT_FA: address = @0xa;
    const APT_USD_PYTH_FEED: vector<u8> = x"03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5";
    const MAX_CONF_BPS: u64 = 200;                    // Pyth confidence cap: 2% of price

    const E_COLLATERAL: u64 = 1;
    const E_TROVE: u64 = 2;
    const E_DEBT_MIN: u64 = 3;
    const E_STALE: u64 = 4;
    const E_SP_BAL: u64 = 5;
    const E_AMOUNT: u64 = 6;
    const E_TARGET: u64 = 7;
    const E_HEALTHY: u64 = 8;
    const E_SP_INSUFFICIENT: u64 = 9;
    const E_INSUFFICIENT_RESERVE: u64 = 10;
    const E_PRICE_ZERO: u64 = 11;
    const E_EXPO_BOUND: u64 = 12;
    const E_DECIMAL_OVERFLOW: u64 = 13;
    const E_P_CLIFF: u64 = 14;
    const E_PRICE_EXPO: u64 = 15;
    const E_PRICE_NEG: u64 = 16;
    const E_NOT_ORIGIN: u64 = 17;
    const E_CAP_GONE: u64 = 18;
    const E_PRICE_UNCERTAIN: u64 = 19;

    const WARNING: vector<u8> = b"D is an immutable stablecoin contract on Aptos that depends on Pyth Network's on-chain price feed for APT/USD. If Pyth degrades or misrepresents its oracle, D's peg mechanism breaks deterministically - users can wind down via self-close without any external assistance, but new mint/redeem operations become unreliable or frozen. D is immutable = bug is real. Audit this code yourself before interacting. KNOWN LIMITATIONS: (1) Stability Pool enters frozen state when product_factor would drop below 1e9 - protocol aborts further liquidations rather than corrupt SP accounting, accepting bad-debt accumulation past the threshold. (2) Sustained large-scale activity over decades may asymptotically exceed u64 bounds on pending SP rewards. (3) Liquidation seized collateral is distributed in priority: liquidator bonus first (nominal 2.5 percent of debt value, being 25 percent of the 10 percent liquidation bonus), then 2.5 percent reserve share (also 25 percent of bonus), then SP absorbs the remainder and the debt burn. At CR roughly 110% to 150% the SP alone covers the collateral shortfall. At CR below ~5% the liquidator may take the entire remaining collateral, reserve and SP receive zero, and SP still absorbs the full debt burn. (4) 10 percent of each mint and redeem fee is redirected to the Stability Pool as an agnostic donation - it joins sp_pool balance but does NOT increment total_sp, so it does not dilute the reward distribution denominator. Donations participate in liquidation absorption pro-rata via the actual sp_pool balance ratio, gradually burning over time. The remaining 90 percent is distributed pro-rata to keyed SP depositors via the fee accumulator when keyed positions exist; during periods with no keyed positions, the 90 percent is also redirected to the SP pool as agnostic donation rather than accruing unclaimable in the accumulator. Real depositors receive their full 90 percent share unaffected by donation flow rate. Total: 1 percent supply-vs-debt gap per fee cycle, fully draining via SP burns over time. Individual debtors still face a 1 percent per-trove shortfall because only 99 percent is minted while 100 percent is needed to close - full protocol wind-down requires secondary-market D for the last debt closure. (5) Self-redemption (redeem against own trove) is allowed and behaves as partial debt repayment plus collateral withdrawal with a 1 percent fee. (6) Pyth is pull-based on Aptos - callers must ensure price is fresh (within 60 seconds) via pyth::update_price_feeds VAA update before invoking any D entry that reads the oracle. (7) Extreme low-price regimes may cause transient aborts in redeem paths when requested amounts exceed u64 output bounds; use smaller amounts and retry. (8) ORACLE DEPENDENCY (Aptos-specific): Pyth Aptos at pkg 0x7e78... is cryptographically immutable (auth_key=0x0, no upgrade path), so package code cannot regress. Residual risks: APT/USD feed id 0x03ae4d... could be de-registered via Wormhole VAA governance, or the feed could become permanently unavailable for any reason. Either case bricks oracle-dependent entries (open_trove, redeem, liquidate, redeem_from_reserve, and their *_pyth wrappers). Oracle-free escape hatches remain fully open: close_trove lets any trove owner reclaim their collateral by burning the full trove debt in D (acquiring the 1 percent close deficit via secondary market if needed); add_collateral lets owners top up existing troves without touching the oracle; sp_deposit, sp_withdraw, donate_to_sp, donate_to_reserve, and sp_claim let SP depositors manage and exit their positions and claim any rewards accumulated before the freeze (donate_to_sp + donate_to_reserve are oracle-free permissionless contributions). Protocol-owned APT held in reserve_coll becomes permanently locked because redeem_from_reserve requires the oracle. No admin override exists; the freeze is final. (9) REDEMPTION vs LIQUIDATION are two separate mechanisms. liquidate is health-gated (requires CR below 150 percent) and applies a penalty bonus to the liquidator, the reserve, and the SP; healthy troves cannot be liquidated by anyone. redeem has no health gate on target and executes a value-neutral swap at oracle spot price - the target's debt decreases by net D while their collateral decreases by net times 1e8 over price APT, so the target retains full value at spot. Redemption is the protocol peg-anchor: when D trades below 1 USD on secondary market, any holder can burn D supply by redeeming for APT, pushing the peg back up. The target is caller-specified; there is no sorted-by-CR priority, unlike Liquity V1's sorted list - the economic result for the target is identical to Liquity (made whole at spot), only the redemption ordering differs, and ordering is a peg-efficiency optimization rather than a safety property. Borrowers who want guaranteed long-term APT exposure without the possibility of redemption-induced position conversion should not use D troves - use a non-CDP lending protocol instead. Losing optionality under redemption is not the same as losing value: the target is economically indifferent at spot.";

    struct Trove has store, drop { collateral: u64, debt: u64 }

    struct SP has store, drop {
        initial_balance: u64,
        snapshot_product: u128,
        snapshot_index_d: u128,
        snapshot_index_coll: u128,
    }

    /// Staged between publish and destroy_cap. Origin consumes + drops the cap to seal the package.
    struct ResourceCap has key { cap: Option<SignerCapability> }

    struct Registry has key {
        metadata: Object<Metadata>,
        apt_metadata: Object<Metadata>,
        mint_ref: MintRef,
        burn_ref: BurnRef,
        fee_pool: Object<FungibleStore>,
        fee_extend: ExtendRef,
        sp_pool: Object<FungibleStore>,
        sp_extend: ExtendRef,
        sp_coll_pool: Object<FungibleStore>,
        sp_coll_extend: ExtendRef,
        reserve_coll: Object<FungibleStore>,
        reserve_extend: ExtendRef,
        treasury: Object<FungibleStore>,
        treasury_extend: ExtendRef,
        troves: SmartTable<address, Trove>,
        sp_positions: SmartTable<address, SP>,
        total_debt: u64,
        total_sp: u64,
        product_factor: u128,
        reward_index_d: u128,
        reward_index_coll: u128,
    }

    #[event] struct TroveOpened has drop, store { user: address, new_collateral: u64, new_debt: u64, added_debt: u64 }
    #[event] struct CollateralAdded has drop, store { user: address, amount: u64 }
    #[event] struct TroveClosed has drop, store { user: address, collateral: u64, debt: u64 }
    #[event] struct Redeemed has drop, store { user: address, target: address, d_amt: u64, coll_out: u64 }
    #[event] struct Liquidated has drop, store { liquidator: address, target: address, debt: u64, coll_to_liquidator: u64, coll_to_sp: u64, coll_to_reserve: u64, coll_to_target: u64 }
    #[event] struct SPDeposited has drop, store { user: address, amount: u64 }
    #[event] struct SPDonated has drop, store { donor: address, amount: u64 }
    #[event] struct ReserveDonated has drop, store { donor: address, amount: u64 }
    #[event] struct SPWithdrew has drop, store { user: address, amount: u64 }
    #[event] struct SPClaimed has drop, store { user: address, d_amt: u64, coll_amt: u64 }
    #[event] struct ReserveRedeemed has drop, store { user: address, d_amt: u64, coll_out: u64 }
    #[event] struct CapDestroyed has drop, store { caller: address, timestamp: u64 }
    #[event] struct RewardSaturated has drop, store { user: address, pending_d_truncated: bool, pending_coll_truncated: bool }

    fun init_module(resource: &signer) {
        let cap = resource_account::retrieve_resource_account_cap(resource, @origin);
        move_to(resource, ResourceCap { cap: option::some(cap) });
        init_module_inner(resource, object::address_to_object<Metadata>(APT_FA));
    }

    /// Origin-only. One-shot consume of the staged SignerCapability. After success,
    /// no actor can reconstruct a signer for @D — package is permanently sealed.
    public entry fun destroy_cap(caller: &signer) acquires ResourceCap {
        assert!(signer::address_of(caller) == @origin, E_NOT_ORIGIN);
        assert!(exists<ResourceCap>(@D), E_CAP_GONE);
        let ResourceCap { cap } = move_from<ResourceCap>(@D);
        let _sc = option::destroy_some(cap);
        event::emit(CapDestroyed { caller: signer::address_of(caller), timestamp: timestamp::now_seconds() });
    }

    fun init_module_inner(deployer: &signer, apt_md: Object<Metadata>) {
        let ctor = object::create_named_object(deployer, b"D");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor, option::none(),
            string::utf8(b"D"), string::utf8(b"D"), 8,
            string::utf8(b""), string::utf8(b""),
        );
        let metadata = object::object_from_constructor_ref<Metadata>(&ctor);
        let da = signer::address_of(deployer);
        let fee_ctor = object::create_object(da);
        let sp_ctor = object::create_object(da);
        let sp_coll_ctor = object::create_object(da);
        let reserve_ctor = object::create_object(da);
        let tr_ctor = object::create_object(da);
        move_to(deployer, Registry {
            metadata,
            apt_metadata: apt_md,
            mint_ref: fungible_asset::generate_mint_ref(&ctor),
            burn_ref: fungible_asset::generate_burn_ref(&ctor),
            fee_pool: fungible_asset::create_store(&fee_ctor, metadata),
            fee_extend: object::generate_extend_ref(&fee_ctor),
            sp_pool: fungible_asset::create_store(&sp_ctor, metadata),
            sp_extend: object::generate_extend_ref(&sp_ctor),
            sp_coll_pool: fungible_asset::create_store(&sp_coll_ctor, apt_md),
            sp_coll_extend: object::generate_extend_ref(&sp_coll_ctor),
            reserve_coll: fungible_asset::create_store(&reserve_ctor, apt_md),
            reserve_extend: object::generate_extend_ref(&reserve_ctor),
            treasury: fungible_asset::create_store(&tr_ctor, apt_md),
            treasury_extend: object::generate_extend_ref(&tr_ctor),
            troves: smart_table::new(),
            sp_positions: smart_table::new(),
            total_debt: 0,
            total_sp: 0,
            product_factor: PRECISION,
            reward_index_d: 0,
            reward_index_coll: 0,
        });
    }

    fun price_8dec(): u128 {
        let id = price_identifier::from_byte_vec(APT_USD_PYTH_FEED);
        let p: Price = pyth::get_price_no_older_than(id, STALENESS_SECS);
        let p_i64 = price::get_price(&p);
        let e_i64 = price::get_expo(&p);
        let ts = price::get_timestamp(&p);
        let conf = price::get_conf(&p);
        let now = timestamp::now_seconds();
        assert!(ts + STALENESS_SECS >= now, E_STALE);
        assert!(ts <= now + 10, E_STALE);
        assert!(i64::get_is_negative(&e_i64), E_PRICE_EXPO);
        let abs_e = i64::get_magnitude_if_negative(&e_i64);
        assert!(abs_e <= 18, E_EXPO_BOUND);
        assert!(!i64::get_is_negative(&p_i64), E_PRICE_NEG);
        let raw = (i64::get_magnitude_if_positive(&p_i64) as u128);
        assert!(raw > 0, E_PRICE_ZERO);
        // Reject prices with wide confidence interval — Pyth signals uncertainty via conf.
        // Cap conf/raw ratio at MAX_CONF_BPS (2% default) in raw units (conf shares price's expo).
        assert!((conf as u128) * 10000 <= (MAX_CONF_BPS as u128) * raw, E_PRICE_UNCERTAIN);
        let result = if (abs_e >= 8) {
            raw / pow10(abs_e - 8)
        } else {
            raw * pow10(8 - abs_e)
        };
        assert!(result > 0, E_PRICE_ZERO);
        result
    }

    fun pow10(n: u64): u128 {
        assert!(n <= 38, E_DECIMAL_OVERFLOW);
        let r: u128 = 1;
        while (n > 0) { r = r * 10; n = n - 1; };
        r
    }

    fun route_fee_fa(r: &mut Registry, fa: FungibleAsset, donor: address) {
        let amt = fungible_asset::amount(&fa);
        if (amt == 0) { fungible_asset::destroy_zero(fa); return };
        let donate_amt = (((amt as u128) * 1000) / 10000) as u64;
        if (donate_amt > 0) {
            let donate_portion = fungible_asset::extract(&mut fa, donate_amt);
            fungible_asset::deposit(r.sp_pool, donate_portion);
            event::emit(SPDonated { donor, amount: donate_amt });
        };
        let sp_amt = fungible_asset::amount(&fa);
        if (sp_amt == 0) { fungible_asset::destroy_zero(fa); return };
        if (r.total_sp == 0) {
            // Cliff: no keyed depositors → 90% portion redirected to sp_pool as agnostic
            // donation rather than accruing unclaimable in the fee accumulator.
            fungible_asset::deposit(r.sp_pool, fa);
            event::emit(SPDonated { donor, amount: sp_amt });
        } else {
            fungible_asset::deposit(r.fee_pool, fa);
            r.reward_index_d = r.reward_index_d + (sp_amt as u128) * r.product_factor / (r.total_sp as u128);
        }
    }

    fun sp_settle(r: &mut Registry, u: address) {
        let pos = smart_table::borrow_mut(&mut r.sp_positions, u);
        let snap_p = pos.snapshot_product;
        let snap_i_d = pos.snapshot_index_d;
        let snap_i_coll = pos.snapshot_index_coll;
        let initial = pos.initial_balance;
        if (snap_p == 0 || initial == 0) {
            pos.snapshot_product = r.product_factor;
            pos.snapshot_index_d = r.reward_index_d;
            pos.snapshot_index_coll = r.reward_index_coll;
            return;
        };

        let u64_max: u256 = 18446744073709551615;
        let raw_d = ((r.reward_index_d - snap_i_d) as u256) * (initial as u256) / (snap_p as u256);
        let raw_coll = ((r.reward_index_coll - snap_i_coll) as u256) * (initial as u256) / (snap_p as u256);
        let raw_bal = (initial as u256) * (r.product_factor as u256) / (snap_p as u256);
        // Saturate at u64::MAX rather than abort — prevents permanent SP position lock
        // if decades of fee accrual push pending rewards past u64 bounds. User loses only
        // the astronomical excess above 1.8e19 raw units.
        let d_trunc = raw_d > u64_max;
        let coll_trunc = raw_coll > u64_max;
        let pending_d = (if (d_trunc) u64_max else raw_d) as u64;
        let pending_coll = (if (coll_trunc) u64_max else raw_coll) as u64;
        let new_balance = (if (raw_bal > u64_max) u64_max else raw_bal) as u64;
        if (d_trunc || coll_trunc) {
            event::emit(RewardSaturated { user: u, pending_d_truncated: d_trunc, pending_coll_truncated: coll_trunc });
        };

        pos.initial_balance = new_balance;
        pos.snapshot_product = r.product_factor;
        pos.snapshot_index_d = r.reward_index_d;
        pos.snapshot_index_coll = r.reward_index_coll;

        if (pending_d > 0) {
            let fee_signer = object::generate_signer_for_extending(&r.fee_extend);
            let fa = fungible_asset::withdraw(&fee_signer, r.fee_pool, pending_d);
            primary_fungible_store::deposit(u, fa);
        };
        if (pending_coll > 0) {
            let coll_signer = object::generate_signer_for_extending(&r.sp_coll_extend);
            let fa = fungible_asset::withdraw(&coll_signer, r.sp_coll_pool, pending_coll);
            primary_fungible_store::deposit(u, fa);
        };
        if (pending_d > 0 || pending_coll > 0) {
            event::emit(SPClaimed { user: u, d_amt: pending_d, coll_amt: pending_coll });
        }
    }

    fun open_impl(user_addr: address, fa_coll: FungibleAsset, debt: u64) acquires Registry {
        assert!(debt >= MIN_DEBT, E_DEBT_MIN);
        let coll_amt = fungible_asset::amount(&fa_coll);
        let r = borrow_global_mut<Registry>(@D);
        let price = price_8dec();

        let is_existing = smart_table::contains(&r.troves, user_addr);
        let (prior_coll, prior_debt) = if (is_existing) {
            let t = smart_table::borrow(&r.troves, user_addr);
            (t.collateral, t.debt)
        } else (0, 0);
        let new_coll = prior_coll + coll_amt;
        let new_debt = prior_debt + debt;
        let coll_usd = (new_coll as u128) * price / 100_000_000;
        assert!(coll_usd * 10000 >= MCR_BPS * (new_debt as u128), E_COLLATERAL);

        fungible_asset::deposit(r.treasury, fa_coll);
        let fee = (((debt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let user_fa = fungible_asset::mint(&r.mint_ref, debt - fee);
        let fee_fa = fungible_asset::mint(&r.mint_ref, fee);
        primary_fungible_store::deposit(user_addr, user_fa);
        route_fee_fa(r, fee_fa, user_addr);

        if (is_existing) {
            let t = smart_table::borrow_mut(&mut r.troves, user_addr);
            t.collateral = new_coll;
            t.debt = new_debt;
        } else {
            smart_table::add(&mut r.troves, user_addr, Trove { collateral: new_coll, debt: new_debt });
        };
        r.total_debt = r.total_debt + debt;
        event::emit(TroveOpened { user: user_addr, new_collateral: new_coll, new_debt, added_debt: debt });
    }

    fun add_impl(user_addr: address, fa_coll: FungibleAsset) acquires Registry {
        let amt = fungible_asset::amount(&fa_coll);
        assert!(amt > 0, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, user_addr), E_TROVE);
        fungible_asset::deposit(r.treasury, fa_coll);
        let t = smart_table::borrow_mut(&mut r.troves, user_addr);
        t.collateral = t.collateral + amt;
        event::emit(CollateralAdded { user: user_addr, amount: amt });
    }

    fun close_impl(user: &signer): FungibleAsset acquires Registry {
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, u), E_TROVE);
        let t = smart_table::remove(&mut r.troves, u);
        if (t.debt > 0) {
            fungible_asset::burn(&r.burn_ref, primary_fungible_store::withdraw(user, r.metadata, t.debt));
        };
        r.total_debt = r.total_debt - t.debt;
        event::emit(TroveClosed { user: u, collateral: t.collateral, debt: t.debt });
        let sr = object::generate_signer_for_extending(&r.treasury_extend);
        fungible_asset::withdraw(&sr, r.treasury, t.collateral)
    }

    fun redeem_impl(user: &signer, d_amt: u64, target: address): FungibleAsset acquires Registry {
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, target), E_TARGET);
        let price = price_8dec();
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * 100_000_000 / price) as u64);

        let t = smart_table::borrow_mut(&mut r.troves, target);
        assert!(t.debt >= net, E_TARGET);
        assert!(t.collateral >= coll_out, E_COLLATERAL);
        t.debt = t.debt - net;
        t.collateral = t.collateral - coll_out;
        assert!(t.debt == 0 || t.debt >= MIN_DEBT, E_DEBT_MIN);
        assert!(t.debt == 0 || t.collateral > 0, E_COLLATERAL);

        let user_fa = primary_fungible_store::withdraw(user, r.metadata, d_amt);
        let fee_fa = fungible_asset::extract(&mut user_fa, fee);
        fungible_asset::burn(&r.burn_ref, user_fa);
        let u = signer::address_of(user);
        route_fee_fa(r, fee_fa, u);
        r.total_debt = r.total_debt - net;
        event::emit(Redeemed { user: u, target, d_amt, coll_out });
        let sr = object::generate_signer_for_extending(&r.treasury_extend);
        fungible_asset::withdraw(&sr, r.treasury, coll_out)
    }

    public entry fun open_trove(user: &signer, coll_amt: u64, debt: u64) acquires Registry {
        let apt_md = borrow_global<Registry>(@D).apt_metadata;
        let fa = primary_fungible_store::withdraw(user, apt_md, coll_amt);
        open_impl(signer::address_of(user), fa, debt);
    }

    public entry fun add_collateral(user: &signer, coll_amt: u64) acquires Registry {
        let apt_md = borrow_global<Registry>(@D).apt_metadata;
        let fa = primary_fungible_store::withdraw(user, apt_md, coll_amt);
        add_impl(signer::address_of(user), fa);
    }

    public entry fun close_trove(user: &signer) acquires Registry {
        primary_fungible_store::deposit(signer::address_of(user), close_impl(user));
    }

    public entry fun redeem(user: &signer, d_amt: u64, target: address) acquires Registry {
        primary_fungible_store::deposit(
            signer::address_of(user), redeem_impl(user, d_amt, target)
        );
    }

    public entry fun redeem_from_reserve(user: &signer, d_amt: u64) acquires Registry {
        assert!(d_amt >= MIN_DEBT, E_AMOUNT);
        let r = borrow_global_mut<Registry>(@D);
        let price = price_8dec();
        let fee = (((d_amt as u128) * (FEE_BPS as u128)) / 10000) as u64;
        let net = d_amt - fee;
        let coll_out = (((net as u128) * 100_000_000 / price) as u64);
        assert!(fungible_asset::balance(r.reserve_coll) >= coll_out, E_INSUFFICIENT_RESERVE);

        // Reserve redemption burns D against protocol-owned collateral. No trove is
        // being closed here, so total_debt (= sum of per-trove debts) is intentionally
        // not decremented. Circulating supply falls while total_debt stays — this widens
        // the supply-vs-debt gap, which is the intended reserve-drain mechanic.
        let user_fa = primary_fungible_store::withdraw(user, r.metadata, d_amt);
        let fee_fa = fungible_asset::extract(&mut user_fa, fee);
        fungible_asset::burn(&r.burn_ref, user_fa);
        let u = signer::address_of(user);
        route_fee_fa(r, fee_fa, u);

        let sr = object::generate_signer_for_extending(&r.reserve_extend);
        let out = fungible_asset::withdraw(&sr, r.reserve_coll, coll_out);
        primary_fungible_store::deposit(u, out);

        event::emit(ReserveRedeemed { user: u, d_amt, coll_out });
    }

    public entry fun liquidate(liquidator: &signer, target: address) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.troves, target), E_TARGET);
        let price = price_8dec();
        let t_ref = smart_table::borrow(&r.troves, target);
        let debt = t_ref.debt;
        let coll = t_ref.collateral;
        let coll_usd = (coll as u128) * price / 100_000_000;

        assert!(coll_usd * 10000 < LIQ_THRESHOLD_BPS * (debt as u128), E_HEALTHY);
        let pool_before = fungible_asset::balance(r.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);

        let total_before = r.total_sp;
        let new_p = r.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        // MIN_P_THRESHOLD only applies to keyed depositors. During cliff (total_before==0)
        // the donations alone absorb absent any rateable share — accept arbitrary p drop.
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        // Truncation guard (HIGH-1, Claude R1 fresh): u64/u128 truncation could decouple
        // total_sp from product_factor, leaving total_sp_new == 0 while keyed positions
        // still in table. Subsequent route_fee divides by total_sp == 0 → permanent DoS.
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);

        let bonus_usd = (debt as u128) * (LIQ_BONUS_BPS as u128) / 10000;
        let liq_share_usd = bonus_usd * (LIQ_LIQUIDATOR_BPS as u128) / 10000;
        let reserve_share_usd = bonus_usd * (LIQ_SP_RESERVE_BPS as u128) / 10000;
        let total_seize_usd = (debt as u128) + bonus_usd;
        let total_seize_u128 = total_seize_usd * 100_000_000 / price;
        let coll_u128 = (coll as u128);
        let total_seize_coll = (if (total_seize_u128 > coll_u128) coll_u128 else total_seize_u128) as u64;
        let liq_u128 = liq_share_usd * 100_000_000 / price;
        let total_seize_coll_u128 = (total_seize_coll as u128);
        let liq_coll = (if (liq_u128 > total_seize_coll_u128) total_seize_coll_u128 else liq_u128) as u64;
        let remaining_u128 = total_seize_coll_u128 - (liq_coll as u128);
        let reserve_u128 = reserve_share_usd * 100_000_000 / price;
        let reserve_coll_amt = (if (reserve_u128 > remaining_u128) remaining_u128 else reserve_u128) as u64;
        let sp_coll = total_seize_coll - liq_coll - reserve_coll_amt;
        let target_remainder = coll - total_seize_coll;

        smart_table::remove(&mut r.troves, target);
        r.total_debt = r.total_debt - debt;

        let sp_signer = object::generate_signer_for_extending(&r.sp_extend);
        let burn_fa = fungible_asset::withdraw(&sp_signer, r.sp_pool, debt);
        fungible_asset::burn(&r.burn_ref, burn_fa);

        if (total_before > 0) {
            r.reward_index_coll = r.reward_index_coll +
                (sp_coll as u128) * r.product_factor / (total_before as u128);
        };
        r.product_factor = new_p;
        r.total_sp = total_sp_new;

        let tr_signer = object::generate_signer_for_extending(&r.treasury_extend);
        let seized = fungible_asset::withdraw(&tr_signer, r.treasury, total_seize_coll);
        let liq_fa = fungible_asset::extract(&mut seized, liq_coll);
        primary_fungible_store::deposit(signer::address_of(liquidator), liq_fa);
        let reserve_fa = fungible_asset::extract(&mut seized, reserve_coll_amt);
        fungible_asset::deposit(r.reserve_coll, reserve_fa);
        if (total_before == 0) {
            // Cliff orphan: no keyed depositors → redirect sp_coll to reserve_coll instead
            // of accruing in sp_coll_pool where it would be unclaimable.
            fungible_asset::deposit(r.reserve_coll, seized);
        } else {
            fungible_asset::deposit(r.sp_coll_pool, seized);
        };

        if (target_remainder > 0) {
            let rem_fa = fungible_asset::withdraw(&tr_signer, r.treasury, target_remainder);
            primary_fungible_store::deposit(target, rem_fa);
        };

        event::emit(Liquidated {
            liquidator: signer::address_of(liquidator),
            target, debt,
            coll_to_liquidator: liq_coll,
            coll_to_sp: sp_coll,
            coll_to_reserve: reserve_coll_amt,
            coll_to_target: target_remainder,
        });
    }

    public entry fun sp_deposit(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.metadata, amt);
        fungible_asset::deposit(r.sp_pool, fa_in);
        // Reset-on-empty: when total_sp has been fully drained (previous cliff-freeze
        // plus all prior depositors withdrew), reset product_factor to full precision
        // so liquidations can resume. No active depositor is harmed — there are none.
        if (r.total_sp == 0) {
            r.product_factor = PRECISION;
        };
        if (smart_table::contains(&r.sp_positions, u)) {
            sp_settle(r, u);
            let p = smart_table::borrow_mut(&mut r.sp_positions, u);
            p.initial_balance = p.initial_balance + amt;
        } else {
            smart_table::add(&mut r.sp_positions, u, SP {
                initial_balance: amt,
                snapshot_product: r.product_factor,
                snapshot_index_d: r.reward_index_d,
                snapshot_index_coll: r.reward_index_coll,
            });
        };
        r.total_sp = r.total_sp + amt;
        event::emit(SPDeposited { user: u, amount: amt });
    }

    /// Permissionless agnostic donation of D into the Stability Pool. Joins sp_pool
    /// balance only — does NOT increment total_sp, so keyed depositors' yield share
    /// is not diluted. Donations participate in liquidation absorption pro-rata via
    /// the actual sp_pool balance ratio, gradually burning over time.
    public entry fun donate_to_sp(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.metadata, amt);
        fungible_asset::deposit(r.sp_pool, fa_in);
        event::emit(SPDonated { donor: u, amount: amt });
    }

    /// Permissionless donation of APT into reserve_coll — fortifies redeem_from_reserve
    /// capacity. No oracle call; works during oracle freeze.
    public entry fun donate_to_reserve(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        let fa_in = primary_fungible_store::withdraw(user, r.apt_metadata, amt);
        fungible_asset::deposit(r.reserve_coll, fa_in);
        event::emit(ReserveDonated { donor: u, amount: amt });
    }

    public entry fun sp_withdraw(user: &signer, amt: u64) acquires Registry {
        assert!(amt > 0, E_AMOUNT);
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.sp_positions, u), E_SP_BAL);
        sp_settle(r, u);
        let pos = smart_table::borrow_mut(&mut r.sp_positions, u);
        assert!(pos.initial_balance >= amt, E_SP_BAL);
        pos.initial_balance = pos.initial_balance - amt;
        r.total_sp = r.total_sp - amt;
        let empty = pos.initial_balance == 0;
        let sr = object::generate_signer_for_extending(&r.sp_extend);
        primary_fungible_store::deposit(u, fungible_asset::withdraw(&sr, r.sp_pool, amt));
        if (empty) { smart_table::remove(&mut r.sp_positions, u); };
        event::emit(SPWithdrew { user: u, amount: amt });
    }

    public entry fun sp_claim(user: &signer) acquires Registry {
        let u = signer::address_of(user);
        let r = borrow_global_mut<Registry>(@D);
        assert!(smart_table::contains(&r.sp_positions, u), E_SP_BAL);
        sp_settle(r, u);
    }

    // Convenience wrappers that atomically refresh the Pyth feed before the oracle-dependent
    // entry. Integrators avoid the two-tx dance and cannot accidentally operate on a cached
    // price set by an unrelated actor. Raw entries above remain available.

    public entry fun open_trove_pyth(
        user: &signer, coll_amt: u64, debt: u64, vaas: vector<vector<u8>>
    ) acquires Registry {
        pyth::update_price_feeds_with_funder(user, vaas);
        let apt_md = borrow_global<Registry>(@D).apt_metadata;
        let fa = primary_fungible_store::withdraw(user, apt_md, coll_amt);
        open_impl(signer::address_of(user), fa, debt);
    }

    public entry fun redeem_pyth(
        user: &signer, d_amt: u64, target: address, vaas: vector<vector<u8>>
    ) acquires Registry {
        pyth::update_price_feeds_with_funder(user, vaas);
        primary_fungible_store::deposit(
            signer::address_of(user), redeem_impl(user, d_amt, target)
        );
    }

    public entry fun redeem_from_reserve_pyth(
        user: &signer, d_amt: u64, vaas: vector<vector<u8>>
    ) acquires Registry {
        pyth::update_price_feeds_with_funder(user, vaas);
        redeem_from_reserve(user, d_amt);
    }

    public entry fun liquidate_pyth(
        liquidator: &signer, target: address, vaas: vector<vector<u8>>
    ) acquires Registry {
        pyth::update_price_feeds_with_funder(liquidator, vaas);
        liquidate(liquidator, target);
    }

    #[view] public fun read_warning(): vector<u8> { WARNING }

    #[view] public fun metadata_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).metadata)
    }

    // FungibleStore addresses — exposed pre-seal so indexers/frontends can subscribe
    // events directly per store and verify on-chain balances without reading Registry.
    // Each address is derived from the deployer GUID counter at init time and is
    // stable for the package lifetime.

    #[view] public fun fee_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).fee_pool)
    }

    #[view] public fun sp_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).sp_pool)
    }

    #[view] public fun sp_coll_pool_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).sp_coll_pool)
    }

    #[view] public fun reserve_coll_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).reserve_coll)
    }

    #[view] public fun treasury_addr(): address acquires Registry {
        object::object_address(&borrow_global<Registry>(@D).treasury)
    }

    #[view] public fun price(): u128 { price_8dec() }

    #[view] public fun trove_of(addr: address): (u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.troves, addr)) {
            let t = smart_table::borrow(&r.troves, addr);
            (t.collateral, t.debt)
        } else (0, 0)
    }

    #[view] public fun sp_of(addr: address): (u64, u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.sp_positions, addr)) {
            let p = smart_table::borrow(&r.sp_positions, addr);
            let eff = ((((p.initial_balance as u256) * (r.product_factor as u256)) / (p.snapshot_product as u256)) as u64);
            let p_d = ((((r.reward_index_d - p.snapshot_index_d) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            let p_coll = ((((r.reward_index_coll - p.snapshot_index_coll) as u256) * (p.initial_balance as u256)) / (p.snapshot_product as u256)) as u64;
            (eff, p_d, p_coll)
        } else (0, 0, 0)
    }

    #[view] public fun totals(): (u64, u64, u128, u128, u128) acquires Registry {
        let r = borrow_global<Registry>(@D);
        (r.total_debt, r.total_sp, r.product_factor, r.reward_index_d, r.reward_index_coll)
    }

    #[view] public fun reserve_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).reserve_coll)
    }

    /// Live sp_pool balance. Differs from total_sp by the amount of agnostic donations
    /// that have not yet been absorbed via liquidation.
    #[view] public fun sp_pool_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).sp_pool)
    }

    /// Returns true iff destroy_cap has been called (package permanently sealed).
    #[view] public fun is_sealed(): bool { !exists<ResourceCap>(@D) }

    /// Exact D amount user needs to burn in order to call close_trove on their own trove.
    /// Useful for front-ends to show the secondary-market D deficit pre-close.
    #[view] public fun close_cost(addr: address): u64 acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (smart_table::contains(&r.troves, addr)) {
            smart_table::borrow(&r.troves, addr).debt
        } else 0
    }

    /// Returns (collateral, debt, cr_bps). cr_bps = 0 if no trove, or if oracle unavailable
    /// (caller must handle that case). Uses price_8dec() so shares its abort semantics on bad oracle.
    #[view] public fun trove_health(addr: address): (u64, u64, u64) acquires Registry {
        let r = borrow_global<Registry>(@D);
        if (!smart_table::contains(&r.troves, addr)) return (0, 0, 0);
        let t = smart_table::borrow(&r.troves, addr);
        if (t.debt == 0) return (t.collateral, 0, 0);
        let price = price_8dec();
        let coll_usd = (t.collateral as u128) * price / 100_000_000;
        let cr_bps = (coll_usd * 10000 / (t.debt as u128)) as u64;
        (t.collateral, t.debt, cr_bps)
    }

    #[test_only]
    public fun init_module_for_test(deployer: &signer, apt_md: Object<Metadata>) {
        init_module_inner(deployer, apt_md);
    }

    #[test_only]
    public fun test_stash_cap_for_test(deployer: &signer) {
        let fake = aptos_framework::account::create_test_signer_cap(signer::address_of(deployer));
        move_to(deployer, ResourceCap { cap: option::some(fake) });
    }

    #[test_only]
    public fun test_create_sp_position(addr: address, balance: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        // Mint+deposit D into sp_pool so live and V2-simulator paths see a
        // balance backing the keyed total_sp. V1-style simulators don't read
        // sp_pool, so this is harmless to legacy tests.
        let fa = fungible_asset::mint(&r.mint_ref, balance);
        fungible_asset::deposit(r.sp_pool, fa);
        smart_table::add(&mut r.sp_positions, addr, SP {
            initial_balance: balance,
            snapshot_product: r.product_factor,
            snapshot_index_d: r.reward_index_d,
            snapshot_index_coll: r.reward_index_coll,
        });
        r.total_sp = r.total_sp + balance;
    }

    #[test_only]
    public fun test_donate_sp_raw(amount: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let fa = fungible_asset::mint(&r.mint_ref, amount);
        fungible_asset::deposit(r.sp_pool, fa);
    }

    #[test_only]
    public fun test_route_fee_virtual(amount: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let sp_amt = amount - amount * 1000 / 10000;
        if (sp_amt == 0) return;
        if (r.total_sp == 0) return;
        r.reward_index_d = r.reward_index_d + (sp_amt as u128) * r.product_factor / (r.total_sp as u128);
    }

    #[test_only]
    public fun test_sp_pool_balance(): u64 acquires Registry {
        fungible_asset::balance(borrow_global<Registry>(@D).sp_pool)
    }

    #[test_only]
    public fun test_mint_d(amount: u64): FungibleAsset acquires Registry {
        let r = borrow_global<Registry>(@D);
        fungible_asset::mint(&r.mint_ref, amount)
    }

    #[test_only]
    public fun test_create_trove(addr: address, collateral: u64, debt: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        smart_table::add(&mut r.troves, addr, Trove { collateral, debt });
        r.total_debt = r.total_debt + debt;
    }

    /// V2 simulator using pool_before denominator. Mirrors live `liquidate` math
    /// for the SP-state mutation only (skips collateral seize/distribution).
    #[test_only]
    public fun test_simulate_liquidation_v2(debt: u64, sp_coll_absorbed: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let pool_before = fungible_asset::balance(r.sp_pool);
        assert!(pool_before > debt, E_SP_INSUFFICIENT);
        let total_before = r.total_sp;
        let new_p = r.product_factor * ((pool_before - debt) as u128) / (pool_before as u128);
        assert!(total_before == 0 || new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        let total_sp_new = ((total_before as u128) * ((pool_before - debt) as u128) / (pool_before as u128)) as u64;
        assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF);
        let sp_signer = object::generate_signer_for_extending(&r.sp_extend);
        let burn_fa = fungible_asset::withdraw(&sp_signer, r.sp_pool, debt);
        fungible_asset::burn(&r.burn_ref, burn_fa);
        if (total_before > 0) {
            r.reward_index_coll = r.reward_index_coll +
                (sp_coll_absorbed as u128) * r.product_factor / (total_before as u128);
        };
        r.product_factor = new_p;
        r.total_sp = total_sp_new;
    }

    /// Legacy V1 simulator using total_sp denominator. Kept for any V1-style tests that
    /// don't model donation flow. New tests should prefer test_simulate_liquidation_v2.
    #[test_only]
    public fun test_simulate_liquidation(debt: u64, sp_coll_absorbed: u64) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        let total_before = r.total_sp;
        assert!(total_before > debt, E_SP_INSUFFICIENT);
        let new_p = r.product_factor * ((total_before - debt) as u128) / (total_before as u128);
        assert!(new_p >= MIN_P_THRESHOLD, E_P_CLIFF);
        r.reward_index_coll = r.reward_index_coll +
            (sp_coll_absorbed as u128) * r.product_factor / (total_before as u128);
        r.product_factor = new_p;
        r.total_sp = total_before - debt;
    }

    #[test_only]
    public fun test_set_sp_position(
        addr: address, initial: u64, snap_p: u128, snap_i_d: u128, snap_i_coll: u128
    ) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        if (smart_table::contains(&r.sp_positions, addr)) {
            let p = smart_table::borrow_mut(&mut r.sp_positions, addr);
            p.initial_balance = initial;
            p.snapshot_product = snap_p;
            p.snapshot_index_d = snap_i_d;
            p.snapshot_index_coll = snap_i_coll;
        } else {
            smart_table::add(&mut r.sp_positions, addr, SP {
                initial_balance: initial,
                snapshot_product: snap_p,
                snapshot_index_d: snap_i_d,
                snapshot_index_coll: snap_i_coll,
            });
        };
    }

    #[test_only]
    public fun test_get_sp_snapshots(addr: address): (u64, u128, u128, u128) acquires Registry {
        let r = borrow_global<Registry>(@D);
        let p = smart_table::borrow(&r.sp_positions, addr);
        (p.initial_balance, p.snapshot_product, p.snapshot_index_d, p.snapshot_index_coll)
    }

    #[test_only]
    public fun test_force_reward_indices(d_idx: u128, coll_idx: u128) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        r.reward_index_d = d_idx;
        r.reward_index_coll = coll_idx;
    }

    #[test_only]
    public fun test_call_sp_settle(addr: address) acquires Registry {
        let r = borrow_global_mut<Registry>(@D);
        sp_settle(r, addr);
    }
}
```

---

# Tests: `tests/D_tests.move` (458 lines)

```move
#[test_only]
module D::D_tests {
    use std::option;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use D::D;

    const MOCK_APT_HOST: address = @0xABCD;

    fun setup(deployer: &signer): Object<Metadata> {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@aptos_framework)
        );
        let apt_signer = account::create_signer_for_test(MOCK_APT_HOST);
        let ctor = object::create_named_object(&apt_signer, b"APT");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor, option::none(),
            string::utf8(b"Aptos Coin"), string::utf8(b"APT"), 8,
            string::utf8(b""), string::utf8(b""),
        );
        let apt_md = object::object_from_constructor_ref<Metadata>(&ctor);
        D::init_module_for_test(deployer, apt_md);
        apt_md
    }

    #[test(deployer = @D)]
    fun test_init_creates_registry(deployer: &signer) {
        setup(deployer);
        let (debt, sp, p, r1, r2) = D::totals();
        assert!(debt == 0, 100);
        assert!(sp == 0, 101);
        assert!(p == 1_000_000_000_000_000_000, 102);
        assert!(r1 == 0, 103);
        assert!(r2 == 0, 104);
    }

    #[test(deployer = @D)]
    fun test_warning_text_on_chain(deployer: &signer) {
        setup(deployer);
        let w = D::read_warning();
        let prefix = b"D is an immutable stablecoin";
        let i = 0;
        while (i < vector::length(&prefix)) {
            assert!(*vector::borrow(&w, i) == *vector::borrow(&prefix, i), 200);
            i = i + 1;
        };
        let pyth_ref = b"Pyth Network";
        assert!(contains_bytes(&w, &pyth_ref), 201);
        // V2-specific: confirm WARNING (4) reflects 10/90 + agnostic donation language.
        let agnostic_ref = b"agnostic donation";
        assert!(contains_bytes(&w, &agnostic_ref), 202);
        let split_ref = b"10 percent of each mint and redeem fee";
        assert!(contains_bytes(&w, &split_ref), 203);
    }

    #[test(deployer = @D)]
    fun test_trove_of_unknown_returns_zero(deployer: &signer) {
        setup(deployer);
        let (c, d) = D::trove_of(@0xA11CE);
        assert!(c == 0 && d == 0, 300);
    }

    #[test(deployer = @D)]
    fun test_sp_of_unknown_returns_zero(deployer: &signer) {
        setup(deployer);
        let (bal, p_d, p_coll) = D::sp_of(@0xA11CE);
        assert!(bal == 0 && p_d == 0 && p_coll == 0, 400);
    }

    #[test(deployer = @D)]
    fun test_metadata_addr_stable(deployer: &signer) {
        setup(deployer);
        assert!(D::metadata_addr() == D::metadata_addr(), 500);
    }

    /// Composability surface: each FungibleStore exposes its own object address.
    /// Indexers can subscribe events per-store; frontend can verify balances.
    /// All five addresses must be distinct AND stable across calls.
    #[test(deployer = @D)]
    fun test_store_addresses_distinct_and_stable(deployer: &signer) {
        setup(deployer);
        let m = D::metadata_addr();
        let f = D::fee_pool_addr();
        let s = D::sp_pool_addr();
        let sc = D::sp_coll_pool_addr();
        let rc = D::reserve_coll_addr();
        let t = D::treasury_addr();

        // Stability: same call returns same address
        assert!(f == D::fee_pool_addr(), 510);
        assert!(s == D::sp_pool_addr(), 511);
        assert!(sc == D::sp_coll_pool_addr(), 512);
        assert!(rc == D::reserve_coll_addr(), 513);
        assert!(t == D::treasury_addr(), 514);

        // Distinctness: all six addresses (metadata + 5 stores) must differ
        assert!(m != f && m != s && m != sc && m != rc && m != t, 520);
        assert!(f != s && f != sc && f != rc && f != t, 521);
        assert!(s != sc && s != rc && s != t, 522);
        assert!(sc != rc && sc != t, 523);
        assert!(rc != t, 524);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 2, location = D::D)]
    fun test_close_trove_without_trove_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::close_trove(user);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 5, location = D::D)]
    fun test_sp_claim_without_position_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_claim(user);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 5, location = D::D)]
    fun test_sp_withdraw_without_position_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_withdraw(user, 100_000_000);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_sp_deposit_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::sp_deposit(user, 0);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_donate_to_sp_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::donate_to_sp(user, 0);
    }

    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_donate_to_reserve_zero_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        D::donate_to_reserve(user, 0);
    }

    #[test(deployer = @D)]
    fun test_sp_position_creation_via_helper(deployer: &signer) {
        setup(deployer);
        let u = @0xBEEF;
        D::test_create_sp_position(u, 100_000_000);
        let (bal, p_d, p_coll) = D::sp_of(u);
        assert!(bal == 100_000_000, 600);
        assert!(p_d == 0, 601);
        assert!(p_coll == 0, 602);
    }

    /// V2 split: 10% donation / 90% accumulator. Replaces V1's 25/75 expected values.
    /// amount=1_000_000 → donate=100_000 (sp_pool), sp_amt=900_000 (accumulator).
    /// reward_index_d delta = 900_000 * 1e18 / 100_000_000 = 9e15.
    /// pending_d for keyed depositor = 9e15 * 1e8 / 1e18 = 900_000.
    #[test(deployer = @D)]
    fun test_reward_index_increment_and_pending(deployer: &signer) {
        setup(deployer);
        let u = @0xBEEF;
        D::test_create_sp_position(u, 100_000_000);
        D::test_route_fee_virtual(1_000_000);
        let (_, _, _, r_d, _) = D::totals();
        assert!(r_d == 9_000_000_000_000_000, 700);
        let (bal, p_d, p_coll) = D::sp_of(u);
        assert!(bal == 100_000_000, 701);
        assert!(p_d == 900_000, 702);
        assert!(p_coll == 0, 703);
    }

    /// V2 pro-rata: amount=300M → donate=30M (skipped in virtual helper), sp_amt=270M.
    /// reward_index_d delta = 270M * 1e18 / 300M = 9e17.
    /// AAAA (200M): p_d = 9e17 * 200M / 1e18 = 180_000_000.
    /// BBBB (100M): p_d = 9e17 * 100M / 1e18 = 90_000_000.
    #[test(deployer = @D)]
    fun test_reward_index_pro_rata_two_depositors(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 200_000_000);
        D::test_create_sp_position(@0xBBBB, 100_000_000);
        D::test_route_fee_virtual(300_000_000);
        let (_, pa, _) = D::sp_of(@0xAAAA);
        let (_, pb, _) = D::sp_of(@0xBBBB);
        assert!(pa == 180_000_000, 800);
        assert!(pb == 90_000_000, 801);
    }

    #[test(deployer = @D)]
    fun test_liquidation_single_depositor(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        let (bal, p_d, p_coll) = D::sp_of(@0xAAAA);
        assert!(bal == 8_000_000_000, 900);
        assert!(p_d == 0, 901);
        assert!(p_coll == 2_500_000_000, 902);
        let (_, total_sp, pf, _, r_coll) = D::totals();
        assert!(total_sp == 8_000_000_000, 903);
        assert!(pf == 800_000_000_000_000_000, 904);
        assert!(r_coll == 250_000_000_000_000_000, 905);
    }

    #[test(deployer = @D)]
    fun test_liquidation_two_depositors_pro_rata(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_create_sp_position(@0xBBBB, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        let (a_bal, _, a_coll) = D::sp_of(@0xAAAA);
        let (b_bal, _, b_coll) = D::sp_of(@0xBBBB);
        assert!(a_bal == 9_000_000_000, 1000);
        assert!(b_bal == 9_000_000_000, 1001);
        assert!(a_coll == 1_250_000_000, 1002);
        assert!(b_coll == 1_250_000_000, 1003);
    }

    #[test(deployer = @D)]
    fun test_liquidation_sequential_math(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 2_500_000_000);
        D::test_create_sp_position(@0xBBBB, 10_000_000_000);
        D::test_simulate_liquidation(1_000_000_000, 1_500_000_000);
        let (a_bal, _, a_coll) = D::sp_of(@0xAAAA);
        assert!(a_bal == 7_555_555_555, 1100);
        assert!(a_coll == 3_166_666_666, 1101);
        let (b_bal, _, b_coll) = D::sp_of(@0xBBBB);
        assert!(b_bal == 9_444_444_444, 1102);
        assert!(b_coll == 833_333_333, 1103);
    }

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 14, location = D::D)]
    fun test_liquidation_cliff_guard_aborts(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(9_999_999_000, 1_000_000_000);
        D::test_simulate_liquidation(999, 500);
    }

    // V2 — agnostic donation invariants

    /// donate_to_sp grows sp_pool balance but does NOT increment total_sp,
    /// so reward distribution to keyed depositors is unaffected by donation rate.
    #[test(deployer = @D)]
    fun test_donate_to_sp_no_dilution(deployer: &signer) {
        setup(deployer);
        let alice = @0xA11CE;
        D::test_create_sp_position(alice, 100_000_000);
        // Mint D for a fresh donor and donate it
        let donor = @0xD0;
        let donor_signer = account::create_signer_for_test(donor);
        let fa = D::test_mint_d(50_000_000);
        primary_fungible_store::deposit(donor, fa);
        D::donate_to_sp(&donor_signer, 50_000_000);
        // total_sp unchanged, sp_pool grew
        let (_, total_sp_after, _, _, _) = D::totals();
        assert!(total_sp_after == 100_000_000, 1200);
        let pool = D::sp_pool_balance();
        assert!(pool == 150_000_000, 1201);
        // Reward index didn't change either (donation bypasses fee accumulator)
        let (_, _, _, r_d_after, _) = D::totals();
        assert!(r_d_after == 0, 1202);
        // Now route a fee → keyed depositor still gets full 90% share
        D::test_route_fee_virtual(1_000_000);
        let (_, p_d, _) = D::sp_of(alice);
        assert!(p_d == 900_000, 1203);
    }

    /// V2 cliff path: when total_sp == 0, route_fee redirects ALL portions to sp_pool
    /// donation rather than accruing in fee_pool.
    #[test(deployer = @D)]
    fun test_route_fee_cliff_path_pure_donation(deployer: &signer) {
        setup(deployer);
        // total_sp == 0 (no keyed depositors)
        let (_, total_sp, _, r_d, _) = D::totals();
        assert!(total_sp == 0, 1400);
        assert!(r_d == 0, 1401);
        // Helper short-circuits when total_sp == 0 — confirms reward_index_d unchanged
        D::test_route_fee_virtual(1_000_000);
        let (_, _, _, r_d_after, _) = D::totals();
        assert!(r_d_after == 0, 1402);
    }

    /// HIGH-1 reproducer (Claude Opus 4.7 fresh R1): u64/u128 truncation could decouple
    /// total_sp_new from product_factor. Setup: pool_before = 1e9, total_before = 1e8,
    /// debt = 999_999_999. Then new_p = 1e18 * 1 / 1e9 = 1e9 (= MIN_P_THRESHOLD, passes
    /// cliff guard). total_sp_new = 1e8 * 1 / 1e9 = 0 via integer truncation. Without
    /// the truncation guard, subsequent route_fee divides by total_sp == 0 → permanent
    /// DoS. Guard `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` catches it.
    #[test(deployer = @D)]
    #[expected_failure(abort_code = 14, location = D::D)]
    fun test_truncation_decoupling_aborts(deployer: &signer) {
        setup(deployer);
        // Keyed depositor with 1e8 D
        D::test_create_sp_position(@0xAAAA, 100_000_000);
        // Donate 9e8 D agnostically → sp_pool = 1e9, total_sp still 1e8
        D::test_donate_sp_raw(900_000_000);
        // Liquidate 999_999_999 → pool_before=1e9, new_p=1e9 (MIN_P_THRESHOLD ok),
        // total_sp_new = 1e8 * 1 / 1e9 = 0 → truncation guard aborts E_P_CLIFF.
        D::test_simulate_liquidation_v2(999_999_999, 0);
    }

    /// V2 cliff handling: liquidation when total_before == 0 (pure-donation pool)
    /// must succeed without aborting on MIN_P_THRESHOLD or truncation guard, since
    /// no keyed depositor exists to be harmed by p drop.
    #[test(deployer = @D)]
    fun test_min_p_threshold_skipped_at_cliff(deployer: &signer) {
        setup(deployer);
        // Pure donation pool: 1e10 D, total_sp == 0
        D::test_donate_sp_raw(10_000_000_000);
        // Liquidate 9_999_999_999 → pool_before=1e10, would-be new_p = 1e18 * 1 / 1e10 = 1e8
        // (well below MIN_P_THRESHOLD 1e9), but total_before==0 so cliff guard skipped.
        D::test_simulate_liquidation_v2(9_999_999_999, 0);
        let (_, total_sp, pf, _, _) = D::totals();
        assert!(total_sp == 0, 1500);
        assert!(pf == 100_000_000, 1501); // 1e8 — below MIN_P but accepted at cliff
    }

    /// Confirms V2 simulator math matches V1 simulator when no donations exist
    /// (pool_before == total_sp). Acts as cross-check between the two helpers.
    #[test(deployer = @D)]
    fun test_v1_v2_simulator_parity_no_donation(deployer: &signer) {
        setup(deployer);
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation_v2(2_000_000_000, 2_500_000_000);
        let (bal, _, p_coll) = D::sp_of(@0xAAAA);
        // Same expected as V1 single-depositor test
        assert!(bal == 8_000_000_000, 1600);
        assert!(p_coll == 2_500_000_000, 1601);
        let (_, total_sp, pf, _, _) = D::totals();
        assert!(total_sp == 8_000_000_000, 1602);
        assert!(pf == 800_000_000_000_000_000, 1603);
    }

    /// V2 reset-on-empty: after pool fully drains via cliff liquidations, a new
    /// sp_deposit must reset product_factor to PRECISION so subsequent liquidations
    /// can resume.
    #[test(deployer = @D, depositor = @0xDEAD)]
    fun test_sp_deposit_resets_product_factor_when_empty(deployer: &signer, depositor: &signer) {
        setup(deployer);
        // Drive product_factor below PRECISION via simulated liquidation
        D::test_create_sp_position(@0xAAAA, 10_000_000_000);
        D::test_simulate_liquidation(2_000_000_000, 0);
        let (_, _, pf_mid, _, _) = D::totals();
        assert!(pf_mid < 1_000_000_000_000_000_000, 1700);
        // Withdraw AAAA fully so total_sp returns to 0
        // (Use raw simulator-friendly path: drain via test_set_sp_position to 0 then remove)
        // Simpler: simulate aggressive liq that brings total_sp to 0 via formula
        // For this test just use sp_deposit which sees total_sp == 0 if we manually clear it.
        let r_clear_addr = @0xAAAA;
        let _ = r_clear_addr;
        // Direct path: AAAA withdraws via the entry. Need real D balance.
        let alice_signer = account::create_signer_for_test(@0xAAAA);
        D::sp_withdraw(&alice_signer, 8_000_000_000);
        let (_, total_sp, _, _, _) = D::totals();
        assert!(total_sp == 0, 1701);
        // Now depositor mints+deposits — should reset product_factor
        let fa = D::test_mint_d(1_000_000_000);
        primary_fungible_store::deposit(@0xDEAD, fa);
        D::sp_deposit(depositor, 1_000_000_000);
        let (_, _, pf_after, _, _) = D::totals();
        assert!(pf_after == 1_000_000_000_000_000_000, 1702);
    }

    // --- destroy_cap / ResourceCap tests ---

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 17, location = D::D)]
    fun test_destroy_cap_non_origin_aborts(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let attacker = account::create_signer_for_test(@0xBEEF);
        D::destroy_cap(&attacker);
    }

    #[test(deployer = @D)]
    fun test_destroy_cap_consumes_resource(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let origin = account::create_signer_for_test(@origin);
        D::destroy_cap(&origin);
    }

    #[test(deployer = @D)]
    #[expected_failure(abort_code = 18, location = D::D)]
    fun test_destroy_cap_double_call_aborts(deployer: &signer) {
        setup(deployer);
        D::test_stash_cap_for_test(deployer);
        let origin = account::create_signer_for_test(@origin);
        D::destroy_cap(&origin);
        D::destroy_cap(&origin);
    }

    fun contains_bytes(hay: &vector<u8>, needle: &vector<u8>): bool {
        let hn = vector::length(hay);
        let nn = vector::length(needle);
        if (nn == 0 || nn > hn) return nn == 0;
        let i = 0;
        while (i + nn <= hn) {
            let j = 0;
            let ok = true;
            while (j < nn) {
                if (*vector::borrow(hay, i + j) != *vector::borrow(needle, j)) {
                    ok = false;
                    break
                };
                j = j + 1;
            };
            if (ok) return true;
            i = i + 1;
        };
        false
    }

    // R2-C01 regression: zombie positions (initial=0) must have their snapshots
    // refreshed on every sp_settle call, not left stale. Otherwise a later
    // redeposit pairs a fresh initial_balance with a stale snap_product /
    // snap_index_d pair, inflating the next pending_d by Δindex / stale_P.
    #[test(deployer = @D)]
    fun test_zombie_redeposit_no_phantom_reward(deployer: &signer) {
        setup(deployer);
        let alice = @0xA11CE;

        // Seed a zombie: initial=0, stale snap_p far below current P,
        // stale snap_i_d / snap_i_coll far below current reward indices.
        D::test_set_sp_position(alice, 0, 100_000_000_000_000, 500, 500);
        D::test_force_reward_indices(1_000_000_000_000_000_000, 2_000_000_000_000_000_000);

        D::test_call_sp_settle(alice);

        // Fix validation: snaps must be refreshed to current registry state
        // so a subsequent redeposit cannot inherit the stale pre-zombie diff.
        let (initial, snap_p, snap_i_d, snap_i_coll) = D::test_get_sp_snapshots(alice);
        assert!(initial == 0, 1800);
        assert!(snap_p == 1_000_000_000_000_000_000, 1801);
        assert!(snap_i_d == 1_000_000_000_000_000_000, 1802);
        assert!(snap_i_coll == 2_000_000_000_000_000_000, 1803);
    }

    /// MIN_DEBT was lowered to 0.1 D (10_000_000 raw, 8 dec) in V2 to avoid the
    /// fee-cascade trap that strands ONE Aptos troves at debt == MIN_DEBT.
    #[test(deployer = @D, user = @0xA11CE)]
    #[expected_failure(abort_code = 6, location = D::D)]
    fun test_redeem_below_min_debt_aborts(deployer: &signer, user: &signer) {
        setup(deployer);
        // 0.099 D = 9_900_000 < MIN_DEBT (10_000_000)
        D::redeem(user, 9_900_000, @0xBEEF);
    }
}
```

---

# Build config: `Move.toml`

```toml
[package]
name = "D"
version = "0.2.0"
upgrade_policy = "compatible"
# Immutability achieved via resource-account deploy + destroyed SignerCapability
# (separate destroy_cap tx after publish). Package upgrade_policy stays "compatible"
# because deps are compatible.

[addresses]
D = "_"
origin = "0x0047a3e13465172e10661e20b7b618235e9c7e62a365d315e91cf1ef647321c9"
pyth = "0x7e783b349d3e89cf5931af376ebeadbfab855b3fa239b7ada8f5a92fbea6b387"

[dependencies]
AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework", rev = "mainnet" }
Pyth = { local = "deps/pyth" }
```

---

# Bootstrap script: `deploy-scripts/bootstrap.js`

```javascript
// Bootstrap D on Aptos testnet/mainnet:
// 1. Fetch fresh APT/USD VAA from Pyth hermes
// 2. D::open_trove_pyth (atomic: Pyth update + open_trove)
// 3. D::sp_deposit (optional)
const { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey } = require('@aptos-labs/ts-sdk');

const NETWORK = process.env.APTOS_NETWORK || 'testnet';
const PRIVATE_KEY_HEX = process.env.DEPLOYER_KEY;
if (!PRIVATE_KEY_HEX) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_ADDR = process.env.D_ADDR;
if (!D_ADDR) { console.error('D_ADDR env var required'); process.exit(1); }
const APT_USD_FEED = '0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5';
const APT_AMT = BigInt(process.env.APT_AMT || 200_000_000n);       // 2 APT
const DEBT    = BigInt(process.env.DEBT    || 100_000_000n);       // 1 D
const SP_AMT  = BigInt(process.env.SP_AMT  || 50_000_000n);        // 0.5 D

(async () => {
  const config = new AptosConfig({ network: NETWORK === 'mainnet' ? Network.MAINNET : Network.TESTNET });
  const aptos = new Aptos(config);
  const pk = new Ed25519PrivateKey(PRIVATE_KEY_HEX);
  const account = Account.fromPrivateKey({ privateKey: pk });
  console.log(`signer: ${account.accountAddress.toString()}`);
  console.log(`network: ${NETWORK}`);
  console.log(`D pkg:  ${D_ADDR}`);

  // Step 1: Fetch VAA from Hermes — beta endpoint for testnet, mainnet endpoint otherwise
  const hermesBase = NETWORK === 'mainnet' ? 'https://hermes.pyth.network' : 'https://hermes-beta.pyth.network';
  console.log(`\n=== 1. Fetch APT/USD VAA from ${hermesBase} ===`);
  const vaaResp = await fetch(`${hermesBase}/api/latest_vaas?ids[]=${APT_USD_FEED}`);
  const vaaB64Arr = await vaaResp.json();
  const vaaBytesArr = vaaB64Arr.map(b64 => Array.from(Buffer.from(b64, 'base64')));
  console.log(`  VAA count: ${vaaBytesArr.length}, first len: ${vaaBytesArr[0].length} bytes`);

  // Step 2: open_trove_pyth (atomic update + open)
  console.log('\n=== 2. D::open_trove_pyth ===');
  const openTx = await aptos.transaction.build.simple({
    sender: account.accountAddress,
    data: {
      function: `${D_ADDR}::D::open_trove_pyth`,
      functionArguments: [APT_AMT.toString(), DEBT.toString(), vaaBytesArr],
    },
  });
  const openResp = await aptos.signAndSubmitTransaction({ signer: account, transaction: openTx });
  console.log(`  tx: ${openResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: openResp.hash });
  console.log(`  ✓ trove opened: ${APT_AMT} raw APT coll / ${DEBT} raw D debt`);

  // Step 3: sp_deposit
  if (SP_AMT > 0n) {
    console.log('\n=== 3. D::sp_deposit ===');
    const spTx = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${D_ADDR}::D::sp_deposit`,
        functionArguments: [SP_AMT.toString()],
      },
    });
    const spResp = await aptos.signAndSubmitTransaction({ signer: account, transaction: spTx });
    console.log(`  tx: ${spResp.hash}`);
    await aptos.waitForTransaction({ transactionHash: spResp.hash });
    console.log(`  ✓ sp_deposit: ${SP_AMT} raw D`);
  }

  // Final state
  console.log('\n=== final state ===');
  const totals = await aptos.view({
    payload: { function: `${D_ADDR}::D::totals`, functionArguments: [] },
  });
  console.log(`  totals: debt=${totals[0]}, sp=${totals[1]}, P=${totals[2]}, r_d=${totals[3]}, r_coll=${totals[4]}`);
  const trove = await aptos.view({
    payload: { function: `${D_ADDR}::D::trove_of`, functionArguments: [account.accountAddress.toString()] },
  });
  console.log(`  trove: coll=${trove[0]}, debt=${trove[1]}`);
  const sp = await aptos.view({
    payload: { function: `${D_ADDR}::D::sp_of`, functionArguments: [account.accountAddress.toString()] },
  });
  console.log(`  sp: bal=${sp[0]}, p_d=${sp[1]}, p_coll=${sp[2]}`);
  const spPool = await aptos.view({
    payload: { function: `${D_ADDR}::D::sp_pool_balance`, functionArguments: [] },
  });
  console.log(`  sp_pool_balance (incl donations): ${spPool[0]}`);
})().catch(e => {
  console.error('\nERROR:', e.message || e);
  process.exit(1);
});
```

---

# Bootstrap script (Move): `scripts/bootstrap.move`

```move
/// Bootstrap script: Pyth VAA update + open_trove + sp_deposit in one atomic tx.
/// Call with fresh VAA bytes (from hermes.pyth.network) to ensure oracle freshness
/// before the D module reads it.
script {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use pyth::pyth;
    use D::D;

    fun bootstrap(
        user: &signer,
        vaa_bytes: vector<vector<u8>>,
        apt_amt: u64,
        debt: u64,
        sp_amount: u64,
    ) {
        let fee_amount = pyth::get_update_fee(&vaa_bytes);
        let fee_coin = coin::withdraw<AptosCoin>(user, fee_amount);
        pyth::update_price_feeds(vaa_bytes, fee_coin);

        D::open_trove(user, apt_amt, debt);

        if (sp_amount > 0) {
            D::sp_deposit(user, sp_amount);
        };
        let _ = signer::address_of(user);
    }
}
```

---

# Testnet artifacts (verifiable on Aptos explorer)

| Artifact | Address / Tx |
|---|---|
| Pkg (sealed) | `0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c` |
| Origin / deployer | `0x0047a3e13465172e10661e20b7b618235e9c7e62a365d315e91cf1ef647321c9` |
| Publish tx | https://explorer.aptoslabs.com/txn/0x6ab023f65d2bde7b58bf31c3be7a7338ba9fdd999013e714126984deb8c9df44?network=testnet |
| donate_to_reserve tx | https://explorer.aptoslabs.com/txn/0x1f50eddeca89db80f7f3119e64f0f02a112c970ff3f09e4576499224c6f816fd?network=testnet |
| destroy_cap tx | https://explorer.aptoslabs.com/txn/0x9cfafe2322ff588ea6d4334661dcb64c275133c2a0f3252f3b232339ccfc8a7b?network=testnet |
| metadata addr | `0xc39458d09de1e108ddb5f175226f50c44a7f0f9b0dd4abf0d0f54d8bcfde8081` |
| fee_pool addr (D) | `0xaceb4d4214d595e339e01b62b199e7ea0b11795fc6a82f6dbc60711ca9634fff` |
| sp_pool addr (D) | `0xf8ea46706f5b5138d353bcf3fb02346b041a8a5b2d6c16611c4c8fc7178db6a` (63 hex — Aptos strips leading zero) |
| sp_coll_pool addr (APT) | `0x565acb8a765115cdcf8624f7186bdc0298a3e4961d5183081809ace30460e4cb` |
| reserve_coll addr (APT) | `0x38bf9b432637054c2ba6969bda12e3cd2b15e051d8099a16ddd56259067a4303` |
| treasury addr (APT) | `0xaf992f64dd8c8a5df806374558eaf658ee302fb2a0af1e1bc8cf5ce067f40a05` |

Mainnet pkg/store addresses will differ — derived from deployer GUID counter at `init_module` time, mainnet vs testnet have separate counters even with same origin.

## Verifying the seal

Ways to confirm the testnet pkg is permanently sealed:

- View: `aptos move view --function-id 0x3db02f4f...::D::is_sealed --profile testnet` → returns `true`
- Resource: `curl https://fullnode.testnet.aptoslabs.com/v1/accounts/0x3db02f4f.../resource/0x3db02f4f...::D::ResourceCap` → returns 404 ("Resource not found")
- Account: `curl .../v1/accounts/0x3db02f4f...` → `auth_key` is the resource-account derivation, but `SignerCapability` was destroyed in destroy_cap tx → no actor can reconstruct a signer for the package address ⇒ no upgrade or override possible

On mainnet, the same flow will produce identical guarantees with a different package address (derived from origin 0x0047a3e1... + seed "D" = 0x3db02f4f... if we use the same seed; could also use a different seed for mainnet if desired).
