// Compute D resource account address from multisig + seed b"D" (mainnet).
const crypto = require('crypto');

const MULTISIG = '0xbefe37923ac3910dc5c2d3799941e489da460cb6c8f8b69c70d68390397571f5';
const SEED = Buffer.from('D'); // b"D"

// Aptos derive_resource_address: sha3-256(creator || seed || 0xFF)
const h = crypto.createHash('sha3-256');
h.update(Buffer.concat([
  Buffer.from(MULTISIG.slice(2), 'hex'),
  SEED,
  Buffer.from([0xFF]),
]));
const derived = '0x' + h.digest('hex');

console.log(`creator (multisig): ${MULTISIG}`);
console.log(`seed: b"D"`);
console.log(`@D (resource_addr) MAINNET: ${derived}`);
