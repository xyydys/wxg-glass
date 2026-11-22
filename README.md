# R13 底栏独立测试 · R8 极光连续色散与圆角性能优化版

版本号为 `0.4.120-test4fix135v3r13`。在 R12 回归 R8 颈部折射骨架的基础上，精准修复真机实测的 4 项问题：（1）**消除右上角与左下角收窄近乎断开**：修复 R8 中带符号象限项 `c0.x * c0.y` 在右上/左下为负导致 `ringSign = 1 + 2.5 * quadrant` 穿过 `0.0` 形成死结、以及 iOS 26 边框在右上/左下消光的问题，改为四象限完全对称的 `|c0.x * c0.y|` 并抬高透镜右上/左下边框底亮；（2）**修复左右两端缺失连续圆角与上下端被挤扁**：开启 Kyant 胶囊网格环的 `WXGContinuousCorrection` 苹果连续圆角修正、在直线与圆弧交界前 16° 平滑起拱法线并采用 $C^2$ 连续颈部斜坡，且当透镜滑到底栏左右两端时自动补偿 `endWrap` 水平超伸量使内缩底栏端头与透镜外连续圆角保持同心等距（全周恒定 `9.5 pt` 间距，不再被压成 `13.9 pt` 偏心小圆）；（3）**将一圈一圈的阶梯色散升级为极光式连续色彩变换**：去除在 7 个偏移坐标重复求交造成的 7 道 `sd = 0` 无限斜率尖点环，改为单表面折射后 Cauchy + 三次平滑包络连续极光色散（严格限制在当前折射带 `hEff` 内，绝不污染内底栏直边），背景 7 层采用重叠高斯钟形光谱权重、Metal 图标/标题层外提折射求交并升级为 15 层连续极光积分；（4）**彻底恢复滑动与落定形变流畅度**：新增第 0 层通道无关几何与中心光线预计算（第 1..6 层直接复用，`7` 层网格完整构建耗时从 `16.24 ms / 7.19 ms` 骤降至 `1.92 ms / 0.95 ms`，提速 `8.5` 倍），配合 `WXGRim26RingLayer` `0.5 pt` 尺寸量化与滑动期容差防抖，彻底消除滑动与落定压扁时的主线程卡顿。

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
