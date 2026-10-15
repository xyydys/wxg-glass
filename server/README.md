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
