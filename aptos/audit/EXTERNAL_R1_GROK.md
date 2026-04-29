# Auditor: Grok (xAI) — Manual source review + framework cross-check (R1)
# Round: R1
# Verdict: GREEN

The submission is a high-quality, well-documented port of the sealed D Sui v0.2.0 design (with its audited V2 fee/donation/liquidation mechanics and HIGH-1 truncation guard) onto the **ONE Aptos v0.1.3** sealing + resource-account model, using Aptos **Fungible Asset (FA)** primitives. The self-audit is thorough, tests are targeted and comprehensive (including regression, V2-specific, cliff, truncation, donation non-dilution, and composability checks), and the code is clean, consistent, and defensively written.

No critical or high-severity issues were identified. The changes are intentional, minimal, and well-justified. The **MIN_DEBT** reduction to 0.1 D meaningfully improves user experience without introducing new economic or arithmetic risks at the implemented scale. The new donation surfaces and view functions are low-risk and additive.

### Findings

**No HIGH, MEDIUM, LOW, or INFO findings requiring fixes.**

All self-audit claims hold under review:

- **Math invariants** (route_fee_fa 10/90 split, liquidate scaled denominator using `pool_before`, truncation guard at the exact equivalent location, cliff orphan redirect to `reserve_coll`) are correctly ported and preserved. The `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` at the post-calculation point (mirroring D Sui) prevents the decoupling DoS. Cliff predicate uses `r.total_sp == 0` (correct, as donations do not increment it).
- **MIN_DEBT lowering** is safe: fee math (1% = 100_000 raw on 10_000_000 debt) stays well within u64/u128 bounds; existing saturation logic and guards cover edge cases. The fee-cascade rescue rationale is sound and improves bootstrappability without weakening the 1% close-cost mechanic.
- **donor: address threading** is correct across all three `route_fee_fa` call sites (`open_impl`, `redeem_impl`, `redeem_from_reserve`). `SPDonated` events always reflect the transaction sender (`signer::address_of(user)`). Cliff-path donor is also the caller.
- **Composability views** (`*_addr()`) correctly return `object::object_address(&store)` for the five `FungibleStore`s. The six addresses (metadata + stores) are derived sequentially via `object::create_object` in `init_module_inner` and are guaranteed distinct + stable (confirmed by test and object model). `sp_pool_balance()` usefully exposes donation delta.
- **Sealing equivalence**: Resource-account + `destroy_cap` (consuming `SignerCapability` from `Option` and dropping `ResourceCap` resource) achieves the same permanent immutability as Sui's `make_immutable(UpgradeCap)`. Post-`destroy_cap`, no signer for `@D` can be reconstructed (`is_sealed()` flips, ResourceCap 404s). `upgrade_policy = "compatible"` is appropriate given the Pyth dep; real immutability is at the resource-account layer. Testnet rehearsal confirms this flow.

### Math invariant verification
- [x] route_fee_fa 10/90 split semantics correct (donate_amt extracted first, remainder routed; cliff redirects 90% to `sp_pool` as agnostic donation).
- [x] liquidate denominator `pool_before` (live `sp_pool` balance) correct — donations absorb pro-rata.
- [x] truncation guard placement correct (post-scaled `total_sp_new` calc, aborts on decoupling case).
- [x] cliff orphan redirect correct (`total_before == 0` → `reserve_coll`; otherwise `sp_coll_pool`).
- [x] MIN_DEBT lowering safe (no new overflows; improves UX).
- [x] donor address threading correct (3 call sites).

### Aptos translation review
- [x] **FA framework usage correct**: `primary_fungible_store::withdraw` (auto-creates primary stores on first use for recipients), `fungible_asset::deposit`/`extract`/`withdraw` (with signer from `ExtendRef` for internal pools), `MintRef`/`BurnRef` usage, and atomic `withdraw → process → deposit/burn` patterns follow Aptos best practices. No unsafe raw store manipulation. Fee extraction via `extract(&mut fa, donate_amt)` mirrors `balance::split` semantics. Seized collateral splitting via repeated `extract` is safe and atomic within the transaction.
- [x] resource-account derivation and `init_module`/`destroy_cap` correct.
- [x] `primary_fungible_store` auto-create behavior on first `donate_to_reserve` / recipient deposits is standard and expected.
- [x] view fn correctness (5 store addresses + `sp_pool_balance`) confirmed.
- [x] sealing equivalence to D Sui `make_immutable` confirmed.

**Reentrancy / interactions**: No external Move calls occur between critical state mutations. Pyth `update_price_feeds_with_funder` runs *before* `borrow_global_mut<Registry>`. FA `deposit`/`withdraw` are atomic within the borrow scope. No hooks/callbacks on `primary_fungible_store::deposit` to arbitrary addresses. Move's resource model + Aptos VM protections reinforce this.

**New attack surface** (`donate_to_sp`, `donate_to_reserve`): Pure permissionless contributions. `donate_to_sp` joins `sp_pool` balance only (no `total_sp` increment → no dilution, as tested). `donate_to_reserve` fortifies oracle-free redemption capacity. Both abort cleanly on `amt == 0`. No privileged state writes. `SPDonated`/`ReserveDonated` events provide good provenance.

**Modified surface** (`route_fee_fa`, `liquidate`): Changes are isolated to V2 design (already externally validated on Sui) + Aptos FA dialect. Donation cliff path and truncation guard explicitly mitigate prior HIGH-1. No regressions vs. ONE Aptos v0.1.3 (cliff `product_factor` freeze, saturation, reset-on-empty, etc., all preserved and tested).

**Oracle considerations**: `price_8dec()` + `get_price_no_older_than` + confidence cap + staleness checks are standard and defensive (multiple distinct error codes). Pyth Aptos immutability (auth_key=0x0) noted correctly. Oracle-free escape hatches (`close_trove`, `add_collateral`, SP management, donations) remain fully functional, as documented in WARNING.

**Other notes**:
- Integer math uses safe patterns (`u128` intermediates, explicit casts, saturation for rewards). No unchecked operations that could overflow in realistic scenarios.
- Events, WARNING text updates, rebrands (`one_*` → `d_*`), and ABI cosmetic changes are consistent.
- Tests cover the diff surface thoroughly, including V1/V2 simulator parity and edge reproducers.
- Testnet rehearsal (publish + donate + destroy_cap) validates core flows.

### Recommendation
**Proceed to mainnet deployment (after final mainnet smoke with oracle-dependent paths)**. This is a clean, low-risk port. The design inherits strong audit history on both lineages, and the Aptos-specific translation is faithful and idiomatic.

**Optional / nice-to-have (non-blocking)**:
- Run one more fresh heavy model (e.g., Claude Opus 4.7) focused solely on the truncation guard port + donation/liquidation interplay under extreme donation ratios.
- Mainnet smoke: full `open_trove_pyth` → fee routing → `sp_claim` → `liquidate_pyth` cycle with real Pyth VAA.
- Consider exposing a `sp_pool_donation_balance()` or similar if indexers need finer donation tracking (current `sp_pool_balance()` vs `total_sp` already suffices).

The code is exemplary for an immutable stablecoin port — defensive, well-tested, and transparent. Excellent work on the self-audit and submission bundle.

**Optional notes**: The WARNING paragraph is one of the most comprehensive and honest oracle-dependency disclosures I've seen. The retail-first ethos (flat 1% fee, no sorted troves, low MIN_DEBT) is preserved while fixing the identified fee-cascade UX trap.

Ready for R2 / mainnet if external passes align.
