# QuWork App 独立更新服务与 Android 迁移开发计划

> 状态：待确认。本文只定义 QuWork 更新资产服务、客户端更新源、品牌配置、Android 包名与签名迁移方案，当前不开始代码改造。
>
> 盘点日期：2026-11-19
>
> 适用范围：Android 首期；鸿蒙和 iOS 的更新渠道另行适配。

## 1. 目标与非目标

目标是把当前 DSH Go 的 App 内更新体系迁移为 QuWork 自有、可独立运维的更新体系，同时保留已经稳定的下载、断点续传、校验和 Android 安装流程。

本计划覆盖：

1. 建立 QuWork 独立的更新清单、APK、校验和和可选增量包服务。
2. 移除更新检查对 DSH Go GitHub 仓库、DSH CDN 和 DSH Beta 通道的依赖。
3. 将更新弹窗、发布页、文件名、导出目录和应用展示名称改为 QuWork。
4. 在开发前确定 Android 是“原地升级”还是“新 App 并行安装”。
5. 固定正式包的 `applicationId`、签名证书和单调递增 `versionCode` 策略。
6. 建立发布、回滚、灰度和真机验收流程。

本计划暂不实现：

- 账号登录后才能更新的权限模型；
- 强制更新、灰度比例和设备分群的客户端行为；
- 鸿蒙 AppGallery 自动更新；
- iOS App Store 更新；
- 更新服务承载聊天、远程主机或模型请求。

更新服务与 QuWork 账号 API、模型 API、远程主机服务保持独立。用户没有登录 QuWork 时，也应能检查和安装公开更新。

## 2. 当前实现基线

当前提醒不是推送通知，而是 App 前台轮询：`HomeShell` 挂载 [update_launch_check.dart](/Users/wujihuan/work/rrzu/quwork-mobile/app/lib/ui/update/update_launch_check.dart)，启动约 6 秒后调用 `autoCheckIfDue()`；成功检查后 24 小时内不再自动检查，失败后 4 小时内重试。设置页可以手动检查、关闭每日检查或跳过某个版本。

状态、缓存和下载安装流程在 [update_state.dart](/Users/wujihuan/work/rrzu/quwork-mobile/app/lib/state/update_state.dart)；更新源在 [update_config.dart](/Users/wujihuan/work/rrzu/quwork-mobile/app/lib/update/update_config.dart)。当前默认源仍是：

```text
Beta 通道（编译进 DSH token 的包）
→ https://dl.dshtui.com/update.json
→ GitHub Release manifest
→ GitHub releases/latest API
```

当前更新资产协议是 schema 1：

```text
update.json
├─ version / tag / title / publishedAt
├─ notes / notesByLocale / page
├─ assets.arm64 / assets.x64
│  └─ name / url / size / sha256
└─ patches.<flavor>[]
   └─ from / fromVersion / name / size / sha256
```

下载器支持 `.part` 文件、HTTP Range 续传、多源回退和 SHA-256 校验；如果当前 APK 的 SHA-256 命中清单中的增量补丁，则先下载 `DSHDLT01`，失败后自动回退完整 APK。安装前会检查 APK 是否可解析、包名是否匹配、签名是否匹配以及 versionCode 是否更高。

当前 Android 身份和品牌仍是 DSH：

- `applicationId`：`io.github.ccch1mneyyy.dsh_app`，见 [app/build.gradle.kts](/Users/wujihuan/work/rrzu/quwork-mobile/app/android/app/build.gradle.kts:51)。
- Android 应用标签：`DSH Go`，见 [AndroidManifest.xml](/Users/wujihuan/work/rrzu/quwork-mobile/app/android/app/src/main/AndroidManifest.xml:53)。
- 更新弹窗标题、发布页回退地址、导出目录和错误文案仍包含 DSH Go，见 [update_sheet.dart](/Users/wujihuan/work/rrzu/quwork-mobile/app/lib/ui/update/update_sheet.dart:139)。
- [quwork-android.sh](/Users/wujihuan/work/rrzu/quwork-mobile/tooling/quwork-android.sh:1) 当前只注入 `QUWORK_API_BASE_URL` 和 `QUWORK_LLM_BASE_URL`，没有注入 QuWork 更新源。

## 3. 必须先作出的产品决策

### 3.1 Android 迁移路径

必须在开始改包名、签名和发布脚本前选择一条路径。

