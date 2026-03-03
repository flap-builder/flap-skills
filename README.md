# Flap Skills（蝴蝶技能）

基于 [BNB Chain MCP](https://docs.bnbchain.org/showcase/mcp/skills/) 的 AI 技能，让 Agent 能够通过 FlapSkill 合约在 BSC 上**创建代币**、用 **USDT** **买入/卖出**指定代币。

---

## 依赖

本技能依赖 **BNB Chain MCP**。使用前请先完成：

- **连接 BNB Chain MCP**：运行 `npx @bnb-chain/mcp@latest`
- **安装 BNB Chain 官方技能**（可选）：`npx skills add bnb-chain/bnbchain-skills`

详细说明见：[BNB Chain Skills 文档](https://docs.bnbchain.org/showcase/mcp/skills/)

---

## 安装

在当前项目中安装（仅当前项目可用）：

```bash
npx skills add flap-builder/flap-skills
```

全局安装（所有项目可用）：

```bash
npx skills add flap-builder/flap-skills -g
```

---

## 如何使用

### 触发方式

在对话中说「**蝴蝶技能**」即可触发本技能。

### 前置条件

- 已安装并连接 [BNB Chain MCP](https://docs.bnbchain.org/showcase/mcp/skills/)
- 在 MCP 的 `env` 中已配置 `PRIVATE_KEY`，否则无法发送链上交易

### 支持的操作

| 操作 | 说明 |
|------|------|
| **创建代币** | 按「名称：… 符号：…，税点：…% 税收地址：0x…」格式说明，可选「官网：…」「简介：…」并附代币图片；Agent 会跑脚本生成 meta 与 salt 并调用合约 |
| **买入** | 先授权 USDT，再按指定代币与 USDT 数量买入 |
| **卖出（按数量）** | 指定代币地址与卖出数量 |
| **卖出（按比例）** | 指定代币地址与比例（如 50%、100%） |

### 创建代币提示词示例

```
蝴蝶技能 创建代币
名称：My Token
符号：MTK
税点：3%
税收地址：0x...
官网：https://example.com
简介：这是一段代币简介
```

（并附上代币图片，Agent 会调用本技能内的 `scripts/upload-token-meta.js` 等脚本完成 meta 与 salt 的生成。）

### 买入 / 卖出示例

- 「蝴蝶技能 用 10 USDT 买入 0x…」
- 「蝴蝶技能 卖出 100 个 0x…」
- 「蝴蝶技能 卖出 50% 的 0x…」

更多合约接口与 ABI 见仓库内 [SKILL.md](./SKILL.md) 与 [references/contract-abi.md](./references/contract-abi.md)。

---

## 捐款

如本技能对你有帮助，欢迎捐赠：

**捐款地址**：`0x62F5cCb8b1744A427b7511374F4eb33114217199`
