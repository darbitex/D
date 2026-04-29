# D Aptos Mainnet Deploy Scripts

Sequential helper scripts for the multisig deploy flow described in `audit/MAINNET_DEPLOY_PLAN.md`.

## Prereqs

- `.aptos/config.yaml` with `mainnet` profile (already copied from ONE Aptos)
- `node_modules/` populated: `cd deploy-scripts && npm install`
- 0x0047 mainnet balance ≥ 3 APT (currently 11.36 APT — comfortable)
- `.env.deploy` (gitignored): `DEPLOYER_KEY=0x...` (private key for 0x0047)

## Order

| # | Script | Action | Cost | Reversible |
|---|---|---|---|---|
| 1 | `01_create_multisig.sh` | Create 1/5 multisig with 5 owners | ~0.012 APT | Multisig stays usable; can scrap and create new one |
| 2 | `02_compute_resource.sh` | Derive resource addr + update Move.toml + recompile + retest | 0 (offline) | Move.toml.bak preserved |
| 3 | `03_publish_via_multisig.js` | Multisig propose + execute publish | ~0.15 APT | Pre-seal: republish via multisig if bug found |
| — | `bootstrap.js` (existing) | Open trove + sp_deposit (oracle-dependent) | ~0.005 APT + 2.2 APT collateral | trove can be closed |
| 4 | `04_smoke_mainnet.sh` | Full smoke: bootstrap + donate_to_sp + donate_to_reserve + 16 view fns | ~0.01 APT | All ops reversible (close_trove, sp_withdraw — donations are one-way) |
| 5 | `05_seal_via_multisig.js` | Multisig propose + execute `destroy_cap` | ~0.0006 APT | **IRREVERSIBLE** |
| 6 | `06_raise_threshold.js` | Multisig propose + execute threshold 1/5 → 3/5 | ~0.0006 APT | Reversible (can lower again with 3/5 threshold) |

## Step gates

Each step requires explicit user GO before execution. Steps 1-4 are reversible; **Step 5 (seal) requires `CONFIRM_SEAL=YES` env var as kill-switch**.

Pre-Step-5 mandatory:
- All Step 4 smoke checks pass empirically
- R1 audit phase closed (Claude Opus 4.7 fresh result documented + user signoff)
- User explicit GO confirmation

## .env.deploy example (gitignored — never commit real values)

```bash
DEPLOYER_KEY=0x<your-mainnet-private-key-hex>   # extract from .aptos/config.yaml profile mainnet
D_MULTISIG=0x...        # populated after step 1
D_RESOURCE=0x...        # populated after step 2
```

**Secret hygiene**: `.env.deploy` and `.aptos/config.yaml` are gitignored. Verify with `git check-ignore .env.deploy` before each commit. Never paste real private keys into chat, README, or audit bundles.

## Rollback notes

- Steps 1-4: re-runnable, idempotent where applicable.
- Step 3 publish: pre-seal package is upgradeable via multisig (compat policy). Bump version + republish via multisig if bug found.
- Step 5 seal: NO ROLLBACK. Verify all smoke checks pass first.
- Step 6 threshold: trivially reversible while threshold > 0.

## TS-SDK version

Pinned via `package.json` dep `@aptos-labs/ts-sdk@^6.3.1`. Module API surface used: `Aptos`, `AptosConfig`, `Network`, `Account`, `Ed25519PrivateKey`, `generateTransactionPayload`, `MultiSigTransactionPayload`, `MoveVector`, `AccountAddress`.
