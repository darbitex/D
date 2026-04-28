# Why D — redeploy from ONE Sui v0.1.0

**Date:** 2026-04-28
**Original:** ONE Sui v0.1.0 — sealed mainnet at `0x9f39a102363cec6218392c2e22208b3e05972ecc87af5daa62bac7015bf3b8dc`
**Redeploy:** D v0.2.0 — sealed mainnet at `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7`

## Why redeploy

ONE Sui v0.1.0 had two design properties we wanted to improve, and one of them required a **breaking change** that an immutable contract cannot patch in-place:

### 1. Reward dilution from satellite donation pattern

The original ONE design routed 25% of every mint/redeem fee to instant burn and 75% to the SP fee accumulator. To support the satellite-ecosystem use case ("token factory creation fees fortify the stablecoin"), we wanted satellites to contribute permanently to SP capacity.

With v0.1.0's accounting, every donation grew `total_sp` (the reward distribution denominator), which **diluted real depositors' yield share** proportionally to donation flow rate. Mathematical analysis: at 1:1 donation:position ratio, real depositors lost ~20% of their share.

**The right fix is a structural change**: `total_sp` tracks keyed positions only, donations affect `sp_pool` balance only. Liquidation math derives from actual pool balance via `pool_before` denominator. This requires modifying:
- `route_fee` body (split + denominator)
- `liquidate` body (product_factor + total_sp adjustment formulas)
- And surfaces a new attack vector (truncation decoupling — see below)

These are not additive — they change the existing audited V1 paths. Cannot be patched in a sealed contract. Hence redeploy.

### 2. Increased depositor yield (10/90 from 25/75)

While at it: V1's 25% instant burn was deflationary by design but at the cost of depositor APR. V2 redirects the 25% portion to SP donation (becomes 10% in v2 with the rebalance) and gives the remaining 90% to depositors. Long-term supply effect is equivalent (the donation eventually burns via liquidation absorption); short-term depositor yield improves 20%.

### 3. Truncation decoupling DoS (caught by external audit)

During the V2 audit (Claude Opus 4.7 fresh session R1), a **HIGH** severity vulnerability was identified in the V2 design: u64/u128 truncation decoupling between `total_sp` and `product_factor` could create a state where `total_sp == 0` while keyed positions remain in the position table. This would cause `route_fee` to abort with division-by-zero on every subsequent mint/redeem operation — sustained DoS.

**Resolution applied pre-deploy** (V2 R2 GREEN by Claude):
- `route_fee` cliff predicate changed from `table::length(&sp_positions) == 0` to `r.total_sp == 0`
- `liquidate` adds invariant guard: `assert!(total_before == 0 || total_sp_new > 0, E_P_CLIFF)` prevents bad state from arising
- Plus regression test reproducing the original PoC

This is the single biggest argument for redeploy: the bug was V2-design-specific. V1 didn't have it (no donation flow into total_sp). Without a fresh deploy, the mitigation couldn't be applied to the new design.

## Why rebrand to D

Practical reasons:
- Different package ID = different Coin type (`0xNEW::D::D` ≠ `0x9f39a102::ONE::ONE`). Cannot share Coin instances even if both alive.
- Avoid user confusion between v1 and v2 instances both named "ONE".
- Clean break for satellite ecosystem (token factory fees flow to D, not ONE).
- Single character name (D) cheaper for indexer event matching, frontend display.

## What stays the same

- **Architecture**: Liquity V1 style CDP, 200% MCR, 150% liquidation threshold, 10% liquidation bonus.
- **Sealing model**: cryptographically immutable via `package::make_immutable`. Zero admin escape.
- **Oracle**: Pyth Sui SUI/USD feed (same risk surface, documented in WARNING).
- **Min debt**: 1 D (retail-first, anti-whale).
- **8-decimal Coin type**, 9-decimal SUI scale.
- **Reserve mechanics**: 25% liquidation bonus → reserve_coll (same redemption capacity).

## V1 → V2 detailed diff

| Component | V1 (ONE) | V2 (D) |
|---|---|---|
| Module path | `ONE::ONE` | `D::D` |
| Coin display name / symbol | "1" / "ONE" | "D" / "D" |
| Mint/redeem fee split | 25% burn / 75% SP rewards | **10% SP donation / 90% SP rewards** |
| Donation accounting | (no donation primitive) | **Agnostic donation: bypass total_sp** |
| `donate_to_sp(reg, coin, ctx)` | absent | **NEW** public permissionless |
| `donate_to_reserve(reg, coin, ctx)` | absent | **NEW** public permissionless |
| `liquidate` denominator | `total_sp` | **`balance::value(&sp_pool)`** |
| `total_sp` post-liquidation | `total_sp - debt` | **`total_sp × (pool_before - debt) / pool_before`** |
| Cliff orphan handling | (V1 didn't have donation orphan path) | **`sp_coll → reserve_coll` redirect when `total_before == 0`** |
| `MIN_P_THRESHOLD` cliff guard | always active | **skipped when `total_before == 0`** (LOW-1 fix) |
| `FeeBurned` event | emitted by route_fee 25% | **removed** (V2 has SPDonated instead) |
| `SPDepositedFor` event | absent | considered, **dropped** (donate_to_sp obviates) |
| Truncation guard | (V1 didn't have donation flow into total_sp, no truncation path) | **`assert!(total_before == 0 \|\| total_sp_new > 0, E_P_CLIFF)`** (HIGH-1 fix) |
| Source LOC | ~830 (V1) | 870 (V2) |

## Audit ledger

V1 (ONE Sui v0.1.0): 6 external auditor passes, 0 H/M/L (Gemini ×2, Grok ×2, Claude ×1, Qwen ×1, DeepSeek ×1, Kimi ×1).

V2 (D v0.2.0):
- 5 external auditors GREEN on initial bundle (Kimi, Grok, DeepSeek, Qwen, Gemini)
- 1 external auditor (Claude Opus 4.7 fresh session) found HIGH-1 truncation decoupling
- HIGH-1 + LOW-1 resolved
- Claude R2 GREEN ("R1→R2 turnaround exemplary, cleanest patch cycle expected on real audit")

Self-audit + 6 external audits + R2 verification = 8 audit passes total.

## ONE v0.1.0 status

ONE v0.1.0 mainnet at `0x9f39a102…` is **sealed and DEPRECATED but still functional**:
- Existing v0.1.0 troves, SP positions, reserve_coll: still operable via the v0.1.0 contract.
- Wind-down available for users who want to exit: close_trove, sp_withdraw, redeem_from_reserve still work.
- No new mints recommended — use D v0.2.0 instead.

D v0.2.0 is the **successor** for all new activity. Migration is voluntary (no forced redemption mechanism) — users with v0.1.0 positions can either close them and reopen on D, or hold v0.1.0 until they choose to wind down.

## V2 mainnet IDs

| Object | Mainnet |
|---|---|
| Package | `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7` |
| Registry | `0x22992b14865add7112b62f6d1e0e5194d8495c701f82e1d907148dfb53b9fc82` |
| Currency<D> | `0x153626a88eee83679f7a44f633b5ed97480e0d7db3a77c60a692246b3977bb0d` |
| Coin type | `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7::D::D` |
| Publish tx | `53FJJ4uYTjmaXpRuFqrBgifKcLUe6sPbMhZnGt6rckJs` |
| Seal tx | `EzUDjieeLf6yPkn4Cx71XHQg5njaHv9b2vwNNwFTYJuf` |

OriginCap deleted (`0x1a185b00…`), UpgradeCap consumed (`0xf82ac470…`). Package permanently immutable via `sui::package::make_immutable`. Registry.sealed = true.
