# Auditor: Gemini
# Round: R1
# Verdict: GREEN

## Findings

### HIGH
- **None.** The V2 invariants and truncation guards have been perfectly preserved in the FA port, and no new structural vulnerabilities were introduced in the Aptos translation.

### MEDIUM
- **None.**

### LOW
- **None.**

### INFO
- **[INFO-1: `donate_amt` integer truncation at dust limits]** — *D.move:240*. The calculation `let donate_amt = (((amt as u128) * 1000) / 10000) as u64;` works flawlessly for standard operational sizes. If `amt` drops below 10 (which is 0.00000010 D), `donate_amt` truncates to 0, effectively turning a 10/90 split into a 0/100 split for dust amounts. Given `MIN_DEBT` is 10,000,000 and the 1% fee on it is 100,000, this dust limit is virtually unreachable in standard paths (`open`, `redeem`), but could technically occur if a user manually calls an entrypoint with dust FA. This is mathematically safe and economically irrelevant, but noted for absolute completeness.
- **[INFO-2: `primary_fungible_store` auto-creation gas dynamics]** — *Aptos Framework specific*. In `sp_settle` and liquidation distributions, you are depositing directly via `primary_fungible_store::deposit`. If the target address has never held the asset before, the framework silently auto-creates the `PrimaryFungibleStore` under the hood. This adds a slight, one-time gas premium to the transaction for the caller triggering the creation. This is standard Aptos behavior and preferable to forcing manual `register` calls, but worth keeping in mind for your bot/arbitrage gas estimations.

## Math invariant verification
- [x] **route_fee_fa 10/90 split semantics correct:** Verified. `extract` natively handles the split without the awkwardness of Sui's `balance::split`, securely sending 10% to `sp_pool` and passing the remainder downstream.
- [x] **liquidate denominator pool_before correct:** Verified. Shifts from `total_before` to `balance(sp_pool)`, properly accounting for the donation buffer.
- [x] **truncation guard placement correct (D.move:498):** Verified. Catches the exact 1e8/1e9 = 0 scenario and explicitly aborts with `E_P_CLIFF` before the zero infects the registry.
- [x] **cliff orphan redirect correct (D.move:520-525):** Verified. Safe diversion to `reserve_coll`.
- [x] **MIN_DEBT lowering safe:** Verified. At 0.1 D (10,000,000), internal math safely handles fees (100,000) without underflowing. Solves the V1 1-ONE trapping cascade cleanly.
- [x] **donor address threading correct (3 call sites):** Verified. Passes `signer::address_of(user)` consistently; `SPDonated` provenance is intact.

## Aptos translation review
- [x] **FA framework usage correct (deposit/withdraw paths):** Exemplary usage of `ExtendRef`, `MintRef`, and `BurnRef`. The use of `extract` vs `withdraw` accurately reflects FA best practices over older `transfer` models.
- [x] **resource-account derivation correct:** Objects derived sequentially from `signer::address_of(deployer)` correctly bind to the `@D` resource account context.
- [x] **primary_fungible_store auto-create on first donate:** Handled correctly by the Aptos framework's standard `deposit` wrapper.
- [x] **view fn correctness (5 store addresses + sp_pool_balance):** Verified distinct and stable.
- [x] **sealing equivalence to D Sui make_immutable:** The `destroy_cap` function flawlessly consumes the staged capability option and drops the struct. True immutability is achieved.

## Attack surface
- **New surface assessment (`donate_to_sp`, `donate_to_reserve`):** Permissionless, no admin paths, strictly additive. Neither modifies privileged registry tracking (`total_sp`, `total_debt`), so no yield dilution or oracle manipulation is possible.
- **Modified surface assessment (`route_fee_fa`, `liquidate`):** The port correctly insulates V2's `pool_before` calculations from the new Aptos stores.
- **Issues considered:** Reentrancy checks pass due to the absence of Aptos FA framework callbacks. No arbitrary code execution window exists between the `borrow_global_mut` bounds.

## Recommendation
- **Proceed to R2 / Mainnet deployment.** The patch cycle is clean, and the dialect port correctly mirrors the sealed V2 logic. Standardize your mainnet derivation seeds, verify your Pyth feed IDs locally, and proceed with confidence.
