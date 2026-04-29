# Auditor: Qwen3.6 (External LLM Audit Assistant)
# Round: R1
# Verdict: **GREEN** ✓

---

## Findings

### HIGH
- *None identified*

### MEDIUM
- *None identified*

### LOW
- **[LOW-1: Integer division precision loss in fee calculation]** — `route_fee_fa:237`: `donate_amt = (((amt as u128) * 1000) / 10000) as u64` uses integer division, which can lose up to 1 raw unit (0.00000001 D) per fee extraction. At MIN_DEBT scale (10_000_000 raw), max loss = 1 raw unit = negligible economic impact. Recommendation: Document this behavior in code comments for transparency.

### INFO
- **[INFO-1: Oracle dependency is single point of failure]** — Pyth feed ID `0x03ae4d...` is hardcoded. If de-registered or stale, oracle-dependent entries freeze. This is documented in `WARNING` paragraph (8) and is by-design for immutability. No mitigation possible without breaking immutability guarantee.
- **[INFO-2: u256 saturation in sp_settle]** — Rewards saturate at `u64::MAX` rather than aborting. Per design, this prevents permanent position lock but silently truncates "astronomical" accruals. Acceptable trade-off documented in code comments.
- **[INFO-3: Primary store auto-creation gas variance]** — `primary_fungible_store::withdraw` auto-creates stores on first call, causing slightly higher gas for new users. Standard Aptos FA behavior; no security impact.

---

## Math Invariant Verification

- [x] **route_fee_fa 10/90 split semantics correct** — 10% to `sp_pool` as agnostic donation, 90% to fee accumulator (or sp_pool at cliff). Integer math verified; pro-rata distribution preserved.
- [x] **liquidate denominator pool_before correct** — Uses `fungible_asset::balance(r.sp_pool)` for absorption calculation, enabling donations to participate pro-rata. Scaled `total_sp_new` formula matches D Sui V2.
- [x] **truncation guard placement correct (D.move:498)** — Guard `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` placed after `total_sp_new` calculation, before state mutation. Reproducer test `test_truncation_decoupling_aborts` exercises exact PoC.
- [x] **cliff orphan redirect correct (D.move:520-525)** — When `total_before == 0`, seized collateral redirects to `reserve_coll` instead of `sp_coll_pool`, preventing unclaimable accumulation. Logic matches D Sui sealed mainnet.
- [x] **MIN_DEBT lowering safe** — 0.1 D (10_000_000 raw) scale: 1% fee = 100_000 raw, well within u64 bounds. Fee-cascade trap rationale sound: external rescuer needs ~$0.10 vs ~$1.01 previously. No overflow/economic vulnerabilities identified.
- [x] **donor address threading correct (3 call sites)** — `open_impl`, `redeem_impl`, `redeem_from_reserve` all pass `signer::address_of(user)`. `SPDonated` event reflects actual caller in all paths including cliff redirect.

---

## Aptos Translation Review

- [x] **FA framework usage correct (deposit/withdraw paths)** — `fungible_asset::extract`, `deposit`, `withdraw`, `primary_fungible_store::withdraw` used consistently. Extract chain in `liquidate` correctly splits seized collateral.
- [x] **resource-account derivation correct** — `resource_account::retrieve_resource_account_cap` in `init_module`, `destroy_cap` consumes `SignerCapability` and drops `ResourceCap`. Post-seal, no actor can reconstruct signer for `@D`.
- [x] **primary_fungible_store auto-create on first donate** — Standard Aptos behavior; no reentrancy hooks. Verified by ONE Aptos v0.1.3 mainnet operation.
- [x] **view fn correctness (5 store addresses + sp_pool_balance)** — Each `*_addr()` returns `object::object_address(&store)`. Test `test_store_addresses_distinct_and_stable` verifies 15 pairwise distinctness checks + stability.
- [x] **sealing equivalence to D Sui make_immutable** — Resource-account + `destroy_cap` achieves cryptographic immutability equivalent to Sui's `make_immutable(UpgradeCap)`. `Move.toml` `upgrade_policy = "compatible"` is for dep compatibility; real immutability at resource-account layer.

---

## Attack Surface

### New Surface Assessment
| Entry | Risk | Assessment |
|-------|------|-----------|
| `donate_to_sp` | Low | Permissionless; only writes to `sp_pool` balance + emits event. Does NOT increment `total_sp` (prevents dilution). No privileged state writes. |
| `donate_to_reserve` | Low | Permissionless APT donation; only writes to `reserve_coll` + emits event. Oracle-free path useful during freeze. |

### Modified Surface Assessment
| Entry | Risk | Assessment |
|-------|------|-----------|
| `route_fee_fa` | Low | New `donor` param + 10/90 split logic. All call sites verified; cliff path donor threading correct. No new reentrancy windows. |
| `liquidate` | Low | `pool_before` denominator + truncation guard + cliff redirect. Math verified; guard prevents DoS. Collateral distribution logic unchanged. |

### Issues Considered (Beyond Self-Audit)
- Gas cost variance for FA auto-creation: Aptos-specific, negligible security impact.
- Front-running on liquidate: Inherent to CDP design; not introduced by V2 port.
- Pyth VAA manipulation: Documented oracle risk; contract cannot mitigate without breaking immutability.
- Integer truncation in fee calc: <1 raw unit loss; economically negligible at all scales.

---

## Recommendation

**Proceed to R2 / External Audit Submission**

The D Aptos v0.2.0 submission demonstrates:
1. Correct porting of D Sui V2 design invariants to Aptos FA dialect
2. Comprehensive self-audit with 29/29 passing tests covering V1 inheritance + V2-specific logic
3. Proper handling of HIGH-1 truncation guard port with reproducer test
4. Sound economic rationale for MIN_DEBT lowering (fee-cascade trap fix)
5. Clean Aptos-specific translations (resource-account sealing, FA primitives, donor threading)
6. Oracle-free testnet rehearsal validating publish → donate → seal flow

No HIGH/MEDIUM findings. One LOW finding (integer precision) is economically negligible. All INFO items are documented design trade-offs.

**Next steps**:
1. Submit to 5 fresh external LLM auditors (including Claude Opus 4.7 fresh for truncation guard second-look)
2. Finalize mainnet deploy parameters (resource-account seed, Pyth dep pin, bootstrap values)
3. Update frontend/Darbitex SPA for D module integration (MIN_DEBT=10_000_000, FEE_BPS=100)

---

## Optional Notes

- The self-audit is exceptionally thorough and well-structured. The inline code comments, test coverage, and diff documentation exceed typical submission quality.
- The `WARNING` constant is comprehensive and appropriately prominent — critical for an immutable contract.
- Consider adding a brief comment at `route_fee_fa:237` documenting the integer division behavior for future maintainers.
- Testnet rehearsal wisely pivoted to oracle-free smoke due to Pyth feed ID mismatch; mainnet smoke will provide final empirical validation for oracle-dependent paths.

**Confidence Level**: High — The combination of inherited audit history (D Sui R1-R2 GREEN, ONE Aptos R1-R4 GREEN), rigorous self-audit, comprehensive test coverage, and correct Aptos-specific translations supports proceeding to external audit submission.
