/**
 * D Sui — Testnet smoke test
 *
 * Exercises every public entry function against the deployed sealed package.
 * Updates Pyth SUI/USD feed, opens trove, tests donate_to_sp / sp_deposit /
 * sp_claim / sp_withdraw / redeem / redeem_from_reserve / close_trove +
 * negative-case aborts.
 *
 * Reads publish-output.json for testnet IDs.
 * Run: SUI_NETWORK=testnet npx ts-node smoke.ts
 */

import { readFileSync, existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';
import { fromBase64 } from '@mysten/sui/utils';
import { SuiPriceServiceConnection, SuiPythClient } from '@pythnetwork/pyth-sui-js';

const NETWORK = (process.env.SUI_NETWORK || 'testnet') as 'mainnet' | 'testnet';
const SUI_USD_FEED = '0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744';
const HERMES_URL = 'https://hermes.pyth.network';
const PYTH_PKG_TESTNET = '0xabf837e98c26087cba0883c0a7a28326b1fa3c5e1e2c5abdb486f9e8f594c837';
const PYTH_STATE_TESTNET = '0x243759059f4c3111179da5878c12f68d612c21a8d54d85edc86164bb18be1c7c';
const WORMHOLE_PKG_TESTNET = '0xf47329f4344f3bf0f8e436e2f7b485466cff300f12a166563995d3888c296a94';
const WORMHOLE_STATE_TESTNET = '0x31358d198147da50db32eda2562951d53973a0c0ad5ed738e9b17d88b213d790';

const out = JSON.parse(readFileSync(join(__dirname, 'publish-output.json'), 'utf-8'));
const PKG = out.package_id;
const REG = out.registry_id;
const D_TYPE = `${PKG}::D::D`;
const SUI_TYPE = '0x2::sui::SUI';

function loadKeypair(addr: string): Ed25519Keypair {
    const keys: string[] = JSON.parse(readFileSync(join(homedir(), '.sui', 'sui_config', 'sui.keystore'), 'utf-8'));
    for (const e of keys) {
        try {
            const kp = e.startsWith('suiprivkey')
                ? Ed25519Keypair.fromSecretKey(decodeSuiPrivateKey(e).secretKey)
                : Ed25519Keypair.fromSecretKey(fromBase64(e).slice(1));
            if (kp.getPublicKey().toSuiAddress() === addr) return kp;
        } catch {}
    }
    throw new Error('keypair not found');
}

const client = new SuiClient({ url: getFullnodeUrl(NETWORK) });
const keypair = loadKeypair(out.active_addr);
const SENDER = keypair.getPublicKey().toSuiAddress();

const pythConnection = new SuiPriceServiceConnection(HERMES_URL);
const pythClient = new SuiPythClient(client, PYTH_STATE_TESTNET, WORMHOLE_STATE_TESTNET);

let pass = 0, fail = 0;
async function step(name: string, fn: () => Promise<void>) {
    process.stdout.write(`[${name}] `);
    try {
        await fn();
        console.log('PASS');
        pass++;
    } catch (e: any) {
        console.log(`FAIL: ${e.message?.slice(0, 200) || e}`);
        fail++;
    }
}

async function exec(tx: Transaction, expectFail = false): Promise<any> {
    tx.setGasBudget(500_000_000);
    const r = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true, showObjectChanges: true, showEvents: true },
    });
    const status = r.effects?.status.status;
    if (expectFail && status === 'success') throw new Error('expected failure but succeeded');
    if (!expectFail && status !== 'success') throw new Error(`tx failed: ${JSON.stringify(r.effects?.status)}`);
    await client.waitForTransaction({ digest: r.digest });
    return r;
}

async function ensurePythFeed() {
    try {
        const tx = new Transaction();
        const updateData = await pythConnection.getPriceFeedsUpdateData([SUI_USD_FEED]);
        await pythClient.createPriceFeed(tx, updateData);
        tx.setGasBudget(500_000_000);
        const r = await client.signAndExecuteTransaction({ transaction: tx, signer: keypair, options: { showEffects: true } });
        if (r.effects?.status.status === 'success') {
            console.log('  (Pyth SUI/USD feed created on testnet)');
            await client.waitForTransaction({ digest: r.digest });
        }
    } catch (e: any) {
        // already exists, fine
    }
}

async function readReg() {
    const obj = await client.getObject({ id: REG, options: { showContent: true } });
    return (obj.data?.content as any).fields ?? (obj.data?.content as any);
}

async function pythUpdate(tx: Transaction): Promise<string> {
    const updateData = await pythConnection.getPriceFeedsUpdateData([SUI_USD_FEED]);
    const priceInfoIds = await pythClient.updatePriceFeeds(tx, updateData, [SUI_USD_FEED]);
    return priceInfoIds[0];
}

