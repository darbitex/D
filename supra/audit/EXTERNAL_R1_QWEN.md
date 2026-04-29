# Auditor: Qwen3.6
# Round: R1
# Verdict: 🟢 GREEN

## Findings

### HIGH
- **None identified**. The 6 porting deltas have been reviewed and no critical vulnerabilities were found.

### MEDIUM
- **None identified**. All medium-severity concerns from the self-audit are either inherited from the audited D Aptos baseline (GREEN) or are accept-by-design disclosures.

### LOW
- **L-01: No oracle confidence-band check** — Supra's push oracle returns a single aggregated value without an explicit confidence interval, unlike Pyth's `conf` field. If the Supra Foundation's median aggregator behaves erratically (e.g., thin-source conditions causing >20% deviation), D Supra will accept the value.
  - *Location*: `price_8dec()` function, oracle validation logic
  - *Impact*: Potential for price manipulation if oracle sources are compromised or sparse
  - *Recommendation*: **Accept by design**. WARNING clause (8) discloses this risk. Adding hardcoded confidence bounds would be fragile (price moves over time) and incompatible with immutability. Pair 500 is "Under Supervision" tier (3-5 sources), mitigating single-source risk.

### INFO
- **I-01: Pyth-specific assertions correctly omitted** — Supra's `decimal: u16` is unsigned, so negative-exponent checks are unnecessary. The `dec <= 38` bound plus `result > 0` guard is sufficient for normalization safety.
- **I-02: Dependency revision pinning** — `SupraFramework` and `dora-interface` deps use `rev = "dev"` / `rev = "master"` rather than commit hashes. Risk: framework upgrade between compile and mainnet publish could introduce ABI drift.
  - *Recommendation*: **Pre-mainnet action**: Pin to specific commit hashes (e.g., `rev = "306b607..."`) before mainnet deployment. Already flagged in self-audit.
- **I-03: Error code renumbering** — `E_NOT_ORIGIN` (17→15), `E_CAP_GONE` (18→16), new `E_STALE_FUTURE=17`. Frontends/indexers parsing abort codes from D Aptos must be re-keyed for D Supra.
  - *Impact*: Tooling incompatibility between sibling chains
  - *Mitigation*: Documented; D Supra is a separate package, not an upgrade of D Aptos.
- **I-04: Event schema compatibility** — All 12 event types retain identical field names/types vs D Aptos. Indexer schemas can be reused with package address swap.

---

## Delta verification (6 ports)

- [x] **price_8dec rewrite correct** (Supra ms-ts, dec normalization, abort paths)
  - ✅ Tuple destructure `(v, d, ts_ms, _round)` matches Supra `get_price(u32) -> (u128, u16, u64, u64)` ABI
  - ✅ Staleness math: `now_ms = timestamp::now_seconds() * 1000` then `now_ms <= ts_ms + STALENESS_MS` — overflow-safe (u64::MAX / 1000 ≈ 1.84e16 secs >> plausible chain time)
  - ✅ Future-drift clause `ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS` correctly rejects timestamps >10s ahead
  - ✅ Decimal normalization handles `dec: u16` unsigned correctly; `dec <= 38` bound prevents pow10 overflow
  - ✅ Abort on `v == 0` and `result == 0` preserved

- [x] **`*_pyth` wrappers cleanly removed** (no orphans)
  - ✅ Grep of source + tests confirms zero references to `open_trove_pyth`, `redeem_pyth`, etc.
  - ✅ Base entries (`open_trove`, `redeem`, etc.) are self-sufficient; no implicit VAA-update dependency
  - ✅ Frontend migration: stop bundling VAAs, call base entries directly — ABI is strict subset

- [x] **MIN_DEBT 0.01 D safe** (no overflow, fee math intact)
  - ✅ Fee at MIN_DEBT: 1% of 1_000_000 = 10_000 raw units — well above zero, no underflow
  - ✅ Fee-cascade trap rationale still applies at smaller scale; rescuer needs ~$0.0001 worth of D — trivial
  - ✅ MIN_DEBT enforced at all 4 sites: `open_impl:280`, `redeem_impl:339/352`, `redeem_from_reserve:389`

- [x] **WARNING (10) USDT-tail accurate**
  - ✅ Text correctly states pair 500 = SUPRA/USDT direct (not USD-derived)
  - ✅ Historical USDT depeg reference (May 2022, $0.95) is accurate
  - ✅ "No fallback" claim correct: `get_derived_price` not used; D peg drifts with USDT by design
  - ✅ "<5%" magnitude estimate is historically defensible

- [x] **Move.toml deps + named addresses correct**
  - ✅ `AptosFramework → SupraFramework` (fork path verified)
  - ✅ `Pyth` dep removed; `core = git(...dora-interface..., subdir="supra/mainnet/core")` added
  - ✅ `origin = "_"` CLI-fillable for testnet/mainnet portability
  - ✅ `upgrade_policy = "compatible"` forced by dep policy chain — documented

