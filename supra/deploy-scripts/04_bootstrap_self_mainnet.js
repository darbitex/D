// Self-bootstrap from 0x0047 (hot wallet) directly — multisig no longer accessible (3/5).
// Opens trove 500 SUPRA / 0.05 D ≈ CR 311% (mainnet SUPRA $0.0003112).
const { SupraClient, SupraAccount, BCS } = require('supra-l1-sdk');

const RPC = 'https://rpc-mainnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_PKG = '0x033374e8457b4e52050f64eee98848cad68cf8c5c004858d8f3df009c57a83d9';

const COLL = 50_000_000_000n;  // 500 SUPRA
const DEBT = 5_000_000n;       // 0.05 D → CR ~311% at $0.0003112

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
  console.log(`sender: ${sender.address().toString()} seq: ${info.sequence_number}`);

  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number,
    D_PKG, 'D', 'open_trove', [],
    [BCS.bcsSerializeUint64(COLL), BCS.bcsSerializeUint64(DEBT)],
    { maxGas: 200000n }
  );
  console.log(`submitting D::open_trove(${Number(COLL)/1e8} SUPRA, ${Number(DEBT)/1e8} D)...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`✓ gas=${d.gasUsed} tx=${r.txHash}`);

  // Verify
  const r2 = await fetch(`${RPC}/rpc/v3/view`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: `${D_PKG}::D::trove_health`, type_arguments: [], arguments: [sender.address().toString()] }),
  });
  const th = (await r2.json()).result;
  console.log(`\ntrove: ${th[0]}/${th[1]}/CR ${th[2]} bps`);
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
