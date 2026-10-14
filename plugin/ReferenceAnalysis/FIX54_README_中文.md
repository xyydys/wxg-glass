# WeChat Liquid Glass · TEST4 FIX54

版本 `0.4.54-test4fix54`：**FIX46 去掉头像和置顶的改动，保留钱包顶部背景的去除**。版本号用 54，避免和原来的 FIX46 混淆。

- 透镜：与 FIX46 相同（内缩恢复、锯齿修复、底栏不做颜色分离）。
- 头像、置顶：与 FIX44 相同（FIX46 的改动已撤掉）。
- 钱包顶部：FIX47 的整页底色 + FIX50 的列表可画到导航栏下方。

逐文件来源见 `HANDOFF_中文.md`。换新对话时，把这个压缩包和 `HANDOFF_中文.md` 一起发过去即可。

## 安装

```bash
cd /var/mobile && unzip -o WeChatLiquidGlass_0_4_54_TEST4_FIX54_flat.zip -d WeChatLiquidGlass_FIX54 && cd WeChatLiquidGlass_FIX54 && chmod +x build.sh && ./build.sh rootless
```
