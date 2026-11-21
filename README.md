# R11 底栏纯玻璃独立测试版

版本号为 `0.4.120-test4fix135v3r11`。本次新增彻底隔离的「底栏纯玻璃测试」独立模块（默认开启，强制屏蔽所有旧版底栏、Kyant、离散底栏、简化透镜、旧透镜折射/色散/滤色等旧开关干扰）：（1）透镜本身直接作为普通液态玻璃（与「其余玻璃」同套 `WXGLensCurve` 折射曲线）+ 恢复分组栏同款的早期 3 层 RGB 色散；（2）彻底去除 45° 斜坡连接线（`shrinkFlat = 1`），无折射时透镜内底栏上下边框完全笔直平行，直接由「透镜内底栏高度 (pt)」控制间距，开启折射后仅由透镜自身折射自然弯曲四角；（3）底栏本体与边框直接复用「其余玻璃」，图标与标题围绕固定中心放大无反向位移；（4）修复修改形变参数（如把「落下后最扁高度」从 `0.82` 调到 `0.90`）时因硬截断和时长不匹配导致的顿挫：改用幅度自适应频率提速 + `tanh` 软膝（3 标签左移冻结时间从 `292 ms` 降至 `8 ms`，落定耗时随幅度成比例缩短）；（5）大幅优化渲染性能与连续快切流畅度：从 11 层 × 5800 顶点降至 3 层 RGB × 1090–1700 顶点，新增运动/静止两级网格精度、修复 `WXGMeshOpticsNear` 相对容差、扩容网格缓存至 400 条 / 24 MB、叠加裁剪区 scissor 优化，且未落下时连续切换 Tab 自动维持玻璃态不再回闪胶囊。

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
