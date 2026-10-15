# 授权台 · wxg-glass 管理 App

一个自签名侧载的 iOS App（SwiftUI），用来远程管理 `xyylwc` 解锁服务器：

- **名单**：加人 / 踢人 / 看当前授权列表，即时生效（走 KV，不用改代码、不用等重部署）。
- **活动**：
  - Cloudflare 聚合请求曲线（24 小时 / 7 天的请求量、错误量、错误率）；
  - 每个账号的联网核对记录（谁、哪台设备、什么时候、通过还是被拒）。
- **概览**：服务器自检（着色器版本、签名私钥、名单来源、公钥）。

所有密钥（管理口令、Cloudflare Token）只存 iOS Keychain，不进 UserDefaults、不打印、不上传。

---

## 一、先让服务器支持远程管理（一次性）

管理功能是 worker 的 **增量**，加在 `/v1/admin/*` 路径上，**不碰原来的签名 / 着色器逻辑**。
没配 KV、没设 `ADMIN_TOKEN` 时，worker 自动退回老行为（名单读 `worker.js` 顶部常量，`/v1/admin/*` 返回 503），
所以下面几步做完之前，现网是完全照旧的。

1. **建 KV**：Cloudflare 控制台 → Storage & Databases → KV → *Create namespace*（名字随意，如 `wxg-list`）。
   记下它的 **Namespace ID**。
2. **绑 KV**：编辑 `server/wrangler.jsonc`，把文件末尾那段注释掉的 `kv_namespaces` 放开，`id` 填上面的真实 ID，
   `binding` 保持 `LIST`。⚠️ 一定填真实 ID 再放开，否则 Cloudflare 会因为绑定不存在的命名空间而部署失败。
3. **设管理口令**：Worker 的 *Settings → Variables and Secrets* 加一个 **Secret**：
   - 名字：`ADMIN_TOKEN`
   - 值：一串够长的随机口令（这就是 App 里要填的「管理口令」，等同后台密码，别外泄）。
4. **提交触发部署**：把 `server/worker.js` + `server/wrangler.jsonc` 推到 `main`，Workers Builds 自动重部署。
5. **导入现有名单**：部署好后，用 App 的「名单」页右上角 → *导入 worker.js 现有名单*
   （等价于 `POST /v1/admin/seed`），把原来 3 个测试账号灌进 KV。之后名单以 KV 为准，加 / 删都即时生效。

> 验证：浏览器打开 `https://xyylwc.kvgdth56kf.workers.dev/`，JSON 里应看到 `listSource:"kv"`、`admin:"set"`。

### Cloudflare 分析 Token（可选，只为看请求曲线）

- **Account ID**：Workers & Pages 概览页右侧。
- **API Token**：My Profile → API Tokens → *Create Token* → Custom，权限加
  **Account → Account Analytics → Read**，范围选你的账号即可。只读，不改任何东西。

不填这两项也能用——「活动」页的 Cloudflare 曲线会提示去配置，但「名单」和「核对记录」照常工作。

---

## 二、打出 ipa（GitHub Actions，无需 Mac）

本仓库已带工作流 `.github/workflows/admin-ipa.yml`：

- 触发：改了 `admin/**` 自动跑，或 Actions 页 *Run workflow* 手动跑。
- 它在 macOS runner 上用 XcodeGen 生成工程、`xcodebuild` 编出 **未签名** 的 `.ipa`，
  作为产物 `WXGAdmin-unsigned-ipa` 上传（保留 30 天）。

下载产物解压得到 `WXGAdmin-unsigned.ipa`，用任意自签工具侧载到自己的 iPhone：

- **Sideloadly** / **AltStore**：用你的 Apple ID 免费签（7 天有效，到期重签；AltStore 可后台自动续签）。
- **TrollStore**（设备支持的话）：永久签，装上不过期。
- 付费开发者账号：签名有效期 1 年。

> 未签名 ipa 不能直接装——上面这些工具会用你自己的证书重新签名后再装，这就是「自签名」。

Bundle ID 是 `com.xyydys.wxgadmin`，桌面显示名「授权台」。最低系统 iOS 16。

---

## 三、本地改 / 预览（可选，需要 Mac + Xcode）

工程不入库，用 XcodeGen 现生成：

```bash
brew install xcodegen
cd admin
xcodegen generate
open WXGAdmin.xcodeproj
```

直接连真机、选你自己的签名 Team，Run 即可（Xcode 会自动免费签）。

---

## 四、首次使用

装好打开 App → **设置**：

1. **Worker 地址**：默认已填 `https://xyylwc.kvgdth56kf.workers.dev`。
2. **管理口令**：填第一步设的 `ADMIN_TOKEN`。
3.（可选）**Cloudflare Account ID / API Token**：看请求曲线用。
4. 点 **测试连接**，显示「连接成功，当前 N 个授权账号」就通了。

然后：

- **名单**页：*添加授权* 可直接输 wxid（App 本地算出 `SHA-256("WXGLiquidGlass.license.v1:"+wxid)`，
  和插件 / 服务器算法完全一致，wxid 不上传、只上传哈希），也可直接粘 64 位哈希；左滑或点垃圾桶踢人（有二次确认）。
- **活动**页：上半 Cloudflare 曲线，下半按账号的核对明细 + 最近流水。

---

## 接口速查（worker `/v1/admin/*`，`Authorization: Bearer <ADMIN_TOKEN>`）

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/v1/admin/ping` | 验证口令，返回授权人数 |
| GET | `/v1/admin/allow` | 列出名单 |
| POST | `/v1/admin/allow` | 加人（body `{account}` 或 `{wxid}` + 可选 `note`）|
| DELETE | `/v1/admin/allow/<account>` | 踢人 |
| POST | `/v1/admin/seed` | 把 worker.js 常量名单导入 KV（幂等）|
| GET | `/v1/admin/activity?limit=200` | 核对流水 + 各账号汇总 |

核对记录是 worker 在每次 `/v1/unlock` 时**尽力而为**写进 KV 的（`ctx.waitUntil`，失败不影响授权），
流水 `ev:*` 有 30 天 TTL，`seen:*` 常驻。