| 路径 | Android 身份 | 用户结果 | 适用情况 |
|---|---|---|---|
| A. 原地升级 | 保留现有 `applicationId` 和正式签名证书；QuWork 的 versionCode 必须高于已发布 DSH 版本 | 用户直接覆盖安装，应用数据和安全存储继续保留 | QuWork 是 DSH Go 的产品迁移或改名 |
| B. 新 App 并行安装 | 使用新的 QuWork `applicationId` 和新签名 | Android 视为新应用，旧 DSH Go 不会被更新器覆盖 | 需要与 DSH 完全隔离、保留旧 App 或不能继续使用旧签名 |

推荐先采用路径 A，除非产品明确要求 DSH Go 与 QuWork 并行存在。路径 A 的硬条件不可绕过：

1. 新 APK 的 `applicationId` 必须和已安装 APK 相同。
2. 新 APK 必须由同一签名证书签发；Android 9+ 可以使用有签名 lineage 的密钥轮换，但 Android 8 兼容性仍需单独验证。
3. 新 APK 的 `versionCode` 必须严格大于已安装版本。
4. 不能把正式签名改成临时 debug 签名，也不能在发布流水线中混用多把证书。

如果选择路径 B，需要另外设计：旧版本数据导出/迁移、旧 App 的停止维护提示、两个应用的深链和文件目录、双应用发布页，以及新应用的首版安装流程。路径 B 不能依赖当前“覆盖安装”逻辑。

### 3.2 更新渠道策略

首期建议固定为：

```text
stable：公开 HTTPS 更新服务，匿名检查
beta：独立的 QuWork Beta 清单和资产目录，可使用独立通道令牌
```

Beta 通道令牌只能作为通道访问控制，不能当作真正的秘密，因为令牌会进入 APK 并可能被提取。QuWork JWT、`llm_token`、远程 Gateway token 和设备配对 secret 不得放入更新清单、二维码或普通偏好。

### 3.3 版本策略

需要确认以下规则并写入发布合同：

- `versionName` 是否沿用当前 SemVer 形式；
- `versionCode` 是否沿用当前构建分钟编码；
- 原地升级时是否继承 DSH 已经发布过的最高 versionCode；
- 是否发布 `arm64` 和 `x64` 两种 APK；
- 首期是否只发布完整 APK，增量补丁延后；
- 是否需要最低版本、强制更新和灰度比例。

首期建议只支持可选更新、完整 APK、稳定渠道和 Beta 渠道。这样可以先验证服务、签名和原地覆盖，不把强制更新策略和增量算法同时引入。

## 4. 独立更新资产服务设计

### 4.1 服务边界

QuWork 更新服务只负责“发布什么版本、在哪里下载、如何校验”，不负责：

- QuWork 登录和 token 刷新；
- 模型列表和 `llm_token`；
- 聊天、文件或远程主机长连接；
- 远程设备配对和授权。

建议采用对象存储 + CDN 的静态资产结构，必要时在边缘层增加 Beta 鉴权和发布统计：

```text
QuWork App
  ├─ GET https://<update-origin>/update.json
  └─ GET https://<update-origin>/download/<version>/<file>

<update-origin>
  ├─ CDN / HTTPS
  └─ immutable object storage
      ├─ update.json              # stable 最新指针
      └─ download/<version>/      # 每个版本不可覆盖
          ├─ quwork-<version>-arm64.apk
          ├─ quwork-<version>-x64.apk
          ├─ *.dshdelta           # 可选
          ├─ SHA256SUMS
          └─ update.json           # 该版本的不可变清单，可选
```

域名先使用占位配置，例如 `update.quwork.example` 或 `download.quwork.example`，正式域名由产品和运维确定。域名确定后必须同时写入客户端构建参数、发布脚本、隐私说明和回滚文档。

### 4.2 必需接口

```http
GET /update.json
GET /download/<version>/<file>
GET /download/<version>/SHA256SUMS
```

接口要求：

| 接口 | 要求 |
|---|---|
| `/update.json` | HTTPS；返回当前稳定渠道清单；短缓存，例如 `public, max-age=300`；不要求登录 |
| APK / 增量包 | 支持 `GET` 和 `Range`；断点续传返回 `206 Partial Content`、正确的 `Content-Range` 和 `Content-Length` |
| `SHA256SUMS` | 使用标准 `sha256sum` 格式；至少覆盖所有 APK 和增量包；可缓存约 1 小时 |
| 版本目录 | 使用不可变路径；同一版本同一文件禁止覆盖；修包必须提升版本号 |
| 错误响应 | 404 表示资产不存在，5xx/超时表示服务暂时不可用；不要返回登录页 HTML 伪装成清单 |

