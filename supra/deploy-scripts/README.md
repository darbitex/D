# D Supra deploy scripts

All scripts read `DEPLOYER_KEY` from `process.env`. Set via:

```bash
export DEPLOYER_KEY=0x<32-byte-ed25519-hex>
# or
cp .env.example .env && edit .env && set -a && source .env && set +a
```

## Sequential deploy flow (mainnet, executed 2026-04-30)

| # | Script | Purpose | Sender |
|---|---|---|---|
| 01 | `01_create_multisig.js` | Create 1/5 multisig with 4 D-Aptos sibling owners + creator | hot wallet |
| 02 | `02_compute_resource_mainnet.js` | Derive `@D` resource address from multisig + seed `b"D"` | (offline computation) |
| 03 | `03_deploy_mainnet.js` | Idempotent: funder migrate + funder→multisig + multisig publish + bootstrap (failed inner) + destroy_cap + raise threshold 3/5 | hot wallet (proposes+executes via 1/5 multisig) |
| 04 | `04_bootstrap_self_mainnet.js` | Self-bootstrap from 0x0047 (multisig route blocked after threshold raise) | hot wallet |
| 05 | `05_sp_deposit_mainnet.js` | sp_deposit 0.0333 D into Stability Pool | hot wallet |

## Testnet rehearsal scripts

| Script | Purpose |
|---|---|
| `02_publish_testnet.js` | Publish via `0x1::resource_account::create_resource_account_and_publish_package` |
| `03_bootstrap_testnet.js` | Run `bootstrap.move` script (Coin→FA + open_trove) |
| `04_smoke_full.js` | Full 12-entry + 16-view smoke with 2 generated wallets |
| `05_smoke_continue.js` | Continue smoke for redeem_from_reserve / sp_claim / sp_withdraw |
| `06_close_trove_test.js` | Cross-wallet D top-up + close_trove |

## Helper

`_fund_owners.js` — one-shot tx record (4 owner accounts seeded with 1 SUPRA each on mainnet).

## Pre-req

```bash
npm install   # installs supra-l1-sdk + deps
aptos move build-publish-payload \
  --json-output-file /tmp/d-supra-mainnet-publish.json \
  --named-addresses D=<resource_addr>,origin=<multisig_addr> \
  --bytecode-version 6 --language-version 1 \
  --skip-fetch-latest-git-deps
```

## Files NOT committed

- `wallets.json` — generated test wallet keys (ed25519). Re-generated on next run if missing.
- `.env` — local environment (DEPLOYER_KEY).
- `node_modules/` — npm deps.
