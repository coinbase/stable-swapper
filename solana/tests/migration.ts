/**
 * End-to-end test for the one-shot `migrate_authorities` instruction.
 *
 * The pool is a PDA, so a legacy-layout pool can't be produced by the new program's
 * `initialize` (which only writes the new layout) and can't be created by an external
 * keypair. We use `solana-bankrun` to deploy the program in an in-process SVM and
 * `context.setAccount` to fabricate a legacy-layout pool at the canonical PDA, then run the
 * real instruction (legacy parse + realloc + rent top-up + reserialize) and assert the
 * migrated state. This is what catches the borsh packed-vs-padded parsing bug: the legacy
 * `supported_tokens` vec is packed, so the trailing fixed fields (fee_rate, pause flags,
 * bump) live at `108 + len * 32`, not `108 + MAX_SUPPORTED_TOKENS * 32`.
 */
import * as path from "path";
import { Program, BN } from "@coral-xyz/anchor";
import { PublicKey, Keypair, SystemProgram } from "@solana/web3.js";
import { start, ProgramTestContext } from "solana-bankrun";
import { BankrunProvider } from "anchor-bankrun";
import { assert } from "chai";
import { ScaasLiquidity } from "../target/types/scaas_liquidity";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const IDL = require("../target/idl/scaas_liquidity.json");

const MAX_SUPPORTED_TOKENS = 50;
// Pre-migration on-chain size: disc + ops + pause + fee_recipient + supported_tokens cap
// + fee_rate + 2 bools + bump. Matches `LiquidityPool::LEGACY_INIT_SPACE` (+ 8 disc).
const LEGACY_TOTAL =
  8 + (32 * 3 + (4 + 32 * MAX_SUPPORTED_TOKENS) + 8 + 1 + 1 + 1);

const LIQUIDITY_POOL_SEED = Buffer.from("liquidity_pool");

interface LegacyFields {
  ops: PublicKey;
  pause: PublicKey;
  feeRecipient: PublicKey;
  tokens: PublicKey[];
  feeRate: number;
  swapsPaused: boolean;
  liquidityPaused: boolean;
  bump: number;
}

// Serialize a legacy pool exactly as borsh/Anchor would have written it: the `supported_tokens`
// vec is packed (len + len*32), with the trailing fixed fields immediately after, and the
// remainder of the allocated account left as zero padding.
function buildLegacyPoolData(disc: Buffer, f: LegacyFields): Buffer {
  const buf = Buffer.alloc(LEGACY_TOTAL);
  disc.copy(buf, 0);
  f.ops.toBuffer().copy(buf, 8);
  f.pause.toBuffer().copy(buf, 40);
  f.feeRecipient.toBuffer().copy(buf, 72);
  buf.writeUInt32LE(f.tokens.length, 104);
  f.tokens.forEach((t, i) => t.toBuffer().copy(buf, 108 + i * 32));
  const trailing = 108 + f.tokens.length * 32;
  buf.writeBigUInt64LE(BigInt(f.feeRate), trailing);
  buf.writeUInt8(f.swapsPaused ? 1 : 0, trailing + 8);
  buf.writeUInt8(f.liquidityPaused ? 1 : 0, trailing + 9);
  buf.writeUInt8(f.bump, trailing + 10);
  return buf;
}

function errText(error: any): string {
  const logs = Array.isArray(error?.logs) ? error.logs.join("\n") : "";
  return `${logs}\n${error?.transactionMessage ?? ""}\n${error}`.toLowerCase();
}