服务端应支持 `HEAD` 或等价的发布校验请求，方便发布脚本验证大小、类型和 Range 行为。APK 返回 `application/vnd.android.package-archive`，清单返回 `application/json`，校验和返回 `text/plain`。

### 4.3 清单兼容策略

首期继续使用 schema 1，保持现有客户端能够解析：

```json
{
  "schema": 1,
  "version": "1.2.0+202611191230",
  "tag": "v1.2.0",
  "title": "QuWork 1.2.0",
  "publishedAt": "2026-11-19T04:30:00Z",
  "notes": "...",
  "notesByLocale": {
    "zh": "...",
    "en": "..."
  },
  "page": "https://<quwork-release-page>/1.2.0",
  "assets": {
    "arm64": {
      "name": "quwork-1.2.0-arm64.apk",
      "url": "https://<update-origin>/download/1.2.0/quwork-1.2.0-arm64.apk",
      "size": 180000000,
      "sha256": "<64 hex characters>"
    }
  }
}
```

manifest 中的 URL 可以使用绝对地址，也可以使用相对 `update.json` 的地址。若 QuWork 完全停用 GitHub 回退，资产文件名可以按 QuWork 命名；如果仍保留 GitHub manifest 解析，则还需要同步修改当前 DSH 文件名正则和仓库地址，避免客户端识别不到 QuWork APK。

### 4.4 稳定版与 Beta 版

稳定版建议公开提供清单和资产，不绑定账号。Beta 可以采用单独目录：

```text
/beta/update.json
/beta/<version>/<file>
```

Beta 服务如需鉴权，应满足：

- 令牌只发送到 Beta 域名和 Beta 路径；
- 令牌不重定向到其他域名；
- 令牌不写入日志、Analytics、错误页面或清单；
- 令牌撤销不会影响 stable；
- stable 清单不回退到 DSH Beta 或 GitHub DSH 版本。

如果 QuWork 暂时没有 Beta 发布需求，首期不要保留旧 DSH Beta 通道，直接关闭客户端 Beta 源，减少错误回退路径。

## 5. 客户端更新源与品牌配置改造

### 5.1 更新源配置

需要调整 [update_config.dart](/Users/wujihuan/work/rrzu/quwork-mobile/app/lib/update/update_config.dart)：

1. 增加 QuWork 更新域名或改为构建期注入的 `QUWORK_UPDATE_FEED`、`QUWORK_UPDATE_MIRROR`、`QUWORK_BETA_*`。
2. stable 默认只包含 QuWork 自有清单和 QuWork 自有下载源。
3. 移除 `ccch1mneyyy/dsh-go`、`dl.dshtui.com`、`go.dshtui.com`、GitHub API 和公共 GitHub 加速镜像的默认回退。
4. 保留“上次成功源优先”的节流逻辑，但优先源只能来自 QuWork 源列表。
5. 更新页回退地址改为 QuWork release page；不能继续使用 GitHub DSH 页面。
6. 更新请求可继续携带匿名 User-Agent 和当前版本/ABI，不应携带账号身份。

只设置 `DSH_UPDATE_FEED` 而保留当前默认镜像并不够：当前代码仍可能继续请求 GitHub DSH 源，导致 QuWork App 显示错误产品的更新。因此必须同时替换源列表或明确关闭 GitHub fallback。

### 5.2 更新模型与产品策略

如果 QuWork 只需要可选更新，`AppUpdateState`、下载器、增量算法和 Android 安装器可以基本复用。

如果需要以下策略，则要另立客户端改造任务：

| 策略 | 需要增加的客户端能力 |
|---|---|
| 最低可用版本 | 解析 `minimumVersion`，在启动入口阻止继续使用或引导更新 |
| 强制更新 | 增加 `mandatory`，不能用“跳过版本”绕过；定义下载失败和无兼容 APK 的恢复路径 |
| 灰度发布 | 解析 `rollout` 或服务端返回分群结果；需要稳定的匿名安装标识和隐私说明 |
| 安全公告 | 解析 `securityNotes`，在更新页和发布记录中显示 |
| 多平台清单 | 增加平台、ABI 和渠道约束，防止 Android 客户端拿到鸿蒙或 iOS 资产 |

