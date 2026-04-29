# D Aptos → D Supra port plan

Source: `/home/rera/d/aptos/sources/D.move` (866 LOC, v0.2.0 mainnet sealed at `0x587c8084…`)
Target: `/home/rera/d/supra/sources/D.move`

## Locked decisions

| # | Param | Value |
|---|---|---|
| 1 | Multisig | `0xbefe37923ac3910dc5c2d3799941e489da460cb6c8f8b69c70d68390397571f5` (1/5 → 3/5 post-seal). Owners = D-Aptos siblings + 0x0047. timeout_duration=86400s. |
| 2 | Oracle | `supra_oracle_storage::get_price(500)` — direct SUPRA/USDT (Opsi A) |
| 3 | Staleness | 60s (= `STALENESS_MS = 60_000`) |
| 4 | ONE Supra v0.4.0 (`0x2365c948…`) | Logical deprecate. Stranded `0x0047` trove (5555 SUPRA / 0.99 ONE in SP) abandoned. |
| 5 | MIN_DEBT | **0.01 D = 1_000_000 raw** (8 dec) |
| 6 | Sealing | Resource account + `destroy_cap` (port D Aptos pattern) |
| 7 | Warning | Multi-clause from D Aptos + Supra-specific clauses + USDT-tail clause |
| 8 | Tokenomics | 200% MCR, 150% LIQ_THRESHOLD, 10% LIQ_BONUS, 1% fee, 10/90 fee split (10%→sp_pool donation, 90%→keyed depositors), unchanged |

## Move.toml changes

```diff
 [package]
 name = "D"
-version = "0.2.0"
+version = "0.2.0"  # unchanged — supra is sibling fork, not new version
 upgrade_policy = "compatible"

 [addresses]
 D = "_"
-origin = "0x37f781195eb0929e5187ebe95dba5d9ac22859187a0ddca3e5afbc815688b826"  # Aptos multisig
-pyth = "0x7e783b349d3e89cf5931af376ebeadbfab855b3fa239b7ada8f5a92fbea6b387"
+origin = "0xbefe37923ac3910dc5c2d3799941e489da460cb6c8f8b69c70d68390397571f5"  # Supra multisig

 [dependencies]
-AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework", rev = "e0f33de9783f2ceaa30e5f2b004d3b39812c4f06" }
-Pyth = { local = "deps/pyth" }
+SupraFramework = { git = "https://github.com/Entropy-Foundation/aptos-core.git", subdir = "aptos-move/framework/supra-framework", rev = "dev" }
+core = { git = "https://github.com/Entropy-Foundation/dora-interface.git", subdir = "supra/mainnet/core", rev = "master" }
```

`core` package exposes `supra_oracle::supra_oracle_storage` module at `0xe3948c9e3a24c51c4006ef2acc44606055117d021158f320062df099c4a94150`.

## D.move source deltas

### 1. Imports (lines 11-27)
```diff
-use aptos_std::smart_table::{Self, SmartTable};
-use aptos_framework::account::SignerCapability;
-use aptos_framework::event;
-use aptos_framework::fungible_asset::{...};
-use aptos_framework::object::{...};
-use aptos_framework::primary_fungible_store;
-use aptos_framework::resource_account;
-use aptos_framework::timestamp;
-use pyth::pyth;
-use pyth::price::{Self, Price};
-use pyth::i64;
-use pyth::price_identifier;
+use aptos_std::smart_table::{Self, SmartTable};
+use supra_framework::account::SignerCapability;
+use supra_framework::event;
+use supra_framework::fungible_asset::{...};
+use supra_framework::object::{...};
+use supra_framework::primary_fungible_store;
+use supra_framework::resource_account;
+use supra_framework::timestamp;
+use supra_oracle::supra_oracle_storage;
```

(`aptos_std::smart_table` stays — Supra fork uses same path)

### 2. Constants (lines 29-44)
```diff
-const STALENESS_SECS: u64 = 60;
-const MIN_DEBT: u64 = 10_000_000;  // 0.1 D
-const APT_FA: address = @0xa;
-const APT_USD_PYTH_FEED: vector<u8> = x"03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5";
-const MAX_CONF_BPS: u64 = 200;
+const STALENESS_MS: u64 = 60_000;          // 60s (Supra ts is millis)
+const MAX_FUTURE_DRIFT_MS: u64 = 10_000;   // 10s drift tolerance
+const MIN_DEBT: u64 = 1_000_000;           // 0.01 D (revised down from 0.1)
+const SUPRA_FA: address = @0xa;            // Supra native FA at same address as APT FA
+const PAIR_ID: u32 = 500;                  // SUPRA/USDT
```

(Other constants — MCR_BPS, LIQ_*, FEE_BPS, PRECISION, MIN_P_THRESHOLD — unchanged)