describe("migrate_authorities (bankrun)", () => {
  let context: ProgramTestContext;
  let provider: BankrunProvider;
  let program: Program<ScaasLiquidity>;
  let programId: PublicKey;
  let pool: PublicKey;
  let poolBump: number;
  let accountDiscriminator: Buffer;

  // Legacy authorities embedded in the fabricated pool. The migration verifies the signers
  // against these on-chain values.
  const legacyOps = Keypair.generate();
  const legacyPause = Keypair.generate();
  const legacyFeeRecipient = Keypair.generate().publicKey;

  // New role keys supplied to the migration.
  const newPause = Keypair.generate();
  const newUnpause = Keypair.generate();
  const newTreasury = Keypair.generate();
  const newConfigure = Keypair.generate();
  const newWithdrawRecipient = Keypair.generate();

  const tokens = [
    Keypair.generate().publicKey,
    Keypair.generate().publicKey,
    Keypair.generate().publicKey,
  ];

  before(async () => {
    // Let bankrun's `start` find the freshly built program binary in target/deploy.
    const deployDir = path.resolve(__dirname, "..", "target", "deploy");
    process.env.SBF_OUT_DIR = deployDir;
    process.env.BPF_OUT_DIR = deployDir;

    programId = new PublicKey(IDL.address);
    context = await start([{ name: "scaas_liquidity", programId }], []);
    provider = new BankrunProvider(context);
    program = new Program(IDL as ScaasLiquidity, provider);

    [pool, poolBump] = PublicKey.findProgramAddressSync(
      [LIQUIDITY_POOL_SEED],
      programId
    );
    accountDiscriminator = Buffer.from(
      IDL.accounts.find((a: any) => a.name === "LiquidityPool").discriminator
    );

    // Fund the legacy signers as system accounts; legacyOps pays the realloc rent top-up.
    for (const kp of [legacyOps, legacyPause]) {
      context.setAccount(kp.publicKey, {
        lamports: 1_000 * 1_000_000_000,
        data: Buffer.alloc(0),
        owner: SystemProgram.programId,
        executable: false,
        rentEpoch: 0,
      });
    }
  });

  async function seedLegacyPool(overrides: Partial<LegacyFields> = {}) {
    const fields: LegacyFields = {
      ops: legacyOps.publicKey,
      pause: legacyPause.publicKey,
      feeRecipient: legacyFeeRecipient,
      tokens,
      feeRate: 30,
      swapsPaused: true,
      liquidityPaused: false,
      bump: poolBump,
      ...overrides,
    };
    const data = buildLegacyPoolData(accountDiscriminator, fields);
    const rent = await context.banksClient.getRent();
    const lamports = Number(rent.minimumBalance(BigInt(data.length)));
    context.setAccount(pool, {
      lamports,
      data,
      owner: programId,
      executable: false,
      rentEpoch: 0,
    });
  }

  function migrate(signers: Keypair[], pauseAuthorityAccount?: PublicKey) {
    return program.methods
      .migrateAuthorities(
        newPause.publicKey,
        newUnpause.publicKey,
        newTreasury.publicKey,
        newConfigure.publicKey,
        newWithdrawRecipient.publicKey
      )
      .accounts({
        pool,
        legacyOperationsAuthority: legacyOps.publicKey,
        legacyPauseAuthority: pauseAuthorityAccount ?? legacyPause.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .signers(signers)
      .rpc();
  }

  async function fetchPool(): Promise<any> {
    const raw = await context.banksClient.getAccount(pool);
    assert.isNotNull(raw, "pool account missing");
    // Anchor's Program constructor camelCases IDL account names.
    return program.coder.accounts.decode(
      "liquidityPool",
      Buffer.from(raw!.data)
    );
  }

  it("migrates a legacy pool and preserves packed trailing state", async () => {
    await seedLegacyPool();

    await migrate([legacyOps, legacyPause]);

    const acct = await fetchPool();
    // New roles applied.
    assert.equal(acct.pauseAuthority.toBase58(), newPause.publicKey.toBase58());
    assert.equal(
      acct.unpauseAuthority.toBase58(),
      newUnpause.publicKey.toBase58()
    );
    assert.equal(
      acct.treasuryAuthority.toBase58(),
      newTreasury.publicKey.toBase58()
    );
    assert.equal(
      acct.configureAuthority.toBase58(),
      newConfigure.publicKey.toBase58()
    );
    // Preserved + new field seeded.
    assert.equal(
      acct.feeRecipient.toBase58(),
      legacyFeeRecipient.toBase58(),
      "fee_recipient must be carried over"
    );
    assert.equal(acct.withdrawRecipients.length, 1);
    assert.equal(
      acct.withdrawRecipients[0].toBase58(),
      newWithdrawRecipient.publicKey.toBase58()
    );
    // Trailing fields read from the packed offset (the bug under test).
    assert.deepEqual(
      acct.supportedTokens.map((t: PublicKey) => t.toBase58()),
      tokens.map((t) => t.toBase58()),
      "packed supported_tokens must be parsed in full"
    );
    assert.equal(
      acct.feeRate.toNumber(),
      30,
      "fee_rate must survive migration"
    );
    assert.equal(acct.swapsPaused, true, "swaps_paused must survive migration");
    assert.equal(acct.liquidityPaused, false);
    assert.equal(
      acct.bump,
      poolBump,
      "bump must survive migration (zero bump would brick the PDA)"
    );
  });

  it("rejects a second migration (AlreadyMigrated)", async () => {
    await seedLegacyPool();
    await migrate([legacyOps, legacyPause]);

    try {
      await migrate([legacyOps, legacyPause]);
      assert.fail("expected AlreadyMigrated");
    } catch (error) {
      assert.include(errText(error), "alreadymigrated");
    }
  });

  it("rejects a migration when a legacy signer does not match", async () => {
    await seedLegacyPool();
    const stranger = Keypair.generate();
    context.setAccount(stranger.publicKey, {
      lamports: 1_000_000_000,
      data: Buffer.alloc(0),
      owner: SystemProgram.programId,
      executable: false,
      rentEpoch: 0,
    });

    try {
      await migrate([legacyOps, stranger], stranger.publicKey);
      assert.fail("expected legacy signer mismatch");
    } catch (error) {
      assert.include(errText(error), "legacydiscriminatormismatch");
    }
  });

  it("works with an empty legacy supported_tokens vec", async () => {
    // Regression guard for the offset math when len = 0: trailing fields sit right after
    // the 4-byte length prefix.
    await seedLegacyPool({ tokens: [], feeRate: 7, swapsPaused: false });
    await migrate([legacyOps, legacyPause]);

    const acct = await fetchPool();
    assert.equal(acct.supportedTokens.length, 0);
    assert.equal(acct.feeRate.toNumber(), 7);
    assert.equal(acct.swapsPaused, false);
    assert.equal(acct.bump, poolBump);
  });
});
