// Comprehensive D Supra testnet smoke — all entries (except liquidate) + all views.
// 2 fresh wallets W1+W2. W1 already has trove from prior run; resumes idempotently.
const fs = require('fs');
const crypto = require('crypto');
const { SupraClient, SupraAccount, HexString, BCS, TxnBuilderTypes } = require('supra-l1-sdk');

const RPC = 'https://rpc-testnet.supra.com';
const FUNDER_KEY = process.env.DEPLOYER_KEY;
if (!FUNDER_KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_PKG = '0x3db02f4fed901890ee1dc71e2db93c2f6828c842832c69120ed4106b33c92c4c';
const D_META = '0xc39458d09de1e108ddb5f175226f50c44a7f0f9b0dd4abf0d0f54d8bcfde8081';
const SUPRA_FA = '0xa';
const WALLET_FILE = `${__dirname}/wallets.json`;
const MIGRATE_MV = '/home/rera/d/supra/scripts_bytecode/migrate_coin_to_fa.mv';

function loadOrGenWallets() {
  if (fs.existsSync(WALLET_FILE)) {
    const j = JSON.parse(fs.readFileSync(WALLET_FILE, 'utf8'));
    return [j.w1, j.w2];
  }
  const w1 = '0x' + crypto.randomBytes(32).toString('hex');
  const w2 = '0x' + crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(WALLET_FILE, JSON.stringify({ w1, w2 }, null, 2));
  return [w1, w2];
}

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
  try {
    const r = await viewCall('0x1::primary_fungible_store::balance', [addr.toString(), meta], ['0x1::fungible_asset::Metadata']);
    return Number(r[0]) / 1e8;
  } catch (e) { return 0; }
}

async function balCoin(c, addr) {
  try { return Number(await c.getAccountSupraCoinBalance(addr)) / 1e8; }
  catch (e) { return 0; }
}

async function pollTx(c, sender, txHash, label) {
  for (let i = 0; i < 12; i++) {
    await new Promise(r => setTimeout(r, 1500));
    try {
      const d = await c.getTransactionDetail(sender.address(), txHash);
      if (d && d.status !== 'Pending') return d;
    } catch {}
  }
  throw new Error(`${label} TIMEOUT polling tx=${txHash}`);
}