### 3. Error codes (lines 46-64)
- **Remove**: `E_PRICE_EXPO`, `E_PRICE_NEG`, `E_PRICE_UNCERTAIN` (Pyth-specific assertions removed)
- **Add**: `E_STALE_FUTURE` (separate code for future-drift bound, since user-friendlier than reusing `E_STALE`)
- Keep all others. Renumber sparingly to keep tests readable.

### 4. WARNING constant (line 66)
Full rewrite. Use D-Aptos clauses (1)-(7) verbatim with `Aptos`→`Supra`, `APT`→`SUPRA`, `Pyth`→`Supra oracle`, `feed id 0x03ae4d…`→`pair id 500`. Replace clauses (6), (8), (9) and add new clauses (10), (11):

- **(6)** "Pyth is pull-based on Aptos…" → "Supra oracle is push-based on Supra L1 — protocol pushes feed updates on cadence (typically <30s for active pairs); D rejects reads older than 60 seconds via STALENESS_MS. Callers do NOT bundle VAAs; just call entries directly."
- **(8) ORACLE DEPENDENCY (Supra-specific)**: "Supra oracle pkg `0xe3948c9e…4150` is governed by Supra Foundation (upgrade_policy=1, NOT immutable). Pair_id 500 (SUPRA/USDT) is "Under Supervision" tier (3-5 sources, lower-confidence than top-tier pairs like BTC/USDT). Residual risks: pair_id could be remapped or decommissioned via Supra governance, package code could be upgraded silently in compatible-breaking ways, feed could become unavailable. Either case bricks oracle-dependent entries (open_trove, redeem, liquidate, redeem_from_reserve). Oracle-free escape hatches: close_trove, add_collateral, sp_deposit, sp_withdraw, donate_to_sp, donate_to_reserve, sp_claim. Protocol-owned SUPRA in reserve_coll becomes permanently locked under freeze. No admin override; freeze is final."
- **(9) REDEMPTION vs LIQUIDATION** — verbatim from Aptos clause, with token rename APT→SUPRA.
- **(10) USDT-TAIL CLAUSE (NEW)**: "D peg target is USDT, not USD. Pair 500 reports SUPRA/USDT directly; D treats USDT as $1.00 per Supranova/Solido precedent. Under USDT depeg events (e.g., May 2022 USDT briefly $0.95), D's effective USD peg drifts proportionally — magnitude historically <5% with quick recovery. Pair 500 chosen over `get_derived_price(500, USDT_USD_id, MUL)` for immutable simplicity, accepting ~50bps long-tail USDT risk. No `get_derived_price` fallback exists; if USDT depegs structurally, D's peg moves with it."
- Drop the *_pyth wrapper docs; remove "Pyth pull-based" mention everywhere.

### 5. Registry struct (lines 80-102)
Field rename for clarity (cosmetic but helpful for audit reading):
```diff
-apt_metadata: Object<Metadata>,
+supra_metadata: Object<Metadata>,
```
All readers updated accordingly (lines 121, 150, 367, 373, 544, 581).

### 6. `init_module` + `init_module_inner` (lines 118-171)
Replace `APT_FA` with `SUPRA_FA`, `apt_md` with `supra_md`. Logic identical.

### 7. `price_8dec()` (lines 173-199) — FULL REWRITE

```move
fun price_8dec(): u128 {
    let (v, d, ts_ms, _) = supra_oracle_storage::get_price(PAIR_ID);
    assert!(v > 0, E_PRICE_ZERO);
    assert!(ts_ms > 0, E_STALE);
    let now_ms = timestamp::now_seconds() * 1000;
    assert!(ts_ms <= now_ms + MAX_FUTURE_DRIFT_MS, E_STALE_FUTURE);
    assert!(now_ms <= ts_ms + STALENESS_MS, E_STALE);
    let dec = (d as u64);
    assert!(dec <= 38, E_EXPO_BOUND);
    let result = if (dec >= 8) v / pow10(dec - 8) else v * pow10(8 - dec);
    assert!(result > 0, E_PRICE_ZERO);
    result
}
```
- Pattern lifted from `/home/rera/one/supra/sources/ONE.move:154-163` (proven mainnet)
- No Pyth conf check (Supra returns pre-aggregated single value, no confidence interval exposed)
- No expo sign check (Supra `decimal` is `u16` unsigned; positive-only)

### 8. `pow10` (lines 201-206)
**Unchanged.**

### 9. `route_fee_fa` (lines 208-228)
**Unchanged.** Pure D-token logic, no oracle/collateral touch.

### 10. `sp_settle` (lines 230-...)
**Unchanged.** Internal accounting only.

### 11. Entry functions (lines 367-557)
- All bodies unchanged except: `r.apt_metadata` → `r.supra_metadata` (4 sites)
- `open_trove`, `add_collateral`, `redeem`, `liquidate`, `redeem_from_reserve` work as-is

