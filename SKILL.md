---
name: flapskill
displayName: 蝴蝶技能
version: 1.5.0
description: 蝴蝶技能（FlapSkill）支持创建代币、用 USDT 买入/卖出代币。用户说「蝴蝶技能」即触发。创建时提示词格式：名称：… 符号：…，税点：…% 税收地址：0x…，可选 官网：… 简介：…（并附代币图片）；上传 meta 时须把用户提供的官网、简介传入 upload 脚本（见 Flap 文档），meta 和 salt 由 Agent 跑脚本填入。买入：先 approve_token_spending 再 write_contract buyTokens。卖出：按数量 sellTokens；按比例 sellTokensByPercent(token, percentBps)，10000=100%。在用户说蝴蝶技能创建/买入/卖出或调用 createToken/buyTokens/sellTokens/sellTokensByPercent 时使用。
---

# 蝴蝶技能：创建代币、买入/卖出代币（USDT）

用户说「**蝴蝶技能**」即触发本技能。通过 FlapSkill 合约可**创建** V2 税收代币（受益人 feeTo），或用 **USDT** 买入/卖出指定代币；买卖经 Portal 兑换，代币/USDT 转给调用者。

**USDT 合约地址（BSC）**：`0x55d398326f99059fF775485246999027B3197955`。

