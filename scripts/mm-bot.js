#!/usr/bin/env node
/**
 * 做市/刷量机器人：资金在 MCP 钱包（funder），MCP 仅对 FlapSkill 合约授权 USDT 并 setAllowedCallers；
 * 买卖由 worker 调用 FlapSkill.buyForCaller / sellForCaller 完成，不是 MCP 直接买卖。
 *
 * 环境变量：FUNDER_ADDRESS, TOKEN_CA 必填。私钥二选一：PRIVATE_KEYS 或 PRIVATE_KEYS_FILE。可选 COLLECT_TO_ADDRESS：停止时（用户停止或 Ctrl+C）自动将 worker 剩余代币与 BNB 归集到该地址。做市不设磨损上限，仅由用户停止。
 * 若 MCP 钱包（funder）无 USDT 导致 buyForCaller 失败（TRANSFER_FROM_FAILED），则自动将所有 worker 持有的该代币通过 sellForCaller 卖给 funder（USDT 回到 funder），然后继续刷量，不停止。
 */

import { createPublicClient, createWalletClient, http, parseAbi, parseUnits, getAddress } from "viem";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
import { privateKeyToAccount } from "viem/accounts";
import { bsc } from "viem/chains";

const FLAP_SKILL = getAddress("0x03a9aeeb4f6e64d425126164f7262c2a754b3ff9");
const USDT_DECIMALS = 18;
const MAX_WORKERS = 20;

const FLAP_SKILL_ABI = parseAbi([
  "function buyForCaller(address _token, uint256 _usdtAmount, address _funder) external",
  "function sellForCaller(address _token, uint256 _tokenAmount, address _funder) external",
]);
const ERC20_ABI = parseAbi([
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
]);

function env(key, def) {
  const v = process.env[key];
  return v !== undefined && v !== "" ? v : def;
}

function parseNum(s, def) {
  if (s === undefined || s === "") return def;
  const n = Number(s);
  if (Number.isNaN(n)) return def;
  return n;
}

function randomInRange(min, max) {
  const m = Math.min(min, max);
  const M = Math.max(min, max);
  const r = m + Math.random() * (M - m);
  return Math.round(r * 1e4) / 1e4;
}

