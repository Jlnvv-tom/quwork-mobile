# QuWork 手机 App 链接方案决策 v3

> 状态：待确认。本文只收敛连接方案，不开始业务代码改造。
>
> 盘点日期：2026-11-18

## 1. 结论

如果目标是先做出一个公网可用、能扫码连接 Qurvis 的 QuWork MVP，首期采用：

```text
手机 QuWork App
  ├─ HTTPS -> one-api
  │           ├─ 手机号/微信登录
  │           ├─ 可用模型和账号状态
  │           └─ token 刷新和退出
  │
  └─ HTTPS/WSS -> Qurvis 内置 Mobile Gateway
                    └─ Cloudflare/FRP/cpolar 隧道
                         └─ Qurvis 本地 DSH Web
```

具体做法是把已有 `quwork-dsh-mobile` 的 Mobile Gateway、配对和设备授权能力集成到 Qurvis，手机新增 Gateway 客户端，one-api 只负责 QuWork 身份和模型。one-api 不转发聊天、文件和 DSH 长连接数据。

这是参考已有 ds-plugin-remote 链路时，代码和协议新增量最小、可以尽快端到端跑通的方案。PoC 可以接受隧道地址变化或管理员配置；面向用户的 MVP 应使用稳定域名，产品化阶段再评估统一 Remote Server/Relay。

## 2. 对“ds-plugin-remote”边界的确认

当前参考到的 Remote 相关包分成三层，不能把它们当成同一个组件：

| 组件 | 已解决的问题 | 是否是公网链路 |
|---|---|---:|
| `@deepseek-ai/dsh-api-remotes` | 选择 Host/Client Remote API、转发事件、挂载 DSH 业务 namespace | 否 |
| `@deepseek-ai/dsh-api-remote-access` | 非 owner Peer 的资源级授权、访问快照、事件过滤 | 否 |
| `packages/dsh_remote` / `ds-harness-remote` | Server 登录、Host 目录、扫码配对、Noise、WebRTC、TURN、Relay、重连 | 是 |

`@deepseek-ai/dsh-api-remotes` 的说明明确指出它“不拥有物理传输或 Host 服务发现”；因此只把该包装进 Qurvis，不能让手机和电脑跨公网连通。公网链路必须使用现有 `ds-harness-remote` Server/Relay，或者另建 Gateway/隧道。

## 3. 为什么首选已有 Mobile Gateway 链路

参考 `ds-plugin-remote`/`quwork-dsh-mobile` 后，首期最省成本的原因不是现有 App 已经有完整 Remote Server 客户端，而是 Qurvis 已经拥有可以被 Gateway 代理的 DSH Web。现有 App 和参考项目分别可复用以下资产：

- `quwork-dsh-mobile/src/gateway.ts`、`src/access.ts`：Gateway、设备配对、设备 token、Session、CSRF、WebSocket 代理和设备撤销。
- `quwork-dsh-mobile/src/cloudflared.ts`、`src/frp.ts`、`src/cpolar.ts`：公网入口和隧道生命周期；还可以使用 Tailscale 或已有反向代理。
- `quwork-dsh-mobile/apps/mobile/android`：配对设备的安全存储、Origin/CA 校验、设备状态和重连行为。
- 当前 App 的 `DshConnection`、扫码和安全存储：可以复用 DSH 会话、模型和聊天 UI，但需要新增独立的 Gateway HTTP/WebSocket 客户端。
- `packages/dsh_remote`：保留为后续 `ds-harness-remote` 路径，不作为首期 Gateway 的传输实现。

因此首期不需要先给 Qurvis 实现完整 Host 注册、Noise、WebRTC、TURN、Relay 和 Remote Server 生命周期，也不需要把 one-api 改造成远控数据面。主要新增工作集中在 Qurvis Gateway 集成、手机 Gateway 客户端和 QuWork 账号/模型接入。

Gateway + 隧道已经满足 MVP 的核心需求：

- 公网：Cloudflare Named Tunnel、FRP、cpolar、Tailscale 或自有 HTTPS 反向代理；
- 配对：Gateway 生成一次性 QR，手机确认电脑信息后换取持久 device token；
- 安全：HTTPS、远程 CA/Origin 校验、HttpOnly Session、CSRF、设备撤销和短期配对窗口；
- 可用性：Gateway 自己维护 Session/设备续期，手机可重连；
- 业务复用：Gateway 代理 DSH Web 的 HTTP、事件 WebSocket 和远程 mux，手机继续使用已有 DSH 会话与模型 UI。

## 4. 三种方案的真实成本对比

