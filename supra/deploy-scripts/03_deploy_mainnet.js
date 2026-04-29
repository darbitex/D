// D Supra MAINNET deploy — idempotent, follows D Aptos flow:
//   1. Funder migrate Coin→FA (so transfer routes work)
//   2. Funder→multisig 600 SUPRA (bootstrap collateral + gas buffer)
//   3. Multisig publish via resource_account::create_resource_account_and_publish_package
//   4. Multisig bootstrap D::open_trove(500 SUPRA, 0.01 D)
//   5. Multisig D::destroy_cap (seal)
//   6. Multisig raise threshold 1/5 → 3/5
//   7. Smoke views
//
// Multisig flow uses MultisigPayload tx type — sender (one of owners) proposes+
// executes in one tx since threshold=1.

const fs = require('fs');
const { SupraClient, SupraAccount, HexString, BCS, TxnBuilderTypes } = require('supra-l1-sdk');

const RPC = 'https://rpc-mainnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const MULTISIG = '0xbefe37923ac3910dc5c2d3799941e489da460cb6c8f8b69c70d68390397571f5';
const D_PKG = '0x033374e8457b4e52050f64eee98848cad68cf8c5c004858d8f3df009c57a83d9';
const PUBLISH_PAYLOAD = '/tmp/d-supra-mainnet-publish.json';
const MIGRATE_MV = '/home/rera/d/supra/scripts_bytecode/migrate_coin_to_fa.mv';
const SUPRA_FA = '0xa';

// Bootstrap sizing
const BOOTSTRAP_COLL = 50_000_000_000n;  // 500 SUPRA, 8 dec
const BOOTSTRAP_DEBT = 1_000_000n;       // 0.01 D = MIN_DEBT
const FUND_MULTISIG = 60_000_000_000n;   // 600 SUPRA → multisig
const FUND_MULTISIG_FLOOR = 55_000_000_000n;  // skip if multisig FA >= 550 SUPRA
const MIGRATE_AMT = 70_000_000_000n;     // 700 SUPRA Coin→FA
const MIGRATE_FLOOR = 65_000_000_000n;   // skip if funder FA >= 650 SUPRA

