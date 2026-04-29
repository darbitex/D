// 0x0047 final donations: 0.01 D → SP, 10 SUPRA → reserve.
const { SupraClient, SupraAccount, BCS } = require('supra-l1-sdk');

const RPC = 'https://rpc-mainnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_PKG = '0x033374e8457b4e52050f64eee98848cad68cf8c5c004858d8f3df009c57a83d9';

const SP_AMT = 1_000_000n;        // 0.01 D, 8 dec
const RESERVE_AMT = 1_000_000_000n; // 10 SUPRA, 8 dec

async function pollTx(c, sender, txHash) {
  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 2000));
    try { const d = await c.getTransactionDetail(sender.address(), txHash); if (d && d.status !== 'Pending') return d; } catch {}
  }
  throw new Error(`timeout ${txHash}`);
}

async function callEntry(c, sender, label, fn, args) {
  const info = await c.getAccountInfo(sender.address());
  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number,
    D_PKG, 'D', fn, [], args,
    { maxGas: 100000n }
  );
  console.log(`${label}...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`✓ gas=${d.gasUsed} tx=${r.txHash}`);
}

(async () => {
  const c = await SupraClient.init(RPC);
  const sender = new SupraAccount(Uint8Array.from(Buffer.from(FUNDER_KEY.slice(2), 'hex')));

  await callEntry(c, sender, 'donate_to_sp(0.01 D)', 'donate_to_sp',
    [BCS.bcsSerializeUint64(SP_AMT)]);
  await callEntry(c, sender, 'donate_to_reserve(10 SUPRA)', 'donate_to_reserve',
    [BCS.bcsSerializeUint64(RESERVE_AMT)]);

  // Verify
  const r1 = await fetch(`${RPC}/rpc/v3/view`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::sp_pool_balance`, type_arguments: [], arguments: [] }) });
  const r2 = await fetch(`${RPC}/rpc/v3/view`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::reserve_balance`, type_arguments: [], arguments: [] }) });
  const r3 = await fetch(`${RPC}/rpc/v3/view`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::totals`, type_arguments: [], arguments: [] }) });
  console.log(`\nsp_pool_balance: ${(await r1.json()).result[0]} (= sp_keyed + donations)`);
  console.log(`reserve_balance: ${(await r2.json()).result[0]} raw SUPRA`);
  console.log(`totals: ${JSON.stringify((await r3.json()).result)}`);
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
