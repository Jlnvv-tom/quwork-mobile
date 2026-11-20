# QuWork Mobile 开发说明

[English](README.quwork.en.md)

这份文档只描述 QuWork 手机端的本地开发、模拟器调试、One-API 环境切换和 APK 打包。仓库通用贡献规则仍以 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [AGENTS.md](AGENTS.md) 为准。

## 开发环境

| 工具 | 要求 |
|---|---|
| macOS | 已安装 Android Studio 和 Android SDK |
| Flutter | 仓库使用的 Flutter 3.47 / Dart 3.13 工具链 |
| Java | JDK 17 |
| Android | API 35 模拟器或 Android 8（API 26）以上真机 |
| Node.js | 只用于 `npm run` 脚本，不参与 App 编译 |
| Python 3 | l10n 检查和 APK 构建号脚本 |

如果工具不在 PATH，把本机路径写入未提交的 `tooling/env.sh`。该文件只放本机路径，不要提交账号、Token 或证书。

服务地址放在未提交的 `tooling/quwork.env`，脚本会自动加载；该文件已加入 `.gitignore`。首次使用可从 `tooling/quwork.env.example` 复制：

```bash
cp tooling/quwork.env.example tooling/quwork.env
```

## 一条命令做一个动作

所有命令从仓库根目录运行：

| 动作 | 命令 |
|---|---|
| 启动或复用 Android 模拟器 | `npm run quwork:emu:start` |
| 启动本地 Mock 并安装、启动 App | `npm run quwork:emu` |
| 启动开发服版本 | `npm run quwork:dev`（地址读取 `tooling/quwork.env`） |
| 启动正式服版本 | `npm run quwork:prod` |
| 只构建 Mock Debug APK | `npm run quwork:apk` |
| 构建正式服 Release APK | `npm run quwork:apk:release` |
| 查看模拟器实时日志 | `npm run quwork:logs` |
| 运行 Flutter 静态分析 | `npm run quwork:analyze` |
| 运行 Flutter 测试 | `npm run quwork:test` |
| 单独启动 Mock API | `npm run quwork:mock` |
| 查看与源项目的差距 | `npm run quwork:sync -- --check` |
| 同步源项目并合入当前分支 | `npm run quwork:sync` |

常用设备变量：

```bash
QUWORK_ANDROID_AVD=pixel_api35 npm run quwork:emu:start
QUWORK_ANDROID_DEVICE=emulator-5554 npm run quwork:emu
```

如果同时连接多个设备，设置 `QUWORK_ANDROID_DEVICE` 指定设备。模拟器启动日志写入 `/tmp/quwork-android-emulator.log`，Mock 服务日志写入 `/tmp/quwork-mock-server.log`。

## 同步源项目

本仓库是 `ccch1mneyyy/dsh-go` 的 fork：`origin` 指向自己的 `quwork-mobile`，源项目用 `upstream` 远端。`tooling/quwork-sync.sh` 拉取两边，把本地 `main` 快进到 `upstream/main`，再把 `upstream/main` 合入当前分支（默认 `quwork`）；只合并不改写历史。

```bash
npm run quwork:sync -- --check   # 只拉取并报告落后/领先多少，不改分支
npm run quwork:sync              # 更新 main 并合入当前分支
npm run quwork:sync -- --push    # 同步后推送到 origin
```

工作区有未提交改动时脚本直接停住，不 stash、不 reset、不覆盖；合并冲突时停在冲突状态，解决后 `git add` + `git commit`，或 `git merge --abort` 放弃。同步完按改动面验证：`l10n_merge.py`、`guide_sync.py`、引擎补丁的 `pins.json`，以及 Dart/Swift 部分的分析和测试。

## One-API 环境

One-API 账号控制面和模型接口分开配置：

- 账号接口：`QUWORK_API_BASE_URL`，例如 `/api/user/login`、`/api/user/self`、`/api/sendVerifyCode`、`/api/token/`。
- OpenAI 兼容模型接口：`QUWORK_LLM_BASE_URL`，例如 `/v1/models`、`/v1/chat/completions`。

### 正式服

仓库当前确认的正式服是：

```text
账号 API： https://llm.rrzu.com
模型 API： https://llm.rrzu.com/v1
```

`npm run quwork:prod` 使用以上默认值，也可以显式覆盖：

```bash
QUWORK_PROD_API_BASE_URL=https://llm.rrzu.com \
QUWORK_PROD_LLM_BASE_URL=https://llm.rrzu.com/v1 \
npm run quwork:prod
```

正式服调试必须使用真实账号和服务端允许的测试数据。不要在日志、截图、Issue 或提交中暴露 JWT、`llm_token`、验证码、Cookie 或完整手机号。

### 开发服

开发服和正式服地址统一配置在本地 `tooling/quwork.env`，不提交到 Git。当前配置为：

```bash
QUWORK_DEV_API_BASE_URL=https://dev-llm.rrzuji.com
QUWORK_DEV_LLM_BASE_URL=https://dev-llm.rrzuji.com/v1
```

