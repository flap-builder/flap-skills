---
name: flapskill
displayName: 蝴蝶技能
version: 1.6.0
description: 蝴蝶技能（FlapSkill）支持创建 V5 代币（0 税或税收代币；税收可分配营销/持币分红/回购销毁/LP回流）、用 USDT 买入/卖出代币。用户说「蝴蝶技能」即触发。创建时：**0 税**只需「蝴蝶技能 创建代币 名称：… 符号：…」（可选官网、简介、代币图片），不需说税点、税收地址；**有税**需「税点：…% 税收地址：0x…」并可选 营销税点/持币分红税点/回购销毁税点/LP回流税点（四者之和100%）、官网、简介、图片；启用持币分红时可选「最低持币数量：…」。salt 按类型选尾号：0 税用 8888，有税用 7777（四档分配时 7777 v2）。上传 meta 时须把用户提供的官网、简介传入 upload 脚本，meta 和 salt 由 Agent 跑脚本填入。买入：先 approve_token_spending 再 write_contract buyTokens。卖出：按数量 sellTokens；按比例 sellTokensByPercent(token, percentBps)，10000=100%。在用户说蝴蝶技能创建/买入/卖出或调用 createToken/buyTokens/sellTokens/sellTokensByPercent 时使用。
---

# 蝴蝶技能：创建代币、买入/卖出代币（USDT）

用户说「**蝴蝶技能**」即触发本技能。通过 FlapSkill 合约可**创建** V5 代币（0 税或税收；税收时代币可分配营销/持币分红/回购销毁/LP回流 四档税点，受益人 feeTo），或用 **USDT** 买入/卖出指定代币；买卖经 Portal 或 PancakeSwap 兑换，代币/USDT 转给调用者。

**USDT 合约地址（BSC）**：`0x55d398326f99059fF775485246999027B3197955`。

