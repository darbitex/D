// Generic mainnet smoke runner for entry fns that need Pyth VAA arg.
// Usage:
//   node smoke_run.js <profile_key_hex> <function> <arg1:type=...> ... [--vaa]
// Example:
//   node smoke_run.js 0x107a... redeem_pyth u64:20000000 address:0x004... --vaa

const path = require('path');
const {
  Aptos, AptosConfig, Network, Account, Ed25519PrivateKey,
} = require('@aptos-labs/ts-sdk');

const D = '0x587c80846b18b7d7c3801fe11e88ca114305a5153082b51d0d2547ad48622c77';
const APT_USD_FEED = '0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5';

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('Usage: node smoke_run.js <key_hex> <fn_name> [args...] [--vaa]');
  process.exit(1);
}

const keyHex = args.shift();
const fnName = args.shift();
const needsVaa = args.includes('--vaa');
const userArgs = args.filter(a => a !== '--vaa');

(async () => {
  const aptos = new Aptos(new AptosConfig({ network: Network.MAINNET }));
  const acct = Account.fromPrivateKey({ privateKey: new Ed25519PrivateKey(keyHex) });
  console.log(`signer: ${acct.accountAddress.toString()}`);

  const functionArguments = userArgs.map(a => {
    const [type, value] = a.split(':');
    if (type === 'u64') return value;
    if (type === 'address') return value;
    throw new Error(`unknown arg type: ${type}`);
  });

  if (needsVaa) {
    const vaaResp = await fetch(`https://hermes.pyth.network/api/latest_vaas?ids[]=${APT_USD_FEED}`);
    const vaaB64 = (await vaaResp.json())[0];
    const vaaBytes = Array.from(Buffer.from(vaaB64, 'base64'));
    functionArguments.push([vaaBytes]);
    console.log(`  VAA fetched: ${vaaBytes.length} bytes`);
  }

  console.log(`fn: ${D}::D::${fnName}`);
  console.log(`args: ${JSON.stringify(functionArguments).slice(0, 200)}`);

  const tx = await aptos.transaction.build.simple({
    sender: acct.accountAddress,
    data: { function: `${D}::D::${fnName}`, functionArguments },
    options: { maxGasAmount: 200000, gasUnitPrice: 100 },
  });
  const resp = await aptos.signAndSubmitTransaction({ signer: acct, transaction: tx });
  console.log(`  tx: ${resp.hash}`);
  const r = await aptos.waitForTransaction({ transactionHash: resp.hash });
  console.log(`  ${r.success ? '✓' : '✗'} ${r.vm_status}`);
  if (!r.success) process.exit(1);
})().catch(e => { console.error('ERROR:', e.message || e); process.exit(1); });
