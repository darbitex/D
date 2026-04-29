# D — immutable stablecoin on Aptos

D Aptos is the Aptos port of [D Sui v0.2.0](../README.md), with the same V2 design (10/90 fee split, agnostic donations, truncation guard) on the Aptos Fungible Asset framework + resource-account sealing model. Sibling to the sealed [ONE Aptos v0.1.3](https://github.com/darbitex/ONE) (the V1 lineage).

**LIVE + SEALED on Aptos mainnet (2026-04-29).**

## Canonical addresses

| Object | Address | Role |
|---|---|---|
| **Package (D)** | `0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77` | Move package, **sealed** (resource account, ResourceCap consumed). Hosts `D::D` module. |
| **D FA metadata** | `0x9015d5a6bbca103bc821a745a7fd3eb2ee1e535d3af65ac9fb4c7d308355c390` | `Object<Metadata>` for the D fungible asset. Decimals 8. Symbol `D`. |
| **Origin multisig (governance)** | `0x37f781195eb0929e5187ebe95dba5d9ac22859187a0ddca3e5afbc815688b826` | 3-of-5 multisig. **Only role left is ResourceCap consumer (already done — package sealed).** Multisig still functional but cannot publish to `@D` ever again. |
| Coin type | `0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77::D::D` | (informational; FA model uses metadata, not coin type) |

### Five FungibleStore objects (composability surface, exposed via view fns)

Each store is a separate `Object<FungibleStore>` with its own address. Indexers/frontends can subscribe events per store directly.

| View fn | Address | Asset | Role |
|---|---|---|---|
| `fee_pool_addr()` | `0x9609e7dc1031ce34ae6ee032ac15a1370880f13af3a85202f86cc85c2458455a` | D | 90% portion of mint/redeem fees, accrued for keyed SP depositors via `reward_index_d` |
| `sp_pool_addr()` | `0x5e2b58e08a56a6d45a0ea8a043d47b68a9b2591a6eab89d931965ce68a5f89e2` | D | Stability Pool. Holds keyed SP deposits + agnostic donations. Burns on liquidation. |
| `sp_coll_pool_addr()` | `0x9f7067b4ee7d088084bbefd7a31efbf1424ac9a2bf1c949942fd5f2fc9c58f31` | APT | SP-share of seized liquidation collateral, distributed to keyed depositors via `reward_index_coll` |
| `reserve_coll_addr()` | `0xf241ca7c86ace9e0a267abce9ea8fbce1d5a814fcace4f86e8dd0313c2622868` | APT | Protocol-owned APT reserve. Sources `redeem_from_reserve`. Receives `donate_to_reserve` deposits + 25% liquidation bonus + cliff orphan redirects. |
| `treasury_addr()` | `0x9593efef231032c3988739aa7108af46e06f4e2c6a89e6b545f2dfb771c4a969` | APT | Trove collateral lockup. Withdrawn on close/redeem/liquidate. |

## Multisig (origin) — 3-of-5

Threshold sequence: **1/5 (publish + seal)** → **3/5 (post-seal governance)**.

After sealing, the multisig has no D-protocol authority — `destroy_cap` is one-shot and the SignerCapability is permanently consumed. The 3/5 threshold is governance hygiene only (multisig owner rotation, etc., though there's nothing left to govern on D itself).

Same 5 owners as Darbitex Final / Darbitex Treasury multisig:

| # | Owner |
|---|---|
| 1 | `0x13f0c2edebcb9df033875af75669520994ab08423fe86fa77651cebbc5034a65` |
| 2 | `0xf6e1d1fdc2de9d755f164bdbf6153200ed25815c59a700ba30fb6adf8eb1bda1` |
| 3 | `0xc257b12ef33cc0d221be8eecfe92c12fda8d886af8229b9bc4d59a518fa0b093` |
| 4 | `0xa1189e559d1348be8d55429796fd76bf18001d0a2bd4e9f8b24878adcbd5e84a` |
| 5 | `0x0047a3e13465172e10661e20b7b618235e9c7e62a365d315e91cf1ef647321c9` (creator + executor for the deploy) |

## Deploy transaction trail

| Step | Tx | Cost |
|---|---|---|
| 1. Create multisig 1/5 | [`0x5150dfe9…`](https://explorer.aptoslabs.com/txn/0x5150dfe993ce47e9b3ff0f01ef3e950647a300ec17963af64e4fa69ddbfb54b5?network=mainnet) | 0.012 APT |
| 2. Propose publish | [`0x351c18f5…`](https://explorer.aptoslabs.com/txn/0x351c18f5dc0ca1453f677efa3485c3c8c36999e79ab523ff30e8da43e6a1becf?network=mainnet) | 0.071 APT |
| 3. Execute publish | [`0xdadc6b90…`](https://explorer.aptoslabs.com/txn/0xdadc6b90a27d6334c0642524b93c0721ee51d039cdb5202f07bbb8180a38d30b?network=mainnet) | 0.141 APT |
| 4. Bootstrap trove (`open_trove_pyth` 2.2 APT / 1 D) | [`0xd9e71239…`](https://explorer.aptoslabs.com/txn/0xd9e712392ca3fb91846c670f0aea6d41e5b4a50dc7cbd73e2a84e43ce09d063f?network=mainnet) | gas + 2.2 APT collateral |
| 5. SP deposit (0.5 D) | [`0x1c6d35b8…`](https://explorer.aptoslabs.com/txn/0x1c6d35b86bf474fda6954f757bee26e71756ee5184abce84409e66d353b51a1a?network=mainnet) | trivial |
| 6. donate_to_sp (0.1 D smoke) | [smoke](https://explorer.aptoslabs.com/account/0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77?network=mainnet) | trivial |
| 7. donate_to_reserve (0.1 APT smoke) | [smoke](https://explorer.aptoslabs.com/account/0x37f781195eb0929e5187ebe95dba5d9ac22859187a0ddca3e5afbc815688b826?network=mainnet) | trivial |
| 8. Propose `destroy_cap` (seal) | seq 624 of multisig | trivial |
| 9. Execute `destroy_cap` | seq 625 | trivial |
| 10. Propose threshold 3/5 | seq 627 | trivial |
| 11. Execute threshold 3/5 | seq 629 | trivial |

## Immutability model — dual layer (important)

Aptos enforces a transitive dep policy rule (per [aptos-labs/aptos-core](https://github.com/aptos-labs/aptos-core)): a package's `upgrade_policy` must be **at least as permissive as** its weakest dependency's policy. AptosFramework is published with `compatible` policy (so the framework can evolve). D depends on AptosFramework, so D's `Move.toml` declares:

```toml
[package]
upgrade_policy = "compatible"
```

**This does NOT mean D is upgradeable.** It just means we can't seal it at the *package layer*. We seal at the *account layer* instead.

D uses **two layers** of immutability:

### Layer 1: Package upgrade_policy

- Value: `"compatible"` (forced by AptosFramework dep)
- Meaning: if anyone could construct a signer for `@D` and call `0x1::code::publish_package_txn`, they'd be allowed to upload bytecode that's signature-compatible with the existing modules.
- **Status: NOT the binding constraint.**

### Layer 2: Account signer (the binding lock)

`@D = 0x587c8084…` is a **resource account**, not a regular account. Resource accounts are unique because their `SignerCapability` is the ONLY way to derive a signer for them — there's no private key, no key rotation, no multisig owner of the account itself.

The deploy flow:
1. Multisig `0x37f78119…` calls `0x1::resource_account::create_resource_account_and_publish_package(seed="D", metadata, code)`.
2. Aptos framework derives `@D` from `(multisig_addr, seed)`, creates a `SignerCapability` for it, and stashes it in a `Container` resource at the multisig's address.
3. D's `init_module` retrieves the cap from `Container` and stashes it inside D's own `ResourceCap` resource at `@D`.
4. D's `destroy_cap` (origin-only, callable only by the multisig) extracts the cap from `ResourceCap`, lets `option::destroy_some` drop it, and deletes the `ResourceCap` resource.

After step 4 (executed in tx [`seq 625`](https://explorer.aptoslabs.com/account/0x37f781195eb0929e5187ebe95dba5d9ac22859187a0ddca3e5afbc815688b826?network=mainnet)):
- `ResourceCap` no longer exists at `@D`.
- The `Container` at `@multisig` no longer holds D's cap (it was moved out at init).
- No actor — not the multisig, not Aptos governance, not anyone — can derive a signer for `@D`.
- Therefore no actor can call `0x1::code::publish_package_txn` with `@D` as the publish target. No upgrade is possible *in practice*, regardless of `upgrade_policy`.

This is the **same end result as Sui's `package::make_immutable`** (which consumes the UpgradeCap), just via a different mechanism. Sui has a single-layer model (UpgradeCap), Aptos has the dual-layer model (package policy + account signer).

### Verify both layers yourself

```bash
# Layer 1: package policy is "compatible" (expected — dep chain constraint)
curl -s https://fullnode.mainnet.aptoslabs.com/v1/accounts/0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77/resource/0x1::code::PackageRegistry \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('policy:', d['data']['packages'][0]['upgrade_policy'])"
# Expected: policy: {'policy': 1}   # 1 = compatible

# Layer 2a: D's is_sealed view → must return true
aptos move view --function-id 0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77::D::is_sealed --profile mainnet
# Result: [true]

# Layer 2b: ResourceCap resource → must 404 (cap is gone)
curl https://fullnode.mainnet.aptoslabs.com/v1/accounts/0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77/resource/0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77::D::ResourceCap
# Expected: 404 "Resource not found"

# Layer 2c: Container resource at multisig — must NOT contain D's cap
# (Container holds caps for resource accounts the multisig spawned. D's was
#  moved out during init_module and then dropped during destroy_cap.)
curl https://fullnode.mainnet.aptoslabs.com/v1/accounts/0x37f781195eb0929e5187ebe95dba5d9ac22859187a0ddca3e5afbc815688b826/resource/0x1::resource_account::Container
# Expected: either 404, or store map without an entry keyed by @D
```

If all four checks pass, the package is permanently sealed. The `compatible` policy in Layer 1 is functionally inert because Layer 2 blocks any signer that could exercise it.

## Protocol parameters

| Parameter | Value |
|---|---|
| Collateral | APT (`@0xa` FA, also paired with legacy `aptos_coin::AptosCoin`) |
| MCR (mint) | 200% |
| Liquidation threshold | 150% |
| Liquidation bonus | 10% (25% liquidator + 25% reserve + 50% SP) |
| Mint fee | 1% (10% donate to SP + 90% SP rewards distribution) |
| Redeem fee | 1% (same split) |
| **Min debt** | **0.1 D** (10_000_000 raw) — lowered from V1 ONE Aptos's 1 ONE per fee-cascade trap fix |
| Decimals | 8 (D), 8 (APT) |
| Oracle | Pyth APT/USD feed `0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5` |
| Pyth package (cryptographically immutable, auth_key=0x0) | `0x7e783b349d3e89cf5931af376ebeadbfab855b3fa239b7ada8f5a92fbea6b387` |
| Staleness | 60s |
| Confidence cap | 200 bps (2%) |
| Sealing | resource-account + `destroy_cap` (consumes SignerCapability) |
| Governance | None |

## Public surface (16 entries + 16 views)

### Trove ops
- `open_trove(user, coll_amt, debt)` / `open_trove_pyth(user, coll_amt, debt, vaas)` (atomic Pyth update)
- `add_collateral(user, coll_amt)` (oracle-free top-up)
- `close_trove(user)` (oracle-free, requires `close_cost` D in wallet)
- `redeem(user, d_amt, target)` / `redeem_pyth(user, d_amt, target, vaas)`
- `redeem_from_reserve(user, d_amt)` / `redeem_from_reserve_pyth(user, d_amt, vaas)`
- `liquidate(liquidator, target)` / `liquidate_pyth(liquidator, target, vaas)`

### SP ops
- `sp_deposit(user, amt)`
- `sp_withdraw(user, amt)`
- `sp_claim(user)`

### Donations (V2 NEW, permissionless, oracle-free)
- `donate_to_sp(user, amt)` — agnostic D donation; joins sp_pool balance, does NOT increment total_sp (no reward dilution for keyed depositors); donations gradually burn via liquidation absorption.
- `donate_to_reserve(user, amt)` — APT to reserve_coll; fortifies `redeem_from_reserve` capacity; works during oracle freeze.

### Sealing (one-shot, irreversible — already executed)
- `destroy_cap(caller)` — origin-only; consumes SignerCapability; permanently seals the package. **Done.**

### Views
- `read_warning() → vector<u8>` — full on-chain disclosure
- `is_sealed() → bool` — `true` on D mainnet
- `metadata_addr() → address` — D FA metadata object
- `fee_pool_addr()`, `sp_pool_addr()`, `sp_coll_pool_addr()`, `reserve_coll_addr()`, `treasury_addr()` — 5 FungibleStore addresses
- `totals() → (debt, sp, p, r_d, r_coll)` — global state
- `trove_of(addr) → (coll, debt)` — per-user trove
- `sp_of(addr) → (effective_balance, pending_d, pending_coll)` — per-user SP
- `reserve_balance() → u64` — reserve_coll APT balance
- `sp_pool_balance() → u64` — live sp_pool balance (= total_sp + donation residue)
- `close_cost(addr) → u64` — exact D required to close `addr`'s trove
- `trove_health(addr) → (coll, debt, cr_bps)` — oracle-dependent
- `price() → u128` — live APT/USD price (8 decimals)

## Mainnet smoke results (2026-04-29)

End-to-end smoke executed with 2 accounts (`0x0047a3e1…` + `0x85d1e4…`). 14 of 16 entry fns + all 16 view fns empirically validated. The 2 untested entries (`liquidate` / `liquidate_pyth`) are skipped intentionally — they require an under-water trove (CR < 150%) which cannot be reproduced on mainnet without an actual market move. The math is unit-tested + matches D Sui sealed mainnet behavior + has 4 CR-continuum trace points covered in audit responses.

| Action | Account | Result | Tx |
|---|---|---|---|
| `open_trove_pyth(2.2 APT, 1 D)` | `0x0047` | trove created, 1% fee 100% → sp_pool (cliff, total_sp was 0) | `0xd9e71239…` |
| `sp_deposit(0.5 D)` | `0x0047` | total_sp 0 → 0.5 D | `0x1c6d35b8…` |
| `donate_to_sp(0.1 D)` | `0x0047` | sp_pool grew, total_sp unchanged | smoke |
| `donate_to_reserve(0.1 APT)` | `0x0047` | reserve 0 → 0.1 APT | smoke |
| `open_trove_pyth(2.5 APT, 1 D)` | `0x85d1e4` | second trove, **fee 10/90 split verified**: `reward_index_d += 1.8e16` (= 0.009 D × 1e18 / 0.5 D) | `0x5731ec73…` |
| `add_collateral(0.3 APT)` | `0x85d1e4` | trove 2.5 → 2.8 APT, oracle-free | `0xf2433aa2…` |
| `sp_deposit(0.5 D)` | `0x85d1e4` | total_sp 0.5 → 1.0 D | `0x246f4b4d…` |
| `redeem_pyth(0.2 D, target=0x0047)` | `0x85d1e4` | 0x0047 trove debt 1 → 0.802 D, 0x85d1e4 received 0.213 APT | `0xf69acb0f…` |
| `redeem (raw)(0.15 D, target=0x0047)` | `0x85d1e4` | confirms raw path works after separate Pyth update tx | `0x27af12d2…` |
| `donate_to_reserve(0.5 APT)` | `0x0047` | reserve 0.1 → 0.6 APT | `0x0ff81e34…` |
| `redeem_from_reserve_pyth(0.11 D)` | `0x0047` | reserve 0.6 → 0.49 APT, **`total_debt` UNCHANGED** (per-design reserve drain) | `0x072f1396…` |
| `sp_claim()` | `0x0047` | `pending_d = 0.01107 D` claimed (V2 reward distribution to keyed depositor) | `0x4adef1fe…` |
| `sp_withdraw(0.1 D)` | `0x85d1e4` | partial exit; sp_of bal 0.5 → 0.4 D | `0xb5fcb041…` |
| `sp_withdraw(0.5 D)` | `0x0047` | full exit; total_sp 0.9 → 0.4 D | `0x469b5a3d…` |
| `redeem_from_reserve (raw)(0.11 D)` | `0x85d1e4` | raw path, separate Pyth update | `0x3dde072e…` |
| `close_trove()` | `0x0047` | full close, trove 0/0, full collateral 1.855 APT returned | `0xf2495bab…` |

**V2 invariants verified empirically on mainnet:**
- ✓ 10% of fee → `sp_pool` agnostic donation (joins balance, NOT `total_sp`)
- ✓ 90% of fee → `fee_pool` + `reward_index_d` update (when `total_sp > 0`)
- ✓ Cliff path: when `total_sp == 0`, full fee → `sp_pool` (not burned, not in fee_pool)
- ✓ Keyed depositor pending_d accrues as expected (0x0047 received 0.01107 D from accumulated fees)
- ✓ `redeem_from_reserve` does NOT decrement `total_debt` (intentional supply-vs-debt gap widening)
- ✓ `add_collateral` is oracle-free (no Pyth call)
- ✓ Raw `redeem` / `redeem_from_reserve` work when Pyth was updated within 60s (separate tx)
- ✓ `close_trove` is oracle-free, returns full collateral, removes trove from registry

Final state post-smoke (only w2's trove remains, ready for any future activity): `total_debt = 1 D`, `total_sp = 0.4 D`, `product_factor = 1e18` (no liquidations). All 16 view fns return expected structures.

## Audit summary

R1 (6 external auditors, all GREEN):
- Grok 4 (xAI): GREEN, 0 findings + 3 optional recommendations
- Kimi K2.6 (Moonshot): GREEN, 0 findings
- Qwen3.6: GREEN, 1 LOW (doc-only) + 3 INFO
- DeepSeek: GREEN, 4 INFO
- Gemini: GREEN, 2 INFO
- Claude Opus 4.7 fresh: GREEN, 3 LOW (test gaps + dep pinning) + 8 INFO

**Cumulative severity: 0 HIGH / 0 MEDIUM / 4 LOW / 20 INFO + 7 optional.**

User decisions:
- 5 prior auditor findings: declined (no logic bugs).
- Claude L1/L2/L3: applied (test/build infrastructure improvements):
  - L1: real-cliff-path unit test added via new `test_route_fee_real(donor, amount)` helper
  - L2: AptosFramework pinned to commit `e0f33de9783f2ceaa30e5f2b004d3b39812c4f06`
  - L3: donor-field event assertion test added
- Source-of-D.move logic: **UNCHANGED** from pre-audit submission.

Final test count: **32/32 passing** (was 30 pre-audit, +2 new V2-coverage tests).

Per-auditor verbatim responses + consolidated tracking in [`audit/`](./audit/):
- [`SELF_AUDIT_R1.md`](./audit/SELF_AUDIT_R1.md)
- [`AUDIT_R1_BUNDLE.md`](./audit/AUDIT_R1_BUNDLE.md) — submission bundle (1930 lines, self-contained)
- [`AUDIT_R1_TRACKING.md`](./audit/AUDIT_R1_TRACKING.md) — consolidated findings table
- [`EXTERNAL_R1_*.md`](./audit/) — per-auditor responses
- [`MAINNET_DEPLOY_PLAN.md`](./audit/MAINNET_DEPLOY_PLAN.md) — deploy SOP

## Lineage

| Pkg | Chain | Status | Address |
|---|---|---|---|
| D Aptos v0.2.0 | Aptos | LIVE + SEALED 2026-04-29 | `0x587c8084…48622c77` |
| D Sui v0.2.0 | Sui | LIVE + SEALED 2026-04-28 | `0x898d83f0…8910b0d7` |
| ONE Aptos v0.1.3 | Aptos | LIVE + SEALED 2026-04-24 (V1, sibling) | `0x85ee9c43…aab87387` |
| ONE Sui v0.1.0 | Sui | LIVE + SEALED 2026-04-25 (V1, sibling, deprecated for new mints) | `0x9f39a102…1bf3b8dc` |

## WARNING (excerpt — full text on-chain via `read_warning()`)

D is an immutable stablecoin contract on Aptos that depends on Pyth Network's on-chain price feed for APT/USD. If Pyth degrades or misrepresents its oracle, D's peg mechanism breaks deterministically — users can wind down via self-close without external assistance, but new mint/redeem operations become unreliable or frozen. **D is immutable = bug is real. Audit this code yourself before interacting.**

10% of each mint and redeem fee is redirected to the Stability Pool as agnostic donation (does NOT increment `total_sp`; no reward dilution). Donations participate in liquidation absorption pro-rata via actual sp_pool balance. Remaining 90% distributes to keyed SP depositors. Total: 1% supply-vs-debt gap per fee cycle, fully draining via SP burns over time.

ORACLE DEPENDENCY: Pyth Aptos at `0x7e78…` is **cryptographically immutable** (auth_key=0x0). Residual risk: feed `0x03ae4d…` could be deregistered via Wormhole governance. Either case bricks oracle-dependent paths. Oracle-free escape hatches remain open: `close_trove`, `add_collateral`, `sp_deposit`, `sp_withdraw`, `donate_to_sp`, `donate_to_reserve`, `sp_claim`. Protocol-owned APT in `reserve_coll` becomes permanently locked if oracle freezes.

## Repo layout

```
aptos/
├── README.md                       ← this file
├── Move.toml                       ← origin = multisig, AptosFramework pinned to commit
├── sources/D.move                  ← 839 LOC contract
├── tests/D_tests.move              ← 32/32 PASS unit tests
├── audit/
│   ├── SELF_AUDIT_R1.md
│   ├── AUDIT_R1_BUNDLE.md          ← submission bundle (1930 lines, self-contained)
│   ├── AUDIT_R1_TRACKING.md        ← consolidated findings + decisions
│   ├── EXTERNAL_R1_*.md            ← per-auditor responses verbatim
│   └── MAINNET_DEPLOY_PLAN.md      ← deploy SOP
├── deploy-scripts/
│   ├── README.md
│   ├── 01_create_multisig.sh
│   ├── 02_compute_resource.sh
│   ├── 03_publish_via_multisig.js
│   ├── 04_smoke_mainnet.sh
│   ├── 05_seal_via_multisig.js
│   ├── 06_raise_threshold.js
│   ├── bootstrap.js                ← Pyth VAA + open_trove_pyth + sp_deposit
│   ├── package.json
│   └── package-lock.json
├── scripts/bootstrap.move          ← Move-script alternative for bootstrap
└── deps/pyth/                      ← vendored Pyth (resolves to mainnet pkg 0x7e78…)
```

## License

Unlicense (public domain). See [LICENSE](../LICENSE).

## Disclaimers

- Built by human + AI collaboration.
- D is immutable — bugs are permanent.
- Use at your own risk.
- No warranty, express or implied.
