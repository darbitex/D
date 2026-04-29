#!/bin/bash
# Derive resource account address from multisig + seed, update Move.toml,
# recompile, re-run unit tests.

set -euo pipefail

cd "$(dirname "$0")/.."

source .env.deploy 2>/dev/null || { echo "Missing .env.deploy with D_MULTISIG=..."; exit 1; }
[[ -n "${D_MULTISIG:-}" ]] || { echo "D_MULTISIG not set in .env.deploy"; exit 1; }

echo "=== Deriving resource account address ==="
echo "Origin multisig: $D_MULTISIG"
echo "Seed: D (utf8)"

D_RESOURCE=$(aptos account derive-resource-account-address \
  --address "$D_MULTISIG" --seed D --seed-encoding utf8 \
  | python3 -c "import json,sys; print('0x' + json.load(sys.stdin)['Result'])")

echo "Resource account: $D_RESOURCE"
echo

echo "=== Updating Move.toml: origin = $D_MULTISIG ==="
sed -i.bak "s|^origin = .*|origin = \"$D_MULTISIG\"|" Move.toml
echo "  (backup: Move.toml.bak)"
grep '^origin' Move.toml
echo

echo "=== Recompiling with D=$D_RESOURCE ==="
aptos move compile --named-addresses "D=$D_RESOURCE" --included-artifacts none > /tmp/d_compile.log 2>&1
if grep -E "^error" /tmp/d_compile.log > /dev/null; then
  echo "COMPILE FAILED — see /tmp/d_compile.log"
  exit 1
fi
echo "  compile clean"
echo

echo "=== Re-running unit tests ==="
aptos move test --named-addresses "D=$D_RESOURCE" 2>&1 | tail -3

echo
echo "=== Pin to .env.deploy ==="
echo "D_RESOURCE=$D_RESOURCE" >> .env.deploy
echo "  added: D_RESOURCE=$D_RESOURCE"
echo
echo "Next: run 03_publish_via_multisig.js to propose+execute publish"