如果开发服的模型接口不是账号接口的 `/v1`，修改 `QUWORK_DEV_LLM_BASE_URL`。开发服必须使用测试账号；开发服和正式服的登录态、模型权限及微信回调配置可能不同。

### 本地 Mock

模拟器访问宿主机不能使用 `127.0.0.1`，脚本自动使用 Android 保留地址 `10.0.2.2`：

```text
宿主 Mock： http://127.0.0.1:8787
模拟器 API： http://10.0.2.2:8787
模拟器模型： http://10.0.2.2:8787/v1
```

测试账号：手机号 `13800138000`，验证码 `123456`。Mock 不访问真实 One-API，只返回固定的模拟用户、模型和聊天结果。

## 模拟器启动和登录调试

1. `npm run quwork:emu:start`：启动第一个 AVD，或复用已在线设备。
2. `npm run quwork:emu`：启动 Mock、构建 Debug APK、安装并打开 App。
3. 在登录页输入 `13800138000`，点击“获取验证码”，再输入 `123456` 登录。
4. `npm run quwork:logs`：另开一个终端查看 Flutter 和 QuWork 实时日志。

清理模拟器中的登录态和引导数据：

```bash
adb -s "${QUWORK_ANDROID_DEVICE:-emulator-5554}" shell pm clear io.github.ccch1mneyyy.dsh_app
```

这是仅针对模拟器的可恢复调试操作，会清除该 App 的本地数据。

## 实时日志

推荐另开终端执行：

```bash
npm run quwork:logs
```

它只显示 Flutter 和 `io.github.ccch1mneyyy.dsh_app` 的日志，停止时按 `Ctrl-C`。需要完整 Android 系统日志时使用：

```bash
adb -s "${QUWORK_ANDROID_DEVICE:-emulator-5554}" logcat
```

日志中不应出现完整 token、Cookie、验证码或 QR secret。排查网络时优先看 HTTP 状态码和稳定错误码。

## APK 打包

### Debug APK

```bash
npm run quwork:apk
```

产物：`app/build/app/outputs/flutter-apk/app-arm64-debug.apk`。该包默认连接本地 Mock，适合模拟器和开发机验证。

### 正式服 Release APK

```bash
npm run quwork:apk:release
```

产物：`app/build/app/outputs/flutter-apk/app-arm64-release.apk`。Release 构建仍需要仓库规定的运行时资源和签名配置；没有 `app/android/key.properties` 时使用本地回退签名，不能当作发布包。想省掉本机构建时用 `.github/workflows/release-apk.yml`（推 `v*` tag 或手动触发），它用仓库 secrets 里的正式密钥出包并校验签名，见 [docs/release.md](docs/release.md) 的「流水线出包」。

### 指定版本和 ABI

需要发布流程或 x64 模拟器时，使用现有构建脚本：

```bash
tooling/build-apk.sh --release -f arm64 --build-name 1.1.0
tooling/build-apk.sh --debug -f x64
```

构建前后按 [CONTRIBUTING.md](CONTRIBUTING.md) 选择对应的分析、测试和运行时检查；APK 构建通过不代表真实账号、真机权限或公网 Gateway 已验证。

## 接口范围

当前 App 使用的 One-API 账号接口包括：

| 能力 | 方法和路径 |
|---|---|
| 手机发码 | `POST /api/sendVerifyCode` |
| 手机登录 | `POST /api/user/login` |
| 当前用户 | `GET /api/user/self` |
| 模型 API-Key | `GET/POST /api/token/` |
| 微信登录 URL | `GET /api/oauth/wechat/url` |
| 微信回调 | `GET /api/oauth/wechat` |
| 绑定微信 | `POST /api/user/wechat/bind` |
| 退出登录 | `GET /api/user/logout` |

模型请求使用 OpenAI 兼容接口 `/v1/models` 和 `/v1/chat/completions`。公网 Gateway 的配对、设备和短期票据属于独立控制面，不能把 One-API JWT 直接当成长期远控连接密钥。

## 故障排查

- `adb` 无法启动：确认 Android SDK 的 `platform-tools/adb` 可执行，并检查是否有其他 ADB 服务占用 5037 端口。
- 模拟器启动超时：查看 `/tmp/quwork-android-emulator.log`，确认磁盘空间和 AVD 名称。
- App 仍显示旧页面：执行上面的 `pm clear`，再运行 `npm run quwork:emu`。
- 登录页请求失败：先确认 `npm run quwork:mock` 或 `npm run quwork:emu` 的 Mock 日志，再确认模拟器使用 `10.0.2.2`，不要填 `127.0.0.1`。
- 开发服启动拒绝：确认设置了 `QUWORK_DEV_API_BASE_URL`，并且开发服允许模拟器来源和测试账号。
- 登录成功后，App 使用 QuWork 账号令牌读取或创建该账号的模型 API-Key，再请求 `QUWORK_DEV_LLM_BASE_URL/models` 和 `QUWORK_LLM_BASE_URL/chat/completions`；不会请求 `api.deepseek.com`。