**前置条件：** 用户需已配置 [BNB Chain MCP](https://docs.bnbchain.org/showcase/mcp/skills/)（如已安装 `bnbchain-mcp-skill`），且 MCP 的 `env` 中已设置 `PRIVATE_KEY`，否则无法发送交易。

---

## 1. 合约接口

**合约地址**：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7`。

### 创建代币 createToken

- **方法**：`createToken(string _name, string _symbol, string _meta, address _feeTo, bytes32 _salt, uint16 _taxRate) external returns (address token)`
- **含义**：经 Portal 创建 V2 税收代币，受益人由 `_feeTo` 指定；`_taxRate` 为税率基点（100=1%，300=3%），范围 1–1000。无需 approve。
- **约束**：`_salt` 为 bytes32（0x + 64 位十六进制），每次创建用不同 salt。
- **何时用**：用户说「蝴蝶技能创建代币 名称：… 符号：…，税点：…% 税收地址：0x…」并可选「官网：…」「简介：…」、附代币图片时使用。**_meta、_salt 由 Agent 跑脚本得到并填入；若用户提供了官网或简介，上传 meta 时须传入脚本（官网→website，简介→description）。**

### 买入 buyTokens

- **方法**：`buyTokens(address _token, uint256 _usdtAmount) external`
- **含义**：从调用者转入 `_usdtAmount`（18 位小数）的 USDT，向 Portal 兑换 `_token` 代币，代币转给调用者。
- **约束**：调用前须对 FlapSkill 合约 approve 至少 `_usdtAmount` 的 USDT。

### 卖出（按数量）sellTokens

- **方法**：`sellTokens(address _token, uint256 _tokenAmount) external`
- **含义**：从调用者转入指定数量 `_tokenAmount` 的代币，向 Portal 兑换为 USDT，USDT 转给调用者。无滑点保护。
- **约束**：调用前须对 FlapSkill 合约 approve 至少 `_tokenAmount` 的该代币。`_tokenAmount` 为该代币最小单位。
- **何时用**：用户说「蝴蝶技能卖出 X 个 0x…」「卖出100个的0x…」等**具体数量**时，用本方法。

### 卖出（按仓位比例）sellTokensByPercent

- **方法**：`sellTokensByPercent(address _token, uint256 _percentBps) external`
- **含义**：按调用者当前该代币持仓的 **比例** 卖出。合约内读取 `balanceOf(msg.sender)`，卖出数量 = 余额 × `_percentBps` / 10000。无滑点保护。
- **约束**：调用前须对 FlapSkill 合约 approve 至少「该比例对应的数量」（建议直接 approve 全部仓位或足够大的数）。
- **何时用**：用户说「蝴蝶技能卖出50%的0x…」「卖出一半 0x…」等**比例**时，用本方法。`_percentBps` 为基点：10000=100%，5000=50%，1000=10%。

---

## 2. 创建代币：使用 BNB Chain MCP 调用

### 2.1 _meta 与 _salt 由 Agent 直接填写（脚本已打包在本技能内）

- **\_meta** 和 **\_salt** 不由用户提供，**由 Agent 在技能目录下执行本技能自带的脚本得到并直接填入** createToken 的 args。
- **脚本位置**：本技能目录下的 `scripts/`（`upload-token-meta.js`、`find-vanity-salt.js`）。安装后技能目录通常为 `.agents/skills/flap-skills`（项目）或 `~/.cursor/skills/flap-skills`（全局），本仓库内为 `skills/flap-skills`。**Agent 须先 cd 到该技能目录**，若未安装依赖则先执行 `npm install`，再执行下面两步。
- 上传 meta 时须带上**官网**和**简介**（见 [Flap 文档](https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal)）：用户创建代币时可选提供「官网：…」「简介：…」，Agent 传入脚本，格式为 `node scripts/upload-token-meta.js <图片路径> "<简介>" "<官网>" [twitter] [telegram]`，脚本将简介写入 meta.description、官网写入 meta.website。
- 流程：用户按「名称：… 符号：…，税点：…% 税收地址：0x…」并可选「官网：…」「简介：…」、附代币图片后，Agent 在**技能目录**下依次执行：
  1. `node scripts/upload-token-meta.js <图片路径> "<简介>" "<官网>" …`，将输出 CID 作为 _meta；
  2. `node scripts/find-vanity-salt.js 7777`，将输出的 `salt (bytes32)` 作为 _salt；
  3. `write_contract` createToken，args 为 `[_name, _symbol, _meta, _feeTo, _salt, _taxRate]`。
- 用户**无需**在提示词里写 meta、salt；若用户提供了官网或简介，Agent 必须传入 upload 脚本。

### 2.2 调用 createToken

无需 approve，直接 **`write_contract`**：

| 参数 | 说明 |
|------|------|
| `contractAddress` | `0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `abi` | createToken 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"createToken"` |
| `args` | `[_name, _symbol, _meta, _feeTo, _salt, _taxRate]`：名称、符号、_meta（Agent 跑 upload 脚本得到）、受益人地址、_salt（Agent 跑 find-salt 得到）、税率基点（如 300=3%）。**_meta 与 _salt 由 Agent 直接填写，用户不填。** |
| `network` | 可选，默认 `bsc` |

---

## 3. 买入：使用 BNB Chain MCP 调用

### 3.1 先授权 USDT（approve）

| 参数 | 说明 |
|------|------|
| `tokenAddress` | USDT：`0x55d398326f99059fF775485246999027B3197955` |
| `spenderAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `amount` | 要支付的 USDT 数量（人类可读如 `"0.01"`） |
| `network` | 可选，默认 `bsc` |

### 3.2 再调用 buyTokens

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `abi` | buyTokens 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"buyTokens"` |
| `args` | `[_token, _usdtAmount]`：目标代币地址、USDT 最小单位（18 位小数，如 0.01 USDT = `"10000000000000000"`） |
| `network` | 可选，默认 `bsc` |

---

## 4. 卖出（按数量）：使用 BNB Chain MCP 调用

用户说**具体数量**（如「蝴蝶技能卖出100个的0x…」）时用此流程。

### 4.1 先授权要卖出的代币（approve）

| 参数 | 说明 |
|------|------|
| `tokenAddress` | 要卖出的代币合约地址 |
| `spenderAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `amount` | 要卖出的代币数量（人类可读或最小单位，≥ 本次 `_tokenAmount`） |
| `network` | 可选，默认 `bsc` |

### 4.2 再调用 sellTokens

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `abi` | sellTokens 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"sellTokens"` |
| `args` | `[_token, _tokenAmount]`：代币地址、卖出数量（该代币最小单位） |
| `network` | 可选，默认 `bsc` |

**注意**：`_tokenAmount` 须按该代币 decimals 换算为最小单位（如 18 位小数，1 个 = `"1000000000000000000"`）。

---

## 5. 卖出（按仓位比例）：使用 BNB Chain MCP 调用

用户说**比例**（如「蝴蝶技能卖出50%的0x…」「卖出一半0x…」）时用此流程。

### 5.1 可选：查询用户该代币余额

用 **`get_erc20_balance`**（tokenAddress=代币，address=用户）得到余额，便于确认或向用户展示。合约内部会再次按当前区块状态计算比例，无需用此结果参与合约参数。

### 5.2 授权代币（approve）

建议对 FlapSkill approve **至少对应比例的数量**，或直接 approve 全部仓位（如 `amount` 用很大或「max」）。例如卖 50% 时，approve 至少当前余额的 50% 或全部。

| 参数 | 说明 |
|------|------|
| `tokenAddress` | 要卖出的代币合约地址 |
| `spenderAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `amount` | 建议 ≥ 本次要卖出的数量（可按比例算，或直接填足够大） |
| `network` | 可选，默认 `bsc` |

### 5.3 调用 sellTokensByPercent

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0xa1b611113e6bc59fb78a26d08a89c3d80bc498a7` |
| `abi` | sellTokensByPercent 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"sellTokensByPercent"` |
| `args` | `[_token, _percentBps]`：代币地址、比例基点（10000=100%，5000=50%，1000=10%） |
| `network` | 可选，默认 `bsc` |

**比例换算**：用户说 50% → `_percentBps` = `"5000"`；10% → `"1000"`；100% → `"10000"`。

---

## 6. 流程简述

- **创建代币**：直接 `write_contract` createToken(`name`, `symbol`, `meta`, `feeTo`, `salt`, `taxRate`)，无需 approve。taxRate 为基点（300=3%）。
- **买入**：approve USDT → `write_contract` buyTokens(`token`, `usdtAmount`)。
- **卖出（按数量）**：用户说具体数量 → approve 代币 → `write_contract` sellTokens。
- **卖出（按比例）**：用户说比例 → 可选 get_erc20_balance → approve 代币 → `write_contract` sellTokensByPercent。
- 发送前向用户确认合约地址、代币/参数和金额/比例。

---

## 7. 参考

- **createToken / buyTokens / sellTokens / sellTokensByPercent ABI**：[references/contract-abi.md](references/contract-abi.md)
- **获取 _meta / _salt**：脚本已打包在本技能 `scripts/` 下（upload-token-meta.js、find-vanity-salt.js），在技能目录执行并先 `npm install`。另本仓库根目录 [scripts/README.md](../../scripts/README.md) 有相同脚本与说明。
- **BNB Chain MCP / Skills**：[BNB Chain Skills](https://docs.bnbchain.org/showcase/mcp/skills/)
- **本仓库合约**：`skill.sol` 中 `FlapSkill.createToken`、`buyTokens`、`sellTokens`、`sellTokensByPercent`
