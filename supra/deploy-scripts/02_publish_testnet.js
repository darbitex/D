// Publish D Supra to TESTNET via 0x1::resource_account::create_resource_account_and_publish_package
// Sender = 0x0047 hot wallet. Seed = b"D". Resource account derived deterministically.
//
// Pre-req: Move.toml `core` dep pointing to supra/testnet/core (already done).
// Build: aptos move build-publish-payload --named-addresses D=<derived>,origin=0x0047...
//        --skip-fetch-latest-git-deps -> /tmp/d-supra-publish.json
const fs = require('fs');
const { SupraClient, SupraAccount, BCS } = require('supra-l1-sdk');

const RPC = 'https://rpc-testnet.supra.com';
const KEY = process.env.DEPLOYER_KEY;
if (!KEY) { console.error('DEPLOYER_KEY env var required'); process.exit(1); }
const PAYLOAD = '/tmp/d-supra-publish.json';
const SEED = Buffer.from('D'); // b"D"

(async () => {
  const c = await SupraClient.init(RPC);
  const sender = new SupraAccount(Uint8Array.from(Buffer.from(KEY.slice(2), 'hex')));
  console.log('chain_id:', c.chainId.value);
  console.log('sender:', sender.address().toString());
  const info = await c.getAccountInfo(sender.address());
  console.log('seq:', info.sequence_number);
  const bal = await c.getAccountSupraCoinBalance(sender.address());
  console.log('balance:', Number(bal)/1e8, 'SUPRA');

  const p = JSON.parse(fs.readFileSync(PAYLOAD, 'utf8'));
  if (p.function_id !== '0x1::code::publish_package_txn') {
    throw new Error('unexpected function_id: ' + p.function_id);
  }

  // Arg 0 (publish_package_txn): metadata hex
  const metadataHex = p.args[0].value;
  const metadata = Uint8Array.from(Buffer.from(metadataHex.slice(2), 'hex'));
  console.log('metadata bytes:', metadata.length);

  // Arg 1 (publish_package_txn): array of module hex
  const moduleHexes = p.args[1].value;
  const modules = moduleHexes.map(h => Uint8Array.from(Buffer.from(h.slice(2), 'hex')));
  console.log('modules:', modules.length, 'sizes:', modules.map(m => m.length).join(','));

  // BCS-encode args for create_resource_account_and_publish_package(seed, metadata, code)
  // arg 0: seed: vector<u8>
  const arg0 = BCS.bcsSerializeBytes(SEED);

  // arg 1: metadata_serialized: vector<u8>
  const arg1 = BCS.bcsSerializeBytes(metadata);

  // arg 2: code: vector<vector<u8>>
  const ser2 = new BCS.Serializer();
  ser2.serializeU32AsUleb128(modules.length);
  for (const m of modules) {
    // each element is vector<u8> = uleb128(len) + bytes
    const lenSer = new BCS.Serializer();
    lenSer.serializeU32AsUleb128(m.length);
    ser2.serializeFixedBytes(lenSer.getBytes());
    ser2.serializeFixedBytes(m);
  }
  const arg2 = ser2.getBytes();

  console.log('\nbuilding tx for create_resource_account_and_publish_package...');
  const serializedTx = await c.createSerializedRawTxObject(
    sender.address(),
    info.sequence_number,
    '0x1',
    'resource_account',
    'create_resource_account_and_publish_package',
    [],
    [arg0, arg1, arg2],
    { maxGas: 1_500_000n }
  );

  console.log('submitting...');
  const result = await c.sendTxUsingSerializedRawTransaction(
    sender,
    serializedTx,
    { enableTransactionWaitAndSimulationArgs: { enableWaitForTransaction: true } }
  );
  console.log('tx hash:', result.txHash);
  console.log('result:', result.result);

  // Poll detail
  await new Promise(r => setTimeout(r, 3000));
  try {
    const d = await c.getTransactionDetail(sender.address(), result.txHash);
    if (d) {
      console.log('status:', d.status, 'gas:', d.gasUsed, 'vm:', d.vm_status);
    }
  } catch(e) { console.log('detail err:', e.message); }
})().catch(e => { console.error('FATAL:', e.message); if (e.response?.data) console.error(JSON.stringify(e.response.data).slice(0,500)); process.exit(1); });
