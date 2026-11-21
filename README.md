# R10 底栏透镜测试版

版本号为 `0.4.120-test4fix135v3r10`。本次基于真实 iOS 26.6 GlassProbe 2 探针快照（CAML/层级树/4pt 标定网格序列）重构底栏透镜四层光学架构：（1）彻底移除 R9 为消除分层而加在背景色散栈上的 `spectralSoft` 高斯模糊，底栏内部上下边框与透明间隙恢复 100% 锐利直边，改用 11 层无模糊 `CABackdropLayer` + `ringU^2.5` 陡峭边缘包络与折射内柯西色散，调节色散滑块可线性拉宽彩色色散范围而不再“越调越糊”；（2）抛弃 Kyant 18 pt 肥厚肉感四角颈部，改为与高系统普通液态玻璃一致的均匀周向 `ClearGlassView` 折射（`0.105×shortSide` 折射带 / `0.31×shortSide` 深度 + 椭圆化梯度），让底栏直边仅在 4 处短促交叉区自然折射出通透虚幻的粘连感，首尾端头 3/9 点同步自然包圆；（3）分离 `ContentLensingView` 选中图标/文字层（`0.20×shortSide` 折射带 + 15-tap 折射前色散），还原高系统图标与文字边缘对称的青蓝 + 金橙红双侧色散，并按单通道自适应优化轮廓网格（~5800 顶点）。

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
