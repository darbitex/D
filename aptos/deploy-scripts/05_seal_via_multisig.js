// Multisig seal: propose + execute D::destroy_cap. POINT OF NO RETURN.
// 1/5 threshold, so single owner approves+executes.

const path = require('path');
const {
  Aptos, AptosConfig, Network, Account, Ed25519PrivateKey,
  generateTransactionPayload, MultiSigTransactionPayload, AccountAddress,
} = require('@aptos-labs/ts-sdk');

require('dotenv').config({ path: path.join(__dirname, '../.env.deploy') });

const D_MULTISIG = process.env.D_MULTISIG;
const D_RESOURCE = process.env.D_RESOURCE;
const DEPLOYER_KEY = process.env.DEPLOYER_KEY;

if (!D_MULTISIG || !D_RESOURCE || !DEPLOYER_KEY) {
  console.error('Missing env: D_MULTISIG, D_RESOURCE, DEPLOYER_KEY'); process.exit(1);
}

(async () => {
  const config = new AptosConfig({ network: Network.MAINNET });
  const aptos = new Aptos(config);
  const pk = new Ed25519PrivateKey(DEPLOYER_KEY);
  const proposer = Account.fromPrivateKey({ privateKey: pk });
  console.log(`Proposer: ${proposer.accountAddress.toString()}`);
  console.log(`Multisig: ${D_MULTISIG}`);
  console.log(`Resource: ${D_RESOURCE}`);
  console.log();
  console.log('==============================================');
  console.log('WARNING: destroy_cap is IRREVERSIBLE');
  console.log('After execution, the package is permanently sealed.');
  console.log('==============================================');
  console.log();
  console.log('Confirm by setting CONFIRM_SEAL=YES in env.');
  if (process.env.CONFIRM_SEAL !== 'YES') {
    console.error('Aborting — CONFIRM_SEAL not set to YES');
    process.exit(1);
  }

  // Inner payload: D::destroy_cap()
  const innerPayload = await generateTransactionPayload({
    function: `${D_RESOURCE}::D::destroy_cap`,
    functionArguments: [],
    aptosConfig: config,
  });
  const multisigPayload = new MultiSigTransactionPayload({ transaction_payload: innerPayload });

  console.log('=== Propose ===');
  const proposeTx = await aptos.transaction.build.simple({
    sender: proposer.accountAddress,
    data: {
      function: '0x1::multisig_account::create_transaction',
      functionArguments: [AccountAddress.from(D_MULTISIG), multisigPayload.bcsToBytes()],
    },
  });
  const proposeResp = await aptos.signAndSubmitTransaction({ signer: proposer, transaction: proposeTx });
  console.log(`  proposal tx: ${proposeResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: proposeResp.hash });

  console.log('\n=== Execute (1/5 threshold; proposer suffices) ===');
  const execTx = await aptos.transaction.build.simple({
    sender: proposer.accountAddress,
    data: {
      function: '0x1::multisig_account::vote_and_execute_transaction',
      functionArguments: [AccountAddress.from(D_MULTISIG), true],
    },
  });
  const execResp = await aptos.signAndSubmitTransaction({ signer: proposer, transaction: execTx });
  console.log(`  execute tx: ${execResp.hash}`);
  await aptos.waitForTransaction({ transactionHash: execResp.hash });

  console.log('\n=== Verify sealed ===');
  const sealed = await aptos.view({
    payload: { function: `${D_RESOURCE}::D::is_sealed`, functionArguments: [] },
  });
  console.log(`  is_sealed: ${sealed[0]}`);
  if (sealed[0] !== true) {
    console.error('  ✗ NOT SEALED — investigate');
    process.exit(1);
  }
  try {
    await aptos.account.getAccountResource({
      accountAddress: D_RESOURCE,
      resourceType: `${D_RESOURCE}::D::ResourceCap`,
    });
    console.error('  ✗ ResourceCap STILL EXISTS — investigate');
    process.exit(1);
  } catch (e) {
    if (e.message.includes('not found')) {
      console.log('  ✓ ResourceCap resource gone (404)');
    } else {
      throw e;
    }
  }
  console.log('\n=== D Aptos v0.2.0 PERMANENTLY SEALED ===');
  console.log(`Package: ${D_RESOURCE} (immutable)`);
  console.log('Next: 06_raise_threshold.js to bring multisig governance to 3/5');
})().catch(e => { console.error('\nERROR:', e.message || e); process.exit(1); });
