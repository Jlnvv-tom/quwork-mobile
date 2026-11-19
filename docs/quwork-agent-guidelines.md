# QuWork Agent 开发规范

本规范适用于 Codex、Agent 和人工开发者。目标是让源仓库同步、QuWork 产品化和真实接口验证可以长期并行。

## 开工前

1. 先阅读 `AGENTS.md`、`CONTRIBUTING.md`、`docs/architecture.md` 和 `docs/quwork-sync-gate.md`。
2. 检查 `git status`，不得覆盖未提交的用户改动。
3. `git fetch origin main`；涉及源仓库同步时再 `git fetch upstream main`。
4. 记录本任务涉及的“上游可同步能力 / QuWork 产品功能 / 冲突保护代码”。

## 账号和模型硬规则

- 只实现 QuWork 账号登录；不得新增 DeepSeek 官方登录或 API Key 输入。
- 登录成功后由 QuWork API 返回的模型凭据配置 `quwork` provider。
- 模型列表来自 QuWork 账号的 entitlement 接口；不得用静态假数据作为生产模型列表。
- 默认模型必须指向 `quwork`；切换模型不能落回 DeepSeek 或其他外部账号 provider。
- 发送模型请求必须经过 QuWork `/v1` 服务，使用 `QUWORK_LLM_TOKEN`；不要在 Flutter 普通设置、日志、诊断包或测试输出中回显 token。
- 页面不能声称有 QuWork 余额或用量，除非服务端提供并已验证对应接口；没有接口时只显示“模型用量由 QuWork 账号统一统计”。

## 真实接口测试

- 开发测试使用 `https://dev-llm.rrzuji.com/`，正式测试使用 `https://llm.rrzu.com/`。
- 登录、模型列表和聊天请求必须使用真实 dev API；mock 只允许用于纯解析单元测试，不能作为登录和聊天验收。
- 不在命令、日志、截图、提交或报告中输出完整手机号、验证码、Cookie、JWT、API key 或 `llm_token`。
- 模拟器只能证明流程可运行，不能替代 Android 真机能力验证；报告中必须区分模拟器和真机结果。
- 真实账号或验证码缺失时明确标记“未验证”，不得把 HTTP 401 或 mock 成功当作登录成功。

## 代码组织

- QuWork API 协议放在 `packages/quwork_api/`；账号状态放在 `app/lib/state/quwork_auth_state.dart`；模型同步放在 `app/lib/state/quwork_models_state.dart`。
- 上游通用引擎能力不要直接写入 QuWork API 客户端；QuWork 适配应通过独立 provider、配置或适配层完成。
- UI 账号入口统一跳转 `QuWorkLoginPage`。旧的 `AccountPage` 入口只能作为兼容别名，不能恢复 DeepSeek UI。
- 只改 l10n 输入 `app/lib/l10n/parts/*.arb`，中英文同步后运行 `python3 app/tool/l10n_merge.py`。
- 不手改生成物、`.dart_tool/`、`app/build/` 或运行时产物。

## 交付前

- 说明改了哪些文件、每个文件属于哪一类变更。
- 运行与改动范围匹配的 `dart analyze`、`flutter analyze`、单元测试和 l10n 检查。
- 真实 dev API 测试记录 endpoint、状态和结果，但不记录敏感凭据。
- 检查 `git diff --check`、`.gitignore` 和暂存路径。
- 未经用户明确要求不 commit、push、建分支或创建 PR。