async function submit(c, sender, label, mod, fn, args, maxGas = 200000n) {
  const info = await c.getAccountInfo(sender.address());
  const tx = await c.createSerializedRawTxObject(
    sender.address(), info.sequence_number, ...mod.split('::'), fn, [], args,
    { maxGas }
  );
  console.log(`  → ${label}...`);
  const result = await c.sendTxUsingSerializedRawTransaction(
    sender, tx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } }
  );
  const d = await pollTx(c, sender, result.txHash, label);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${result.txHash}`);
  console.log(`     ✓ gas=${d.gasUsed} tx=${result.txHash}`);
  return d;
}

async function submitScript(c, sender, label, scriptPath, u64Args, maxGas = 500000n) {
  const code = Uint8Array.from(fs.readFileSync(scriptPath));
  const info = await c.getAccountInfo(sender.address());
  const args = u64Args.map(v => new TxnBuilderTypes.TransactionArgumentU64(v));
  const tx = c.createSerializedScriptTxPayloadRawTxObject(
    sender.address(), info.sequence_number, code, [], args, { maxGas }
  );
  console.log(`  → ${label}...`);
  const result = await c.sendTxUsingSerializedRawTransaction(
    sender, tx, { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } }
  );
  const d = await pollTx(c, sender, result.txHash, label);
  if (d.status !== 'Success') throw new Error(`${label} FAILED: ${d.vm_status} tx=${result.txHash}`);
  console.log(`     ✓ gas=${d.gasUsed} tx=${result.txHash}`);
  return d;
}

async function dumpState(c, label, accs) {
  console.log(`\n────── ${label} ──────`);
  const totals = await viewCall(`${D_PKG}::D::totals`);
  const sealed = (await viewCall(`${D_PKG}::D::is_sealed`))[0];
  const price = (await viewCall(`${D_PKG}::D::price`))[0];
  const reserve = (await viewCall(`${D_PKG}::D::reserve_balance`))[0];
  const sp_pool = (await viewCall(`${D_PKG}::D::sp_pool_balance`))[0];
  console.log(`  totals: debt=${totals[0]} sp=${totals[1]} P=${totals[2]} r_d=${totals[3]} r_coll=${totals[4]} | sealed=${sealed} price=${price} reserve=${reserve} sp_pool=${sp_pool}`);
  for (const [name, addr] of accs) {
    const th = await viewCall(`${D_PKG}::D::trove_health`, [addr.toString()]);
    const sp = await viewCall(`${D_PKG}::D::sp_of`, [addr.toString()]);
    const cc = (await viewCall(`${D_PKG}::D::close_cost`, [addr.toString()]))[0];
    const dB = (await balFA(addr, D_META)).toFixed(8);
    const supraB = (await balFA(addr, SUPRA_FA)).toFixed(2);
    const coinB = (await balCoin(c, addr)).toFixed(2);
    console.log(`  ${name}: trove=${th[0]}/${th[1]}/CR ${th[2]} | sp(eff,p_d,p_coll)=(${sp[0]},${sp[1]},${sp[2]}) | close_cost=${cc} | D=${dB} | FA=${supraB} | Coin=${coinB}`);
  }
}

(async () => {
  const c = await SupraClient.init(RPC);
  const funder = new SupraAccount(Uint8Array.from(Buffer.from(FUNDER_KEY.slice(2), 'hex')));
  const [w1Key, w2Key] = loadOrGenWallets();
  const w1 = new SupraAccount(Uint8Array.from(Buffer.from(w1Key.slice(2), 'hex')));
  const w2 = new SupraAccount(Uint8Array.from(Buffer.from(w2Key.slice(2), 'hex')));
  console.log(`W1: ${w1.address().toString()}`);
  console.log(`W2: ${w2.address().toString()}`);
  const accs = [['W1', w1.address()], ['W2', w2.address()]];

  // ---- ONE-SHOT VIEWS ----
  console.log('\n────── VIEWS (16 fns) ──────');
  for (const fn of ['metadata_addr', 'fee_pool_addr', 'sp_pool_addr', 'sp_coll_pool_addr', 'reserve_coll_addr', 'treasury_addr']) {
    console.log(`  ${fn}: ${(await viewCall(`${D_PKG}::D::${fn}`))[0]}`);
  }
  const w = await viewCall(`${D_PKG}::D::read_warning`);
  console.log(`  read_warning: ${Buffer.from(w[0].slice(2), 'hex').toString('utf8').length} chars`);

  // ---- Step 1+2: funder setup + W2 funding — guarded by need-checks ----
  console.log('\n────── STEP 1+2: FUND (idempotent) ──────');
  let w2HasAccount = false;
  try { await c.getAccountInfo(w2.address()); w2HasAccount = true; } catch {}
  const w2trove0 = Number((await viewCall(`${D_PKG}::D::trove_of`, [w2.address().toString()]))[1]);
  const w2bal = await balFA(w2.address(), SUPRA_FA);
  if (!w2HasAccount || (w2trove0 === 0 && w2bal < 500)) {
    // Need to fund W2. Migrate funder Coin→FA first if needed.
    const fFA = await balFA(funder.address(), SUPRA_FA);
    if (fFA < 700) {
      const fCoin = await balCoin(c, funder.address());
      const want = Math.min(700 - Math.floor(fFA), Math.floor(fCoin) - 5);
      if (want > 0) await submitScript(c, funder, `funder migrate ${want} SUPRA Coin→FA`, MIGRATE_MV, [BigInt(want) * 100_000_000n]);
    }
    const sRecip = new BCS.Serializer();
    TxnBuilderTypes.AccountAddress.fromHex(w2.address().toString()).serialize(sRecip);
    await submit(c, funder, 'funder→W2 700 SUPRA', '0x1::supra_account', 'transfer',
      [sRecip.getBytes(), BCS.bcsSerializeUint64(70_000_000_000n)], 300000n);
  } else console.log(`  W2 ready (account=${w2HasAccount}, trove_debt=${w2trove0}, FA=${w2bal})`);

  await dumpState(c, 'after funder setup', [['funder', funder.address()], ...accs]);

  // ---- Continue with smoke (reuse W1's existing trove) ----
  // STATE PRE: W1 has trove 1000/0.05, D bal 0.0495, Coin 1998. W2 has 700 FA. Funder migrated.

  // Step 3: W2 open_trove (500 SUPRA / 0.025 D) directly (FA already in W2)
  console.log('\n────── STEP 3: W2 open_trove ──────');
  const w2trove = (await viewCall(`${D_PKG}::D::trove_of`, [w2.address().toString()]))[1];
  if (Number(w2trove) === 0) {
    await submit(c, w2, 'W2 open_trove(500 SUPRA, 0.025 D)', `${D_PKG}::D`, 'open_trove',
      [BCS.bcsSerializeUint64(50_000_000_000n), BCS.bcsSerializeUint64(2_500_000n)]);
  } else console.log('  W2 already has trove, skip');

  await dumpState(c, 'after W2 open_trove', accs);

  // Step 4: W1 migrate 700 Coin→FA (so W1 has FA for add_collateral + donate_to_reserve)
  console.log('\n────── STEP 4: W1 migrate Coin→FA ──────');
  const w1faSup = await balFA(w1.address(), SUPRA_FA);
  if (w1faSup < 600) {
    await submitScript(c, w1, `W1 migrate ${700 - Math.ceil(w1faSup)} SUPRA Coin→FA`, MIGRATE_MV, [BigInt(700 - Math.ceil(w1faSup)) * 100_000_000n]);
  } else console.log(`  W1 has ${w1faSup} FA, skip`);

  // Step 5: add_collateral
  console.log('\n────── STEP 5: add_collateral ──────');
  await submit(c, w1, 'W1 add_collateral(500 SUPRA)', `${D_PKG}::D`, 'add_collateral',
    [BCS.bcsSerializeUint64(50_000_000_000n)]);

  await dumpState(c, 'after add_collateral', accs);

  // Step 6: redeem (W2 redeems against W1)
  console.log('\n────── STEP 6: redeem ──────');
  const ser = new BCS.Serializer();
  TxnBuilderTypes.AccountAddress.fromHex(w1.address().toString()).serialize(ser);
  const w1AddrBcs = ser.getBytes();
  await submit(c, w2, 'W2 redeem(0.0202 D, W1)', `${D_PKG}::D`, 'redeem',
    [BCS.bcsSerializeUint64(2_020_000n), w1AddrBcs]);

  await dumpState(c, 'after redeem', accs);

  // Step 7: sp_deposit
  console.log('\n────── STEP 7: sp_deposit ──────');
  await submit(c, w1, 'W1 sp_deposit(0.02 D)', `${D_PKG}::D`, 'sp_deposit',
    [BCS.bcsSerializeUint64(2_000_000n)]);

  // Step 8: donate_to_sp
  console.log('\n────── STEP 8: donate_to_sp ──────');
  await submit(c, w1, 'W1 donate_to_sp(0.005 D)', `${D_PKG}::D`, 'donate_to_sp',
    [BCS.bcsSerializeUint64(500_000n)]);

  await dumpState(c, 'after sp_deposit + donate_to_sp', accs);

  // Step 9: donate_to_reserve
  console.log('\n────── STEP 9: donate_to_reserve ──────');
  await submit(c, w1, 'W1 donate_to_reserve(100 SUPRA)', `${D_PKG}::D`, 'donate_to_reserve',
    [BCS.bcsSerializeUint64(10_000_000_000n)]);

  await dumpState(c, 'after donate_to_reserve', accs);

  // Step 10: redeem_from_reserve (W1 — has more D than W2 after W2's redeem; needs >= MIN_DEBT)
  console.log('\n────── STEP 10: redeem_from_reserve ──────');
  await submit(c, w1, 'W1 redeem_from_reserve(0.01 D)', `${D_PKG}::D`, 'redeem_from_reserve',
    [BCS.bcsSerializeUint64(1_000_000n)]);

  await dumpState(c, 'after redeem_from_reserve', accs);

  // Step 11: another redeem with W1 (>= MIN_DEBT) against own trove to generate keyed sp rewards
  console.log('\n────── STEP 11: redeem #2 (generate keyed sp rewards) ──────');
  await submit(c, w1, 'W1 redeem(0.01 D, W1) — self-redeem', `${D_PKG}::D`, 'redeem',
    [BCS.bcsSerializeUint64(1_000_000n), w1AddrBcs]);

  await dumpState(c, 'after redeem #2', accs);

  // Step 12: sp_claim
  console.log('\n────── STEP 12: sp_claim ──────');
  await submit(c, w1, 'W1 sp_claim', `${D_PKG}::D`, 'sp_claim', []);

  await dumpState(c, 'after sp_claim', accs);

  // Step 13: sp_withdraw
  console.log('\n────── STEP 13: sp_withdraw ──────');
  await submit(c, w1, 'W1 sp_withdraw(0.01 D)', `${D_PKG}::D`, 'sp_withdraw',
    [BCS.bcsSerializeUint64(1_000_000n)]);

  await dumpState(c, 'after sp_withdraw', accs);

  // Step 14: close_trove (W1 if can afford, else W2 if can afford, else skip with explanation)
  console.log('\n────── STEP 14: close_trove ──────');
  for (const [name, w, addr] of [['W1', w1, w1.address()], ['W2', w2, w2.address()]]) {
    const cost = Number((await viewCall(`${D_PKG}::D::close_cost`, [addr.toString()]))[0]);
    const bal = await balFA(addr, D_META);
    if (cost === 0) { console.log(`  ${name}: no trove, skip`); continue; }
    if (bal * 1e8 >= cost) {
      await submit(c, w, `${name} close_trove (cost=${cost/1e8} D)`, `${D_PKG}::D`, 'close_trove', []);
      break;
    } else {
      console.log(`  ${name}: short by ${(cost/1e8 - bal).toFixed(8)} D — try next`);
    }
  }

  await dumpState(c, 'FINAL', accs);
  console.log('\n✅ smoke complete (liquidate intentionally skipped)');
})().catch(e => { console.error('\n❌ FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
