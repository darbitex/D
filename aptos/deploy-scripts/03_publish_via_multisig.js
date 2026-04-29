// Multisig publish for D Aptos.
// 1. Build entry-fn payload for 0x1::resource_account::create_resource_account_and_publish_package
//    using metadata + code from `aptos move build-publish-payload`
// 2. Submit proposal via multisig (any 1 owner approves; 1/5 threshold = 1 sig sufficient)
// 3. Print execute command for the same owner to run

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const {
  Aptos, AptosConfig, Network, Account, Ed25519PrivateKey,
  generateTransactionPayload, MultiSig, MultiSigTransactionPayload,
  generateRawTransaction, AccountAddress, Hex, MoveVector, U8,
} = require('@aptos-labs/ts-sdk');

require('dotenv').config({ path: path.join(__dirname, '../.env.deploy') });

const D_MULTISIG = process.env.D_MULTISIG;
const D_RESOURCE = process.env.D_RESOURCE;
const DEPLOYER_KEY = process.env.DEPLOYER_KEY;

if (!D_MULTISIG || !D_RESOURCE || !DEPLOYER_KEY) {
  console.error('Missing env: D_MULTISIG, D_RESOURCE, DEPLOYER_KEY');
  process.exit(1);
}

(async () => {
  // 1. Build publish payload
  console.log('=== 1. aptos move build-publish-payload ===');
  const payloadPath = '/tmp/d_publish_payload.json';
  execSync(
    `cd ${path.join(__dirname, '..')} && aptos move build-publish-payload ` +
    `--json-output-file ${payloadPath} --included-artifacts none ` +
    `--named-addresses D=${D_RESOURCE} --assume-yes`,
    { stdio: 'inherit' }
  );

  const raw = JSON.parse(fs.readFileSync(payloadPath, 'utf8'));
  // CLI emits:
  //   args[0] = { type: "hex", value: "<hex string>" }              // metadata_serialized
  //   args[1] = { type: "hex", value: ["<hex per-module>", ...] }   // code (array of module bytecodes)
  const metadataHex = raw.args[0].value;
  const codeArray = raw.args[1].value;  // array of hex strings, one per module
  if (!Array.isArray(codeArray)) {
    throw new Error('Expected args[1].value to be array of module bytecodes');
  }
  console.log(`  metadata: ${(metadataHex.length - 2) / 2} bytes`);
  console.log(`  code modules: ${codeArray.length}, total ${codeArray.reduce((s, h) => s + (h.length - 2) / 2, 0)} bytes`);

  // 2. Construct resource_account variant payload
  // Function: 0x1::resource_account::create_resource_account_and_publish_package
  // Args: (seed: vector<u8>, metadata_serialized: vector<u8>, code: vector<vector<u8>>)
  const seedBytes = Buffer.from('D', 'utf8'); // [0x44]

  const config = new AptosConfig({ network: Network.MAINNET });
  const aptos = new Aptos(config);
  const pk = new Ed25519PrivateKey(DEPLOYER_KEY);
  const proposer = Account.fromPrivateKey({ privateKey: pk });
  console.log(`\n=== 2. Proposer: ${proposer.accountAddress.toString()} ===`);

  const innerPayload = await generateTransactionPayload({
    function: '0x1::resource_account::create_resource_account_and_publish_package',
    functionArguments: [
      MoveVector.U8(Array.from(seedBytes)),
      MoveVector.U8(Array.from(Buffer.from(metadataHex.replace(/^0x/, ''), 'hex'))),
      // code: vector<vector<u8>> — one MoveVector<U8> per module bytecode
      new MoveVector(codeArray.map(h => MoveVector.U8(Array.from(Buffer.from(h.replace(/^0x/, ''), 'hex'))))),
    ],
    aptosConfig: config,
  });

  const multisigPayload = new MultiSigTransactionPayload({ transaction_payload: innerPayload });

  console.log('\n=== 3. Propose via multisig (creates pending tx) ===');
  const proposeTx = await aptos.transaction.build.simple({
    sender: proposer.accountAddress,
    data: {
      function: '0x1::multisig_account::create_transaction',
      functionArguments: [
        AccountAddress.from(D_MULTISIG),
        multisigPayload.bcsToBytes(),
      ],
    },
  });
  const proposeResp = await aptos.signAndSubmitTransaction({
    signer: proposer, transaction: proposeTx,
  });
  console.log(`  proposal tx: ${proposeResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: proposeResp.hash });
  console.log('  ✓ proposal submitted');

  console.log('\n=== 4. Execute (1/5 threshold; proposer vote suffices) ===');
  const execTx = await aptos.transaction.build.simple({
    sender: proposer.accountAddress,
    data: {
      function: '0x1::multisig_account::vote_and_execute_transaction',
      functionArguments: [AccountAddress.from(D_MULTISIG), true /* approve */],
    },
  });
  const execResp = await aptos.signAndSubmitTransaction({
    signer: proposer, transaction: execTx,
  });
  console.log(`  execute tx: ${execResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: execResp.hash });
  console.log('  ✓ executed');

  // 5. Verify pkg lives at D_RESOURCE
  console.log('\n=== 5. Verify package at resource account ===');
  const modules = await aptos.account.getAccountModules({ accountAddress: D_RESOURCE });
  const dModule = modules.find(m => m.abi?.name === 'D');
  if (dModule) {
    console.log(`  ✓ D::D module published at ${D_RESOURCE}`);
  } else {
    console.error('  ✗ D module NOT found — investigate');
    process.exit(1);
  }
})().catch(e => {
  console.error('\nERROR:', e.message || e);
  process.exit(1);
});