function parsePrivateKeys(input) {
  if (!input || typeof input !== "string") return [];
  return input
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function loadWorkerKeys() {
  const fromEnv = parsePrivateKeys(env("PRIVATE_KEYS", ""));
  if (fromEnv.length >= 2) return fromEnv;
  const filePath = env("PRIVATE_KEYS_FILE", "");
  if (!filePath) return [];
  const abs = path.isAbsolute(filePath) ? filePath : path.join(process.cwd(), filePath);
  if (!fs.existsSync(abs)) return [];
  const data = JSON.parse(fs.readFileSync(abs, "utf8"));
  const keys = Array.isArray(data.privateKeys) ? data.privateKeys : [];
  return keys.filter((k) => typeof k === "string" && k.length > 0);
}

async function main() {
  const tokenCa = env("TOKEN_CA", process.argv[2]);
  if (!tokenCa) {
    console.error("用法: TOKEN_CA=0x... node scripts/mm-bot.js  或  node scripts/mm-bot.js <TOKEN_CA> [usdtMin] [usdtMax] [intervalSec] [rounds]");
    console.error("必须: FUNDER_ADDRESS (MCP 钱包地址), TOKEN_CA");
    console.error("私钥二选一: PRIVATE_KEYS (2～20 个逗号分隔) 或 PRIVATE_KEYS_FILE=.mm-workers.json（由 mm-generate-workers.js 生成）");
    console.error("必填: COLLECT_TO_ADDRESS（资金归集地址）。可选: RPC_URL, USDT_MIN, USDT_MAX, INTERVAL_SEC, ROUNDS");
    process.exit(1);
  }
  const token = getAddress(tokenCa);
  const collectTo = env("COLLECT_TO_ADDRESS", "");
  if (!collectTo) {
    console.error("请设置环境变量 COLLECT_TO_ADDRESS（资金归集地址；停止时将 worker 剩余代币与 BNB 归集到该地址）");
    process.exit(1);
  }
  getAddress(collectTo);
  const rpcUrl = env("RPC_URL", "https://bsc-dataseed.binance.org");
  const funderAddressRaw = env("FUNDER_ADDRESS", "");
  if (!funderAddressRaw) {
    console.error("请设置环境变量 FUNDER_ADDRESS（MCP 钱包地址，资金方；须已对 FlapSkill approve USDT）");
    process.exit(1);
  }
  const funderAddress = getAddress(funderAddressRaw);
  const workerKeys = loadWorkerKeys();
  if (workerKeys.length < 2 || workerKeys.length > MAX_WORKERS) {
    console.error(`请设置 PRIVATE_KEYS 或 PRIVATE_KEYS_FILE（.mm-workers.json），需 2～${MAX_WORKERS} 个 worker 私钥`);
    process.exit(1);
  }

  const usdtMin = parseNum(env("USDT_MIN", process.argv[3]), 0.005);
  const usdtMax = parseNum(env("USDT_MAX", process.argv[4]), 0.02);
  const intervalSec = parseNum(env("INTERVAL_SEC", process.argv[5]), 15);
  const rounds = parseNum(env("ROUNDS", process.argv[6]), 0);

  let collected = false;
  const runCollectOnExit = () => {
    if (collected) return;
    collected = true;
    const keysFile = env("PRIVATE_KEYS_FILE", "");
    if (!keysFile) return;
    console.log("正在将 worker 剩余资金归集到", collectTo, "...");
    try {
      execSync(`node "${path.join(__dirname, "mm-collect.js")}"`, {
        env: { ...process.env, TARGET_ADDRESS: collectTo, TOKEN_CA: tokenCa },
        cwd: process.cwd(),
        stdio: "inherit",
      });
    } catch (e) {
      console.error("归集失败:", e.message || e);
    }
  };

  process.on("SIGINT", () => {
    console.log("收到停止信号，做市将在本轮结束后停止并执行归集…");
    stopRequested = true;
  });
  process.on("SIGTERM", () => {
    console.log("收到停止信号，做市将在本轮结束后停止并执行归集…");
    stopRequested = true;
  });

  const transport = http(rpcUrl);
  const chain = bsc;
  const publicClient = createPublicClient({ chain, transport });
  const accounts = workerKeys.map((pk) => privateKeyToAccount(pk));
  const walletClients = accounts.map((account) => createWalletClient({ account, chain, transport }));

  const tokenContract = { address: token, abi: ERC20_ABI };

  console.log("做市机器人配置:");
  console.log("  FlapSkill:", FLAP_SKILL);
  console.log("  资金方(funder):", funderAddress);
  console.log("  代币:", token);
  console.log("  交易地址数:", accounts.length);
  console.log("  每笔 USDT 范围:", usdtMin, "~", usdtMax);
  console.log("  间隔(秒):", intervalSec, "  轮数(0=无限):", rounds);
  console.log("---");
  console.log("请确认已通过 MCP 用 funder 钱包：1) 对 FlapSkill approve USDT  2) 调用 setAllowedCallers(" + token + ", [上述 " + accounts.length + " 个地址])，以区分不同人、不同代币的刷量会话。");
  console.log("---");

  let done = 0;
  let stopRequested = false;
  let prevBuyerIdx = null;
  let prevSellerIdx = null;

  const isGasRelatedError = (msg) => {
    if (!msg || typeof msg !== "string") return false;
    const s = msg.toLowerCase();
    return (
      s.includes("insufficient") ||
      s.includes("exceeds the balance") ||
      s.includes("not enough") ||
      s.includes("balance of the account")
    );
  };

  /** funder 无 USDT 导致 buyForCaller 扣款失败 */
  const isFunderNoUsdtError = (msg) => {
    if (!msg || typeof msg !== "string") return false;
    const s = msg.toLowerCase();
    return s.includes("transfer_from_failed") || s.includes("transferhelper");
  };

  /** 将当前所有 worker 持有的该代币通过 sellForCaller 卖给 funder，然后退出并归集 */
  const runSellAllWorkersToFunder = async () => {
    console.log("[MCP 无 USDT] 正在将各 worker 持有的代币全部卖给 funder…");
    let soldCount = 0;
    for (let i = 0; i < accounts.length; i++) {
      const account = accounts[i];
      const wallet = walletClients[i];
      try {
        const balance = await publicClient.readContract({
          ...tokenContract,
          functionName: "balanceOf",
          args: [account.address],
        });
        if (balance === 0n) continue;
        const approveHash = await wallet.writeContract({
          ...tokenContract,
          functionName: "approve",
          args: [FLAP_SKILL, balance],
          account,
        });
        await publicClient.waitForTransactionReceipt({ hash: approveHash });
        const sellHash = await wallet.writeContract({
          address: FLAP_SKILL,
          abi: FLAP_SKILL_ABI,
          functionName: "sellForCaller",
          args: [token, balance, funderAddress],
          account,
        });
        await publicClient.waitForTransactionReceipt({ hash: sellHash });
        soldCount++;
        console.log(`  worker ${account.address.slice(0, 10)}… 已卖出，tx ${sellHash.slice(0, 10)}…`);
      } catch (e) {
        console.error(`  worker ${account.address} 卖出失败:`, (e && e.message) || e);
      }
    }
    console.log(`[MCP 无 USDT] 已将所有 worker 代币卖给 funder，共 ${soldCount} 笔。funder 已收回 USDT，继续刷量。`);
  };

  const runOne = async () => {
    const amount = randomInRange(usdtMin, usdtMax);
    const usdtAmountWei = parseUnits(String(amount), USDT_DECIMALS);
    const L = accounts.length;
    const indices = [...Array(L).keys()];
    const canBuy = prevSellerIdx === null ? indices : indices.filter((i) => i !== prevSellerIdx);
    const canSeller = prevBuyerIdx === null ? indices : indices.filter((i) => i !== prevBuyerIdx);
    const buyerIdx = canBuy[Math.floor(Math.random() * canBuy.length)];
    let sellerCandidates = canSeller.filter((i) => i !== buyerIdx);
    if (sellerCandidates.length === 0) sellerCandidates = indices.filter((i) => i !== buyerIdx);
    const sellerIdx = sellerCandidates[Math.floor(Math.random() * sellerCandidates.length)];
    const buyer = accounts[buyerIdx];
    const seller = accounts[sellerIdx];
    const buyerWallet = walletClients[buyerIdx];
    const sellerWallet = walletClients[sellerIdx];

    try {
    // 1) 买家通过 FlapSkill.buyForCaller 买入（扣 funder 的 USDT，代币给买家）
    const buyHash = await buyerWallet.writeContract({
      address: FLAP_SKILL,
      abi: FLAP_SKILL_ABI,
      functionName: "buyForCaller",
      args: [token, usdtAmountWei, funderAddress],
      account: buyer,
    });
    await publicClient.waitForTransactionReceipt({ hash: buyHash });
    const tokenBalance = await publicClient.readContract({
      ...tokenContract,
      functionName: "balanceOf",
      args: [buyer.address],
    });
    if (tokenBalance === 0n) {
      console.warn(`[${new Date().toISOString()}] 轮 ${done + 1} 买入后余额为 0，跳过`);
      done++;
      return;
    }

    // 卖出数量随机：本次买入得到的代币的 50%～100% 随机比例
    const ratioBps = 5000 + Math.floor(Math.random() * 5001);
    let sellAmount = (tokenBalance * BigInt(ratioBps)) / 10000n;
    if (sellAmount < 1n) sellAmount = 1n;

    // 2) 买家把要卖出的代币转给卖家
    const transferHash = await buyerWallet.writeContract({
      ...tokenContract,
      functionName: "transfer",
      args: [seller.address, sellAmount],
      account: buyer,
    });
    await publicClient.waitForTransactionReceipt({ hash: transferHash });

    // 3) 卖家授权 FlapSkill 并调用 sellForCaller（所得 USDT 回 funder）
    const approveHash = await sellerWallet.writeContract({
      ...tokenContract,
      functionName: "approve",
      args: [FLAP_SKILL, sellAmount],
      account: seller,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
    const sellHash = await sellerWallet.writeContract({
      address: FLAP_SKILL,
      abi: FLAP_SKILL_ABI,
      functionName: "sellForCaller",
      args: [token, sellAmount, funderAddress],
      account: seller,
    });
    await publicClient.waitForTransactionReceipt({ hash: sellHash });

    const sellPct = (ratioBps / 100).toFixed(1);
    console.log(
      `[${new Date().toISOString()}] 轮 ${done + 1} 买 ${amount} U | 卖 ${sellPct}% 仓位 | 买 ${buyHash.slice(0, 10)}… → 转 → 卖 ${sellHash.slice(0, 10)}…`
    );
    prevBuyerIdx = buyerIdx;
    prevSellerIdx = sellerIdx;
    done++;
    } catch (e) {
      const errMsg = (e && e.message) ? String(e.message) : "";
      if (isFunderNoUsdtError(errMsg)) {
        console.error(`[${new Date().toISOString()}] 轮 ${done + 1} 失败: MCP 钱包(funder)无 USDT，无法扣款。`);
        await runSellAllWorkersToFunder();
        return;
      }
      if (isGasRelatedError(errMsg)) {
        console.error(
          `[${new Date().toISOString()}] 轮 ${done + 1} 失败(可能 worker Gas 不足):`,
          errMsg.slice(0, 200)
        );
        console.error(
          `[Agent 自主补 Gas 无需主人批准] 请用 MCP transfer_native_token 向以下可能缺 Gas 的 worker 各转 0.001 BNB 后继续： buyer=${buyer.address} seller=${seller.address}`
        );
      }
      throw e;
    }
  };

  const loop = async () => {
    while (!stopRequested && (rounds === 0 || done < rounds)) {
      try {
        await runOne();
      } catch (e) {
        const errMsg = (e && e.message) ? String(e.message) : "";
        if (!isGasRelatedError(errMsg)) {
          console.error(`[${new Date().toISOString()}] 轮 ${done + 1} 失败:`, errMsg || e);
        }
      }
      if (stopRequested || (rounds > 0 && done >= rounds)) break;
      await new Promise((r) => setTimeout(r, intervalSec * 1000));
    }
    console.log("做市结束，共执行", done, "轮");
  };

  await loop();
  runCollectOnExit();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
