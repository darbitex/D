// Continue smoke from where 04 left off — cover remaining 4 entries.
const fs = require('fs');
const { SupraClient, SupraAccount, BCS, TxnBuilderTypes } = require('supra-l1-sdk');

const RPC = 'https://rpc-testnet.supra.com';
const D_PKG = '0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c';
const D_META = '0xc39458d09de1e108ddb5f175226f50c44a7f0f9b0dd4abf0d0f54d8bcfde8081';
const SUPRA_FA = '0xa';
const WALLET_FILE = `${__dirname}/wallets.json`;

async function viewCall(fn, args = [], typeArgs = []) {
  const r = await fetch(`${RPC}/rpc/v3/view`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ function: fn, type_arguments: typeArgs, arguments: args }),
  });
  const j = await r.json();
  if (j.message) throw new Error(`view err ${fn}: ${j.message}`);
  return j.result;
}
async function balFA(addr, meta) {
  try { const r = await viewCall('0x1::primary_fungible_store::balance', [addr.toString(), meta], ['0x1::fungible_asset::Metadata']); return Number(r[0]) / 1e8; }
  catch { return 0; }
}
async function pollTx(c, sender, txHash) {
  for (let i = 0; i < 12; i++) {
    await new Promise(r => setTimeout(r, 1500));
    try { const d = await c.getTransactionDetail(sender.address(), txHash); if (d && d.status !== 'Pending') return d; } catch {}
  }
  throw new Error(`timeout ${txHash}`);
}
async function submit(c, sender, label, mod, fn, args, maxGas = 200000n) {
  const info = await c.getAccountInfo(sender.address());
  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number, ...mod.split('::'), fn, [], args, { maxGas });
  console.log(`  → ${label}...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`     ✓ gas=${d.gasUsed} tx=${r.txHash}`);
  return d;
}
async function dump(label, accs) {
  console.log(`\n──── ${label} ────`);
  const t = await viewCall(`${D_PKG}::D::totals`);
  const reserve = (await viewCall(`${D_PKG}::D::reserve_balance`))[0];
  const sp_pool = (await viewCall(`${D_PKG}::D::sp_pool_balance`))[0];
  console.log(`  totals: debt=${t[0]} sp=${t[1]} P=${t[2]} r_d=${t[3]} r_coll=${t[4]} | reserve=${reserve} sp_pool=${sp_pool}`);
  for (const [name, addr] of accs) {
    const th = await viewCall(`${D_PKG}::D::trove_health`, [addr.toString()]);
    const sp = await viewCall(`${D_PKG}::D::sp_of`, [addr.toString()]);
    const dB = (await balFA(addr, D_META)).toFixed(8);
    const supraB = (await balFA(addr, SUPRA_FA)).toFixed(2);
    console.log(`  ${name}: trove=${th[0]}/${th[1]}/CR ${th[2]} | sp=(${sp[0]},${sp[1]},${sp[2]}) | D=${dB} | FA=${supraB}`);
  }
}

(async () => {
  const c = await SupraClient.init(RPC);
  const { w1: w1Key, w2: w2Key } = JSON.parse(fs.readFileSync(WALLET_FILE, 'utf8'));
  const w1 = new SupraAccount(Uint8Array.from(Buffer.from(w1Key.slice(2), 'hex')));
  const w2 = new SupraAccount(Uint8Array.from(Buffer.from(w2Key.slice(2), 'hex')));
  const accs = [['W1', w1.address()], ['W2', w2.address()]];

  await dump('PRE', accs);

  // 1. redeem_from_reserve — W1 has plenty D + reserve has 100 SUPRA
  console.log('\n──── ENTRY: redeem_from_reserve ────');
  const reserveBal = Number((await viewCall(`${D_PKG}::D::reserve_balance`))[0]);
  if (reserveBal > 1_000_000_000) {
    await submit(c, w1, 'W1 redeem_from_reserve(0.01 D)', `${D_PKG}::D`, 'redeem_from_reserve',
      [BCS.bcsSerializeUint64(1_000_000n)]);
  } else console.log(`  reserve already drained (${reserveBal}), skip`);

  await dump('after redeem_from_reserve', accs);

  // 2. redeem (self-redeem by W1, generates keyed sp rewards because total_sp > 0)
  console.log('\n──── ENTRY: redeem (W1 self) ────');
  const ser = new BCS.Serializer();
  TxnBuilderTypes.AccountAddress.fromHex(w1.address().toString()).serialize(ser);
  const w1AddrBcs = ser.getBytes();
  await submit(c, w1, 'W1 redeem(0.01 D, W1) — self redeem', `${D_PKG}::D`, 'redeem',
    [BCS.bcsSerializeUint64(1_000_000n), w1AddrBcs]);

  await dump('after self-redeem (sp rewards accrued)', accs);

  // 3. sp_claim
  console.log('\n──── ENTRY: sp_claim ────');
  await submit(c, w1, 'W1 sp_claim', `${D_PKG}::D`, 'sp_claim', []);

  await dump('after sp_claim', accs);

  // 4. sp_withdraw
  console.log('\n──── ENTRY: sp_withdraw ────');
  const w1sp = await viewCall(`${D_PKG}::D::sp_of`, [w1.address().toString()]);
  const eff = Number(w1sp[0]);
  const wd = Math.min(eff, 1_000_000); // 0.01 D max
  if (wd > 0) {
    await submit(c, w1, `W1 sp_withdraw(${wd/1e8} D)`, `${D_PKG}::D`, 'sp_withdraw',
      [BCS.bcsSerializeUint64(BigInt(wd))]);
  }

  await dump('after sp_withdraw', accs);

  // 5. close_trove — try W1 first, then W2; report if neither has enough D
  console.log('\n──── ENTRY: close_trove ────');
  for (const [name, w, addr] of [['W1', w1, w1.address()], ['W2', w2, w2.address()]]) {
    const cost = Number((await viewCall(`${D_PKG}::D::close_cost`, [addr.toString()]))[0]);
    if (cost === 0) { console.log(`  ${name}: no trove`); continue; }
    const bal = await balFA(addr, D_META);
    if (bal * 1e8 >= cost) {
      await submit(c, w, `${name} close_trove (cost=${cost/1e8} D)`, `${D_PKG}::D`, 'close_trove', []);
      break;
    } else console.log(`  ${name}: short by ${(cost/1e8 - bal).toFixed(8)} D`);
  }

  await dump('FINAL', accs);
  console.log('\n✅ remaining entries verified');
})().catch(e => { console.error('\n❌ FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,400)); process.exit(1); });
