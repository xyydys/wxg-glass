# wxg-glass · WeChat Liquid Glass 解锁服务器

私有仓库。Cloudflare 从这里自动部署（Workers Builds）。

- `worker.js`：服务器代码 + 授权名单（文件开头的 ALLOWLIST）+ 着色器。
- `wrangler.jsonc`：部署配置，`name` 要和 Cloudflare 里的 Worker 名字一致（现在是 xyylwc）。
- 私钥不在仓库里，在 Cloudflare 的 Settings → Variables and Secrets 里，名字 `SIGN_PRIV`（Secret）。

改名单或换着色器：改 `worker.js` 并提交，Cloudflare 会自动重新部署。

部署：Cloudflare Worker `xyylwc` 已连接本仓库 main 分支，每次推送自动部署。

## FIX106 · 着色器密钥与验签绑定（与插件必须成对升级）

着色器不再明文下发。服务器用 `HKDF-SHA256(ikm=签名, salt=着色器摘要,
info="WXGLiquidGlass.shader.v1|账号|设备")` 派生 AES-256 密钥，把着色器封成
`iv(16)‖AES-256-CBC 密文` 放进 `shader` 字段；`digest`/`sig`/签名报文格式都不变
（`sig` 仍是 X9.62 DER）。只有拿到对这个账号 + 这台设备的真签名才解得开，patch 掉
验签或自建服务器伪造票据都只会解出坏着色器。

> **成对升级**：这版 `worker.js` 下发的是封好的密文，只有带 FIX106 解封逻辑的新插件
> 读得懂。部署这版 Worker 时，三台测试机的插件也要一并换成新包，否则旧插件会把密文
> 当明文着色器去编译（玻璃坏掉）。旧的本地票据缓存会因摘要不符被自动丢弃并重新联网取。

### 复查间隔 `RECHECK_AFTER`

票据随包下发 `recheckAfter`（现 **2 天**，文件顶部一个常量，上限 7 天）。它决定**在线用户
多久联网核对一次 = 踢人多久生效**；离线仍按 `expiresAt`（7 天）。只影响在线核对频率与负载，
不碰签名有效期，服务器下发、改它不用重新编插件。Cloudflare 免费额度（约 10 万次/天）对这个
频率绰绰有余。

### 着色器水印（溯源）

每个账号下发的着色器都按 `账号 + 签名私钥` 把 8 个 Metal-only 的保护/边界常数（`WM_SITES`，二进制里没有参照）做了一点点肉眼无感的
确定性微扰。流落在外的 `.metal` 用 `plugin/tools/watermark_decode.mjs <leaked.metal>
<SIGN_PRIV> [账号…]` 逐个比对即可认出**是从哪个授权账号扒出去的**——插件通用、不用每人单独
分发，指纹在着色器数据里。诚实边界：拿到两个账号的着色器一 diff 能定位并抹掉水印（水印通病），
对本体量不值得上抗合谋编码；它拦的是"随手原样转发"这一大类。
