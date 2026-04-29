# D — immutable stablecoin (Sui + Aptos)

D is a sealed, governance-free, retail-first CDP stablecoin contract. Architecture: Liquity V1 + agnostic donation primitive (V2 design). Same code semantics on both chains; different sealing model + dialect.

**LIVE + SEALED on both chains:**

| Chain | Package | Sealed | Date |
|---|---|---|---|
| Sui | [`0x898d83f0…8910b0d7`](https://suiscan.xyz/mainnet/object/0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7) | `package::make_immutable` | 2026-04-28 |
| Aptos | [`0x587c8084…48622c77`](https://explorer.aptoslabs.com/account/0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77?network=mainnet) | resource-account + `destroy_cap` (3-of-5 multisig governs the empty multisig shell) | 2026-04-29 |

See chain-specific READMEs for full address inventory + audit history:
- **Sui**: details below in this file.
- **Aptos**: [`aptos/README.md`](./aptos/README.md) — multisig + 5 store addresses + tx trail + audit ledger.

---

## D on Sui

| Object | ID |
|---|---|
| Package | `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7` |
| Registry | `0x22992b14865add7112b62f6d1e0e5194d8495c701f82e1d907148dfb53b9fc82` |
| Currency<D> | `0x153626a88eee83679f7a44f633b5ed97480e0d7db3a77c60a692246b3977bb0d` |
| Coin type | `0x898d83f0e128eb2024e435bc9da116d78f47c631e74096e505f5c86f8910b0d7::D::D` |

Package owner: **Immutable** (consumed via `sui::package::make_immutable`). Registry.sealed = true. OriginCap deleted, UpgradeCap consumed.

## Why D (and not just ONE v2)

D is a redeploy of [ONE Sui v0.1.0](https://github.com/darbitex/ONE) (also still live at `0x9f39a102…`) with three motivating changes that required a breaking redeploy:

1. **Agnostic donation primitive.** Donations bypass `total_sp` denominator → real depositors get full yield without dilution from satellite ecosystem flow.
2. **10/90 fee split** (was 25/75). Depositors get 20% more yield.
3. **Truncation decoupling guard.** Caught by external audit (Claude Opus 4.7 R1 HIGH-1) — V2-design-specific bug, fixed pre-deploy.

See [REDEPLOY_FROM_ONE.md](./REDEPLOY_FROM_ONE.md) for full rationale + diff.

ONE v0.1.0 is **deprecated** but still functional for wind-down. D v0.2.0 is the successor for new activity.

## Protocol parameters

| Parameter | Value |
|---|---|
| Collateral | SUI (`0x2::sui::SUI`) |
| MCR (mint) | 200% |
| Liquidation threshold | 150% |
| Liquidation bonus | 10% (25% liquidator + 25% reserve + 50% SP) |
| Mint fee | 1% (10% donate to SP + 90% SP rewards distribution) |
| Redeem fee | 1% (same split) |
| Min debt | 1 D |
| Decimals | 8 (D), 9 (SUI scale) |
| Oracle | Pyth SUI/USD feed `23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744` |
| Staleness | 60s |
| Confidence cap | 200 bps |
| Sealing | `package::make_immutable` + Registry.sealed=true |
| Governance | None |

## Public surface

**Trove ops:**
- `open_trove(reg, coll: Coin<SUI>, debt: u64, pi, clock, ctx) → Coin<D>`
- `add_collateral(reg, coll: Coin<SUI>)`
- `close_trove(reg, d_in: Coin<D>, ctx) → Coin<SUI>`
- `redeem(reg, d_in: Coin<D>, target: address, pi, clock, ctx) → Coin<SUI>`
- `redeem_from_reserve(reg, d_in: Coin<D>, pi, clock, ctx) → Coin<SUI>`
- `liquidate(reg, target, pi, clock, ctx) → Coin<SUI>`

**SP ops:**
- `sp_deposit(reg, d_in: Coin<D>, ctx)`
- `sp_withdraw(reg, amt, ctx) → Coin<D>`
- `sp_claim(reg, ctx)`

**Donations (V2 NEW):**
- `donate_to_sp(reg, d_in: Coin<D>, ctx)` — agnostic D donation, no position created
- `donate_to_reserve(reg, sui_in: Coin<SUI>, ctx)` — SUI to reserve_coll, fortifies redemption capacity

**Views:**
- `read_warning() → vector<u8>`
- `is_sealed(reg) → bool`
- `totals(reg) → (debt, sp, p, r_d, r_coll)`
- `trove_of(reg, addr) → (coll, debt)`
- `sp_of(reg, addr) → (bal, p_d, p_coll)`
- `reserve_balance(reg) → u64`
- `close_cost(reg, addr) → u64`
- `trove_health(reg, addr, pi, clock) → u128`
- `price_view(pi, clock) → u128`

**Entry wrappers** for CLI usability: `open_trove_entry`, `close_trove_entry`, `redeem_entry`, `redeem_from_reserve_entry`, `liquidate_entry`, `sp_withdraw_entry`.

## Repo structure

```
d/
├── REDEPLOY_FROM_ONE.md          ← why D, V1→V2 diff, audit ledger
├── README.md                      ← this file
├── LICENSE                        ← Unlicense (public domain)
└── sui/
    ├── Move.toml
    ├── Published.toml             ← canonical mainnet address
    ├── sources/D.move             ← 870 LOC contract
    ├── tests/D_tests.move         ← 29/29 PASS unit tests
    ├── audit/
    │   ├── SELF_AUDIT_R1.md
    │   ├── AUDIT_R1_BUNDLE.md     ← submitted to 6 auditors
    │   ├── AUDIT_R2_BUNDLE.md     ← Claude HIGH-1 fix verification
    │   ├── AUDIT_TRACKING.md
    │   └── EXTERNAL_R{1,2}_*.md   ← per-auditor responses
    ├── deploy-scripts/
    │   ├── publish.sh             ← Tx 1
    │   ├── seal.ts                ← Tx 2 PTB (finalize_registration + destroy_cap)
    │   ├── verify.ts              ← post-seal sanity check
    │   ├── smoke.ts               ← testnet smoke harness
    │   └── publish-output.json    ← canonical mainnet IDs
    └── deps/                      ← vendored Pyth + Wormhole
```

## Audit summary

- **Self-audit R1**: 0 H / 0 M / 0 L (1 LOW pre-resolved) / 2 INFO. GREEN.
- **External R1** (6 auditors):
  - Kimi K2.6: GREEN
  - Grok 4: GREEN
  - DeepSeek: GREEN
  - Qwen3.6: GREEN
  - Gemini 3 Pro: GREEN
  - Claude Opus 4.7 (fresh session): YELLOW — found HIGH-1 truncation decoupling
- **HIGH-1 fix applied** + 2 regression tests added
- **External R2** (Claude verification): GREEN — "R1→R2 turnaround exemplary, cleanest patch cycle expected on real audit"
- **8 total audit passes**, 0 unresolved findings ≥ MEDIUM.

## WARNING (excerpt — full text on-chain via `read_warning()`)

D is an immutable stablecoin contract on Sui that depends on Pyth Network's on-chain price feed for SUI/USD. If Pyth degrades or misrepresents its oracle, D's peg mechanism breaks deterministically — users can wind down via self-close without external assistance, but new mint/redeem operations become unreliable or frozen. **D is immutable = bug is real. Audit this code yourself before interacting.**

10% of each mint and redeem fee is redirected to the Stability Pool as agnostic donation (does NOT increment total_sp; no reward dilution). Donations participate in liquidation absorption pro-rata via actual sp_pool balance. Remaining 90% distributes to keyed SP depositors. Total: 1% supply-vs-debt gap per fee cycle, fully draining via SP burns over time.

ORACLE UPGRADE RISK: Pyth Sui (`0x04e20ddf…`, state `0x1f931023…`) is NOT cryptographically immutable. UpgradeCap inside shared State, policy=0 (compatible), Pyth DAO controlled via Wormhole VAA governance. Sui's compatibility checker prevents signature regressions but does NOT prevent feed-id deregistration, Price struct field reshuffling, or Wormhole state rotation. No admin escape once D is sealed.

Oracle-free escape hatches remain fully open for unwind: `close_trove`, `add_collateral`, `sp_deposit`, `sp_withdraw`, `sp_claim`. Protocol-owned SUI in reserve_coll becomes permanently locked if oracle freezes (`redeem_from_reserve` requires oracle). Acceptable as external-dependency risk.

## License

Unlicense (public domain). See [LICENSE](./LICENSE).

## Disclaimers

- Built by human + AI collaboration. Audit history above documents the chain of review.
- D is immutable — bugs are permanent.
- Use at your own risk.
- No warranty, express or implied.
