# D Aptos v0.2.0 — Mainnet Deploy Plan

**Status:** PREPARED 2026-04-29 — pending Claude Opus 4.7 fresh audit + user go-ahead for execution.
**SOP source:** `feedback_mainnet_deploy_sop.md` — "1/5 multisig → publish → smoke → freeze immutable → raise to 3/5. Never hot wallet."
**Pattern reference:** Darbitex Final v0.1.0 mainnet deploy (`darbitex_final_deployed.md`).

## Multisig topology

Same 5 owners as Darbitex Final / Darbitex Treasury:

| # | Owner address | Notes |
|---|---|---|
| 1 | `0x13f0c2edebcb9df033875af75669520994ab08423fe86fa77651cebbc5034a65` | preserved from beta |
| 2 | `0xf6e1d1fdc2de9d755f164bdbf6153200ed25815c59a700ba30fb6adf8eb1bda1` | preserved from beta |
| 3 | `0xc257b12ef33cc0d221be8eecfe92c12fda8d886af8229b9bc4d59a518fa0b093` | preserved from beta |
| 4 | `0xa1189e559d1348be8d55429796fd76bf18001d0a2bd4e9f8b24878adcbd5e84a` | preserved from beta |
| 5 | `0x0047a3e13465172e10661e20b7b618235e9c7e62a365d315e91cf1ef647321c9` | hot wallet, creator + executor for this deploy |

**Threshold sequence**: 1/5 (publish + bootstrap + seal) → 3/5 (post-immutable governance).

