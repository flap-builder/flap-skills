#!/usr/bin/env node
/**
 * 计算 createToken 所需的 _salt（bytes32），使 CREATE2 部署出的代币地址满足 Portal 要求的 vanity 后缀。
 * 文档：https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal
 * - 税收代币 (tax)：后缀 7777
 * - 标准代币 (no tax)：后缀 8888
 */

import { keccak256, toHex, getContractAddress, hexToBytes } from "viem";
import crypto from "crypto";

const PORTAL_BSC = "0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0";
const TAX_TOKEN_V1_IMPL_BSC = "0x29e6383F0ce68507b5A72a53c2B118a118332aA8";
const TAX_TOKEN_V2_IMPL_BSC = "0xae562c6A05b798499507c6276C6Ed796027807BA";

function getInitCode(implAddress) {
  const impl = implAddress.toLowerCase().replace(/^0x/, "").padStart(40, "0");
  return ("0x3d602d80600a3d3981f3363d3d373d3d3d363d73" + impl + "5af43d82803e903d91602b57fd5bf3");
}

function predictTokenAddress(salt, tokenImpl = TAX_TOKEN_V1_IMPL_BSC, portal = PORTAL_BSC) {
  const bytecode = getInitCode(tokenImpl);
  const addr = getContractAddress({
    from: portal,
    salt: hexToBytes(salt),
    bytecode,
    opcode: "CREATE2",
  });
  return addr;
}

/**
 * 寻找使代币地址以 suffix 结尾的 salt。
 * @param {string} suffix - 4 字符，如 "7777" 或 "8888"
 */
export function findVanitySalt(suffix = "7777", tokenImpl = TAX_TOKEN_V1_IMPL_BSC, portal = PORTAL_BSC) {
  if (suffix.length !== 4) {
    throw new Error("suffix 必须为 4 个字符，如 7777 或 8888");
  }
  const suffixLower = suffix.toLowerCase();

  let salt = keccak256(toHex(crypto.randomBytes(32)));
  let iterations = 0;

  while (true) {
    const addr = predictTokenAddress(salt, tokenImpl, portal);
    if (addr.toLowerCase().endsWith(suffixLower)) {
      return { salt, address: addr, iterations };
    }
    salt = keccak256(salt);
    iterations++;
    if (iterations % 100000 === 0) {
      process.stdout.write(`\r已尝试 ${iterations} 次...`);
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const suffix = (args[0] || "7777").toLowerCase();
  if (!/^[0-9a-f]{4}$/.test(suffix)) {
    console.error("用法: node find-vanity-salt.js [suffix]");
    console.error("suffix: 4 位十六进制，税收代币用 7777，标准代币用 8888。默认 7777");
    process.exit(1);
  }

  console.log("正在计算 salt（后缀 " + suffix + "），请稍候…");
  const { salt, address, iterations } = findVanitySalt(suffix);
  console.log("\n结果:");
  console.log("  salt (bytes32):", salt);
  console.log("  预测代币地址:  ", address);
  console.log("  迭代次数:      ", iterations);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
