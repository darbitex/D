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