**前置条件：** 用户需已配置 [BNB Chain MCP](https://docs.bnbchain.org/showcase/mcp/skills/)（如已安装 `bnbchain-mcp-skill`），且 MCP 的 `env` 中已设置 `PRIVATE_KEY`，否则无法发送交易。

---

## 1. 合约接口

**合约地址**：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28`。

### 创建代币 createToken

- **方法**：`createToken(string _name, string _symbol, string _meta, address _feeTo, bytes32 _salt, uint16 _taxRate, uint16 _mktBps, uint16 _dividendBps, uint16 _deflationBps, uint16 _lpBps, uint256 _minimumShareBalance) external returns (address token)`
- **含义**：经 Portal 创建 V5 代币。**0 税代币**：`_taxRate=0`，不校验四档分配，合约使用 V3_MIGRATOR；**salt 须用尾号 8888**（脚本：`node scripts/find-vanity-salt.js 8888`）。**税收代币**：`_taxRate` 1–1000（如 300=3%），`_mktBps`（营销）、`_dividendBps`（持币分红）、`_deflationBps`（回购销毁）、`_lpBps`（LP 回流）四者之和须为 10000；**salt 须用尾号 7777**（全营销用 `find-vanity-salt.js 7777`，四档分配用 `find-vanity-salt.js 7777 v2`）。若 `_dividendBps > 0`，`_minimumShareBalance` 须 ≥ 10_000 ether；用户未说时 Agent 默认 10_000 ether。详见 [Flap Portal](https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal) 与 [部署地址](https://docs.flap.sh/flap/developers/token-launcher-developers/deployed-contract-addresses)（standard:8888，Tax:7777）。无需 approve。
- **约束**：`_salt` 为 bytes32（0x+64 位十六进制），每次创建用不同 salt；**必须按税点选对尾号（0 税→8888，有税→7777）及对应脚本 impl（7777 四档时加 v2）**。
- **何时用**：**0 税**：用户说「蝴蝶技能 创建代币 名称：… 符号：…」即可，可选官网、简介、代币图片；**不需说税点、税收地址**，Agent 自动 taxRate=0、feeTo=调用者地址、salt 用 8888。**有税**：用户说「蝴蝶技能 创建代币 名称：… 符号：…，税点：…% 税收地址：0x…」并可选四档分配、官网、简介、图片；有税且未指定四档时默认全部归营销；启用持币分红时用户可说「最低持币数量：1 万」等，不说则默认 10_000 ether。**_meta、_salt 由 Agent 跑脚本填入；官网、简介须传入 upload 脚本。**

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
- **Salt 尾号与脚本**（见 [Flap 文档](https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal#3-find-the-salt-vanity-suffix)、[部署地址](https://docs.flap.sh/flap/developers/token-launcher-developers/deployed-contract-addresses)）：**0 税**（税点 0%）→ 地址尾号 **8888**，执行 `node scripts/find-vanity-salt.js 8888`；**有税**→ 地址尾号 **7777**，全营销执行 `node scripts/find-vanity-salt.js 7777`，四档分配执行 `node scripts/find-vanity-salt.js 7777 v2`。
- 流程：**0 税**：用户只说「蝴蝶技能 创建代币 名称：… 符号：…」（可选官网、简介、图片）。Agent 在技能目录下：① 上传 meta（有图/官网/简介时跑 upload 脚本，否则可用占位 CID 或简单 meta）；② 执行 `node scripts/find-vanity-salt.js 8888` 得 _salt；③ _feeTo = 调用者地址（发送交易的钱包），_taxRate=0，四档与 minimumShareBalance 均 0；④ `write_contract` createToken(…)。**有税**：用户说「名称：… 符号：…，税点：…% 税收地址：0x…」并可选四档、官网、简介、图片。Agent：① 跑 upload 脚本得 _meta；② 按税点跑 salt（全营销 7777，四档 7777 v2）；③ 确定四档与 minimumShareBalance；④ `write_contract` createToken(…)。
- 用户**无需**写 meta、salt；0 税**无需**说税点、税收地址，Agent 用调用者地址作 feeTo。

### 2.2 调用 createToken

无需 approve，直接 **`write_contract`**：

| 参数 | 说明 |
|------|------|
| `contractAddress` | `0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
| `abi` | createToken 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"createToken"` |
| `args` | `[_name, _symbol, _meta, _feeTo, _salt, _taxRate, _mktBps, _dividendBps, _deflationBps, _lpBps, _minimumShareBalance]`。**0 税**：_feeTo=调用者地址，_taxRate=0，四档与 minimumShareBalance 填 0，_salt 用 8888。**有税**：_feeTo=用户提供的税收地址，_taxRate 1–1000，四档之和 10000，_salt 用 7777 或 7777 v2。**_meta、_salt 由 Agent 跑脚本填入。** |
| `network` | 可选，默认 `bsc` |

---

## 3. 买入：使用 BNB Chain MCP 调用

### 3.1 先授权 USDT（approve）

| 参数 | 说明 |
|------|------|
| `tokenAddress` | USDT：`0x55d398326f99059fF775485246999027B3197955` |
| `spenderAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
| `amount` | 要支付的 USDT 数量（人类可读如 `"0.01"`） |
| `network` | 可选，默认 `bsc` |

### 3.2 再调用 buyTokens

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
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
| `spenderAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
| `amount` | 要卖出的代币数量（人类可读或最小单位，≥ 本次 `_tokenAmount`） |
| `network` | 可选，默认 `bsc` |

### 4.2 再调用 sellTokens

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
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
| `spenderAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
| `amount` | 建议 ≥ 本次要卖出的数量（可按比例算，或直接填足够大） |
| `network` | 可选，默认 `bsc` |

### 5.3 调用 sellTokensByPercent

| 参数 | 说明 |
|------|------|
| `contractAddress` | FlapSkill：`0x62ed2e3fbfba62bba0d13572d4829d82f4d26d28` |
| `abi` | sellTokensByPercent 的 ABI（见 [references/contract-abi.md](references/contract-abi.md)） |
| `functionName` | `"sellTokensByPercent"` |
| `args` | `[_token, _percentBps]`：代币地址、比例基点（10000=100%，5000=50%，1000=10%） |
| `network` | 可选，默认 `bsc` |

**比例换算**：用户说 50% → `_percentBps` = `"5000"`；10% → `"1000"`；100% → `"10000"`。

---

## 6. 流程简述

- **创建代币**：**0 税**：用户只说「蝴蝶技能 创建代币 名称：… 符号：…」；Agent 用调用者地址作 feeTo，taxRate=0，四档与 minimumShareBalance 填 0，salt 用 8888。**有税**：用户需说税点、税收地址；taxRate 1–1000，四档之和 10000，salt 用 7777 或 7777 v2；启用分红时 minimumShareBalance ≥ 10_000 ether。无需 approve。
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
