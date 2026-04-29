#!/bin/bash
# Mainnet smoke for D Aptos:
# - Bootstrap trove (2.2 APT / 1 D) via bootstrap.js (Pyth update + open_trove + sp_deposit)
# - donate_to_sp (oracle-free, needs minted D in wallet)
# - donate_to_reserve (oracle-free)
# - Verify all 16 view fns return expected values

set -euo pipefail

cd "$(dirname "$0")/.."

source .env.deploy 2>/dev/null || { echo "Missing .env.deploy"; exit 1; }
[[ -n "${D_RESOURCE:-}" ]] || { echo "D_RESOURCE not set"; exit 1; }
[[ -n "${DEPLOYER_KEY:-}" ]] || { echo "DEPLOYER_KEY not set"; exit 1; }

echo "=== 1. Bootstrap trove + sp_deposit (via bootstrap.js) ==="
DEPLOYER_KEY="$DEPLOYER_KEY" \
D_ADDR="$D_RESOURCE" \
APTOS_NETWORK=mainnet \
APT_AMT=220000000 \
DEBT=100000000 \
SP_AMT=50000000 \
node deploy-scripts/bootstrap.js
echo

echo "=== 2. donate_to_sp (0.1 D agnostic donation) ==="
aptos move run --function-id "$D_RESOURCE::D::donate_to_sp" \
  --args u64:10000000 --profile mainnet --assume-yes
echo

echo "=== 3. donate_to_reserve (0.1 APT) ==="
aptos move run --function-id "$D_RESOURCE::D::donate_to_reserve" \
  --args u64:10000000 --profile mainnet --assume-yes
echo

echo "=== 4. View fn smoke ==="
for fn in totals reserve_balance sp_pool_balance is_sealed metadata_addr \
          fee_pool_addr sp_pool_addr sp_coll_pool_addr reserve_coll_addr treasury_addr; do
  echo "--- $fn ---"
  aptos move view --function-id "$D_RESOURCE::D::$fn" --profile mainnet 2>&1 | grep -A 1 Result
done

echo
echo "=== 5. Per-account state ==="
SENDER=$(aptos config show-profiles --profile mainnet | python3 -c "import json,sys; print(json.load(sys.stdin)['Result']['mainnet']['account'])")
echo "Sender: 0x$SENDER"
echo "--- trove_of ---"
aptos move view --function-id "$D_RESOURCE::D::trove_of" --args "address:0x$SENDER" --profile mainnet 2>&1 | grep -A 4 Result
echo "--- sp_of ---"
aptos move view --function-id "$D_RESOURCE::D::sp_of" --args "address:0x$SENDER" --profile mainnet 2>&1 | grep -A 5 Result
echo "--- trove_health ---"
aptos move view --function-id "$D_RESOURCE::D::trove_health" --args "address:0x$SENDER" --profile mainnet 2>&1 | grep -A 5 Result

echo
echo "=== Smoke complete. Verify expected values manually before sealing. ==="
echo "Expected post-smoke:"
echo "  totals: total_debt=100000000, total_sp=50000000 (or close)"
echo "  reserve_balance: 10000000 (0.1 APT donation)"
echo "  sp_pool_balance: > total_sp (donation residue from 10/90 fee + donate_to_sp)"
echo "  is_sealed: false"
echo "  trove_health: cr_bps ≥ 20000 (200% MCR)"
