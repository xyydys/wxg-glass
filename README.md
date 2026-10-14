# wxg-glass · WeChat Liquid Glass 解锁服务器

私有仓库。Cloudflare 从这里自动部署（Workers Builds）。

- `worker.js`：服务器代码 + 授权名单（文件开头的 ALLOWLIST）+ 着色器。
- `wrangler.jsonc`：部署配置，`name` 要和 Cloudflare 里的 Worker 名字一致（现在是 xyylwc）。
- 私钥不在仓库里，在 Cloudflare 的 Settings → Variables and Secrets 里，名字 `SIGN_PRIV`（Secret）。

改名单或换着色器：改 `worker.js` 并提交，Cloudflare 会自动重新部署。

部署：Cloudflare Worker `xyylwc` 已连接本仓库 main 分支，每次推送自动部署。