// ── helpers ──
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
  try { const r = await viewCall('0x1::primary_fungible_store::balance', [addr.toString(), meta], ['0x1::fungible_asset::Metadata']); return BigInt(r[0]); }
  catch { return 0n; }
}
async function pollTx(c, sender, txHash) {
  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 2000));
    try { const d = await c.getTransactionDetail(sender.address(), txHash); if (d && d.status !== 'Pending') return d; } catch {}
  }
  throw new Error(`timeout ${txHash}`);
}
async function submit(c, sender, label, mod, fn, args, typeArgs = [], maxGas = 100000n) {
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
async function submitScript(c, sender, label, scriptPath, u64Args, maxGas = 100000n) {
  const code = Uint8Array.from(fs.readFileSync(scriptPath));
  const info = await c.getAccountInfo(sender.address());
  const args = u64Args.map(v => new TxnBuilderTypes.TransactionArgumentU64(v));
  const tx = c.createSerializedScriptTxPayloadRawTxObject(
    sender.address(), info.sequence_number, code, [], args, { maxGas });
  console.log(`  → ${label}...`);
  const r = await c.sendTxUsingSerializedRawTransaction(sender, tx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d = await pollTx(c, sender, r.txHash);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${r.txHash}`);
  console.log(`     ✓ gas=${d.gasUsed} tx=${r.txHash}`);
  return d;
}
async function submitMultisig(c, sender, label, multisigAddr, mod, fn, typeArgs, args, maxGas = 100000n) {
  // Step 1: PROPOSE via 0x1::multisig_account::create_transaction (sender auto-votes approve)
  const info1 = await c.getAccountInfo(sender.address());
  const proposeTx = await c.createSerializedRawTxObjectToCreateMultisigTx(
    sender.address(), info1.sequence_number,
    new HexString(multisigAddr),
    ...mod.split('::'), fn, typeArgs, args, { maxGas: 200000n });
  console.log(`  → [multisig propose] ${label}...`);
  const r1 = await c.sendTxUsingSerializedRawTransaction(sender, proposeTx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d1 = await pollTx(c, sender, r1.txHash);
  if (d1.status !== 'Success') throw new Error(`${label} PROPOSE FAILED: ${d1.vm_status} tx=${r1.txHash}`);
  console.log(`     ✓ propose gas=${d1.gasUsed} tx=${r1.txHash}`);

  // Step 2: EXECUTE via Multisig payload type (sender executes the just-proposed tx)
  const info2 = await c.getAccountInfo(sender.address());
  const execTx = c.createSerializedMultisigPayloadRawTxObject(
    sender.address(), info2.sequence_number,
    new HexString(multisigAddr),
    ...mod.split('::'), fn, typeArgs, args, { maxGas });
  console.log(`  → [multisig execute] ${label}...`);
  const r2 = await c.sendTxUsingSerializedRawTransaction(sender, execTx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } });
  const d2 = await pollTx(c, sender, r2.txHash);
  if (d2.status !== 'Success') throw new Error(`${label} EXECUTE FAILED: ${d2.vm_status} tx=${r2.txHash}`);
  console.log(`     ✓ execute gas=${d2.gasUsed} tx=${r2.txHash}`);
  return d2;
}

// ── main ──
(async () => {
  const c = await SupraClient.init(RPC);
  const funder = new SupraAccount(Uint8Array.from(Buffer.from(FUNDER_KEY.slice(2), 'hex')));
  console.log(`chain_id: ${c.chainId.value} (mainnet)`);
  console.log(`funder: ${funder.address().toString()}`);
  console.log(`multisig: ${MULTISIG}`);
  console.log(`@D: ${D_PKG}`);

  // ── STEP 1: Funder Coin→FA migration ──
  console.log('\n══ STEP 1: Funder Coin→FA migration ══');
  const fundFA = await balFA(funder.address(), SUPRA_FA);
  if (fundFA < MIGRATE_FLOOR) {
    await submitScript(c, funder, `funder migrate ${Number(MIGRATE_AMT)/1e8} SUPRA Coin→FA`, MIGRATE_MV, [MIGRATE_AMT]);
  } else console.log(`  funder FA=${Number(fundFA)/1e8} SUPRA — sufficient, skip`);

  // ── STEP 2: Funder → Multisig (600 SUPRA) ──
  console.log('\n══ STEP 2: Funder → Multisig 600 SUPRA ══');
  const msFA = await balFA(new HexString(MULTISIG), SUPRA_FA);
  if (msFA < FUND_MULTISIG_FLOOR) {
    const sRecip = new BCS.Serializer();
    TxnBuilderTypes.AccountAddress.fromHex(MULTISIG).serialize(sRecip);
    await submit(c, funder, `funder→multisig ${Number(FUND_MULTISIG)/1e8} SUPRA`,
      '0x1::supra_account', 'transfer',
      [sRecip.getBytes(), BCS.bcsSerializeUint64(FUND_MULTISIG)]);
  } else console.log(`  multisig FA=${Number(msFA)/1e8} SUPRA — sufficient, skip`);

  // ── STEP 3: Multisig publish ──
  console.log('\n══ STEP 3: Multisig publish package ══');
  // Check if @D already has a Registry resource (= already published)
  let alreadyPublished = false;
  try {
    await viewCall(`${D_PKG}::D::is_sealed`);
    alreadyPublished = true;
  } catch {}
  if (!alreadyPublished) {
    const p = JSON.parse(fs.readFileSync(PUBLISH_PAYLOAD, 'utf8'));
    if (p.function_id !== '0x1::code::publish_package_txn') throw new Error('bad payload');
    const metadata = Uint8Array.from(Buffer.from(p.args[0].value.slice(2), 'hex'));
    const moduleHexes = p.args[1].value;
    const modules = moduleHexes.map(h => Uint8Array.from(Buffer.from(h.slice(2), 'hex')));
    console.log(`  payload: metadata=${metadata.length}B, ${modules.length} module(s) sizes=${modules.map(m => m.length).join(',')}`);

    // BCS args for resource_account::create_resource_account_and_publish_package(seed, metadata, code)
    const arg0 = BCS.bcsSerializeBytes(Buffer.from('D'));
    const arg1 = BCS.bcsSerializeBytes(metadata);
    const ser2 = new BCS.Serializer();
    ser2.serializeU32AsUleb128(modules.length);
    for (const m of modules) {
      const lenSer = new BCS.Serializer();
      lenSer.serializeU32AsUleb128(m.length);
      ser2.serializeFixedBytes(lenSer.getBytes());
      ser2.serializeFixedBytes(m);
    }
    const arg2 = ser2.getBytes();

    await submitMultisig(c, funder, 'create_resource_account_and_publish_package',
      MULTISIG, '0x1::resource_account', 'create_resource_account_and_publish_package',
      [], [arg0, arg1, arg2], 1_500_000n);
  } else console.log(`  @D already has Registry — package already published, skip`);

  // ── STEP 4: Multisig bootstrap (open_trove) ──
  console.log('\n══ STEP 4: Bootstrap (multisig open_trove) ══');
  const msTrove = await viewCall(`${D_PKG}::D::trove_of`, [MULTISIG]);
  if (Number(msTrove[1]) === 0) {
    await submitMultisig(c, funder, `D::open_trove(${Number(BOOTSTRAP_COLL)/1e8} SUPRA, ${Number(BOOTSTRAP_DEBT)/1e8} D)`,
      MULTISIG, `${D_PKG}::D`, 'open_trove',
      [], [BCS.bcsSerializeUint64(BOOTSTRAP_COLL), BCS.bcsSerializeUint64(BOOTSTRAP_DEBT)],
      300000n);
  } else console.log(`  multisig already has trove (${msTrove[0]}/${msTrove[1]}), skip`);

  // ── STEP 5: Multisig destroy_cap (seal) ──
  console.log('\n══ STEP 5: destroy_cap (seal) ══');
  const sealed = (await viewCall(`${D_PKG}::D::is_sealed`))[0];
  if (!sealed) {
    await submitMultisig(c, funder, 'D::destroy_cap',
      MULTISIG, `${D_PKG}::D`, 'destroy_cap',
      [], [], 200000n);
  } else console.log(`  is_sealed=true already, skip`);

  // ── STEP 6: Raise threshold 1/5 → 3/5 ──
  console.log('\n══ STEP 6: Raise multisig threshold 1/5 → 3/5 ══');
  const msResource = await fetch(`${RPC}/rpc/v3/accounts/${MULTISIG}/resources/0x1::multisig_account::MultisigAccount`);
  const msData = (await msResource.json()).data;
  const currentThreshold = Number(msData?.num_signatures_required || 1);
  if (currentThreshold < 3) {
    await submitMultisig(c, funder, 'multisig_account::update_signatures_required(3)',
      MULTISIG, '0x1::multisig_account', 'update_signatures_required',
      [], [BCS.bcsSerializeUint64(3n)], 200000n);
  } else console.log(`  threshold already ${currentThreshold}, skip`);

  // ── STEP 7: Smoke ──
  console.log('\n══ STEP 7: Mainnet smoke ══');
  const totals = await viewCall(`${D_PKG}::D::totals`);
  const sealedFinal = (await viewCall(`${D_PKG}::D::is_sealed`))[0];
  const price = (await viewCall(`${D_PKG}::D::price`))[0];
  const trove = await viewCall(`${D_PKG}::D::trove_health`, [MULTISIG]);
  const reserve = (await viewCall(`${D_PKG}::D::reserve_balance`))[0];
  const sp_pool = (await viewCall(`${D_PKG}::D::sp_pool_balance`))[0];
  console.log(`  is_sealed: ${sealedFinal}`);
  console.log(`  totals: debt=${totals[0]} sp=${totals[1]} P=${totals[2]} r_d=${totals[3]} r_coll=${totals[4]}`);
  console.log(`  price (oracle 8-dec): ${price}`);
  console.log(`  multisig trove: ${trove[0]}/${trove[1]}/CR ${trove[2]} bps`);
  console.log(`  reserve_balance: ${reserve}`);
  console.log(`  sp_pool_balance: ${sp_pool}`);

  for (const fn of ['metadata_addr', 'fee_pool_addr', 'sp_pool_addr', 'sp_coll_pool_addr', 'reserve_coll_addr', 'treasury_addr']) {
    console.log(`  ${fn}: ${(await viewCall(`${D_PKG}::D::${fn}`))[0]}`);
  }

  // Final multisig threshold check
  const msResource2 = await fetch(`${RPC}/rpc/v3/accounts/${MULTISIG}/resources/0x1::multisig_account::MultisigAccount`);
  const msData2 = (await msResource2.json()).data;
  console.log(`  multisig threshold: ${msData2?.num_signatures_required}/${msData2?.owners?.length}`);

  console.log('\n✅ D SUPRA MAINNET LIVE + SEALED + 3/5 multisig hygiene');
})().catch(e => { console.error('\n❌ FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
