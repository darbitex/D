// Close W1 trove by topping up D from 0x0047 funder wallet (which has 0.0099 D
// from initial bootstrap). W1 short 0.00542 D — funder transfers 0.0055 D, W1 closes.
const fs = require('fs');
const { SupraClient, SupraAccount, BCS, TxnBuilderTypes } = require('supra-l1-sdk');

const RPC = 'https://rpc-testnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_PKG = '0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c';
const D_META = '0xc39458d09de1e108ddb5f175226f50c44a7f0f9b0dd4abf0d0f54d8bcfde8081';
const SUPRA_FA = '0xa';

async function viewCall(fn, args = [], typeArgs = []) {
  const r = await fetch(`${RPC}/rpc/v3/view`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: fn, type_arguments: typeArgs, arguments: args }),
  });
  const j = await r.json();
  if (j.message) throw new Error(`view err: ${j.message}`);
  return j.result;
}
async function balFA(addr, meta) {
  const r = await viewCall('0x1::primary_fungible_store::balance', [addr.toString(), meta], ['0x1::fungible_asset::Metadata']);
  return Number(r[0]) / 1e8;
}
async function pollTx(c, sender, txHash) {
  for (let i = 0; i < 12; i++) {
    await new Promise(r => setTimeout(r, 1500));
    try { const d = await c.getTransactionDetail(sender.address(), txHash); if (d && d.status !== 'Pending') return d; } catch {}
  }
  throw new Error('timeout');
}
async function submitEntry(c, sender, label, mod, fn, typeArgs, args, maxGas = 200000n) {
  const info = await c.getAccountInfo(sender.address());
  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number, ...mod.split('::'), fn, typeArgs, args, { maxGas });
  console.log(`  → ${label}...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`     ✓ gas=${d.gasUsed} tx=${r.txHash}`);
  return d;
}

(async () => {
  const c = await SupraClient.init(RPC);
  const funder = new SupraAccount(Uint8Array.from(Buffer.from(FUNDER_KEY.slice(2), 'hex')));
  const { w1: w1Key } = JSON.parse(fs.readFileSync(`${__dirname}/wallets.json`, 'utf8'));
  const w1 = new SupraAccount(Uint8Array.from(Buffer.from(w1Key.slice(2), 'hex')));

  // Pre-state
  const fundD0 = await balFA(funder.address(), D_META);
  const w1D0 = await balFA(w1.address(), D_META);
  const w1Trove0 = await viewCall(`${D_PKG}::D::trove_health`, [w1.address().toString()]);
  const w1FA0 = await balFA(w1.address(), SUPRA_FA);
  console.log(`PRE: funder D=${fundD0} | W1 D=${w1D0} trove=${w1Trove0[0]}/${w1Trove0[1]} W1 FA=${w1FA0}`);

  // Step 1: funder transfer 0.0055 D → W1 (covers W1's shortfall)
  const sMeta = new BCS.Serializer();
  TxnBuilderTypes.AccountAddress.fromHex(D_META).serialize(sMeta);
  const sRecip = new BCS.Serializer();
  TxnBuilderTypes.AccountAddress.fromHex(w1.address().toString()).serialize(sRecip);
  await submitEntry(c, funder, 'funder→W1 0.0055 D',
    '0x1::primary_fungible_store', 'transfer',
    [new TxnBuilderTypes.TypeTagStruct(TxnBuilderTypes.StructTag.fromString('0x1::fungible_asset::Metadata'))],
    [sMeta.getBytes(), sRecip.getBytes(), BCS.bcsSerializeUint64(550_000n)],
    50000n);

  const w1D1 = await balFA(w1.address(), D_META);
  console.log(`  W1 D after transfer: ${w1D1}`);

  // Step 2: W1 close_trove
  const cost = Number((await viewCall(`${D_PKG}::D::close_cost`, [w1.address().toString()]))[0]);
  console.log(`  close_cost: ${cost / 1e8} D, W1 has ${w1D1} D`);
  await submitEntry(c, w1, 'W1 close_trove', `${D_PKG}::D`, 'close_trove', [], []);

  // Verify
  const w1TroveAfter = await viewCall(`${D_PKG}::D::trove_health`, [w1.address().toString()]);
  const w1DAfter = await balFA(w1.address(), D_META);
  const w1FAAfter = await balFA(w1.address(), SUPRA_FA);
  console.log(`POST: W1 trove=${w1TroveAfter[0]}/${w1TroveAfter[1]} D=${w1DAfter} FA=${w1FAAfter}`);
  if (Number(w1TroveAfter[1]) === 0) console.log('\n✅ close_trove SUCCESS — trove deleted, collateral returned');
  else console.log('\n❌ close_trove unexpected residual');
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,400)); process.exit(1); });
