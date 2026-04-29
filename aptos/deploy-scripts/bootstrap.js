// Bootstrap D on Aptos testnet/mainnet:
// 1. Fetch fresh APT/USD VAA from Pyth hermes
// 2. D::open_trove_pyth (atomic: Pyth update + open_trove)
// 3. D::sp_deposit (optional)
const { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey } = require('@aptos-labs/ts-sdk');

const NETWORK = process.env.APTOS_NETWORK || 'testnet';
const PRIVATE_KEY_HEX = process.env.DEPLOYER_KEY;
if (!PRIVATE_KEY_HEX) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const D_ADDR = process.env.D_ADDR;
if (!D_ADDR) { console.error('D_ADDR env var required'); process.exit(1); }
const APT_USD_FEED = '0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5';
const APT_AMT = BigInt(process.env.APT_AMT || 200_000_000n);       // 2 APT
const DEBT    = BigInt(process.env.DEBT    || 100_000_000n);       // 1 D
const SP_AMT  = BigInt(process.env.SP_AMT  || 50_000_000n);        // 0.5 D

(async () => {
  const config = new AptosConfig({ network: NETWORK === 'mainnet' ? Network.MAINNET : Network.TESTNET });
  const aptos = new Aptos(config);
  const pk = new Ed25519PrivateKey(PRIVATE_KEY_HEX);
  const account = Account.fromPrivateKey({ privateKey: pk });
  console.log(`signer: ${account.accountAddress.toString()}`);
  console.log(`network: ${NETWORK}`);
  console.log(`D pkg:  ${D_ADDR}`);

  // Step 1: Fetch VAA from Hermes — beta endpoint for testnet, mainnet endpoint otherwise
  const hermesBase = NETWORK === 'mainnet' ? 'https://hermes.pyth.network' : 'https://hermes-beta.pyth.network';
  console.log(`\n=== 1. Fetch APT/USD VAA from ${hermesBase} ===`);
  const vaaResp = await fetch(`${hermesBase}/api/latest_vaas?ids[]=${APT_USD_FEED}`);
  const vaaB64Arr = await vaaResp.json();
  const vaaBytesArr = vaaB64Arr.map(b64 => Array.from(Buffer.from(b64, 'base64')));
  console.log(`  VAA count: ${vaaBytesArr.length}, first len: ${vaaBytesArr[0].length} bytes`);

  // Step 2: open_trove_pyth (atomic update + open)
  console.log('\n=== 2. D::open_trove_pyth ===');
  const openTx = await aptos.transaction.build.simple({
    sender: account.accountAddress,
    data: {
      function: `${D_ADDR}::D::open_trove_pyth`,
      functionArguments: [APT_AMT.toString(), DEBT.toString(), vaaBytesArr],
    },
  });
  const openResp = await aptos.signAndSubmitTransaction({ signer: account, transaction: openTx });
  console.log(`  tx: ${openResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: openResp.hash });
  console.log(`  ✓ trove opened: ${APT_AMT} raw APT coll / ${DEBT} raw D debt`);

  // Step 3: sp_deposit
  if (SP_AMT > 0n) {
    console.log('\n=== 3. D::sp_deposit ===');
    const spTx = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${D_ADDR}::D::sp_deposit`,
        functionArguments: [SP_AMT.toString()],
      },
    });
    const spResp = await aptos.signAndSubmitTransaction({ signer: account, transaction: spTx });
    console.log(`  tx: ${spResp.hash}`);
    await aptos.waitForTransaction({ transactionHash: spResp.hash });
    console.log(`  ✓ sp_deposit: ${SP_AMT} raw D`);
  }

  // Final state
  console.log('\n=== final state ===');
  const totals = await aptos.view({
    payload: { function: `${D_ADDR}::D::totals`, functionArguments: [] },
  });
  console.log(`  totals: debt=${totals[0]}, sp=${totals[1]}, P=${totals[2]}, r_d=${totals[3]}, r_coll=${totals[4]}`);
  const trove = await aptos.view({
    payload: { function: `${D_ADDR}::D::trove_of`, functionArguments: [account.accountAddress.toString()] },
  });
  console.log(`  trove: coll=${trove[0]}, debt=${trove[1]}`);
  const sp = await aptos.view({
    payload: { function: `${D_ADDR}::D::sp_of`, functionArguments: [account.accountAddress.toString()] },
  });
  console.log(`  sp: bal=${sp[0]}, p_d=${sp[1]}, p_coll=${sp[2]}`);
  const spPool = await aptos.view({
    payload: { function: `${D_ADDR}::D::sp_pool_balance`, functionArguments: [] },
  });
  console.log(`  sp_pool_balance (incl donations): ${spPool[0]}`);
})().catch(e => {
  console.error('\nERROR:', e.message || e);
  process.exit(1);
});