- [x] **Field rename `apt_metadata→supra_metadata` complete**
  - ✅ Cosmetic rename only; all 4 reader sites updated; zero semantic effect

---

## Inheritance verification

- [x] **V2 design (10/90, truncation guard, cliff redirect) byte-identical to D Aptos**
  - ✅ Fee split logic, `route_fee_fa` math, `liquidate` distribution unchanged
  - ✅ Cliff `product_factor` freeze at `MIN_P_THRESHOLD=1e9` preserved
  - ✅ Truncation guard at liquidate: `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` verified at correct location

- [x] **sp_settle saturation, MIN_P_THRESHOLD freeze, reset-on-empty preserved**
  - ✅ u64 saturation checks in `sp_settle` unchanged
  - ✅ `sp_deposit` reset-on-empty logic intact

- [x] **5 store-address views all distinct + stable**
  - ✅ `metadata_addr`, `fee_pool_addr`, `sp_pool_addr`, `sp_coll_pool_addr`, `reserve_coll_addr` all computed via deterministic `@D` derivation

---

## Supra-specific

- [x] **Resource-account derivation correct on Supra fork**
  - ✅ Supra fork uses same `0x1::resource_account` + `0x1::account` modules as Aptos; `destroy_cap` pattern ports identically
  - ✅ Post-`destroy_cap`: `ResourceCap` removed, `Option<SignerCap>` consumed, `is_sealed()=true` — no actor can reconstruct signer for `@D`

- [x] **supra_oracle::supra_oracle_storage::get_price ABI match**
  - ✅ Verified against Supra docs: `get_price(u32) -> (u128 value, u16 decimals, u64 timestamp_ms, u64 round)`
  - ✅ Testnet rehearsal confirmed live feed returns expected tuple format

- [x] **Paired-FA Coin/FA semantics — no logical impact on D accounting**
  - ✅ `primary_fungible_store::withdraw(user, supra_metadata, amt)` reads from FA primary store regardless of Coin/FA origin
  - ✅ Supra FA module semantics align with Aptos FA framework; no accounting divergence

- [x] **Move.toml dep policy chain — compatible enforcement correct**
  - ✅ `upgrade_policy = "compatible"` is forced by SupraFramework + dora-interface dep policies
  - ✅ Functional immutability achieved via runtime sealing (`destroy_cap`), not package-policy — documented in Move.toml comment

---

## Attack surface delta

| Change | Analysis |
|--------|----------|
| **New: USDT depeg sensitivity (clause 10)** | Accept-by-design. Pair 500 reports SUPRA/USDT directly; if USDT trades at $0.95, D's effective USD peg drifts ~5%. Historical precedent supports "<5%" bound. No code mitigation possible in immutable contract. |
| **Removed: Pyth conf-band protection** | Supra returns single aggregated value; no `conf` field exposed. WARNING clause (8) discloses this. Mitigation: pair 500 is "Under Supervision" (3-5 sources). Accept-by-design. |
| **Time unit: seconds → milliseconds** | Overflow-safe: `u64::MAX / 1000 ≈ 1.84e16 secs` >> plausible chain lifetime. Boundary semantics (`<=`) correct. |
| **Error code renumbering** | Tooling incompatibility between sibling chains; documented. No security impact. |

**Issues considered but not flagged**:
- Oracle freeze escape hatches: `close_trove`, `add_collateral`, `sp_*` entries remain functional if `get_price` aborts — same as D Aptos baseline.
- Self-redeem (target == caller): Allowed by design; validated on testnet.
- Bootstrap trove CR: 500 SUPRA → 0.01 D at oracle price $0.0003127 yields CR ≈ 1563% — safely above 200% MCR.

---

## Recommendation

**✅ Proceed to mainnet** pending pre-mainnet action item:

1. **Pin dependency revisions** (I-02): Update `Move.toml` to pin `SupraFramework` and `dora-interface` to specific commit hashes before mainnet publish:
   ```toml
   SupraFramework = { git = "...", rev = "306b60776be2ba382e35e327a7812233ae7acb13" }
   core = { git = "...dora-interface", subdir = "supra/mainnet/core", rev = "37a9d80bd076a5f4d81163952068bb4e27518d5b" }
   ```

All other findings are either inherited from the GREEN-audited D Aptos baseline, accept-by-design with explicit disclosures, or informational. The 32/32 test pass rate + 12/13 entry + 16/16 view testnet rehearsal provides strong empirical validation.

---

## Optional notes

- The self-audit (Claude Opus 4.7) is thorough and correctly scoped to the 6 porting deltas. I concur with its findings and GREEN verdict.
- The Supra push oracle integration follows the proven pattern from ONE Supra v0.4.0 mainnet (`/home/rera/one/supra/sources/ONE.move:154-163`).
- The resource-account + `destroy_cap` sealing pattern is cryptographically equivalent on Supra fork since it uses the same `0x1::resource_account` module path as Aptos.
- Frontend integrators should note: stop calling `*_pyth` wrappers and stop bundling VAAs; base entries now work standalone with push-based oracle.
