# Auditor: Claude Opus 4.7 (Anthropic, model `claude-opus-4-7`)
# Round: R1
# Verdict: **GREEN**

## Findings

### HIGH
None.

### MEDIUM
None.

### LOW

**L1 — `test_route_fee_cliff_path_pure_donation` does not exercise the production cliff path.**
Location: `tests/D_tests.move:1571-1581`.
The test name claims to test the cliff redirect (90% portion → `sp_pool` as `SPDonated`), but the body uses `test_route_fee_virtual`, whose body short-circuits when `total_sp == 0`:
```move
if (r.total_sp == 0) return;
```
So the assertion `r_d_after == 0` is trivially true and proves nothing about the production cliff path in `route_fee_fa` (lines 661-666 of bundle: `if (r.total_sp == 0) { deposit(r.sp_pool, fa); emit SPDonated{...} }`). The production cliff redirect is therefore **only** validated by inheritance from D Sui's sealed mainnet — it has no local Move unit test on the Aptos port.
Impact: Low (the inherited math is identical and the path is mechanically simple), but the gap should be closed before mainnet smoke.
Recommendation: Add a `#[test_only] public fun test_route_fee_real(amt)` that mints + calls `route_fee_fa` directly, then asserts `sp_pool_balance` grew by the full amount and `reward_index_d` is unchanged at cliff. Same pattern can also assert donor field on the `SPDonated` event.

**L2 — `AptosFramework` dep pinned to a moving branch.**
Location: `Move.toml:1770`.
```toml
AptosFramework = { ..., rev = "mainnet" }
```
`mainnet` is a branch, not a commit. Two builds days apart can resolve to different framework code, undermining audit reproducibility. The Pyth dep is `local = "deps/pyth"` which is fine, but the framework should be pinned.
Recommendation: Replace `rev = "mainnet"` with the specific commit hash you're building against (and record it in the audit bundle for reproducibility). The same `aptos-core` repo will host that commit forever.