| 方案 | 手机 App 改动 | Qurvis 改动 | 服务端/运维 | 用户公网体验 | 综合判断 |
|---|---|---|---|---|---|
| **A. Qurvis 内置 Mobile Gateway + 外部隧道** | **中偏小**：新增 Gateway QR、Cookie/设备 token、WSS/HTTPS 客户端；可复用 `DshConnection` | **中偏小**：集成 `quwork-dsh-mobile` 的 Gateway，或按其公开协议重实现 | **小到中**：不建 Relay；PoC 可用 Quick Tunnel，MVP 用 Named Tunnel/自建 FRP | **可用**：稳定隧道可扫码直连；Quick Tunnel 地址可能变化，重启后需要重新扫码 | **首期最低成本** |
| B. 复用 `ds-harness-remote` Server/Relay | 小：当前 App 已有 `packages/dsh_remote`，但仍要接入 QuWork 身份 | **中到大**：Qurvis 尚未发现现成 Host 注册/配对/Server 接入，需要补 Host 端 | 中：部署和维护 Server/Relay、账号映射和多实例状态 | 好：公网、直连/Relay、重连边界更完整 | 产品正式版演进方案 |
| C. one-api 内嵌远控 WS/Relay | 中到大：需要新协议适配 | 中到大：仍需 Host/Relay 适配 | 大：受引擎级中间件、发布耦合、WS 生命周期和多实例影响 | 好，但稳定性和运维风险最高 | 不建议 |

这里的“小成本”按首期完整可用链路计算，而不是只按新增代码行数计算。方案 A 的代价是隧道配置、域名/地址变化和单 Gateway 连接限制；方案 B 的代价则是 Qurvis Host 端、Remote Server/Relay、设备目录、Noise/WebRTC/TURN 适配和多实例运维。对当前项目，方案 A 的端到端新增面更小。

## 5. 方案 A 的适用边界和限制

首期采用方案 A，需要接受以下边界：

1. Qurvis 运行本地 Gateway；公网入口由 Cloudflare Named Tunnel、FRP、cpolar、Tailscale 或自有反向代理提供。
2. 手机直接连接 Gateway 的 HTTPS/WSS；one-api 只负责登录、模型和账号状态，不承载聊天、文件和 DSH 长连接。
3. 首期设备目录以 Gateway 本地设备存储为准；one-api 不复制一套完整 Remote Server 设备目录。
4. Cloudflare Quick Tunnel 只用于 PoC；正式使用应使用稳定域名的 Named Tunnel、FRP 或自有反向代理，否则公网地址变化后需要重新扫码。
5. 首期可限制为一个 Qurvis Gateway 一次连接，不实现统一 Host 目录、P2P/TURN 选路和 Relay 多实例。

参考实现 `/Users/wujihuan/work/rrzu/quwork-dsh-mobile` 根目录采用 Apache-2.0。若复制或移植其代码，必须保留 `LICENSE`、原版权/许可声明、第三方 notices，并在修改过的文件中标注修改；不得把其品牌和商标当成代码授权。若只按行为重实现，也应保留来源记录。

方案 A 不能直接复用当前 `dsh_remote` 配对后端：它的配对 payload、device token、Cookie、CSRF、TLS/CA pinning 和连接入口与 `ds-harness-remote` 不同。App 需要新增独立的 `QuWorkGatewayClient`，不能把两种凭据混存成同一种 Host 记录。

## 6. 推荐的最小实施边界

### 6.1 one-api：首期只做账号和模型控制面

首期不必先新增完整的远控配对接口。先确认并接入现有账号、模型和 token 接口：

```text
手机号/微信登录、刷新、当前用户
可用模型列表
账号退出和封禁状态
```

Gateway 自己生成和验证配对 secret、device token、Session 和 CSRF。QR 不放 one-api JWT、`llm_token`、Cookie 或长期设备密钥。若后续需要把 Gateway 设备归属同步到 QuWork 账号，再新增单独的设备绑定/撤销接口；不要把 one-api JWT 直接当作 Gateway 或 Noise 凭据。

如果已有 `ds-harness-remote` Server 自己维护账号和设备目录，则 one-api 不必复制完整 Remote Server，只需建立 QuWork user ↔ Remote account/device 的映射和短期授权同步。不要把 one-api JWT 直接当成 Noise 或长期 Remote 凭据。

### 6.2 Qurvis：优先接入 Mobile Gateway

MVP 只集成以下能力：

- loopback HTTPS Gateway；
- `/api/events.mux`、`/api/events.host`、`/api/remote.mux` 等 DSH WebSocket 代理；
- 短期 QR pairing secret、持久 device token、设备撤销；
- Cloudflare Quick/Named Tunnel 或自建 FRP 的出站连接；
- Gateway 到 DSH Web 的 Host/Origin、CSRF、缓存和 WebSocket 升级保护。

Gateway 方案的 pairing secret、device token、Cookie 和 CA fingerprint 必须使用独立的数据模型；不能复用 `dsh_remote` 的 Server account credential。

### 6.3 Qurvis：首期集成 Gateway，正式版再接入 Remote Host

首期优先顺序：

1. 在 Qurvis 内启动 loopback Gateway，并接入已有 DSH Web 的认证、HTTP、事件 WebSocket 和 remote mux 代理。
2. 复用 `quwork-dsh-mobile` 的设备配对、设备 token、Session、CSRF、撤销和隧道行为；优先保留代码来源和协议边界。
3. 对外提供稳定 HTTPS Origin，优先 Named Tunnel/FRP/自有反向代理；Quick Tunnel 只作为 PoC。
4. 正式版再评估接入兼容当前 `packages/dsh_remote` 的 `ds-harness-remote` Host 插件；不要在首期重写 Noise、Relay 或 WebRTC。