**Why 1/5 first**: only the multisig itself can call `destroy_cap` (since `@origin = multisig` and `assert!(signer::address_of(caller) == @origin)`). With 1/5, any single owner can propose-and-execute the seal in two txs without coordination friction. After seal, package is immutable regardless of multisig threshold — so raising to 3/5 is purely future governance hygiene (multisig key rotation, etc., though there's nothing left to govern post-seal).

## Pre-flight (verified 2026-04-29)

- [x] All 5 owner addresses exist on Aptos mainnet (sequence_number ≥ 4)
- [x] Creator wallet `0x0047a3e1…` mainnet balance = 11.36 APT (sufficient for create + publish + bootstrap gas)
- [x] Pyth pkg `0x7e78…` is auth_key=0x0 sealed on mainnet (per `aptos_one_v013_audit_state.md` V-03)
- [x] APT/USD feed `0x03ae4d…` registered on mainnet Pyth (verified by ONE Aptos v0.1.3 mainnet operation)
- [x] D.move + tests compile clean, 30/30 pass
- [x] Audit R1: 5/6 GREEN (Grok+Kimi+Qwen+DeepSeek+Gemini); 6th (Claude Opus 4.7 fresh) **PENDING**
- [x] Testnet rehearsal sealed at `0x3db02f4f…` (oracle-free smoke validated publish + donate_to_reserve + destroy_cap + 5 store-address views)

## Constraint

D.move's sealing model (resource-account + destroy_cap) requires the package address to be a **resource account derived from `@origin`**, not the multisig itself. So:
- Multisig is `@origin`
- Package lives at `derive(multisig_addr, seed="D")`
- Multisig calls `0x1::resource_account::create_resource_account_and_publish_package(seed, metadata, code)`
- Resource account holds the `Registry` + `ResourceCap` (with the SignerCapability for the resource account)
- Multisig calls `D::destroy_cap` to consume the SignerCapability post-bootstrap

This differs from Darbitex Final (which publishes to the multisig address directly via `code::publish_package_txn`). The CLI flow is therefore custom — we build the entry-function payload manually.

## Deploy steps

### Step 1: Create multisig (1/5)

```bash
aptos multisig create \
  --additional-owners 0x13f0c2edebcb9df033875af75669520994ab08423fe86fa77651cebbc5034a65,0xf6e1d1fdc2de9d755f164bdbf6153200ed25815c59a700ba30fb6adf8eb1bda1,0xc257b12ef33cc0d221be8eecfe92c12fda8d886af8229b9bc4d59a518fa0b093,0xa1189e559d1348be8d55429796fd76bf18001d0a2bd4e9f8b24878adcbd5e84a \
  --num-signatures-required 1 \
  --profile mainnet
```

Output → multisig address `0xMULTI`. Capture and pin to env var.

Cost: ~0.012 APT (per Darbitex Final `0x2747b1fb…`).

### Step 2: Compute resource account address + update Move.toml

```bash
RESOURCE_ADDR=$(aptos account derive-resource-account-address \
  --address 0xMULTI --seed D --seed-encoding utf8 | jq -r '.Result')

# Update Move.toml: origin = "0xMULTI"
sed -i 's|^origin = .*|origin = "0xMULTI"|' /home/rera/d/aptos/Move.toml
```

### Step 3: Recompile + verify

```bash
cd /home/rera/d/aptos
aptos move compile --named-addresses D=$RESOURCE_ADDR --included-artifacts none
aptos move test --named-addresses D=$RESOURCE_ADDR  # 30/30 must still pass
```

### Step 4: Multisig publish

Build the entry-function payload for `0x1::resource_account::create_resource_account_and_publish_package(seed, metadata_serialized, code)`. Manually construct from build artifacts in `build/D/`.

```bash
# Helper: deploy-scripts/03_build_publish_payload.js — extracts BCS metadata + code
#         from build/, produces payload.json for multisig submission
node deploy-scripts/03_build_publish_payload.js > publish_payload.json

# Propose (any owner)
aptos multisig create-transaction \
  --multisig-address 0xMULTI \
  --json-file publish_payload.json \
  --profile mainnet  # = 0x0047a3e1...

# Execute (since threshold=1, the proposer's vote alone is enough; execute as separate tx)
aptos multisig execute \
  --multisig-address 0xMULTI \
  --profile mainnet
```

Cost: propose ~0.07 APT + execute ~0.08 APT (per Darbitex Final).

After execute: pkg lives at `$RESOURCE_ADDR`, `init_module` ran, `Registry` shared, `ResourceCap` stashed.

### Step 5: Mainnet smoke (oracle-dependent — first time)

Bootstrap trove + sp_deposit via `bootstrap.js`:

```bash
DEPLOYER_KEY=$KEY_0047 \
D_ADDR=$RESOURCE_ADDR \
APTOS_NETWORK=mainnet \
APT_AMT=220000000 \  # 2.2 APT
DEBT=100000000 \      # 1 D
SP_AMT=50000000 \     # 0.5 D (leaves 0.49 D in wallet for donate test)
node deploy-scripts/bootstrap.js
```

Then validate the V2-specific paths that testnet couldn't:
```bash
# donate_to_sp: needs minted D in wallet → use the 0.49 D leftover
aptos move run --function-id $RESOURCE_ADDR::D::donate_to_sp \
  --args u64:10000000 --profile mainnet  # 0.1 D donation

# Verify: sp_pool_balance > total_sp (donation residue visible)
aptos move view --function-id $RESOURCE_ADDR::D::sp_pool_balance --profile mainnet
aptos move view --function-id $RESOURCE_ADDR::D::totals --profile mainnet

# donate_to_reserve: small APT donation
aptos move run --function-id $RESOURCE_ADDR::D::donate_to_reserve \
  --args u64:10000000 --profile mainnet  # 0.1 APT

# Verify: reserve_balance increases
aptos move view --function-id $RESOURCE_ADDR::D::reserve_balance --profile mainnet
```

Required smoke checks (all must pass before seal):
- [ ] `open_trove_pyth` works (Pyth VAA accepted, trove created, fee routed via 10/90)
- [ ] `sp_deposit` works (total_sp updated)
- [ ] `donate_to_sp` works (sp_pool > total_sp confirms agnostic donation)
- [ ] `donate_to_reserve` works (reserve_balance grows)
- [ ] All 16 view fns (totals, trove_of, sp_of, reserve_balance, sp_pool_balance, is_sealed, close_cost, trove_health, price, metadata_addr, fee_pool_addr, sp_pool_addr, sp_coll_pool_addr, reserve_coll_addr, treasury_addr, read_warning) return expected values
- [ ] All 6 store addresses are distinct and stable
- [ ] Events emitted correctly (TroveOpened, SPDeposited, SPDonated, ReserveDonated)

### Step 6: destroy_cap via multisig (seal)

```bash
# Build payload: D::destroy_cap()
echo '{
  "function": "'$RESOURCE_ADDR'::D::destroy_cap",
  "type_arguments": [],
  "arguments": []
}' > seal_payload.json

# Propose + execute (1/5 threshold = 1 owner sufficient)
aptos multisig create-transaction --multisig-address 0xMULTI --json-file seal_payload.json --profile mainnet
aptos multisig execute --multisig-address 0xMULTI --profile mainnet
```

Verify:
```bash
aptos move view --function-id $RESOURCE_ADDR::D::is_sealed --profile mainnet
# expect: true

curl https://fullnode.mainnet.aptoslabs.com/v1/accounts/$RESOURCE_ADDR/resource/$RESOURCE_ADDR::D::ResourceCap
# expect: 404 "Resource not found"
```

### Step 7: Raise threshold 1/5 → 3/5

```bash
echo '{
  "function": "0x1::multisig_account::update_signatures_required",
  "type_arguments": [],
  "arguments": ["3"]
}' > threshold_payload.json

aptos multisig create-transaction --multisig-address 0xMULTI --json-file threshold_payload.json --profile mainnet
aptos multisig execute --multisig-address 0xMULTI --profile mainnet
```

Verify on explorer that multisig threshold is now 3/5.

### Step 8: Post-deploy documentation

- Update `memory/d_aptos_v020_r1_green.md`: mainnet pkg + multisig + 6 store addresses + tx hashes + sealed=true
- Append entry to `memory/MEMORY.md`: "D Aptos v0.2.0 MAINNET LIVE + SEALED"
- Push code to `github.com/darbitex/D-aptos` (or similar) for public audit transparency
- Update Darbitex SPA `/one` route → D module integration (separate task: `lanjut D aptos frontend`)

## Cost estimate (per Darbitex Final reference)

| Step | Tx | Approx cost |
|---|---|---|
| Multisig create | 1 | 0.012 APT |
| Resource derivation | 0 | free (offline) |
| Publish propose | 1 | 0.07 APT |
| Publish execute | 1 | 0.08 APT |
| Bootstrap (open_trove_pyth) | 1 | ~0.005 APT (Pyth fee + gas) + 2.2 APT bootstrap collateral |
| sp_deposit | 1 | ~0.001 APT |
| donate_to_sp smoke | 1 | ~0.001 APT |
| donate_to_reserve smoke | 1 | ~0.001 APT |
| Seal propose + execute | 2 | ~0.0006 APT |
| Threshold raise propose + execute | 2 | ~0.0006 APT |
| **Total deploy spend** | ~10 txs | **~2.37 APT** (mostly bootstrap collateral, recoverable) |

0x0047 has 11.36 APT mainnet — comfortable headroom. After deploy, ~9 APT free remains.

## Rollback considerations

| Failure mode | Recovery |
|---|---|
| Multisig create fails | Retry; no impact (failed tx just costs gas) |
| Publish fails (compile error) | Move.toml + recompile; retry propose. Multisig is reusable. |
| Publish succeeds but bootstrap fails | Investigate (Pyth feed? collateral too low?); retry bootstrap. Pkg is upgradeable until destroy_cap (just increment version + republish via multisig). |
| Seal fails | Retry. Multisig + ResourceCap intact. |
| Seal succeeds, smoke discovers bug post-seal | **NO RECOVERY** — package is permanently immutable. Mitigation: thorough smoke BEFORE seal. |
| Threshold raise fails | Retry. Threshold 1/5 still functional. |

**Critical irreversible action**: Step 6 (destroy_cap). Pre-flight checklist for Step 6:
- [ ] All Step 5 smoke checks pass
- [ ] R1 audit phase closed (Claude Opus 4.7 fresh result documented + user signoff)
- [ ] User explicit GO confirmation

## Resume keywords

- `lanjut D aptos mainnet step 1` — execute multisig creation
- `lanjut D aptos mainnet step 4` — execute publish (after resource addr computed + Move.toml updated)
- `lanjut D aptos mainnet step 5` — execute smoke
- `lanjut D aptos mainnet step 6` — execute seal (point of no return; requires user GO)
- `lanjut D aptos mainnet step 7` — raise threshold post-seal