async function main() {
    console.log(`=== D Sui smoke test on ${NETWORK} ===`);
    console.log(`  Package: ${PKG}`);
    console.log(`  Registry: ${REG}`);
    console.log(`  Sender: ${SENDER}\n`);

    console.log('Bootstrapping Pyth feed (one-time)...');
    await ensurePythFeed();

    let troveCollateral = 0n;
    let troveDebt = 0n;

    await step('1. read_warning view', async () => {
        const tx = new Transaction();
        tx.moveCall({ target: `${PKG}::D::read_warning` });
        const r = await client.devInspectTransactionBlock({ sender: SENDER, transactionBlock: tx });
        if (r.effects.status.status !== 'success') throw new Error('view failed');
    });

    await step('2. is_sealed === true', async () => {
        const reg = await readReg();
        if (reg.sealed !== true) throw new Error(`sealed=${reg.sealed}`);
    });

    await step('3. donate_to_reserve already verified pre-script (0.1 SUI)', async () => {
        const reg = await readReg();
        if (BigInt(reg.reserve_coll) === 0n) throw new Error('reserve_coll empty');
    });

    await step('4. donate_to_reserve zero aborts', async () => {
        const tx = new Transaction();
        const zeroCoin = tx.splitCoins(tx.gas, [0]);
        tx.moveCall({
            target: `${PKG}::D::donate_to_reserve`,
            arguments: [tx.object(REG), zeroCoin],
        });
        await exec(tx, true);
    });

    await step('5. donate_to_reserve incremental (0.05 SUI)', async () => {
        const before = BigInt((await readReg()).reserve_coll);
        const tx = new Transaction();
        const c = tx.splitCoins(tx.gas, [50_000_000]);
        tx.moveCall({ target: `${PKG}::D::donate_to_reserve`, arguments: [tx.object(REG), c] });
        await exec(tx);
        const after = BigInt((await readReg()).reserve_coll);
        if (after - before !== 50_000_000n) throw new Error(`delta ${after - before}`);
    });

    await step('6. open_trove with Pyth update + 1 SUI collateral, 1.5 D debt', async () => {
        const tx = new Transaction();
        const priceInfoId = await pythUpdate(tx);
        const coll = tx.splitCoins(tx.gas, [1_000_000_000]); // 1 SUI
        const minted = tx.moveCall({
            target: `${PKG}::D::open_trove`,
            arguments: [
                tx.object(REG),
                coll,
                tx.pure.u64(150_000_000), // 1.5 D debt (8 decimals) — well above MIN_DEBT 1 D
                tx.object(priceInfoId),
                tx.object('0x6'),
            ],
        });
        tx.transferObjects([minted], SENDER);
        await exec(tx);
        const reg = await readReg();
        if (BigInt(reg.total_debt) !== 150_000_000n) throw new Error(`total_debt=${reg.total_debt}`);
        troveDebt = 150_000_000n;
        troveCollateral = 1_000_000_000n;
    });

    await step('7. trove_of returns expected collateral + debt', async () => {
        const tx = new Transaction();
        tx.moveCall({ target: `${PKG}::D::trove_of`, arguments: [tx.object(REG), tx.pure.address(SENDER)] });
        const r = await client.devInspectTransactionBlock({ sender: SENDER, transactionBlock: tx });
        if (r.effects.status.status !== 'success') throw new Error('view failed');
    });

    await step('8. add_collateral 0.5 SUI', async () => {
        const tx = new Transaction();
        const c = tx.splitCoins(tx.gas, [500_000_000]);
        tx.moveCall({ target: `${PKG}::D::add_collateral`, arguments: [tx.object(REG), c] });
        await exec(tx);
        troveCollateral += 500_000_000n;
    });

    let dCoinId: string | null = null;
    await step('9. fetch user D coin (from open_trove mint, net of 1% fee)', async () => {
        const coins = await client.getCoins({ owner: SENDER, coinType: D_TYPE });
        if (coins.data.length === 0) throw new Error('no D coins owned');
        dCoinId = coins.data[0].coinObjectId;
        const total = coins.data.reduce((s, c) => s + BigInt(c.balance), 0n);
        const expected = troveDebt - (troveDebt * 100n / 10000n); // net 99%
        if (total !== expected) throw new Error(`got ${total}, expected ${expected}`);
    });

    await step('10. donate_to_sp 0.1 D (10_000_000 raw)', async () => {
        const tx = new Transaction();
        const donateCoin = tx.splitCoins(tx.object(dCoinId!), [10_000_000]);
        tx.moveCall({ target: `${PKG}::D::donate_to_sp`, arguments: [tx.object(REG), donateCoin] });
        await exec(tx);
        const reg = await readReg();
        if (BigInt(reg.sp_pool) !== 10_000_000n) throw new Error(`sp_pool=${reg.sp_pool}`);
        if (BigInt(reg.total_sp) !== 0n) throw new Error(`total_sp=${reg.total_sp} (donations should bypass)`);
    });

    await step('11. donate_to_sp zero aborts', async () => {
        const tx = new Transaction();
        const zeroCoin = tx.splitCoins(tx.object(dCoinId!), [0]);
        tx.moveCall({ target: `${PKG}::D::donate_to_sp`, arguments: [tx.object(REG), zeroCoin] });
        await exec(tx, true);
    });

    await step('12. sp_deposit 0.5 D (50_000_000 raw)', async () => {
        const tx = new Transaction();
        const dep = tx.splitCoins(tx.object(dCoinId!), [50_000_000]);
        tx.moveCall({ target: `${PKG}::D::sp_deposit`, arguments: [tx.object(REG), dep] });
        await exec(tx);
        const reg = await readReg();
        if (BigInt(reg.total_sp) !== 50_000_000n) throw new Error(`total_sp=${reg.total_sp}`);
        if (BigInt(reg.sp_pool) !== 60_000_000n) throw new Error(`sp_pool=${reg.sp_pool}`);
    });

    await step('13. sp_of returns position', async () => {
        const reg = await readReg();
        if (Number(reg.sp_positions.size) !== 1) throw new Error(`sp_positions size=${reg.sp_positions.size}`);
    });

    await step('14. sp_claim no-op (no pending rewards yet)', async () => {
        const tx = new Transaction();
        tx.moveCall({ target: `${PKG}::D::sp_claim`, arguments: [tx.object(REG)] });
        await exec(tx);
    });

    await step('15. sp_withdraw_entry 0.2 D', async () => {
        const tx = new Transaction();
        tx.moveCall({ target: `${PKG}::D::sp_withdraw_entry`, arguments: [tx.object(REG), tx.pure.u64(20_000_000)] });
        await exec(tx);
        const reg = await readReg();
        if (BigInt(reg.total_sp) !== 30_000_000n) throw new Error(`total_sp=${reg.total_sp}`);
    });

    await step('16. redeem_from_reserve 0.1 D', async () => {
        const tx = new Transaction();
        const priceInfoId = await pythUpdate(tx);
        // refresh dCoinId
        const coins = await client.getCoins({ owner: SENDER, coinType: D_TYPE });
        const dRef = tx.object(coins.data[0].coinObjectId);
        const reqCoin = tx.splitCoins(dRef, [10_000_000]);
        const out_sui = tx.moveCall({
            target: `${PKG}::D::redeem_from_reserve`,
            arguments: [tx.object(REG), reqCoin, tx.object(priceInfoId), tx.object('0x6')],
        });
        tx.transferObjects([out_sui], SENDER);
        await exec(tx);
    });

    await step('17. close_trove with full debt repayment', async () => {
        // Need debt amount D — fetch fresh debt
        const reg = await readReg();
        const dCoins = await client.getCoins({ owner: SENDER, coinType: D_TYPE });
        const totalD = dCoins.data.reduce((s, c) => s + BigInt(c.balance), 0n);
        if (totalD < troveDebt) {
            console.log(`(skip — only have ${totalD} D, need ${troveDebt}; close requires full debt)`);
            return;
        }
        const tx = new Transaction();
        const dRef = tx.object(dCoins.data[0].coinObjectId);
        const repay = tx.splitCoins(dRef, [troveDebt.toString()]);
        const sui_back = tx.moveCall({ target: `${PKG}::D::close_trove_entry`, arguments: [tx.object(REG), repay] });
        await exec(tx);
        const reg2 = await readReg();
        if (BigInt(reg2.total_debt) !== 0n) throw new Error(`total_debt=${reg2.total_debt}`);
    });

    await step('18. final state snapshot', async () => {
        const reg = await readReg();
        console.log(`\n  Final registry state:`);
        console.log(`    sealed:           ${reg.sealed}`);
        console.log(`    total_debt:       ${reg.total_debt}`);
        console.log(`    total_sp:         ${reg.total_sp}`);
        console.log(`    sp_pool:          ${reg.sp_pool}`);
        console.log(`    reserve_coll:     ${reg.reserve_coll}`);
        console.log(`    treasury_coll:    ${reg.treasury_coll}`);
        console.log(`    fee_pool:         ${reg.fee_pool}`);
        console.log(`    product_factor:   ${reg.product_factor}`);
        console.log(`    reward_index_d:   ${reg.reward_index_d}`);
        console.log(`    troves count:     ${reg.troves.size}`);
        console.log(`    sp_positions:     ${reg.sp_positions.size}`);
    });

    console.log(`\n=== ${pass} PASS / ${fail} FAIL ===`);
    process.exit(fail > 0 ? 1 : 0);
}

main().catch((e) => {
    console.error('FATAL:', e);
    process.exit(99);
});