Qurvis 的 `@deepseek-ai/dsh-api-remotes` 和 `@deepseek-ai/dsh-api-remote-access` 继续负责 DSH Remote API/权限；它们与 Server/Relay 是不同层，不能互相替代。

### 6.4 手机 App：新增 QuWork 账号和 Gateway 连接

- 新增 `QuWorkAuthState`，不改写当前面向 DeepSeek OAuth 的 `AccountState`。
- 新增 `packages/quwork_api`，实现手机号、微信、滑块、刷新和模型接口；设备归属控制面留作后续阶段。
- 保留 `remote_pairing_state.dart` 和 `DshRemoteRelayBackend` 作为未来 `ds-harness-remote` 路径；新增独立 `QuWorkGatewayClient` 与 Gateway 配对页。
- 将 QuWork 登录身份与 Gateway 设备记录关联的工作放在后续控制面；不把 QuWork `llm_token` 放进 Gateway QR、设备 token、日志或普通偏好。
- 模型列表从 one-api 读取；消息请求仍通过已连接的 Qurvis DSH Host 发送，模型凭据由 Host 侧按安全配置注入，或由明确的 QuWork provider profile 使用。

## 7. 首期用户流程

```text
1. 手机 App 用手机号/微信登录 one-api。
2. App 读取账号可用模型。
3. 用户在 Qurvis 启用 Mobile Gateway 和公网隧道，Gateway 展示一次性配对 QR/链接。
4. App 扫描 QR，校验 Origin、实例标识和（自签入口时）CA，显示电脑名和配对有效期。
5. 用户确认后，App 将配对请求提交到 Gateway，Gateway 返回 device token、Session/CSRF 和设备摘要。
6. App 加密保存 Gateway 设备凭据，建立 DSH WebSocket/mux 连接。
7. 用户选择 QuWork 模型并开始聊天。
8. 账号 token 过期时只刷新 QuWork 控制面；Gateway 连接异常按设备续期和重连策略处理。
```

## 8. 不能做的简化

- 不能只把 `dsh-api-remotes` 安装到 Qurvis，就声称已经有公网连接。
- 不能把 one-api JWT 放进 QR，也不能用它代替 Gateway device token、Origin/CA 校验或未来的 Noise。
- 不能把 `llm_token` 作为手机与电脑之间的通用连接密钥。
- 不能把 `dsh_remote` 的 Server/Relay 凭据和 Mobile Gateway 的 Cookie/device token 存在同一字段。
- 不能在 one-api 中直接新增一个 WS handler 后跳过 Gateway 配对、Session/CSRF、心跳、重连和设备撤销设计。

## 9. 实施顺序

### 阶段 0：先做 Gateway 端到端验证

- 固定 Qurvis DSH Web 版本和 Gateway 代理路径。
- 用最小 Gateway PoC 展示 QR，完成 App 扫码、设备配对、`DshConnection` 登录和 `listSessions()`。
- 先用 LAN/本机反向代理验证，再验证稳定的 Cloudflare Named Tunnel 或 FRP 公网入口、断线重连、设备撤销和 Gateway 重启。

### 阶段 1：账号和控制面

- 实现 `packages/quwork_api`、`QuWorkAuthState`、安全存储和 token refresh single-flight。
- 接入手机号/微信登录、滑块和模型列表；首期不阻塞在 one-api 远控配对控制面。
- 保持 DSH `AccountState` 独立。

### 阶段 2：模型和 Host 凭据

- 固定 QuWork provider profile、Base URL、模型元数据和 `llm_token` 的 Host 注入边界。
- 用真实聊天请求验证模型选择生效，不只验证列表显示。

### 阶段 3：MVP 连接产品化

- 完成 Qurvis Gateway 生命周期、设备管理、连接状态和升级兼容。
- 完成 App 真机扫码、公网隧道、断线重连和撤销。
- MVP 稳定后，再评估是否迁移到 `ds-harness-remote` Server/Relay，获得统一 Host 目录、P2P/TURN 和多实例能力。

## 10. 最终建议

如果目标是先做出满足需求、可跨公网扫码连接的 QuWork 版本，选 **方案 A：Qurvis Mobile Gateway + 稳定 HTTPS 隧道**。它最接近已有 ds-plugin-remote 的实际实现，Qurvis 已经拥有 DSH Web 和 Gateway 参考代码，手机端新增 Gateway 客户端即可；one-api 只做账号和模型，改动边界最清晰。

如果目标是面向普通用户的长期正式版，再演进到 **方案 B：`ds-harness-remote` Server/Relay + Qurvis Host 适配**。这条路可以减少用户配置隧道，并提供统一 Host 目录、P2P/TURN 和 Relay，但 Qurvis Host 和服务端接入工作明显更大。

无论选择 A 还是 B，one-api 都只承载账号、模型和可选的设备归属控制面；不建议把远控长连接数据面并入 one-api。