这些字段写入 schema 1 后，旧客户端会忽略。强制更新和灰度必须与客户端版本同步发布，不能只改后端清单。

### 5.3 品牌与文案

需要修改输入源，不直接修改生成的 l10n 文件：

- `app/lib/l10n/parts/*_zh.arb`；
- `app/lib/l10n/parts/*_en.arb`；
- `app/android/app/src/main/AndroidManifest.xml` 的应用标签；
- App 图标、启动图、关于页和版本页；
- 更新弹窗中的产品名、发布页和导出目录；
- `Download/DSH-Go` 改为 `Download/QuWork` 或产品确定的目录；
- 更新错误中的“不是 DSH 安装包”“签名不一致”等产品文案；
- 发布说明、README、用户指南和隐私说明中的更新地址。

更新文案必须保持中英文同步，然后运行：

```bash
python3 app/tool/l10n_merge.py
python3 app/tool/l10n_merge.py --check
```

## 6. Android 包名与签名迁移方案

### 6.1 路径 A：原地升级的实施步骤

适用于 DSH Go 用户直接转为 QuWork 用户。

1. 盘点已发布 DSH APK 的正式 `applicationId`、证书指纹、最高 versionCode 和签名 lineage。
2. 确定 QuWork 首个 versionName，但 versionCode 取全局高水位之后的值，不能重置为 `+1`。
3. 由同一正式 keystore 构建 QuWork APK；本地 debug key 不能进入发布渠道。
4. 先做一份内部签名覆盖包，在真实设备上验证安装、数据、Keystore、运行时和远程主机配置仍可读取。
5. 更新发布脚本和 manifest，确认 APK 内的包名、versionName、versionCode、签名证书与清单完全一致。
6. 发布第一版 QuWork stable，旧 DSH App 收到更新后覆盖安装。
7. 在新版本中再逐步清理 DSH 旧品牌文案；不要在迁移首版同时做大规模存储路径迁移。

必须保留的内容：

- `applicationId`；
- 正式签名证书；
- 版本号单调递增；
- 需要继续兼容的数据目录、SharedPreferences、Android Keystore alias 和本地运行时结构。

### 6.2 路径 B：新 App 并行安装的实施步骤

适用于 QuWork 必须与 DSH Go 分离。

1. 申请并固定新的 QuWork `applicationId`。
2. 创建只用于 QuWork 的正式签名证书和 CI 密钥访问策略。
3. 修改 Android manifest、Gradle namespace、启动脚本中的包名和所有 authority/deep link。
4. 明确旧 App 数据是否可导出；不要假设 Android 会自动迁移 SharedPreferences、文件或 Keystore。
5. 新 App 首次安装走完整安装流程，更新器只处理 QuWork 自己的包名和签名。
6. 旧 DSH Go 可以继续使用原更新源，或在其发布页中提示迁移到 QuWork。

路径 B 下可以重新开始 versionCode，但不能把新包误发布到旧 App 的更新清单中。

### 6.3 签名密钥管理

签名迁移阶段必须建立密钥台账，但不把密钥内容写入仓库：

- 正式 keystore 放在仓库外的受控发版环境；
- CI 使用短期凭据或受控签名服务；
- keystore、alias、证书指纹和备份位置由少数维护者管理；
- 构建日志不得打印密码、私钥或完整签名材料；
- 发布前使用 `apksigner verify` 和 APK 证书指纹检查；
- 换钥匙前先验证 Android 版本覆盖范围，并制定旧用户迁移方案。

签名校验是更新信任链的最后一道防线。SHA-256 只能证明下载文件与清单一致，不能替代 Android 签名。

## 7. 发布流水线改造

### 7.1 构建输入

需要将 [release_assets.py](/Users/wujihuan/work/rrzu/quwork-mobile/tooling/release_assets.py) 和 [build-apk.sh](/Users/wujihuan/work/rrzu/quwork-mobile/tooling/build-apk.sh) 从 DSH 固定值改为 QuWork 配置输入：

