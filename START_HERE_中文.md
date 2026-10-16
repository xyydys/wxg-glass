# 新会话起步说明（wxg-glass）

> 给接手的人 / 新的 Claude Code 会话：开头读这一份 + `plugin/VALIDATION.md` 顶部，几分钟即可上手。
> 当前 main：见 git log 最新提交。整个工程是 monorepo。

## 这是什么

微信「液态玻璃」插件（iOS 越狱 Tweak），给微信套一层玻璃视觉效果，自带授权校验（服务器发签名票据）。

```
plugin/   插件本体（Objective-C + Metal 着色器思路, Theos 风格, Linux/CI 编 .deb）
server/   Cloudflare Worker：/v1/unlock 发签名票据 + 着色器；/v1/admin/* 管理接口（名单/活动）
admin/    管理 App「授权台」（SwiftUI, iOS 26, XcodeGen）——远程增删名单、看活动/额度
obfuscation/  Arkari 混淆工具链说明
```

## 做 UI 新功能（顶栏/底栏/输入框/花哨模块）要动的文件

渲染 / 视图层都在 `plugin/Sources/`：

- `WXGHost.m` —— 宿主集成、overlay 安装、dock/导航/输入接管的总调度（最大的文件，入口在这）
- `WXGGlassView.m` —— 玻璃视图、Metal 管线、网格折射、rim/描边/glow
- `WXGSurface.m` / `WXGBackdrop*.{m,h}` —— backdrop 捕获与合成
- `WXGDecorations.m` —— 描边/装饰层
- `WXGInput.m` / `WXGNativeInput.m` / `WXGInput*Policy.h` —— 输入框相关
- `WXGDock*.{m,h}` —— 底栏/dock
- `WXGConfig.m` —— 所有可调参数（折射/色散/模糊/边宽/圆角/颜色…），加新开关从这里加
- `WXGBubbles.m` `WXGEdgeFade.m` `WXGCalmBackdrop.m` `WXGNativeIcons.m` —— 其它模块

## 渲染架构（别踩的坑，省得重新摸）

玻璃有**两条后端**，`renderMode` 默认 2（`WXGConfig.m`）：

1. **网格后端**（`CAMeshTransform`，本地）：横条/气泡等主体的**几何折射**靠它。`applyRefraction:` / `WXGBuildMeshTransform`。开关 `syncMeshRefraction`（默认开）。
2. **Metal 着色器后端**（服务器发的 SHADER，在 `server/worker.js` 的 `SHADER` 常量里）：veil / 模糊 / 色散场 / 底栏透镜 / 图标折射。编译入口 `WXGPrepareMetal`（`WXGGlassView.m`），uniform 结构 `WXGUniforms`（304 字节，19×float4）。

要点：
- **纯着色器改动**（改 `server/worker.js` 的 SHADER、不动 `WXGUniforms`、不动 `VER`）→ 纯服务器：推 main → Cloudflare 自动重部署 → 设备下次复查（≤1 天/清缓存即时）拿到。**不用重编插件、不用升 VER、不是成对升级。**
- 动了 `WXGUniforms` 结构 → 才需要重编插件 + 升 `VER`（成对升级）。
- 着色器里有 8 个水印位 `WM_SITES`（靠前后文字匹配），改 SHADER 别动到它们的上下文。

## 编译 / 部署

- **插件 .deb（CI）**：`.github/workflows/build.yml`。
  - 普通包：push main / 打 tag / 手动 Run 不勾 obfuscate。
  - **混淆包（对外发这个）**：Actions 手动 Run，勾 `obfuscate=true` → 产物 `WeChatLiquidGlass-deb-obf`，名字带 `_obf`。
  - 自测开关（手动 Run）：`force_authorized`（强制已授权, 复现"破解"态）、`mesh_off`（关网格折射, 只看纯着色器）。
- **着色器 / 名单（server）**：`server/` push main → Cloudflare Worker `xyylwc` 自动部署。名单在 KV，用 `admin/` 的 App 管。
- **管理 App ipa**：`.github/workflows/admin-ipa.yml`，macOS runner 出未签名 ipa，自签侧载。

## 验证只能真机看

这环境没法编译 ObjC / 渲染 Metal，所有可见效果**都要装到真机上肉眼验**。省时间的招：
- 能做成 `WXGConfig` 开关的变体，一个包里塞几个，一次安装对比（参考 `mesh_off`/`force_authorized` 的做法）。
- 纯着色器改动循环最快（改 worker → 重部署 → 清缓存看，不用装 deb）。
- 多轮迭代走 feature 分支，满意再合 main。

## 发版纪律 + 每次发版检查清单

见 `plugin/VALIDATION.md` 顶部「发版纪律与防破解姿态（B 方案）」：对外只发 `_obf`、勤升 `VER`、真机验「正版不误伤 + 帧率」。

## 授权 / 缓存（现状，一般不用动）

- 账号 = `SHA-256("WXGLiquidGlass.license.v1:" + wxid)`（小写 hex）。
- 票据缓存在 `Application Support/<不透明十六进制目录>/<不透明名>.dat`（FIX111，中性化过），AES-256-CBC，钥匙绑 account+device。
- `WXGPluginEnabled()` 含防篡改陷阱（FIX109）：自称已授权却无票/无着色器过 60s → 停渲染。改渲染门控时注意它。
