# 授权台 · wxg-glass 管理 App

一个自签名侧载的 iOS App（SwiftUI），用来远程管理 `xyylwc` 解锁服务器：

- **名单**：加人 / 踢人 / 看当前授权列表。改动直接写进 KV，不用改代码、不用等重部署；
  加人对方下次联网核对就能用，踢人在对方下次复查时生效（见「五、踢人多久生效」）。
- **活动**：
  - Cloudflare 聚合请求曲线（24 小时 / 7 天的请求量、错误量、错误率）；
  - 每个账号的联网核对记录（谁、哪台设备、什么时候、通过还是被拒）。
- **概览**：服务器自检（着色器版本、签名私钥、名单来源、公钥）。

所有密钥（管理口令、Cloudflare Token）只存 iOS Keychain，不进 UserDefaults、不打印、不上传。

---

## 一、服务器配置（已完成，记录备查）

管理功能是 worker 的 **增量**，加在 `/v1/admin/*` 路径上，**不碰原来的签名 / 着色器 / 水印逻辑**。
现状：

1. **KV**：命名空间 `wxg-list`（ID `0e2c7c8397f141bc82602102f46e6241`），在 `server/wrangler.jsonc` 里以绑定名
   `LIST` 绑到 worker。绑定名必须是 `LIST`（Cloudflare 示例里的 `KV_BINDING` 不能用）。
2. **管理口令**：Worker 的 Secret `ADMIN_TOKEN`。⚠️ 要加在 *Settings → Variables and Secrets*（运行时那一栏，
   `SIGN_PRIV` 也在那里），**不是** Build 设置里的那个 Variables and secrets——那里的变量只在打包时可见，worker 读不到。
   换口令：在同一处改值并 Deploy，然后把 App「设置」里的管理口令改成新值。
3. **名单**：已用 App「名单」页的 *导入 worker.js 现有名单*（= `POST /v1/admin/seed`）把常量名单导入 KV，
   之后名单以 KV 为准。`worker.js` 顶部的 `ALLOWLIST` 只剩回退与种子作用，改它不生效。

> 验证：浏览器打开 `https://xyylwc.kvgdth56kf.workers.dev/`，JSON 里应看到 `listSource:"kv"`、`admin:"set"`、
> `allowCount` 为当前人数。

> KV 是最终一致的：加人 / 踢人后，列表或别处读到新结果通常要几秒、最长约 60 秒，稍后下拉刷新即可。

### Cloudflare 分析 Token（可选，只为看请求曲线）

1. **建 Token**：Cloudflare 控制台右上角头像 → *My Profile* → *API Tokens* → *Create Token* →
   最下面 *Custom token* 的 *Get started*。
   - Token name：随意，如 `授权台只读`
   - Permissions：三个下拉依次选 **Account** / **Account Analytics** / **Read**
   - Account Resources：**Include** / 你的账号
   - 其余不动 → *Continue to summary* → *Create Token*，**复制 Token**（只显示这一次）。
2. **找 Account ID**：在 Cloudflare 控制台随便点进一个页面，网址里 `dash.cloudflare.com/` 后面那串 32 位字符就是；
   电脑上 Workers & Pages 概览页右侧也有。
3. **填进 App**：「设置」→ Cloudflare 分析里填 Account ID 和 API Token，回「活动」页下拉刷新。

这个 Token 只读，不能改任何东西。不填也能用——曲线会提示去配置，「名单」和「核对记录」照常工作。
曲线查询走 Cloudflare GraphQL（`workersInvocationsAdaptiveGroups`），出错时 App 会显示 Cloudflare 的原始报错。

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

Bundle ID 是 `com.xyydys.wxgadmin`，桌面显示名「授权台」。**最低系统 iOS 26**（用了原生 Liquid Glass UI：`glassEffect`、玻璃按钮、玻璃 Tab 栏）。CI 跑在 `macos-26` runner（Xcode 26 带 iOS 26 SDK）。

---

## 三、本地改 / 预览（可选，需要 Mac + Xcode 26）

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
  和插件 / 服务器算法完全一致，wxid 不上传、只上传哈希），也可直接粘 64 位哈希；点垃圾桶踢人（有二次确认）。
  长按某个账号可「复制完整哈希」。
- **活动**页：上半 Cloudflare 曲线，下半按账号的核对明细 + 最近流水。长按账号行复制完整哈希；
  右上角 *复制全部账号哈希*（空格分隔，含已踢出的账号），可直接当水印溯源工具
  `plugin/tools/watermark_decode.mjs` 的候选账号参数——工具不传账号时只比对 `worker.js` 常量名单，
  App 里新加的、已踢出的账号都不在其中。

---

## 五、踢人多久生效

服务器没法主动通知手机，插件只在「复查」时知道自己被踢：复查被拒（403）会**立刻删掉本地票据并关闭**。
所以踢人的延迟 = 对方下次复查的时间：

- 复查间隔由 `server/worker.js` 顶部的 `RECHECK_AFTER` 决定（现 1 天），插件接受 60 秒～7 天，改它只需改 worker，不用重编插件。
- 新间隔要等每台设备下一次核对拿到新票据后才生效（过渡期最长等于旧间隔）。
- 复查只在微信前台、插件在跑时发生；完全离线或连不上服务器的设备，会按手上票据用到 7 天有效期结束。
- 间隔越短，请求和 KV 写入越多（每次核对约 2 次写，KV 免费额度每天 1000 次写），调短前先估算人数。

## 六、额度

Cloudflare 免费版每天额度（UTC 0 点 = 北京时间 08:00 重置，全账号合计）：Worker 请求 10 万、
KV 读 10 万、KV 写 / 删 / 列 各 1000。按 1 天复查，每人每天约 1 次核对 = 2 读 2 写，
最紧的是 KV 写：约 **500 人**才会用满；App 自己每刷新一次「活动」页约 2～3 次列 + 最多两百来次读。

「概览」页的 **今日额度** 卡片用同一个 Cloudflare 只读 Token 查当天用量（Worker 请求按全账号算；
KV 读 / 写 / 删 / 列来自 `kvOperationsAdaptiveGroups`），进度条 60% 变橙、90% 变红。数据是 Cloudflare
分析的近似值，比实际晚几分钟。写超了只丢核对记录、不影响授权，但当天 App 里加人也会失败。

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
