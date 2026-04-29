#!/bin/bash
# Create 1/5 multisig with 5 owners (4 additional + creator).
# Creator = profile `mainnet` = 0x0047a3e1...
# After execution, capture the multisig address from output and pin to .env.

set -euo pipefail

cd "$(dirname "$0")/.."

# 4 other owners (creator = 0x0047 from --profile mainnet adds itself as the 5th)
OWNER_2=0x13f0c2edebcb9df033875af75669520994ab08423fe86fa77651cebbc5034a65
OWNER_3=0xf6e1d1fdc2de9d755f164bdbf6153200ed25815c59a700ba30fb6adf8eb1bda1
OWNER_4=0xc257b12ef33cc0d221be8eecfe92c12fda8d886af8229b9bc4d59a518fa0b093
OWNER_5=0xa1189e559d1348be8d55429796fd76bf18001d0a2bd4e9f8b24878adcbd5e84a

echo "=== Creating 1/5 multisig on Aptos mainnet ==="
echo "Creator: 0x0047a3e1... (profile: mainnet)"
echo "Additional owners:"
echo "  $OWNER_2"
echo "  $OWNER_3"
echo "  $OWNER_4"
echo "  $OWNER_5"
echo "Threshold: 1 of 5"
echo
read -p "Proceed? (y/N) " confirm
[[ "$confirm" == "y" ]] || { echo "Aborted."; exit 1; }

aptos multisig create \
  --additional-owners "$OWNER_2,$OWNER_3,$OWNER_4,$OWNER_5" \
  --num-signatures-required 1 \
  --profile mainnet \
  --assume-yes

echo
echo "=== NEXT STEPS ==="
echo "1. Capture multisig address from output above (e.g. 0xMULTI...)"
echo "2. echo \"D_MULTISIG=0xMULTI...\" >> /home/rera/d/aptos/.env.deploy"
echo "3. Run 02_compute_resource.sh to derive resource account address"
