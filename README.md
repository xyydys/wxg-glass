# R9 底栏透镜测试版

版本号为 `0.4.120-test4fix135v3r9`。本次修复：（1）移除旧象限正负号翻转与 -15° 偏转，配合有限斜率平滑四分之一圆折射曲线，彻底消除左右不对称、左侧分层叠变及右上/左下收窄断点；（2）色散响应曲线放宽并拓宽至 `0.55×minHalf` 环域，配合底栏 7 层背景按色散比例柔化与 Metal 选中图标/文字 15-tap 折射后色散，色散拉满也能连续发光无叠层；（3）将 iOS 26 实测连续胶囊曲线（`WXGCapsule26`）纳入 Kyant 透镜 SDF 与轮廓网格环，并独立标定左右端头包裹折射参数，消除上下圆角被挤扁的感觉且让首尾端头 3/9 点外唇完整包圆。

# wxg-glass

单仓库（monorepo），三部分：

- **`plugin/`** — WeChat Liquid Glass 插件本体（iOS 越狱 Tweak，Theos 工程）。
  源码、测试、云端编译脚本都在这里。详见 `plugin/README_中文.md` 与交接说明
  `plugin/HANDOFF_中文.md`。
- **`server/`** — Cloudflare Worker 授权检测模块。`/v1/unlock` 收账号码、查
  授权名单（KV `wxg-list`，空时回退 `worker.js` 里的 `ALLOWLIST` 常量）、用 `env.SIGN_PRIV`
  （Cloudflare Secret）做 ECDSA P-256 签名，把着色器装进签名票据下发；`/v1/admin/*` 是管理接口
  （`ADMIN_TOKEN` 鉴权）。详见 `server/README.md`。
- **`admin/`** — 管理 App「授权台」（SwiftUI，iOS 26），远程增删名单、看核对记录与请求曲线。
  CI `.github/workflows/admin-ipa.yml` 在 macOS runner 出未签名 ipa，自签侧载。详见 `admin/README_中文.md`。

## 对接点

插件在 `plugin/Sources/WXGBuildProfile.h` 里配置服务器地址
（`WXG_UNLOCK_ENDPOINTS`）和验签公钥（`WXG_UNLOCK_PUBLIC_KEY`，公开信息）。
`plugin/Sources/WXGUnlock.m` 拿票据后用该公钥验签，离线优先缓存。

## 云端编译

CI 在根目录 `.github/workflows/build.yml`，**工作目录为 `plugin/`**。推 `main`、
打 `v*` 标签或手动 Run 即在 Linux runner 出 rootless `.deb`。混淆开关
（`obfuscate`）默认关，接好 Arkari / obfuscator-llvm 的 clang 后再手动开启，
只对 `Sources/WXGUnlock.m`、`Sources/WXGLicense.m` 生效（渲染热路径不混淆）。

## 注意 · Cloudflare 自动部署

Cloudflare Worker `xyylwc` 的 Workers Build 连接本仓库 `main`。worker 已从仓库
根目录挪到 `server/`，**合并到 `main` 之前，需要在 Cloudflare 控制台把该 Worker
构建的“根目录 / Root directory”设为 `server/`**，否则自动部署会在仓库根找不到
`wrangler.jsonc` 而失败。私钥 `SIGN_PRIV` 仍只在 Cloudflare 的 Secret 里，不在仓库。
