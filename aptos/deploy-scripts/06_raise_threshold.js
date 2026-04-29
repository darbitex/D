// Raise multisig threshold 1/5 → 3/5 post-seal.
// Pure governance hygiene; package is already immutable so this doesn't affect security.

const path = require('path');
const {
  Aptos, AptosConfig, Network, Account, Ed25519PrivateKey,
  generateTransactionPayload, MultiSigTransactionPayload, AccountAddress,
} = require('@aptos-labs/ts-sdk');

require('dotenv').config({ path: path.join(__dirname, '../.env.deploy') });

const D_MULTISIG = process.env.D_MULTISIG;
const DEPLOYER_KEY = process.env.DEPLOYER_KEY;

if (!D_MULTISIG || !DEPLOYER_KEY) { console.error('Missing env'); process.exit(1); }

(async () => {
  const config = new AptosConfig({ network: Network.MAINNET });
  const aptos = new Aptos(config);
  const pk = new Ed25519PrivateKey(DEPLOYER_KEY);
  const proposer = Account.fromPrivateKey({ privateKey: pk });
  console.log(`Proposer: ${proposer.accountAddress.toString()}`);
  console.log(`Multisig: ${D_MULTISIG}`);

  const innerPayload = await generateTransactionPayload({
    function: '0x1::multisig_account::update_signatures_required',
    functionArguments: [3], // raise to 3/5
    aptosConfig: config,
  });
  const multisigPayload = new MultiSigTransactionPayload({ transaction_payload: innerPayload });

  console.log('\n=== Propose: update_signatures_required(3) ===');
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

  console.log('\n=== Execute (last action under 1/5 threshold) ===');
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

  console.log('\n=== Verify ===');
  const ms = await aptos.account.getAccountResource({
    accountAddress: D_MULTISIG,
    resourceType: '0x1::multisig_account::MultisigAccount',
  });
  console.log(`  num_signatures_required: ${ms.num_signatures_required}`);
  if (parseInt(ms.num_signatures_required) === 3) {
    console.log('  ✓ Multisig governance now 3/5');
  } else {
    console.error('  ✗ threshold not 3 — investigate');
  }
})().catch(e => { console.error('\nERROR:', e.message || e); process.exit(1); });
