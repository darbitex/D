# Auditor: Kimi K2.6 (Moonshot AI)
# Round: R1
# Verdict: GREEN

## Findings

### HIGH
- None.

### MEDIUM
- None.

### LOW
- None.

### INFO
- None.

---

## Math invariant verification

| Invariant | Status | Notes |
|---|---|---|
| `route_fee_fa` 10/90 split semantics correct | ✅ | `donate_amt = amt * 1000 / 10000` (10%). Remainder `sp_amt` goes to fee_pool when `total_sp > 0`, else cliff redirect to sp_pool. Matches D Sui V2 exactly. |
| `liquidate` denominator `pool_before` correct | ✅ | Uses `fungible_asset::balance(r.sp_pool)` (live balance incl. donations) rather than `r.total_sp`. Scaled formula `total_before * (pool_before - debt) / pool_before` preserves pro-rata keyed share while absorbing donations. |
| Truncation guard placement correct (`D.move:498`) | ✅ | `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` placed immediately after `total_sp_new` computation, before any state mutation. Identical placement to D Sui sealed mainnet. |
| Cliff orphan redirect correct (`D.move:520-525`) | ✅ | `if (total_before == 0) { deposit(r.reserve_coll, seized) } else { deposit(r.sp_coll_pool, seized) }`. Prevents unclaimable collateral accumulation when no keyed depositors exist. |
| MIN_DEBT lowering safe | ✅ | `10_000_000` (0.1 D). 1% fee = 100_000 raw — well within u64. Fee-cascade trap correctly addressed: rescuer needs ~$0.10 external D vs ~$1.01 previously. No algebraic overflow risk. |
| Donor address threading correct (3 call sites) | ✅ | `open_impl` → `user_addr`, `redeem_impl` → `signer::address_of(user)`, `redeem_from_reserve` → `signer::address_of(user)`. All pass actual transaction sender. |

---

## Aptos translation review

| Item | Status | Notes |
|---|---|---|
| FA framework usage correct (deposit/withdraw paths) | ✅ | `fungible_asset::extract`/`deposit` chain correctly replaces Sui's `balance::split`/`join`. `primary_fungible_store::withdraw` auto-creates stores on first call (Aptos framework guarantee). No `public_transfer` usage. |
| Resource-account derivation correct | ✅ | `resource_account::retrieve_resource_account_cap` in `init_module`, stashed in `ResourceCap`. `destroy_cap` consumes `SignerCapability` via `option::destroy_some`. Pattern matches V1 ONE Aptos mainnet seal. |
| `primary_fungible_store` auto-create on first donate | ✅ | Confirmed: `primary_fungible_store::withdraw` creates store if absent; `deposit` to arbitrary address (e.g. `liquidate` target remainder) also auto-creates. No manual store initialization needed. |
| View fn correctness (5 store addresses + `sp_pool_balance`) | ✅ | Each `*_addr()` returns `object::object_address(&store)` — stable GUID-derived addresses. `sp_pool_balance()` returns `fungible_asset::balance(r.sp_pool)` — correctly exposes donation-vs-keyed delta. |
| Sealing equivalence to D Sui `make_immutable` | ✅ | Resource-account + `destroy_cap` achieves cryptographic immutality: no signer reconstructable for `@D` after cap destruction. `Move.toml` `upgrade_policy = "compatible"` is a dep-chain necessity (Pyth compat); real seal is at account layer. Verified on testnet: `ResourceCap` 404 post-destroy_cap. |

---

## Attack surface

### New surface assessment

| Entry | Risk | Analysis |
|---|---|---|
| `donate_to_sp` | Very Low | Permissionless, no privileged state. Increases `sp_pool` balance without diluting `total_sp` — correct per V2 design. Cannot grief keyed depositors (donations absorb debt in liquidation but don't steal yield). Zero amount aborts (`E_AMOUNT`). |
| `donate_to_reserve` | Very Low | Permissionless APT donation to `reserve_coll`. Fortifies `redeem_from_reserve` capacity. No oracle dependency — works during freeze. Zero amount aborts. |
| `sp_pool_balance()` view | None | Read-only. Exposes public state. |

### Modified surface assessment

| Entry | Risk | Analysis |
|---|---|---|
| `route_fee_fa` | Low | 10/90 split + cliff redirect. Donor threading verified. No reentrancy (atomic within borrow scope). |
| `liquidate` | Low | `pool_before` denominator correctly includes donations. Truncation guard prevents HIGH-1 decoupling. Cliff orphan redirect prevents unclaimable accumulation. |

### Issues considered but not found

- **Donation griefing**: `donate_to_sp` cannot be used to freeze liquidations — it increases `pool_before`, making `pool_before > debt` *easier* to satisfy, not harder.
- **MIN_DEBT bypass**: `redeem`/`redeem_from_reserve` enforce `d_amt >= MIN_DEBT` (`E_AMOUNT`). Post-redeem trove debt checked `== 0 || >= MIN_DEBT` (`E_DEBT_MIN`).
- **Truncation in fee split**: `donate_amt = (amt * 1000) / 10000` — if `amt < 10`, `donate_amt = 0`, entire fee goes to accumulator/cliff. Acceptable (sub-atomic dust).
- **Pyth confidence cap**: `MAX_CONF_BPS = 200` (2%) carried forward from V1. Correct.
- **u64 saturation in `sp_settle`**: `raw_d`/`raw_coll` capped at `u64::MAX` with `RewardSaturated` event. Prevents permanent lock. Carried from V1.
- **Reset-on-empty**: `sp_deposit` resets `product_factor = PRECISION` when `total_sp == 0`. Verified in `test_sp_deposit_resets_product_factor_when_empty`.

---

## Recommendation

**Proceed to R2.** No fixes required.

---

## Optional notes

1. **Testnet rehearsal completeness**: Oracle-dependent paths (`open_trove_pyth`, `redeem_pyth`, `liquidate_pyth`, `donate_to_sp` with minted D) were deferred to mainnet smoke per submitter notes. This is acceptable given: (a) math is unit-tested and matches D Sui sealed mainnet, (b) Pyth testnet/mainnet feed ID mismatch is a known environmental constraint, (c) oracle-free paths (`donate_to_reserve`, views, sealing) validated end-to-end.

2. **V1 regression coverage**: The `test_zombie_redeposit_no_phantom_reward` test (R2-C01 from V1 lineage) confirms stale snapshot refresh for zero-balance positions — important for composability safety if a user fully withdraws then redeposits later.

3. **Composability gap fix**: The 5 store-address view functions directly address the pre-seal requirement from `feedback_core_composability_gap.md`. Indexers can now subscribe to `Withdraw`/`Deposit` events per `FungibleStore` object without reading `Registry`.

4. **Sealing verification**: On testnet, `is_sealed()` returns `true` and `ResourceCap` resource is 404 at `0x3db02f4f...`, confirming the `destroy_cap` flow works as designed. Mainnet will use identical logic with a different resource-account address (origin + seed derivation).