- QuWork 仓库或发布页地址；
- QuWork APK 文件名模板；
- QuWork 更新域名和清单地址；
- QuWork 产品名和 release title；
- stable/beta channel；
- 是否生成增量补丁；
- 发布的 ABI 集合；
- 正式 versionName 和 versionCode。

脚本仍应从 APK 本身读取真实版本和 ABI，不接受清单与 APK 不一致的发布输入。

### 7.2 首期发布顺序

```text
1. 构建并签名 arm64/x64 APK
2. 检查 applicationId、versionName、versionCode 和签名
3. 生成 SHA256SUMS 和 update.json
4. 上传 version 目录中的不可变资产
5. 从 CDN/对象存储下载回来校验大小、SHA-256 和 Range
6. 发布版本清单（可选）
7. 最后替换 stable/update.json 指针
8. 用正式 QuWork APK 真机检查更新和覆盖安装
```

根目录 `update.json` 必须最后更新。这样即使资产上传中断，客户端也不会看到一个指向未完成文件的版本。

### 7.3 回滚

回滚只把 stable `update.json` 切回上一版本，不删除或覆盖已发布版本目录。需要保留：

- 每个版本的 APK、补丁、`SHA256SUMS` 和版本清单；
- 清单发布历史；
- 签名证书指纹和构建参数；
- 每次回滚的原因、时间和影响范围。

如果新 APK 已经在部分设备安装，回滚清单只能让新安装设备回到上一版本；Android 不允许通过更新安装更低 versionCode 的 APK。出现安全问题时，应发布更高 versionCode 的修复版本。

## 8. 分阶段实施计划

### 阶段 0：决策和基线冻结

交付物：更新服务契约、迁移路径决议、签名和版本基线。

- 决定路径 A 或 B；
- 记录当前正式包名、证书 SHA-256 指纹、最高 versionCode；
- 决定 QuWork stable/beta 域名；
- 决定 ABI、versionName 和 versionCode 规则；
- 决定首期只发完整 APK；
- 确定 QuWork 发布页和隐私说明地址。

验收：产品、客户端、后端和发版负责人对上述值有书面确认。

### 阶段 1：更新服务 PoC

交付物：可独立访问的 QuWork 更新域名和测试资产。

- 部署 `/update.json`、版本目录、APK 和 `SHA256SUMS`；
- 验证 HTTPS、Range、缓存头、Content-Type、Content-Length；
- 验证清单中的 SHA-256、大小和实际文件一致；
- 验证错误响应不会返回登录页；
- 完成 stable 与 beta 的目录隔离；
- 暂不接入真实用户账号。

验收：用 `curl` 和测试脚本从不同网络完整下载、断点下载和校验 APK。

### 阶段 2：客户端更新源改造

交付物：QuWork 测试包可以检查 QuWork 测试清单。

- 替换更新源常量和构建期 defines；
- 关闭 DSH/GitHub 默认回退；
- 替换品牌标题、发布页、导出目录和错误文案；
- 保持每日检查、缓存、跳过、断点续传、SHA-256 和安装回执逻辑；
- 让 `tooling/quwork-android.sh` 同时注入 QuWork 账号/模型地址和更新地址；
- 运行 l10n 生成与检查。

验收：测试包只请求 QuWork 域名，不能在 DNS、网络日志或模拟器抓包中看到 DSH 更新域名。

### 阶段 3：包名与签名迁移验证

交付物：真机覆盖安装报告或新 App 并行安装报告。

路径 A 验收：

- 旧 DSH 正式包可以安装 QuWork 测试升级包；
- 对话、设置、运行时和必要的安全存储仍可用；
- 版本号和签名校验通过；
- 旧包名没有被误改；
- versionCode 没有降级。

路径 B 验收：

- 新 QuWork 包可以与 DSH Go 同时安装；
- 两个 App 的 Provider authority、文件目录、深链和通知互不冲突；
- 用户能明确知道是否迁移数据；
- 两个 App 的更新清单互不交叉。

### 阶段 4：正式发布流水线

交付物：可重复的 QuWork 发布命令和回滚演练记录。

- 构建正式签名 APK；
- 生成清单、校验和和可选补丁；
- 上传并回读所有资产；
- 只在校验完成后更新 stable 指针；
- 演练清单回滚和高 versionCode 修复发布；
- 建立更新检查、下载失败、校验失败和安装失败的监控。

### 阶段 5：增量和产品化策略

交付物：可选的增量更新、灰度和强制更新方案。

