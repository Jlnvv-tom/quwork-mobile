# QuWork 同步门禁

> 本文件是 `quwork` 产品分支同步源仓库时的强制门禁。它保护 QuWork 产品化改造，同时允许安全吸收上游通用能力。

## 1. 分支与同步顺序

仓库关系：

- `upstream`：源仓库 `ccch1mneyyy/dsh-go`。
- `origin`：QuWork fork。
- `main`：只承载已经完成门禁审查的同步基线。
- `quwork`：QuWork 产品化开发分支。

每次同步必须按以下顺序进行：

1. 开工前检查工作区；用户或其他任务的未提交改动不得覆盖、重置或丢弃。
2. `git fetch upstream main`，查看上游提交和文件变更。
3. 将 `upstream/main` 同步到本仓库 `main`，优先使用 fast-forward；不能快进时先人工审查差异再合并。
4. 从最新本仓库 `main` 将通用能力合入 `quwork`。
5. 在 `quwork` 上重新应用并验证 QuWork 产品保护项。
6. 只暂存明确路径；不使用 `git add .` 或 `git add -A`；未经明确要求不 commit、push 或创建 PR。

`main` 不是 QuWork 功能开发分支。任何“先把源仓库 main 合入本仓库 main，再把功能更新到 quwork”的操作，都必须保留本文件规定的产品保护项。

## 2. 可以同步的能力

以下内容默认属于上游通用能力，可以同步，但仍需检查调用方、协议和测试：

- `packages/dsh_client/`、`packages/dsh_remote/` 的协议兼容性修复和通用能力。
- `runtime/`、`runtime/bridge/` 的引擎、桥接和补丁能力；补丁必须同步 `pins.json` 的 `targetSets`。
- 不包含品牌、账号和服务地址的通用 Flutter UI、状态管理、可访问性和性能修复。
- 通用测试、构建脚本和 CI 检查，但不能改变 QuWork 的构建参数和发布源。
- 安全修复、崩溃修复、协议兼容修复，以及不改变 QuWork 产品契约的文档改进。

同步后必须验证：QuWork 登录仍是唯一登录入口；聊天请求仍使用 QuWork provider；模型用量仍由 QuWork 服务端统计。

## 3. 必须保留的 QuWork 产品能力

下列内容属于产品保护区，禁止被上游自动覆盖。发生冲突时必须人工处理并保留 QuWork 行为：

### 品牌与资源

- 产品名称为 `QuWork`，不得恢复为 `DSH Go` 或 `DeepSeek`。
- QuWork 图标输入为 `/Users/wujihuan/work/rrzu/quwork-dsh-mobile/assets/mobile-push/icon-512.png`。
- Android、iOS、鸿蒙的展示名称、启动图标、应用内品牌文案和更新页品牌必须保持 QuWork。

### 服务配置

- 正式账号服务：`https://llm.rrzu.com/`。
- 开发账号服务：`https://dev-llm.rrzuji.com/`。
- 正式模型服务：`https://llm.rrzu.com/v1`。
- 开发模型服务：`https://dev-llm.rrzuji.com/v1`。
- 本机配置文件：`tooling/quwork.env`；示例文件为 `tooling/quwork.env.example`。
- `tooling/quwork.env`、token、验证码、Cookie、JWT、`llm_token` 和登录态不得提交 Git。

### 账号与模型路由

- 产品只保留 QuWork 账号体系；用户不登录 DeepSeek 官方账号。
- 用户不填写 DeepSeek 官方 API Key。
- 用户登录 QuWork 后直接读取 QuWork 可用模型并进入对话。
- 聊天 provider 必须为 `quwork`，凭据引用为 `QUWORK_LLM_TOKEN`。
- 模型请求必须通过 QuWork OpenAI-compatible `/v1/chat/completions` 服务，模型消耗、额度和用量由 QuWork 服务端统计。
- 设置页、账号页、模型页、首次引导、模型失败提示和远程配对入口不得重新暴露 DeepSeek 账号、DeepSeek API Key、ChatGPT 或 Claude 登录入口。
- 上游引擎可以保留通用 provider 实现，但 QuWork 产品 UI 不得将其作为账号体系或默认模型渠道暴露。

## 4. 冲突处理表

| 文件或目录 | 上游能力 | QuWork 保护规则 | 处理方式 |
|---|---|---|---|
| `app/lib/state/quwork_auth_state.dart` | 通用状态管理 | 保留 QuWork token、刷新和安全存储 | 手工合并 |
| `app/lib/state/quwork_models_state.dart` | 模型目录能力 | 只同步 QuWork provider，并强制默认路由 | 手工合并 |
| `packages/quwork_api/` | QuWork API 客户端 | 保留真实 dev/prod 地址和响应解析 | 手工合并 |
| `app/lib/ui/auth/` | 登录界面 | 只保留 QuWork 登录 | 手工合并 |
| `app/lib/ui/settings/`、`app/lib/ui/providers/` | 设置和 provider UI | 账号、用量和模型入口统一指向 QuWork | 手工合并 |
| `tooling/quwork*`、`tooling/quwork.env.example` | 构建与同步 | 保留 QuWork 配置和门禁检查 | 手工合并 |
| 图标、名称、包名、更新源 | 上游品牌 | QuWork 品牌不可覆盖 | 禁止直接同步 |
| `packages/dsh_client/`、`runtime/` | 通用引擎能力 | 保持协议兼容，不能替换 QuWork 路由 | 可同步后验证 |

## 5. 每次开发的变更标记

每个任务、提交或 PR 描述必须把改动分为三类：

1. **上游可同步能力**：未来可以从 `upstream/main` 重新吸收的通用代码。
2. **QuWork 产品功能**：账号、品牌、服务地址、模型路由、用量展示和产品文案。
3. **冲突保护代码**：为防止上游覆盖 QuWork 行为而存在的适配层、门禁或测试。

如果一个文件同时包含三类改动，必须在描述中列出具体函数、类或配置键，不能只写“同步上游”。

## 6. 合并前检查清单

- [ ] `upstream/main` 已检查，当前分支基于最新本仓库 `main`。
- [ ] QuWork 名称和图标没有被覆盖。
- [ ] `tooling/quwork.env` 仍被 `.gitignore` 忽略且未进入暂存区。
- [ ] 账号入口只跳转 QuWork 登录。
- [ ] 未新增 DeepSeek 官方账号/API Key/ChatGPT/Claude 产品入口。
- [ ] 默认模型 provider 为 `quwork`，凭据引用为 `QUWORK_LLM_TOKEN`。
- [ ] 真实 dev API 登录、模型列表和模型请求已验证；没有用 mock 代替真实接口验收。
- [ ] 运行受影响的 Dart、Flutter、引擎和 l10n 检查。
- [ ] 报告中写明未能完成的真机、真实账号或验证码验证项。