### 12. *_pyth wrappers (lines 573-607) — DELETE ENTIRELY
Supra is push-based; users call base entries directly. No VAA injection needed. **Remove**:
- `open_trove_pyth`
- `redeem_pyth`
- `redeem_from_reserve_pyth`
- `liquidate_pyth`

This is a SIMPLIFICATION — D Supra has fewer entries than D Aptos.

### 13. `read_warning()` view (line 609)
**Unchanged** signature. Returns updated WARNING constant.

### 14. Test module (`tests/D_tests.move`, 522 LOC)
- Replace Pyth mock with Supra oracle mock
- Pattern: ONE Supra v0.4.0 has Supra mock at `/home/rera/one/supra/tests/` (TBD — read first)
- All trove/SP/redeem/liquidate test cases: identical scenarios, just different oracle setup
- Number target: 32/32 PASS (matches D Aptos)

### 15. Bootstrap module (`bootstrap.move`)
- Coin<SupraCoin>→FA conversion via `coin::coin_to_fungible_asset` (Supra has this; reverse is private)
- Open trove with: bootstrap collateral N SUPRA + debt 0.01 D (= MIN_DEBT)
- At SUPRA spot ~$0.0004, 0.01 D → ~$0.10 USD value → CR 200% min → ≥250 SUPRA collateral. Pick **500 SUPRA → 0.01 D** for ~400% CR safety buffer.

## Sealing flow on Supra (multisig + resource account + destroy_cap)

D Aptos uses `aptos move create-resource-account-and-publish-package` from multisig. Supra needs supra-l1-sdk equivalent. Steps:

1. **Multisig proposes** `0x1::resource_account::create_resource_account_and_publish_package(seed, metadata, code)` from multisig as creator → resource account address derived deterministically from `multisig_addr + seed`
2. **Multisig executes** (1/5 threshold during deploy phase)
3. Resource account holds the package code at `@D` (its own address). SignerCapability is moved into `ResourceCap` resource at init_module.
4. **Bootstrap tx**: multisig proposes `D::open_trove(500 SUPRA, MIN_DEBT)` → executes
5. **Multisig proposes `D::destroy_cap()`** — only `@origin` (= multisig) can call. Consumes `Option<SignerCap>`, drops it. After this, no signer reachable for `@D`.
6. **Multisig threshold raise**: 1/5 → 3/5 via `multisig_account::update_signatures_required(3)` for governance hygiene.

Address derivation:
- `seed = b"D"` (or any agreed bytes — locks the resource account address)
- `resource_addr = sha3-256(multisig_addr || seed || 0xFF)` per Aptos `account::create_resource_address` impl
- Pre-compute via SDK `getResourceAccountAddress(multisig_addr, seed_bytes)` to verify before publish.

## Deploy script lineup

```
deploy-scripts/
├── 01_create_multisig.js      ✅ DONE (multisig 0xbefe37923ac…)
├── 02_compute_resource.js     — derive resource_addr from multisig + seed
├── 03_publish_via_multisig.js — propose+execute create_resource_account_and_publish_package
├── 04_bootstrap.js            — propose+execute open_trove (500 SUPRA / 0.01 D)
├── 05_seal_via_multisig.js    — propose+execute destroy_cap
├── 06_raise_threshold.js      — propose+execute update_signatures_required(3)
└── 07_smoke_mainnet.js        — view-fn checks (is_sealed, totals, store balances)
```

Pattern templates: `/home/rera/d/aptos/deploy-scripts/0[1-6]*.{sh,js}` (port to supra-l1-sdk).

Multisig payload helper: SDK has `createSerializedMultisigPayloadRawTxObject` + `createSerializedRawTxObjectToCreateMultisigTx` — Supra has full multisig propose/execute support.

## Open items (not blocking scaffold)

- **Frontend**: D Aptos `/d` route on `darbitex.wal.app` lives. Need parallel Supra page or chain-toggle? Defer until D Supra mainnet live.
- **Token Factory port**: D Aptos token factory pending; D Sui has token factory deployed. Supra port of factory follows D Supra core.
- **Stranded ONE Supra trove rescue**: not pursued. Note in D Supra README that ONE Supra `0x2365c948…` is deprecated.

## Estimated work

- Move source port: 30 min (mostly mechanical sed-style edits)
- Tests port: 1-2 hr (oracle mock swap)
- Compile green: 30 min (resolve any aptos→supra framework API drift)
- Deploy scripts: 2-3 hr (port 6 scripts to supra-l1-sdk, multisig propose/execute pattern)
- Smoke + R1 audit: 1 day
- Mainnet seal: 1 hr (with reviewed scripts)

Total to LIVE+SEALED: ~2 working days.