- 从 QuWork 自己的 APK SHA-256 生成增量补丁；
- 不能复用旧 DSH APK 的补丁；
- 增加最低版本、强制更新和灰度字段前，先升级客户端解析和 UI；
- 明确无兼容 ABI、无空间、无网络和签名错误时的可恢复路径；
- 根据隐私要求决定是否收集匿名检查和下载统计。

## 9. 测试与门禁

代码实现阶段按改动范围执行：

```bash
(cd app && flutter pub get && flutter analyze && flutter test)
python3 app/tool/l10n_merge.py --check
(cd packages/dsh_remote && dart pub get && dart analyze && dart test)
```

如果修改发布资产生成器或更新服务：

```bash
python3 tooling/release_assets.py --help
(cd services/share-worker && npm test)
```

更新安装必须在真实 Android 设备验证，至少覆盖：

1. 首次安装未知应用权限；
2. 同包名、同签名覆盖安装；
3. 不同签名被拒绝；
4. 不同包名被拒绝或走新 App 安装；
5. versionCode 降级被拒绝；
6. 下载中断后 Range 续传；
7. SHA-256 错误后删除并回退；
8. 增量补丁失败后完整 APK 回退；
9. App 被系统替换后安装结果 reconcile；
10. arm64 真机和 x64 模拟器分别拿到正确资产。

桌面测试、模拟器测试和 CI 通过不能代替真实设备上的签名覆盖安装验证。

## 10. 风险与控制措施

| 风险 | 控制措施 |
|---|---|
| QuWork 清单仍回退到 DSH GitHub | 客户端源列表只保留 QuWork；测试检查请求域名 |
| 包名改了导致旧用户无法覆盖 | 阶段 0 锁定迁移路径；发布前用旧正式 APK 做覆盖安装 |
| 签名证书丢失或混用 | 仓库外备份、CI 受控签名、发布前证书指纹检查 |
| 清单指向未上传完成的 APK | 版本目录先上传并回读，最后再替换根清单 |
| CDN 缓存旧文件或文件被覆盖 | 版本路径 immutable；修包升版本；清单短缓存 |
| SHA-256 被清单一并篡改 | 保持 Android 正式签名校验；必要时增加 manifest Ed25519 签名 |
| Beta token 被提取 | 把 token 视为访问控制而非秘密；支持撤销和轮换 |
| 更新服务依赖登录导致新用户无法升级 | stable 更新保持匿名；不发送 JWT、`llm_token` 或设备 token |
| x64/arm64 缺少资产 | 发布脚本按 ABI 检查；客户端缺失时只打开发布页，不安装错误 APK |
| 鸿蒙误拿 Android APK | 清单按平台分开；鸿蒙继续走 AppGallery 或专用更新服务 |

## 11. 待确认事项

在进入代码改造前需要确认：

1. QuWork 选择原地升级还是新 App 并行安装？
2. 如果原地升级，正式签名证书是否仍可使用？证书指纹和最高 versionCode 是什么？
3. QuWork 更新域名、发布页域名和对象存储由谁维护？
4. stable 和 beta 是否都需要？Beta 是否需要通道鉴权？
5. 首期是否只发 arm64，还是同时发 x64？
6. 首期是否关闭增量补丁？
7. 是否需要强制更新、最低版本和灰度发布？
8. 鸿蒙是否纳入同一发布计划，还是单独走 AppGallery？
9. 是否需要匿名更新检查/下载统计？保留多久，隐私说明放在哪里？
10. QuWork 品牌素材、应用图标和发布页文案是否已经获得使用授权？

## 12. 完成定义

本计划对应的更新迁移完成，需要同时满足：

- QuWork App 只访问 QuWork 更新源；
- QuWork 更新服务可以独立发布和回滚，不依赖账号登录；
- 清单、APK、校验和、版本和 ABI 一致；
- 选择原地升级时，旧正式包可以在真机上保留数据并覆盖安装；
- 选择新 App 时，两个包可以并行安装且更新源不交叉；
- 正式包使用固定可追溯的签名证书；
- 更新弹窗、发布页、文件名、导出目录和中英文文案完成 QuWork 品牌替换；
- 发布脚本能在上线前回读并校验全部资产；
- 回滚和高 versionCode 修复流程已经演练；
- 相关静态检查、Flutter 测试和真机安装验证均有记录。
