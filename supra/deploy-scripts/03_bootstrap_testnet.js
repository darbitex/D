// Run bootstrap.mv script on Supra TESTNET — converts Coin<SupraCoin>→FA + opens trove.
// Sender = 0x0047 hot wallet.
const fs = require('fs');
const { SupraClient, SupraAccount, TxnBuilderTypes } = require('supra-l1-sdk');

const RPC = 'https://rpc-testnet.supra.com';
const KEY = process.env.DEPLOYER_KEY;
if (!KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const SCRIPT_PATH = '/home/rera/d/supra/build/D/bytecode_scripts/bootstrap.mv';

// Open with 500 SUPRA → 0.01 D (MIN_DEBT). At testnet SUPRA ~$0.00031, CR = 1500%+.
const SUPRA_AMT = 50_000_000_000n;   // 500 SUPRA, 8 dec
const DEBT      = 1_000_000n;        // 0.01 D, 8 dec

(async () => {
  const scriptCode = Uint8Array.from(fs.readFileSync(SCRIPT_PATH));
  console.log(`script: ${scriptCode.length} bytes`);

  const c = await SupraClient.init(RPC);
  const sender = new SupraAccount(Uint8Array.from(Buffer.from(KEY.slice(2), 'hex')));
  console.log('chain_id:', c.chainId.value);
  console.log('sender:', sender.address().toString());
  const info = await c.getAccountInfo(sender.address());
  console.log('seq:', info.sequence_number);

  const args = [
    new TxnBuilderTypes.TransactionArgumentU64(SUPRA_AMT),
    new TxnBuilderTypes.TransactionArgumentU64(DEBT),
  ];

  const serializedTx = c.createSerializedScriptTxPayloadRawTxObject(
    sender.address(),
    info.sequence_number,
    scriptCode,
    [],
    args,
    { maxGas: 500000n }
  );

  console.log('\nsubmitting bootstrap (500 SUPRA → 0.01 D)...');
  const result = await c.sendTxUsingSerializedRawTransaction(
    sender, serializedTx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } }
  );
  console.log('tx hash:', result.txHash);
  console.log('result:', result.result);

  await new Promise(r => setTimeout(r, 3000));
  try {
    const d = await c.getTransactionDetail(sender.address(), result.txHash);
    if (d) console.log(`status: ${d.status}, gas: ${d.gasUsed}, vm: ${d.vm_status}`);
  } catch(e) { console.log('detail err:', e.message); }
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
