// Create 1/5 multisig on Supra mainnet via 0x1::multisig_account::create_with_owners.
// Sender (creator) = 0x0047. Additional 4 owners = D-Aptos sibling owners (already
// funded with 1 SUPRA each in _fund_owners.js).
//
// After execution: scan account_address from CreateMultisigAccount event in tx output.

const {
  SupraClient,
  SupraAccount,
  HexString,
  BCS,
  TxnBuilderTypes,
} = require('supra-l1-sdk');

const RPC = 'https://rpc-mainnet.supra.com';
const KEY = process.env.DEPLOYER_KEY;
if (!KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }

const ADDITIONAL_OWNERS = [
  '0x13f0c2edebcb9df033875af75669520994ab08423fe86fa77651cebbc5034a65',
  '0xf6e1d1fdc2de9d755f164bdbf6153200ed25815c59a700ba30fb6adf8eb1bda1',
  '0xc257b12ef33cc0d221be8eecfe92c12fda8d886af8229b9bc4d59a518fa0b093',
  '0xa1189e559d1348be8d55429796fd76bf18001d0a2bd4e9f8b24878adcbd5e84a',
];
const THRESHOLD = 1n;
const TIMEOUT_DURATION = 86400n; // 1 day, well above MINIMAL_TIMEOUT_DURATION (300s)

(async () => {
  const c = await SupraClient.init(RPC);
  const sender = new SupraAccount(Uint8Array.from(Buffer.from(KEY.slice(2), 'hex')));
  const senderAddr = sender.address();
  console.log(`creator: ${senderAddr.toString()}`);
  console.log(`chain_id: ${c.chainId.value}`);

  const info = await c.getAccountInfo(senderAddr);
  const seq = info.sequence_number;
  console.log(`creator seq: ${seq}`);

  // BCS-encode args
  // arg 0: vector<address>
  const ser0 = new BCS.Serializer();
  ser0.serializeU32AsUleb128(ADDITIONAL_OWNERS.length);
  for (const o of ADDITIONAL_OWNERS) {
    TxnBuilderTypes.AccountAddress.fromHex(o).serialize(ser0);
  }
  const arg0 = ser0.getBytes();

  // arg 1: u64 threshold
  const arg1 = BCS.bcsSerializeUint64(THRESHOLD);

  // arg 2: vector<String> metadata_keys (empty)
  const ser2 = new BCS.Serializer();
  ser2.serializeU32AsUleb128(0);
  const arg2 = ser2.getBytes();

  // arg 3: vector<vector<u8>> metadata_values (empty)
  const ser3 = new BCS.Serializer();
  ser3.serializeU32AsUleb128(0);
  const arg3 = ser3.getBytes();

  // arg 4: u64 timeout_duration (Supra-specific)
  const arg4 = BCS.bcsSerializeUint64(TIMEOUT_DURATION);

  const serializedTx = await c.createSerializedRawTxObject(
    senderAddr,
    seq,
    '0x1',
    'multisig_account',
    'create_with_owners',
    [],
    [arg0, arg1, arg2, arg3, arg4],
    { maxGas: 500000n }
  );

  console.log('\nsubmitting create_with_owners (1/5)...');
  const result = await c.sendTxUsingSerializedRawTransaction(
    sender,
    serializedTx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } }
  );
  console.log(`tx hash: ${result.txHash}`);
  console.log(`result: ${result.result}`);

  const detail = await c.getTransactionDetail(senderAddr, result.txHash);
  if (detail) {
    console.log(`status: ${detail.status}, gas: ${detail.gasUsed}, vm: ${detail.vm_status}`);
  }

  // Fetch raw tx to scan events for multisig address
  const txUrl = `${RPC}/rpc/v3/transactions/${result.txHash}`;
  const r = await fetch(txUrl);
  const txJson = await r.json();
  console.log('\nevents:');
  const evts = txJson?.output?.Move?.events || txJson?.events || [];
  let multisigAddr = null;
  for (const ev of evts) {
    console.log(`  ${ev.type || ev.guid?.account_address}`);
    if (ev.type?.includes('CreateMultisigAccount') || ev.type?.includes('multisig_account::Create')) {
      console.log(`    data: ${JSON.stringify(ev.data)}`);
      multisigAddr = ev.data?.multisig_account || ev.data?.account || ev.data?.multisig_address;
    }
  }
  if (!multisigAddr) {
    // fallback: scan changes for new account
    const changes = txJson?.output?.Move?.changes || [];
    for (const ch of changes) {
      if (ch.type === 'write_resource' && ch.data?.type?.includes('multisig_account::MultisigAccount')) {
        multisigAddr = ch.address;
        console.log(`(from changes) multisig_address: ${multisigAddr}`);
        break;
      }
    }
  }
  if (multisigAddr) {
    console.log(`\n✅ MULTISIG ADDRESS: ${multisigAddr}`);
  } else {
    console.log('\n⚠️  Could not auto-detect multisig address. Inspect tx manually:');
    console.log(JSON.stringify(txJson, null, 2).slice(0, 4000));
  }
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