**L3 — Donor field on `SPDonated` event not asserted in any test.**
The `donor: address` parameter threading through `route_fee_fa` is covered by code review (3 call sites all pass `signer::address_of(user)` correctly), but no test catches the `SPDonated` event and verifies its `donor` field. Given that this is one of the explicit V2 deltas the cover letter asks the auditor to verify (audit goal #3), an event-level assertion would be appropriate.
Recommendation: Add a test that calls `donate_to_sp(alice, x)` then asserts `event::emitted_events<SPDonated>()` contains an event with `donor == @alice`. Aptos' `event` module exposes `emitted_events_by_handle` / `emitted_events` for testing.

### INFO

**I1 — Documentation drift on test count and source LOC.**
- Cover letter §"Build status" says **30/30 PASS** and §"Test coverage" lists "21 V1 inheritance + 9 V2-specific + 1 composability = **31**".
- Self-audit line 192 says **29 tests, 29 pass**.
- Actual test file contains **30** `#[test]` functions (counted manually).
- Cover letter §"839-line source" vs self-audit §"760 LOC" for the same `D.move` file.

These are documentation/changelog drifts, not bugs. Reconcile before publishing the bundle externally.

**I2 — Truncation guard line reference is stale.**
Cover letter and audit goal #4 reference "`D.move:498`" for the truncation guard. In the bundled source, the guard is at the equivalent of bundle line 878. The actual D.move line number depends on the working copy and likely drifted. Suggest re-pinning by anchor (e.g., "the `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` immediately following the `total_sp_new` computation in `liquidate`") rather than line numbers.

**I3 — `total_sp` vs Σ`pos.initial_balance` drift after multi-depositor liquidation.**
Inherited from V1, also present in D Sui. Concrete example: `total_before=10`, two depositors with `initial=5` each, debt=3, `pool_before=10`. After settle, each per-user effective truncates to `5*7e17/1e18 = 3` (sum=6), but `total_sp_new = 10*7/10 = 7`. After both fully withdraw, `r.total_sp = 1` while no positions exist. This 1 raw unit is functionally stranded:
- It does not match any `sp_positions` entry, so no future `sp_withdraw` can claim it.
- The `reset-on-empty` clause in `sp_deposit` (line 948) only fires when `total_sp == 0` exactly, so a stuck-at-1 state will not auto-reset.
- A new `sp_deposit` on top will inherit the stuck `product_factor` and the asymmetry persists.

Bound: per liquidation event, drift is at most `(N-1)` raw units where N = number of depositors active at settle. At MIN_DEBT=0.1 D = 1e7 raw, drift of single-digit raw is ~$1e-9. **No exploit, no theft, no DoS** — `liquidate` continues to work because it uses `pool_before`, not `total_sp`, as the burn denominator. Carried forward from V1 sealed (8 audit passes did not flag it) and D Sui sealed (6 audit passes did not flag it). Flagging here for completeness only.

**I4 — `reward_index_d` u128 overflow in pathological sustained-low-`total_sp` scenarios.**
Per-update delta can be up to `sp_amt * 1e18 / total_sp`. With `sp_amt` near u64::MAX/100 ≈ 1.8e17 and `total_sp = 1`, a single update adds ~1.8e35 to the index. After ~2,000 such updates, u128 (max 3.4e38) overflows in `route_fee_fa:668`. Sustained `total_sp = 1` is economically implausible (someone holding 1e-8 D as their entire keyed SP for thousands of fee cycles), and `sp_settle` already uses u256 for downstream multiplications. But if it ever happened, the overflow would cause a hard abort in `route_fee_fa`, blocking all fee-emitting entries (open_trove, redeem, redeem_from_reserve). Documented as known limitation per WARNING (2). No action needed; tagging only.

**I5 — `bootstrap.move` script uses legacy `coin::withdraw<AptosCoin>` for Pyth fee.**
Location: `scripts/bootstrap.move:1888-1890`.
```move
let fee_amount = pyth::get_update_fee(&vaa_bytes);
let fee_coin = coin::withdraw<AptosCoin>(user, fee_amount);
pyth::update_price_feeds(vaa_bytes, fee_coin);
```
This works for users holding APT in the legacy Coin store, but Aptos has been migrating accounts toward FA-only APT (at `@0xa`). FA-only wallets may fail the `coin::withdraw<AptosCoin>` call. The `*_pyth` entries in `D.move` use `pyth::update_price_feeds_with_funder(user, vaas)` which handles both flows automatically. Recommend the script use the same wrapper for consistency.

**I6 — `bootstrap.js` does not validate Hermes response shape.**
Location: `deploy-scripts/bootstrap.js:1807-1810`.
```js
const vaaResp = await fetch(`${hermesBase}/api/latest_vaas?ids[]=${APT_USD_FEED}`);
const vaaB64Arr = await vaaResp.json();
const vaaBytesArr = vaaB64Arr.map(b64 => Array.from(Buffer.from(b64, 'base64')));
```
On Hermes outage or API change, `vaaResp.json()` could yield an error object, an empty array, or non-array JSON. `vaaB64Arr.map` would throw or produce empty `vaaBytesArr`, and the subsequent `open_trove_pyth` would either revert with `E_STALE` or post no VAA. Recommend `if (!Array.isArray(vaaB64Arr) || vaaB64Arr.length === 0) throw new Error('Hermes returned empty VAA');` before the map.

**I7 — WARNING (3) imprecision: "below ~5%" should be ~2.5%.**
At CR=5%, `liq_coll = 0.5 × total_seize_coll` and `reserve_coll = 0.5 × total_seize_coll`, leaving `sp_coll = 0`. Below ~2.5% (where the liquidator's pure share already exceeds total seizable collateral), liquidator takes 100% and reserve gets 0 too. The sentence "At CR below ~5% the liquidator may take the entire remaining collateral, reserve and SP receive zero" conflates "SP gets zero" (CR<5%) with "reserve gets zero" (CR<2.5%). Cosmetic; the protocol behaves correctly.

**I8 — Two `SPDonated` events from a single fee-routing call in cliff path.**
When `total_sp == 0` and `amt > 0`, `route_fee_fa` emits one `SPDonated{donor, donate_amt}` (10% portion) followed by `SPDonated{donor, sp_amt}` (90% portion). Indexers must aggregate these per-tx if they want a "fee event" view. Documented in self-audit §6 ("emitted in 3 distinct sites"). No action; flag for indexer authors.

---

## Math invariant verification

- [x] `route_fee_fa` 10/90 split semantics correct — verified by code trace (lines 650-670) and `test_reward_index_increment_and_pending` numerics (donate=100k, sp_amt=900k, r_d_delta=9e15, pending_d=900k for 1e8 keyed depositor).
- [x] `liquidate` denominator `pool_before` correct — verified at line 866: `let pool_before = fungible_asset::balance(r.sp_pool);`. Both `new_p` and `total_sp_new` use `pool_before` consistently.
- [x] Truncation guard placement correct — assertion `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` immediately follows the `total_sp_new` computation, AFTER the cliff predicate. PoC `test_truncation_decoupling_aborts` exercises it: `pool_before=1e9`, `total_before=1e8`, `debt=999_999_999` → `new_p=1e9` (passes MIN_P_THRESHOLD), `total_sp_new=0` (truncated) → guard aborts with `E_P_CLIFF (14)`. The expected_failure code matches.
- [x] Cliff orphan redirect correct — `liquidate` lines 916-922: when `total_before == 0`, seized `sp_coll` deposited to `reserve_coll` instead of `sp_coll_pool`. Prevents accumulation of unclaimable APT in the SP collateral pool.
- [x] MIN_DEBT lowering safe — at `debt=1e7`: fee=1e5, donate_amt=1e4, sp_amt=9e4, `reward_index_d` delta = `9e4 * pf / total_sp` (no overflow), bonus_usd=1e6, liq/reserve shares=2.5e5 each — all u128 safe. `redeem_impl` self-redemption path: minimum full-clear cost ≈ 0.1010 D (~$0.10), 10× more bootstrappable than V1's ~$1.01. Trap is mitigated, not eliminated, as cover letter states.
- [x] Donor address threading correct — verified at 3 call sites:
  - `open_impl:742` → `route_fee_fa(r, fee_fa, user_addr)` where `user_addr` is the original signer-derived address passed in.
  - `redeem_impl:801` → `let u = signer::address_of(user); route_fee_fa(r, fee_fa, u)`.
  - `redeem_from_reserve:847` → same pattern as redeem_impl.
  Cliff path (line 665) reuses the same `donor` parameter — donor field is consistent across both `SPDonated` emissions in the same call.

---

## Aptos translation review

- [x] FA framework usage correct.
  - `fungible_asset::extract(&mut fa, donate_amt)` (line 655) is the FA equivalent of Sui's `balance::split` — semantics match.
  - `fungible_asset::deposit(r.sp_pool, donate_portion)` deposits into a `Object<FungibleStore>` directly (no `primary_fungible_store::deposit` indirection because we own the store via `ExtendRef`).
  - `primary_fungible_store::withdraw(user, r.metadata, amt)` correctly auto-creates the user's primary store on first use.
  - All FA values are consumed (deposit/burn/destroy_zero) — no leaked `FungibleAsset` resources (FA has `store` but not `drop`).
- [x] Resource-account derivation correct — testnet rehearsal confirms publish at `0x3db02f4f…` from origin `0x0047a3e1…` with seed `D`. Move.toml `D = "_"` substitution path validated end-to-end.
- [x] `primary_fungible_store` auto-create on first donate — `donate_to_sp`/`donate_to_reserve` use `primary_fungible_store::withdraw` which auto-creates the source store if needed. Recipient stores (`sp_pool`/`reserve_coll`) are pre-created at init. ✓
- [x] View fn correctness — all 5 store address views (`fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr`, `treasury_addr`) call `object::object_address(&r.<store>)` with no mutation. `test_store_addresses_distinct_and_stable` asserts all 6 addresses (metadata + 5 stores) pairwise-distinct (15 inequality checks) and stable across calls. Sequential `object::create_object(da)` calls in `init_module_inner` are guaranteed to produce distinct addresses (each derived from the deployer's incrementing GUID counter).
- [x] Sealing equivalence to D Sui `make_immutable`. `destroy_cap` consumes the `SignerCapability` (which has `drop, store` ability in current Aptos framework, so out-of-scope `_sc` is auto-dropped). After destroy_cap: (a) `ResourceCap` resource removed from `@D`, (b) no actor can derive a fresh `SignerCapability` for `@D` since no other framework path reconstructs one for an existing resource account. Equivalent immutability to Sui's UpgradeCap consumption. The `upgrade_policy = "compatible"` in Move.toml is a constraint imposed by the Pyth dep being compat-only, not a sealing weakness — actual sealing is at the account layer. Verified end-to-end on testnet (`is_sealed=true`, ResourceCap GET returns 404).

---

## Attack surface

**New surface: `donate_to_sp`, `donate_to_reserve`.**
- Permissionless, both abort on `amt == 0`.
- No callback or hook: FA `deposit`/`withdraw` do not invoke recipient code. No reentrancy possible.
- Donations are net loss for the donor — there is no claim mechanism. Donor's D becomes part of `sp_pool` balance with no `total_sp` increment, so it absorbs liquidation burns pro-rata and is gradually consumed without producing any reward back to the donor.
- `test_donate_to_sp_no_dilution` confirms keyed depositors' rewards are not affected by donation rate (donations bypass the `reward_index_d` accumulator).
- Self-donation gambit analyzed: an attacker with both keyed SP and a separate donate is strictly worse off than holding the same total as keyed SP, because keyed SP receives all seized collateral while donations receive nothing. No profitable strategy.
- `donate_to_reserve` is oracle-free → callable during Pyth freeze → fortifies escape hatch capacity. Aligns with WARNING (8) intent.

**Modified surface: `route_fee_fa`, `liquidate`.**
- `route_fee_fa` now takes a `donor: address` for `SPDonated` event provenance. All call sites pass authenticated signer addresses; donor cannot be spoofed.
- Cliff path correctly redirects 90% to `sp_pool` and emits a second `SPDonated` event with the same donor. Behavior matches D Sui sealed mainnet.
- `liquidate` denominator switch from `total_sp` to `pool_before` is the V2 invariant change. Combined with the truncation guard, this prevents the HIGH-1 `total_sp == 0` decoupling that Claude Opus 4.7 fresh found in D Sui R1.
- Cliff orphan redirect (sp_coll → reserve_coll when total_before == 0) prevents APT accumulation in an unclaimable pool.
- The 50% liquidation-bonus split (25% liquidator + 25% reserve, with SP residue) is unchanged from V1 and behaves correctly across the CR continuum (verified by trace at CR=150%, 110%, 100%, 5%, 2%).

**Considered and ruled out:**
- Pyth VAA selection / replay (Pyth enforces publish-time monotonicity, signed by Pyth publishers).
- Self-redemption / self-liquidation (math is consistent; user takes economic loss in proportion to bonus paid).
- Donation-during-liquidation race (donations change `pool_before` but cannot make a healthy trove liquidatable; CR check is independent).
- Stale-snapshot zombie redeposit (R2-C01 inheritance regression test `test_zombie_redeposit_no_phantom_reward` confirms snapshots refresh on every `sp_settle`).
- Integer overflow in `coll_usd * 10000`, `bonus_usd`, etc. — all u128 with realistic bounds well below 3.4e38.
- `r.total_debt` underflow — every decrement matches a prior increment, with the documented exception of `redeem_from_reserve` (intentionally does not decrement, widening the supply-vs-debt gap per WARNING (4)).

---

## Recommendation

**Proceed to R2.** No HIGH or MEDIUM findings; the V2 design correctly ports from D Sui sealed mainnet, the Aptos dialect translation is faithful, and the new composability surface (5 view fns + 2 donate entries + `sp_pool_balance` + `donor` event field) is minimal and safe. The HIGH-1 truncation guard from D Sui R1 is preserved with an effective reproducer test.

For R2, address:
- **L1**: Add a real-`route_fee_fa` cliff-path unit test (close the only meaningful test gap on V2-specific surface).
- **L2**: Pin AptosFramework to a specific commit for audit reproducibility.
- **L3**: Add donor-field event assertion test.

I1–I8 are documentation polish or pre-existing inherited characteristics — handle at your discretion before mainnet.

## Optional notes

- The MIN_DEBT lowering rationale is well-argued and does mitigate the W2 fee-cascade trap proportionally, but the trap mechanism itself is structural to flat-fee redemption with a hard floor — it is reduced from $1.01 to $0.10 rescue cost, not eliminated. Future iterations might consider a graduated minimum (e.g., MIN_DEBT scales with TVL or decays toward 0 under specific conditions), but that's outside the scope of this port and would require fresh audit lineage.
- The decision to keep `upgrade_policy = "compatible"` and rely on resource-account sealing is correct given Aptos' "all deps must be immutable" rule. Worth documenting prominently in user-facing materials that immutability on Aptos is account-layer, not package-policy-layer — this is non-obvious to users coming from Sui, and the WARNING (8) wording "cryptographically immutable" is accurate but could be expanded with a one-liner explaining the dual-layer model.
- The testnet rehearsal correctly validated everything that does not require oracle. The deferred mainnet smoke (open_trove_pyth → first real fee → first real route_fee_fa with non-zero `total_sp`) is the last empirical gap; given the math is unit-tested and matches D Sui sealed, the gap is acceptable for R1 submission, but should be the very first action post-mainnet-deploy before any user-facing announcement.
