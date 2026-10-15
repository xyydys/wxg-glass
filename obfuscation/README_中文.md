# 混淆工程（Arkari）

目标：让破解者 `strings` 搜不到 **服务器地址 / 验签公钥**，也难定位、难 patch
掉 `WXGUnlock.m` / `WXGLicense.m` 里的联网验签逻辑。渲染热路径一律不混淆，保帧率。

关键认知：**着色器在服务器、不在二进制**。破解只剩两条路——共享有效票据、
或 patch 验签 + 自建服务器。混淆护的就是后者。

## 工具链镜像由公开 builder 库构建

Arkari 没有 Linux 预编译包，需从源码编 clang+lld（很重）。为省私库的免费额度和
私有镜像存储，这件事放在**公开仓库** [`xyydys/arkari-ios-toolchain`](https://github.com/xyydys/arkari-ios-toolchain)
里做（那里只有一个 Dockerfile，不含任何业务代码）：

1. 该库 push / 手动 Run `build-image` → 公开免费额度上编镜像（约 1.5~3 小时，一次性）。
2. 首次成功后，到 GitHub → 头像 → Packages → `arkari-ios-toolchain` → Package settings →
   可见性设为 **Public**。本私库即可免凭证、免存储额度地拉取。
3. 升级 Arkari：在那个库手动 Run，`arkari_ref` 填新分支（如 `llvm-21.x`）。

产物镜像：`ghcr.io/xyydys/arkari-ios-toolchain:latest`，本库 `build-obf` 作业直接拉。

## 每次出混淆包

GitHub → 本库 Actions → **build-deb** → Run workflow：

- `obfuscate` = **true**
- `obf_flags` = 这次开哪些混淆（见下方分步计划）
- `obf_files` = 只混淆哪些文件（默认 `Sources/WXGUnlock.m Sources/WXGLicense.m`）

产物在运行页 Artifacts 的 `WeChatLiquidGlass-deb-obf`。作业自带自检：混淆后 dylib
里应搜不到 `workers.dev` 明文。

> `obfuscate=false`（或普通 push / 打 tag）走 `build` 作业，普通 clang-18，不变。

## 分步上（强烈建议按这个顺序，每步真机验一版）

Arkari 的 flag 是 `-irobf-*` 系（不是经典 OLLVM 的 `-sobf/-fla/-sub`）。

| 步 | `obf_flags` | 加了什么 | 验什么 |
|---|---|---|---|
| 1 | `-mllvm -irobf -mllvm -irobf-cse` | 字符串加密（藏 endpoint/公钥） | 玻璃正常；dylib 搜不到 `workers.dev` |
| 2 | 上面 + `-mllvm -irobf-fla` | 控制流平坦化 | 授权/踢人正常；无明显掉帧 |
| 3 | 上面 + `-mllvm -irobf-indbr -mllvm -irobf-icall` | 间接跳转/调用 | 冷启、验签、复查都正常 |
| 4 | 上面 + `-mllvm -irobf-indgv -mllvm -irobf-cie` | 间接全局 + 整数常量加密 | 全流程回归 |

每步只在前一步真机通过后再加下一个 flag；一旦某步出问题，回退上一步单独排查。

## flag 速查

| flag | 作用 |
|---|---|
| `-irobf` | 启用框架（单独开不跑 pass） |
| `-irobf-cse` | C 字符串加密 ← 最高性价比 |
| `-irobf-fla` | 控制流平坦化 |
| `-irobf-indbr` | 间接跳转（加密目标） |
| `-irobf-icall` | 间接调用（加密目标地址） |
| `-irobf-indgv` | 间接全局变量引用 |
| `-irobf-cie` / `-irobf-cfe` | 整数 / 浮点常量加密 |
| `-level-icall=3` 等 | 强度 0–3 |

## 待验证 / 风险

- **iOS 代码生成**：Arkari 基于 LLVM 20，比项目原来的 clang-18 新；首版务必真机验。
  若遇链接/codegen 怪问题，可把 builder 库的 `arkari_ref` 降到更接近 18 的分支，或回退某个 flag。
- **arm64e**：当前只出 arm64。要 arm64e 需另验（ABI 在 iOS14/Xcode12 变过）。
- **帧率**：只混授权/联网文件，渲染路径不动；别把 `obf_files` 加进渲染文件。
