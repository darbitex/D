// 0x0047 sp_deposit 0.0333 D after self-bootstrap.
const { SupraClient, SupraAccount, BCS } = require('supra-l1-sdk');

const RPC = 'https://rpc-mainnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_PKG = '0x033374e8457b4e52050f64eee98848cad68cf8c5c004858d8f3df009c57a83d9';
const AMT = 3_330_000n;  // 0.0333 D, 8 dec

async function pollTx(c, sender, txHash) {
  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 2000));
    try { const d = await c.getTransactionDetail(sender.address(), txHash); if (d && d.status !== 'Pending') return d; } catch {}
  }
  throw new Error(`timeout ${txHash}`);
}

(async () => {
  const c = await SupraClient.init(RPC);
  const sender = new SupraAccount(Uint8Array.from(Buffer.from(FUNDER_KEY.slice(2), 'hex')));
  const info = await c.getAccountInfo(sender.address());
  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number,
    D_PKG, 'D', 'sp_deposit', [],
    [BCS.bcsSerializeUint64(AMT)],
    { maxGas: 100000n }
  );
  console.log(`sp_deposit(${Number(AMT)/1e8} D)...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`✓ gas=${d.gasUsed} tx=${r.txHash}`);

  const sp = await fetch(`${RPC}/rpc/v3/view`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::sp_of`, type_arguments: [], arguments: [sender.address().toString()] }) });
  const t = await fetch(`${RPC}/rpc/v3/view`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::totals`, type_arguments: [], arguments: [] }) });
  console.log(`sp_of(0x0047): ${JSON.stringify((await sp.json()).result)}`);
  console.log(`totals: ${JSON.stringify((await t.json()).result)}`);
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
