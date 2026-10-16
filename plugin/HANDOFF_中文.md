# 交接说明（给新对话）· WeChat Liquid Glass TEST4 · 当前 FIX106 测试版 J（离散底栏）

## FIX106（测试版 A–J · 离散底栏 + 顶栏修复）

- 分支：`feature/discrete-dock`（含试过又撤回的 E/F/G 及其 revert）和 `feature/discrete-dock-clean`（只有保留的 A/B/C/D/H/I/J，两者代码树完全相同）。`master` = 基线 FIX105（4a8e3f8）。干净补丁 `git format-patch master..feature/discrete-dock-clean`。包版本 0.4.106-test4fix106j；设置页里的 `versionString` 和诊断 `version` 还写着 0.4.105（没改，只差显示）。
- 编译（Linux，不用完整 Theos）：先跑一次 `plugin/tools/setup_linux_toolchain.sh`（clang-18 + ld64.lld、ldid procursus、theos/sdks 稀疏拉 iOS 16.5 SDK 到 `/home/claude/toolchain`），再 `cd plugin && sh tools/build_deb_linux.sh "$PWD" dist/out.deb`（解析 Makefile，`-Werror`，出 deb + dylib）。测试：`Tests/*.c` 57 个，x86 上用 `-O2 -ffp-contract=off`（不加的话 LensEndRimTests / RestingSelectionTests 在 FMA 下会 abort，基线就这样）；`DockScriptTests.c` 带 `-Werror` 有个基线就有的 unused 变量警告。`tools/check_msl.py`、`tools/check_unused_statics.py` 通过。纯插件改动，没动着色器、`WXGUniforms`、`VER`、服务器。

### A–H 离散底栏（`WXGDockDiscrete.h` 纯 C + `Tests/DockDiscreteTests.c`，`WXGDemoBar.m`）

- 用户要的样子（参考 React DiscreteTabs）：选中项是宽胶囊（左图标，右侧上中文下英文标题），其余是只有图标的玻璃小球（可选连成一个胶囊：小球占位 + 间距相连，不漏标题）；切换用阻尼弹簧（参考 damping 20 / stiffness 230 / mass 1.2）；可选给选中项加原来的选中胶囊。
- A：每个胶囊一块 dock 玻璃（`WXGGlassView`，dockSurface），图标标题是 UIKit 视图叠在上面；所有 tab 的宽度跟同一个半隐式弹簧（`WXGSpring`），展开量之和恒为 1，整行不漂移，过冲时新 tab 鼓、旧 tab 挤；原来的整条玻璃休眠，搜索变形时交叉淡回整条；按下即切（按下时）、提交、角标照旧；`lensAtRest` 等弹簧停。`WXGGlassView.deferShapeField`（轮廓在动时用胶囊距离场）。宿主：`renderGlasses` / `allGlasses` / `propagateGlassSources` 接入采样、预热、内存释放。
- B：未读角标放在每个胶囊右上 45° 处（不再压宽位的图标标题）；图标 / 标题加大到 30 / 15 / 11 pt（各一个设置）；相连小球和展开同时开始衔接（约 0.16 s 内连成一体，恒速 0.35×响应），不是等展开完再连。
- C：相连时一串的图标向这串的中间均匀收拢（默认 0.22 格，设置），随弹簧滑动，角标跟着。
- D：冷启动后快速切 tab（常是“我”）的闪退：底栏图标图集在后台队列读微信 tab 图标的 `-[UIImage imageAsset]`，主线程同时为离散底栏读同一批图，那个调用会创建并注册 asset、不是线程安全（`-[UIImageAsset _unsafe_registerImage:withConfiguration:]` EXC_BAD_ACCESS）。现在图标只在主线程解析（`WXGDockTabArtwork`），队列只画。
- E（撤回）：软化各块边缘带 / 边框——用户看不出变化。“圆角鼓鼓的”核实过：轮廓就是连续圆角，观感来自边缘带 + iOS 27 边框参数。
- F（撤回）：缩小宽位图标——用户要的是左右布局占位，不是大小。G（撤回）：图标贴左、标题右侧居中——用户要 A 的居中布局。
- H：A 的居中块整体左移一个偏移（默认 10 pt，`dockDiscreteContentShift` 0–30，“宽位内容左移”；不超过左端圆角中心处的图标位置；小球不移），`WXGDiscreteContentShifted`。
- 设置（底栏 › 离散样式，`WXGConfig.m` 的 `WXGExtraSpecs`）：`dockDiscrete`(开) `dockDiscreteConnected` `dockDiscreteGather`(.22) `dockDiscretePill` `dockDiscreteGap`(8) `dockDiscreteWide`(2 格) `dockDiscreteBall`(.9) `dockDiscreteIconSize`(30) `dockDiscreteTitleSize`(15) `dockDiscreteSubtitleSize`(11) `dockDiscreteContentShift`(10) `dockDiscreteDamping`(.6) `dockDiscreteResponse`(.45 s) `dockDiscreteLight`。

### I / J 顶栏被吃（`WXGSettings.m`、`WXGHost.m`、`WXGEdgeFade.m`）

- 用户：原生顶部被吃掉一部分——聊天设置（单聊 / 群聊的聊天信息）每次都是，微信设置和从它进的插件页偶尔（没有标题和返回）。截图逐像素对比（关插件的同页）：设置是导航栏被隐藏（列表上移“导航栏底 − 安全区顶”= 38 pt）；聊天信息是导航栏和玻璃都在，但列表内容整整压进顶栏 100 pt。
- I（设置）：插件设置页出现时隐藏微信导航栏、离开时还回去（`WXGSettingsNavigationState`）。交互式返回（边缘滑、iOS 26 全屏滑）可以中途取消，UIKit 把导航栏恢复成隐藏、页面再出现一次；原来在 will-disappear 就丢掉“微信原来的状态”，再出现时把隐藏记成微信的，真正离开时交给微信一个隐藏的导航栏。现在状态保留到 pop 真正完成（coordinator completion、未取消）。兜底：`WXGSettingsReleaseStaleNavigation`（宿主每次 refresh：导航里已没有设置页还被拿着 → 还回导航栏和返回手势）；`WXGSettingsShowBarForPage`（设置 / 聊天信息出现时导航栏是隐藏的、栈里没有设置页、上面没有弹出 → 显示）。用户反馈 I 之后设置没再出现（本来就是偶发，继续观察）。
- I 还加了 `WXGCheckPageTop`（`WXGHost.m`）：设置 / 聊天信息被 push 后约 1 秒内查 4 次，每次写一行日志“顶部 #n：页面 列表 y/高 | 内边距 系统后/自身/行为 | 偏移 | 内容顶 | 导航栏 | 列表是第几个子视图（底板）”；列表因偏移压进顶栏（内边距本身对）时回到顶部。计数 `runtime.pageTopRepairs`。
- J（聊天信息，原因由 I 的日志确定）：聊天信息的 `WCTableView` 是 `contentInsetAdjustmentBehavior = never`、自身内边距 0、在页面视图里排第 2——第 1 个是渐隐的背景底板（`WXGEdgePlateView`，FIX66 起插在列表下面防黑边）。微信只给页面的**第一个子视图**留顶部内边距（同 UIKit 旧的自动内边距规则）；设置页自己设 88，不受影响。现在（非聊天页、列表本来排第一时）底板放在列表**后面**、`zPosition` 比列表低 1（`place:behind:`），列表仍是第一个、画面不变；底板仍是视图，玻璃采样照旧跳过它、照旧拆分页面（页面子图层全是视图，不能直接塞 CALayer，否则采样走整页慢路径）。聊天页不变。兜底：从未调整、内边距 0、从顶栏下面开始的列表，push 后补上导航栏需要的内边距（日志“补上顶部内边距”）。诊断 `edgeFade.pages[].backgroundPlate.behindList`、`listIndex`。
- 待用户确认：J 装机后聊天信息是否正常；若不正常，日志里“顶部 #0”那行能看出列表排第几、内边距是谁给的。


## FIX105（测试版 ABC · 未授权整块撤出图层）

- 用户：没授权就彻底不碰微信；注入了但没授权成功，微信任何地方都不受插件影响、也别“底栏跳成玻璃又闪回”。
- 结论先说清楚：真正没授权过的账号本来就不显示玻璃（效果都 gate 在 `WXGPluginEnabled()`）；用户看到的“闪玻璃又回原生”基本是**被踢但本地还有有效票据**的情况——冷启动凭缓存票据显示玻璃，后台联网收到 403 再撤。这属于离线优先授权的固有现象，没在这版消除。
- 这版做的是“零痕迹”：`WXGHost.m` refresh 的 `!available` 分支里，`!licensed` 时调 `detachOverlays`——把 `_overlay`、`_navigationOverlay` 从视图树 `removeFromSuperview`、`_launcher` 隐藏。`ensureOverlay` 在重新授权后把它们装回来（幂等）。
- `ensureOverlay` 里悬浮入口的显隐改成 `WXGSettingsEntryReady || 未授权` 才隐藏（原来只看 `WXGSettingsEntryReady`）：设置入口钩子失败时，未授权账号也不再露出悬浮按钮。
- `WXGInsertSettingsEntry` 开头加 `WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized` 时直接 return：未授权时微信「设置」里不插入插件入口行。它跟着 `reloadTableData` 跑，授权后下次微信重建该表格时才出现（不主动 reload 微信的设置页）。
- 风险/没做：每次刷新对未授权账号会 attach（ensureOverlay）又 detach，同一 runloop 无可见闪动，仅极小浪费；被踢账号的冷启动闪一下未处理（需求之外，且要联网优先才能免）。版本号 0.4.105。
- 验证：56 个 C 测试通过；arm64/arm64e、iOS 14、`-Werror` 0 诊断；deb 构建通过；dylib 无着色器文本。

## FIX104（测试版 ABC · 服务器决定复查间隔、冷启动不闪）

- 用户：从 FIX103 继续。①去掉 12 h 复查间隔，改由服务器在回答里下发；“重新检测”对已授权账号也要强制联网（`WXGUnlockStateFor` 的 Ready 分支没看 force）。目的是从名单删掉账号后很快生效。②冷启动先显示原生界面、过一下才跳成玻璃：本地票据要等后台读完再绕一圈主线程，着色器也等这之后才编译，第一次刷新时授权还是“正在验证”。
- 服务器（`xyydys/wxg-glass`，**改动还没推送**，见 `ServerPatch_FIX104/worker.js.diff`）：
  - `RECHECK_AFTER`（300）、`DENIED_RECHECK_AFTER`（300）；200 回答加 `recheckAfter`，403 加 `recheckAfter`。
  - 不进签名（签名内容不变，FIX103 插件照常验签）。node 跑过：200/403 都带字段，签名 OpenSSL 验证通过。
- `WXGUnlockPolicy.h`：
  - 去掉 `WXG_UNLOCK_REFRESH_AFTER`；`WXG_UNLOCK_RECHECK_DEFAULT` 600、`_MIN` 60、`_MAX` 7 天；
  - `WXGUnlockRecheckInterval(sent)`（无 / ≤0 / NaN → 默认，否则夹到 [60 s, 7 d]）、`WXGUnlockDeniedWait(sent)`（无 → 600，否则 [60 s, 1 d]）；
  - `WXGUnlockRefreshDue(now,expiresAt,fetchedAt,recheck)`：不可用、过了间隔、时钟比取票早了一个间隔以上、剩 < 3 天 → 到期。
- `WXGUnlock.m`：
  - 票据 `recheckAfter`（`WXGSecondsValue`：数字或数字字符串）；写进缓存 JSON；FIX103 的缓存没有 → 默认。
  - Ready 分支：`force || (!waiting && !waitOutdated && due)` 才请求（拿到票据后 60 s 冷却、退避照旧，force 无视）。
  - 403 的等待用 `deniedWait`。
  - `WXGChanged(host)`：拒绝、或者账号可用性和宿主上次看到的（`WXGEvalState`，在时间偏差更新之前取）不同、或者和回答前不同，才 `schedule` 宿主；通知总是发（设置页更新到期时间）。续期日志一小时最多一条。
  - 请求在 `WXGUnlockQueue` 上组装和发送（主线程只记 in-flight）。
  - 着色器：`WXGShaderText/Origin/Waiters` 改由 `os_unfair_lock` 保护，`WXGOfferShader` / `WXGUnlockWhenShaderReady` 任意线程可调（不再跳主线程）；已就绪时续期不再解码。
  - 冷启动：`WXGUnlockStart` 从宿主构造函数的 `install` 开头调用（原来在下一轮主队列里）。`WXGStartCacheLoad` 在 `WXGUnlockQueue` 上跑一个 `ENFORCE_QOS` USER_INITIATED 的块：算设备码（后台 identifierForVendor）→ 读缓存 → **在后台直接把最新票据的着色器交给 Metal** → 结果写进静态量 → 离开 `WXGCacheGroup` → 异步回主线程 `WXGAdoptCache(0)`（接手了就 `WXGChanged(YES)`）。
  - `WXGUnlockStateFor` 开头先 `WXGAdoptCache`：第一次最多等 0.3 s（`WXG_UNLOCK_LAUNCH_WAIT`），之后不等。没有设备码（重启后首次解锁前）时，等到主线程算出来再读一次，也等一次。
  - 诊断：`cacheReadAtMS`、`cacheReadMS`、`cacheWaitMS`、`ticket.recheckAfterSent`、`ticket.recheckEveryS`；`shaderReady/From` 加锁读。
  - 新导出 `WXGUnlockAsking(code)`。
- `WXGSettings.m`：首页“通用”第 4 张卡 `license`（“授权”，checkmark.seal），点按 → `recheckLicense`；副标题“有效至 M月d日 · 点按检测” / “正在联网检测…”。`_recheckPending`：回答到达（通知）时弹结果（授权有效 / 联网检测没有成功 / 插件需要更新）；页面不在屏幕上就记下来，`viewDidAppear` 再弹。状态变了照旧重建（被踢 → 未授权卡片）。
- `WXGHost.m`：`WXGUnlockStart()` 移到 `install` 开头；版本号 0.4.104。`WXGGlassView.m` 只改注释。
- 验证：56 个 C 测试；23 个 .m 用 iOS 16.5 SDK、arm64/arm64e、`-Werror` 通过；Linux 出 deb；dylib 无着色器文本。
- 独立审查（一轮）：修了“只纠正时间偏差的回答没通知宿主”“不在首页时结果提示丢失”“等待超时时 `cacheWaitMS` 没记”“版本不符的提示文字”，以及续期时重复解码、日志刷屏、设备码迟到时的一次跳变、连点。
- 没做 / 风险：
  - 服务器改动要推送才生效（之前插件用默认 10 分钟）；改小间隔后每台手机要等当前这轮间隔到了才拿到新值。
  - 后台线程调用 `identifierForVendor`（文档没写线程安全，业界常见）；构造函数里就开始读缓存，需要真机确认。
  - 关闭设置页的按钮不清 `_settings`（FIX103 之前就这样，没动）。
  - 每次复查都会重新下发 43 KB 着色器；如果嫌流量，可以让插件带上已有摘要、服务器摘要相同就不发着色器（签名本来就不含着色器字节）。


## FIX103（测试版 ABC · 联网解锁）

- 用户：服务器端已完成并测过（授权账号拿到着色器且签名对得上；不在名单的 403）。这一版做插件端：联网解锁、校验、本地缓存。
- 服务器：私有仓库 `xyydys/wxg-glass`（`worker.js` + `wrangler.jsonc`），推送 main 自动部署到 Cloudflare Worker `xyylwc`。
  - 地址 `https://xyylwc.kvgdth56kf.workers.dev`；`POST /v1/unlock`，body `{account, device, ts}`（插件另带 `ver:"1"`，服务器现在忽略）。
    - account：授权码，64 位小写十六进制；
    - device：≤128 字符；
    - ts：Unix 秒，和服务器相差 > 300 s 返回 400 `{"error":"stale"}`。
  - 200：`{ver, expiresAt, shader(base64), digest(sha256 hex), sig(base64 DER)}`。签名内容 `account|device|ver|expiresAt|digest`，有效期 7 天。
  - 403：`{"error":"not authorized"}`。GET 任意路径是自检（`pub` 是公钥）。
  - 私钥在 Worker 的 Secret `SIGN_PRIV`。
  - `ALLOWLIST` 是授权码列表；着色器在 `worker.js` 的 `SHADER`，和 FIX102 的 `WXGMetalSource` 逐字节相同（sha256 `93b80522…a88b6`，43429 字节）。
- 插件：
  - `WXGShaderSource.h` 不再被编进 dylib，只留给 `check_msl.py` 和模拟器用；
  - `WXGGlassView.m` 的 `WXGPrepareMetal` 改为在 `WXGUnlockWhenShaderReady` 回调里编译（全局队列）；在那之前所有玻璃视图都在等，和等编译一样。
- `WXGUnlock.m`（新）：
  - 状态只在主线程改；网络回答和磁盘在串行队列 `wxg.unlock` 上做，结果交回主线程（`WXGApplyAnswer`）。
  - 设备码：`SHA-256("WXGLiquidGlass.device.v1:" + identifierForVendor)`。
  - 校验（`WXGTicketProblem`，后台）：
    - 着色器 SHA-256 等于 digest；
    - `WXGUnlockSignedMessage`（`WXGUnlockPolicy.h`，纯 C）拼出签名内容；
    - `SecKeyCreateWithData`（原始 65 字节公钥）+ `SecKeyVerifySignature(kSecKeyAlgorithmECDSASignatureMessageX962SHA256)`；
    - `ver` 必须等于 `WXG_SHADER_VERSION`（"1"），否则是 Outdated。
  - 缓存：
    - 位置：`Library/Application Support/WeChatLiquidGlass/Unlock/<授权码>.wxgu`；
    - 格式：`WXGU1` + IV + AES-256-CBC(JSON)，密钥 `HMAC-SHA256(内置种子, "cache.v1|账号|设备")`；
    - 启动时 `WXGUnlockStart`（在宿主 start 之前）读入全部有效票据，用最新那张的着色器立刻编译；
    - 读不出 / 解不开的文件留着，解开后无效或过期的删掉。
  - 什么时候请求（`WXGUnlockPolicy.h` 有测试）：
    - 没有可用票据就请求；
    - 有票据时，拿到后 12 h 或剩 < 3 天续期；
    - 失败退避 5/15/60/300/900 s，有可用票据时至少 300 s；
    - 403 后 10 min、版本不符后 1 h 才再问；
    - 刚拿到票据 60 s 内不再问；
    - 退避和错误只属于最后一次回答的账号（`WXGAttemptAccount`），换账号不受影响；
    - stale：用响应的 `Date` 校正时间偏差，立即重试一次；
    - 只有正文是 `not authorized` 的 403 才算拒绝（删票据、删缓存、插件当场关闭），其他 403 当失败；
    - 时间回拨超过取票时间 1 天，票据不算数。
  - 设置页“重新检测”→ `WXGLicenseRecheckServer()`：无视退避立即请求；`buildContent` 里的 `WXGLicenseCurrentState(YES)` 不强制请求，避免“通知 → 重建 → 请求”循环。
  - 回答到达后发 `WXGLicenseChangedNotification` 并 `schedule` 宿主，设置首页自动重建。
- `WXGLicense.m`：本地名单 `WXG_LICENSED_ACCOUNT_HASHES` 删除。
  - 状态 = 账号（照旧，60 s / 安静时才读）+ `WXGUnlockStateFor(授权码)`（每秒最多算一次）。
  - 新状态 `WXGLicenseChecking` / `Unreachable` / `Outdated`（追加在枚举末尾）。
  - 诊断 `license.code`、`license.unlock`。
- `WXGBuildProfile.h`：`WXG_UNLOCK_ENDPOINTS`（按顺序试，失败换下一个）、`WXG_UNLOCK_PUBLIC_KEY`。Makefile 加 `Sources/WXGUnlock.m` 和 `Security`。
- 工具：
  - `tools/export_worker_shader.py <worker.js>`：从 `WXGShaderSource.h` 重写 `worker.js` 的 `SHADER`，对现有 `worker.js` 输出逐字节相同；
  - `tools/license_hash.py`：输出 `ALLOWLIST` 行；
  - `tools/build_deb_linux.sh`：Linux 出 deb，文件头里有工具链准备命令。
- 验证：
  - 56 个 C 测试；
  - 23 个 .m 用 iOS 16.5 SDK `-Werror` 检查通过；
  - 在 node 里运行 `worker.js` 原 handler（临时密钥）：200 / 403 / stale 都对，返回的票据用 OpenSSL 按插件同样步骤验证通过；
  - dylib 里没有着色器文本；
  - 独立审查一轮，修了 6 处：版本不符时请求不停、任何 403 都吊销、退避跨账号、过期提示文字、stale 退避、诊断里的版本号。又加固 3 处：拿到票据后 60 s 冷却、读不出的缓存不删、`Date` 头大小写。
- 没做 / 风险：
  - `workers.dev` 在国内可能连不上，建议绑自定义域名放到 `WXG_UNLOCK_ENDPOINTS` 最前；
  - 服务器不认请求里的 `ver`，换不兼容的着色器会让旧插件全部失效；
  - 没授权或还在验证时，设置页卡片也没有玻璃（没有着色器）；
  - 断网的被踢账号最多还能用 7 天。

## FIX102（测试版 ABC）

- 用户（附 FIX101 诊断）：“更慢了”。
- FIX101 诊断：
  - 7 次点按都等了空闲（`calmWaitMS` 65–210）；
  - `slowFrames` 显示长帧几乎只在按下后 11–29 ms 那一帧（切换帧，100–240 ms，已有暂停处理），之后 26–83 ms；
  - 第一次打开「通讯录」：refresh 67 ms，其中 `gateMS` 56.7。
- `gateMS` 来自 `WXGLicenseCurrentState(NO)`：每 3 s 调一次 `WXGReadAccount`（CContactMgr getSelfContact 等），50–95 ms。
  - 改为已知账号 60 s 一次，并且要宿主的 `WXGHostQuietForLicense`（底栏不跟手、透镜静止、切换后 > 2 s、无原生转场）同意，否则推迟。未知账号仍 0.5 s 一次；设置页 `recheck` 照旧。
  - 证据：`license` 里 `accountReads` / `accountReadLastMS` / `accountReadMaxMS` / `accountReadsPutOff`。
- 等空闲：新键 `dockTapCalmWaitOn`，默认 0（旧键 `dockTapWaitForCalm` 弃用）。
- 按下时请求改回 `dispatch_async`（去掉 0.03 s）。
- 追上：`WXGScriptScaleTime`（围绕 pivot 的时间仿射）、`WXGScriptCatchUp`（剩余部分缩短 pause × 0.6，最多 25%）。
  - 在 `tabSwitchForwardedFrom:` 的后移之后、`animationNow` 里丢失 > 10 ms 时调用；开关 `dockTapCatchUp`，默认 1。
  - `taps.catchUp` 是累计的 (1 − f)。
- 诊断：`WXGProfileHooks`。
  - `WXGHookVoid` 的 after 块和 `WXGPerfTimePluginWork`（气泡观察者、渐隐、平稳采样、装饰观察者）计时，扣掉其中嵌套的 tick / refresh / switch / hooks（`WXGProfileOursTotal`）；
  - 慢帧记录 `hooksMS`，`otherMS` 再减去它。
- 测试：`DockScriptTests` 加时间缩放逐点相等、追上的量与上限、微小停顿不变、pivot 处不跳。

## FIX101（测试版 ABC）

- 用户（附 FIX100 诊断）：底栏还是不稳定，明明有流畅的时候，但冷启动很卡、聊天返回后再切换也卡；一直维持最高标准就不难受。
- FIX100 诊断：12 次点按，计划约 470 ms，实际 539–1198 ms。
  - 切换本身已后移，卡的是之后 0.1–0.7 s 的慢帧，`afterSwitch` 的 `otherMS` 100–510。
  - 聊天返回后切到「微信」：`refresh` 99.8 ms，其中 `treeScanMS` 93.7（这一步含多段，原因未知，这次拆开计时）。
- 等空闲（`dockTapWaitForCalm`，默认 1）：
  - `tabSwitchForwardedFrom:` 之后在 tick 里每帧把脚本后移时钟走过的量（透镜原地不动，速度置 0），直到 `WXGScriptCalmWait`：连续 3 帧 ≤ max(1.6 × 帧长, 22 ms)；0.6 s 后只要求这一帧准时；1.2 s 封顶。
  - 结束时把时钟落后量也后移、时钟回到真实时间。
- 诊断：
  - `WXGProfileCommit`（1999999 / 2000001 两个观察者夹住 CA 的 commit），慢帧记录里 `commitMS`，`otherMS` 再减去它；
  - `taps` 加 `slowFrames`（[距按下 ms, 帧长 ms]，最多 10）和 `calmWaitMS`；
  - refresh 的 `routeSteps` 加 `gateMS`、`appearanceMS`、`routeTokenMS`，`treeScanMS` 只剩 WXGViews。
- 没做：透镜脱离主线程绘制（后台线程 Metal + CA 关键帧几何）。这是唯一能完全不受微信主线程影响的办法，但要大改 `WXGGlassView` 的布局路径，风险高。

## FIX100（测试版 ABC）

- 用户（附 FIX99 诊断）：
  - 不理解为什么原生微信是秒切，两者不应该这么冲突；
  - 头像每次启动进聊天都重新读取，明明上次读好了。
- FIX99 诊断：
  - 首次打开时微信切换：我 57 ms；发现 194 ms，`otherMS` 307；通讯录 15 ms，`refresh` 49 ms（`treeScanMS` 36），`otherMS` 111。
  - `taps`：点按 #3 实际 814 ms（计划 449），暂停 353 ms，因为落在上一次切换的 0.8 s 窗口里。
- 按下时（新键 `dockTapSwitchWhen` 0 按下时 / 1 松手时 / 2 快到位时 / 3 落下后，默认 0；旧 `dockTapSwitchMoment` ≠ 1 时 +1 搬过来）：
  - `WXGDemoBar`：跳到别的标签的按下（steps > 0.3）→ 0.03 s 后（手指还按着、`earlyIndex` 未变）调用 `tabSwitchRequest(index)`（返回 BOOL）→ 宿主 `dockRequestedTabAtTouchDown:`。
    - 宿主有挂起的切换时返回 NO，不吞前一个；否则 `forwardTabIndex`，返回是否已在该标签。`earlySent` 用这个返回值。
  - 松手：`switchedAtTouchDown`（`earlySent && earlyIndex==selectedIndex`，只在发 ValueChanged 时为真）→ `dockChanged:` 直接返回，不再转发（再转发等于点当前标签：回顶部 / 跳未读）。
    - 滑出底栏或系统取消：保留按下的标签（`keptEarly`、cancelTracking）。
  - `config.dockTapSwitchMoment` = max(0, when − 1)（松手后的时机）；`dockTapSwitchAtTouchDown`。
- 卡顿后接着走：
  - 宿主 `forwardTabIndex` 结束时（含 refresh）调用 `[_dockView tabSwitchForwardedFrom:forwardStart]`；
  - 运行中的脚本整体后移 `real − clock − since`（`WXGScriptShift`），时钟回到真实时间。卡多久都不跳。
  - 之后 0.8 s 的忙碌帧每步最多 1/30 s（`WXGScriptAfterSwitchCap`）；紧接的第一步 1/60。
- `noteVisitedTab:` 在 `dockChanged:` 和按下请求的开头记下当前标签（review：按下时的松手提前返回，启动时的标签就没记上）。
- 头像磁盘缓存：
  - `Caches/WeChatLiquidGlass/Avatars/<FNV-1a(userName)>.plist`（二进制 plist：user、url、image、saved）；
  - `keptAvatarFor:contact:` 先查内存再查磁盘，地址变了每次启动后台重下一次（`refresh:YES`，低优先级，下好后替换当前页 `state.image`，`state.user` 校验）；
  - `avatarImageForTitle:` 里它排在头像服务前面；写盘在后台队列，超过 300 个删最早的 60 个；诊断 `avatarDiskHits`。
- review 指出且已修：长卡顿 > 0.5 s 时跳（改成后移脚本）；按下记录靠 10 s 计时、取消后吞掉之后的点按（改成松手时由底栏标记）；宿主拒绝也算已发；启动标签没记访问（同上）。
- 没做：每次第一次进页面时插件自己的树扫描（通讯录 36 ms）还可以再省。

## FIX99（测试版 ABC）

- 用户：中间过程（变成透明透镜、再变回有色）反而比滑动占的时间多，不自然，要加快；冷启动后前几下为什么那么迟钝。
- 时序（`WXGDockScript.h`）：
  - `WXGScriptGlide` / `WXGScriptTravel` 加 `share`：升起和颜色共用一段（默认 0.40，原来升起 0.55、颜色 0.65）；
  - `WXGScriptDropLead` 0.40 → 0.70（到位前 70% 开始落）。
  - 默认：滑动 1.4 倍、落下 0.16 s。一个标签 0.35 s 到位、0.40 s 落下（到位后 0.048 s），颜色 0.14 s 褪完、0.24 s 开始回来。
- 配置：新键 `dockTapMoveScale`（1.4）、`dockTapDropTime`（0.16）、`dockTapLensShare`（0.40，0.15–0.9）。旧键 `dockTapDurationScale` / `dockTapDropDuration` 去掉了；载入时如果旧值不是 FIX98 默认值（1.5 / 0.26），就搬到新键。访问器名字没变。
- 冷启动：
  - FIX93/94 诊断里，第一次打开标签时 `afterSwitch` 主线程忙 0.3–1.3 s（`otherMS` 是微信自己的工作）。
  - 宿主 `visitedTabs`：启动后没显示过的标签按时机 2（等落下）挂起（`_pendingMoment`、`holdsTabSwitchAtMoment:`）。`forwardTabIndex` 标记已访问；`tabTrace.firstVisit`；前 4 次首次打开写日志（含微信切换 ms）。
  - 动画时钟：`WXGScriptClockAdvance(clock,lastReal,real,switchAt)`。只在宿主转发切换前后（`noteTabSwitchForwarding`，−0.02…+0.8 s）每步最多 1/60 s，最多落后 0.5 s；其它时候是真实时间（FIX98 对所有慢帧都压到 1/24 s，冷启动时慢动作）。
  - 图标重扫（0.45 / 0.9 s）在脚本运行时每 0.1 s 推迟，最多 2 s。
  - 诊断 `taps`：前 12 次（since、kind、to、landed、plannedMS、actualMS、longestFrameMS、switchAtMS、pausedMS），前 6 次写日志。`WXGSecondsSinceLoad()`。
- 没做：预先加载微信的标签页（可能有副作用；要看真机的 `taps` 和首次打开日志再决定）。透镜折射网格冷缓存：每个新尺寸 / 按压档位第一次要建，这里量约 0.4 ms 一个，真机估计 1 ms 左右，不是主要原因。

## FIX98（测试版 ABC）

- 用户：点按切换太快；选中胶囊色应该在移动中渐变成透明透镜、落下时再渐变回来，现在一按就透明、一落就有色，很不舒服、像卡顿；页面切换的瞬间动画未必要完成，动画慢一点自然一点不影响。
- 原因：`WXGRestingSelectionWeight` 在按压 0–0.12 内从 1 到 0；触摸时按压直接 0.10、落下最后约 30 ms 才低于 0.12。
- `WXGDockScript.h`：
  - 新 `select` 轨道：滑动 s0 → 0（65%）；落下段是 `dropStart..land` 的“尾巴”，压按从 dropStart 时的值降到 0（.45,0,.35,1），颜色从当时的值回到 1（.42,0,.58,1）。
  - `WXGScriptPressValue` / `WXGScriptSelectValue` 取代直接读轨道；滑动曲线一直保留到 dropStart。
  - `WXGScriptDrop(s,now,drop)`：dropStart = max(now, planEnd − 0.4·drop)，land = max(dropStart + drop, now + 0.1)。
  - `WXGScriptTravel(…,s0,…,scale,drop)`：时长 × scale；升起时颜色同样褪；dropStart 同上（且不早于升到顶 + 0.02 s）。
  - `WXGScriptHoldsSwitch(s,now,moment)`：0 不等，1 到移动的 80%，2 到 land（FIX95）。手指还按着滑动时总是等。
  - `WXGScriptClockStep`：动画时钟每步最多 1/24 s（`WXGScriptClockCap`，高于 30 fps 的一帧）。
- `WXGDemoBar.m`：
  - `animationNow`：有脚本时用上面的时钟，没有脚本时回到真实时间；记 `clockStalls` / `clockLostMS`。
  - 滑动从按下前的按压和颜色开始（不受按下时 0.10 的影响）；`_jumpPlanEnd` = 脚本的 planEnd，脚本结束时把时钟落后量加回去。
  - `_selectionShown`：有脚本时取脚本颜色，否则按压映射 + `_selectionCarry`（脚本结束时的差值，τ 0.08 s 衰减），所以任何打断都连续。
  - 传给 `WXGGlassView.selectionWeight`（-1 = 按压映射）→ uniform `extra2.w = 1 + weight` → 着色器 `wxgSelectionWeight`（镜内层叠和读回路径）。`_fallbackLens` 同样。
- `WXGLensOptics.h`：`WXGRestingSelectionWeight` 改成按压 0.05–0.45（拖动、按住、拖动松手）。
- `WXGHost.m`：等待最多 1.5 s；同一个标签在挂起时又点一次、而这次落下不等（时机 1、没有移动）：切换后补发第二次点按（`sendSecondTapToIndex:`，review 发现的）。
- 配置：`dockTapDurationScale`（0.6–3，默认 1.5）、`dockTapDropDuration`（0.08–0.8 s，默认 0.26）、`dockTapSwitchMoment`（0–2，默认 1）；设置在“底栏 → 图标与动画”。
- 测试：`DockScriptTests.c` 重写（颜色轨道、无跳变、时长、落下、旅行、三种时机、时钟、120 Hz 逐帧 + 0.18 s 卡顿）；`RestingSelectionTests.c` 改成 0.05–0.45。
- 没改：`dockTapSimpleTravel` 的系统渲染动画（颜色线性 1 − p/0.9），它交接给逐帧透镜时颜色仍可能差一截（FIX98 后最多约 0.5，以前约 0.87）。持续低于 24 fps 时动画会变慢（时钟上限）。

## FIX97（测试版 ABC）

- 用户（附 iOS 26“文件”App 底栏截图）：“基本没问题了”，但透镜内部别的地方也要有一定的色散，不只两端高折射范围（那里要较强），比如内部那个括号边界（上下深色槽的边）。
- 实现（只在同步渲染模式的透镜 pass，`WXGGlass.metal` 的 `u.sync.x>1.5` 分支）：
  - FIX46…FIX96 内联的“透镜里的底栏”（弯曲、FIX94 放大、inset、屏幕距离 dd）抽成 `wxgLensBar(p,…)`，可以在偏移点再问一次；层叠（veil、描边、第二道高光、静止选中）抽成 `wxgLensBarLayers(dd,…)`。`extra2` 为 0 时和 FIX96 逐像素一样（模拟器比对过）。
  - 分色向量 `split = dome × extra2.x × press + 透镜法线 × extra2.y × 透镜色散 × 1.55 × press × rim`：dome = (p − 透镜中心) / 半尺寸（圆顶：中心 0、边缘 1）；rim = 底栏折射带内的深度 × 折射带宽 / 两端宽（两端 1，上下按比例变小）。
  - `wxgLensBarSpectrum`：dd 在 p+split（红）、p、p−split（蓝）各算一次，按 t∈[−1,1] 二次插值，7 个波长逐个合成层叠，红绿蓝用峰在 t=1/0/−1 的三角权重（和为 2/3/2）。每个波长的柔化 `wide=max(soft,|a1|·.25+|a2|·.4)` 盖住步长，没有条纹。
  - 只取三个点的第一版：描边亮线裂成红、绿、蓝三条线，不要。
  - CA 只用一个 alpha 合成：取三通道最大的 alpha，再把 `extra2.z ×（alpha_max − alpha_c）` 补回 rgb（extra2.z = 假定的页面亮度：深色 0、浅色 1）。不补的话白底上色带低到 −0.8（review 发现的）。
  - 透镜画布是整个视图：只在 `lens.distance<1` 时算光谱（性能）。
- 配置：`lensBarDispersionOn`（b，默认 1）、`lensBarDispersion`（0–2 pt，默认 0.6）、`lensBarDispersionNearRim`（0–1，默认 0.35）；设置 → 折射强度和色散 → 底栏，“镜内底栏色散”一组。`WXGUniforms` 加 `extra2`（304 字节，`_Static_assert`）。
- 检查：`tools/shader_sim/check_bar_dispersion.py`（黑底 / 白底 × 4 个位置）：未按下与关闭相同、离边缘远不变、有彩边、每通道均值变化 < 0.004、每通道在关闭图 4 pt 邻域的范围内（±0.06）、亮度峰 / 谷数不多于关闭时。模拟器加了 `page`、`tint`、`pageGuess` 参数，默认值输出和以前一样。
- 没做：页面是图片或深色壁纸（浅色模式）时，补回的页面亮度是猜的，彩边那一两像素会略亮。

## FIX96（测试版 ABC）

- 用户：透镜和选中胶囊都是“安卓圆角”（FIX95 改成了 circular），很丑；他认为之前的问题也是圆形圆角造成的。
- 结论：之前的问题确实是 CA 的连续圆角和着色器的圆形胶囊对不上（见 FIX95 的测量）。这一版两边都用连续圆角。
- 测量：
  - FIX93 截图（`d0a2d038`）里透镜外框和底栏左端外框亮线的亚像素质心（列 / 行按法线方向选，窗口 ±2 / ±4 px）；
  - 以各自端头圆心为极点，φ 为离开直边法线的角度；
  - 透镜（长宽比 1.26）和底栏（5.3）的 ρ/R − 圆形胶囊在 −16°…28° 内吻合到 0.002 R，说明曲线与尺寸、长宽比无关（长宽比 ≥ 约 1.25）；
  - 数据和拟合脚本在 `ReferenceAnalysis/FIX96_continuous_corner/`。
- 实现：
  - `WXGOptics.h`：`WXGContinuousDeviation(phi)`（−24°…90° 的 5 项正弦级数，rms 0.0016 R）、`WXGContinuousCorrection(x,y,w,h)`；
  - `WXGCapsuleOpticalField` 的 distance 减去修正，法线仍用圆形的；
  - 长宽比 1.15→1.25 从圆形过渡到连续（圆形按钮不变）；端头圆心 0.15–0.40 R 内淡出；直边上 φ < −24° 提前返回。
  - 所有用胶囊场的地方（着色器 `wxgShape`、`WXGMeshRefraction.h`、`WXGTravelVeil.h`、`WXGSharpRingAlpha`）自动一致。
  - 轮廓网格：`WXGMeshContourPointC` 把环沿圆形法线外移修正量（环深度 = 场深度）；`WXGMeshContour` 在胶囊直边两端 0.40 R 内每 0.1 R 采样（连续曲线比圆形早离开直边）。底栏网格顶点 1656 → 1908，透镜 598 → 754，最大误差 0.20 → 0.24 pt。
  - 恢复 continuous：`_lensClip`、`_lensRim`、`_fallbackLens`、`_travelLens`。
- 测试：
  - 新 `ContinuousCornerTests.c`：与测量值的最大偏差 0.0011 R、圆形回退、交界处与 42° 的方向、边界、无跳变、对称、竖向胶囊；
  - `OpticsTests`、`RollbackOpticsTests` 的圆形轮廓断言改为连续轮廓。
- 没做：圆形按钮（CA continuous 下的圆是微方的圆）和圆角矩形不在这次的测量范围内。

## FIX95（测试版 ABC）

- 用户对 FIX94：
  - “底栏透镜改成啥了”，FIX94 的贴边放大不要；
  - 他说的透镜边框应该从圆角往上下最外侧一路变窄（图一 iOS 26），现在是圆角处最窄、上下又变宽（图二、图三，就是 FIX93 的截图）；
  - 下拉修好了；
  - 头像这次读到没有？头像大小、上下位置、描边宽度和颜色要能自定义；
  - 点按快速切换呼出的不是完整透镜，只是形状，透镜和里面都没效果。他原本的设计是：点按只是按设计好的速度和过程量自己走，不该改成别的东西。
- 透镜边框：
  - 量 FIX93 截图（`d0a2d038`）每列外框亮线和透镜内“底栏边缘亮线”的位置：正上方相距约 4 px，±11–19 pt 处 2–3 px，再往外变宽。
  - 外框按列下沉比圆形胶囊多约 1.5 px（±12–18 pt），说明系统 continuous 圆角在直边转圆弧处比圆形往里收约 0.5 pt。着色器按圆形胶囊算（`WXGCapsuleOpticalField`），亮线跟着圆形走，所以在那一段离 CA 外框最近。
  - 修改：`_lensClip` / `_lensRim` 的 `cornerCurve` 改为 circular（`WXGGlassView` init）。`_fallbackLens`、`_travelLens` 同样改。
  - 新工具 `tools/shader_sim/`：把嵌入的着色器当 C++ 在 CPU 上跑（`stub/metal_stdlib` 带像素纹理，`fwidth` 两遍模拟），按用户参数出图。`python3 tools/shader_sim/build.py <out> params.txt…`。圆形外框下，正上方相距 4 px，往外 5、6、7、8 px，单调。
  - 试过在着色器里加一圈“亮环”（style.w），模拟下和自然边界差不多，撤掉了。
  - FIX94 的贴边放大：键改为 `lensBarFollowOn`（默认 0）。旧键 `lensBarFollow` 不再读，所以 FIX94 自动打开的也关了。`WXGLensBarZoom` 和测试保留。
- 点按切换（推翻了“已经定下来的”里“点按在渲染服务里滑动”这一条，用户要求）：
  - `WXGDockScript.h`（纯 C，`Tests/DockScriptTests.c`）。按下别的标签：`WXGScriptGlide`（FIX43 时长、贝塞尔 .40/0/.30/1，前 55% 升到 max(.9,p0)，之后保持）。
  - 松手在该标签：`WXGScriptDrop`（land = max(now+.1, planEnd)，land−.09 起落下，land+.05 结束）。拖到别的标签松手：`WXGScriptTravel`（同 FIX43/FIX88 的 beginTravelToIndex 关键帧）。
  - `-tick:` 里 script 生效时直接设 `_lensX/_velocityX/_press/_pressVelocity`，弹簧不走，弹性形变照常用速度。按住过 planEnd+.02 → 结束 script、`_targetPress=1`（跟手）。拖动超过 10 pt → 结束 script（保留速度）。
  - 新触摸打断落下时记 `_resumeIndex`，在同一标签松手再落一次（`beginTravelToIndex`，无位移时只落下）。
  - 减弱动态效果、或打开 `dockTapSimpleTravel`（“点按时用简化透镜”）时不用 script：前者走 FIX42 主线程补间，后者走原渲染服务 travel，且都立即切换。
  - 宿主 `dockChanged`：`holdsTabSwitch`（script 第 1 段，或第 2 段且未到 land）时挂起，`pendingUntilLanded`。`firePendingTabIfReady`（两种渲染分支的 tick 里都调用）要等 `!holdsTabSwitch && !tracking`，再按 dockSwitchTiming 判断，最多等 1 s。
  - 挂起期间点回微信当前标签 → 取消挂起，什么都不转发。同一标签再点一次 → `pendingRetaps=1`，切换后下一轮 runloop 再转发一次点按。
  - 日志“底栏：透镜落下后切换到第 N 个标签（松手后等了 xx ms）”（前 6 次）。诊断里有 `landedSwitches`，dockInteraction 里有 `tapAnimation`、`scriptGlides/Drops/Travels/Drags`、`scripted`。
- 头像：
  - FIX94 诊断：`avatarStatus` 为“找到了聊天联系人，但头像服务和消息里都没读到图片”，`avatarLookups` 9 次。
  - 新路径 `downloadedAvatarFor:contact:started:`：读联系人的 `m_nsHeadHDImgUrl` / `m_nsHeadImgUrl`，http 先改 https，`NSURLSession.sharedSession` 下载，`NSCache` 按 userName 缓存，失败最多再试一次。下载中 3 s 内不取消息列表的图（`downloadWaitUntil`）。下完若屏幕上是消息列表的图，会刷新换掉。
  - 消息列表：表格或集合视图；类名含 HeadImage / HeadImg / HeadView / Avatar / avatar / headImage；`WXGAvatarImageOfLayer` 找子图层的 CGImage。
  - 探测（每个聊天页第一次，`avatarProbe`）：页面类、联系人类、单聊 / 群聊、三个头像字段（只记有无和域名）、MMServiceCenter / MMContext / MMHeadImageMgr 是否存在、管理器类名和带 head / avatar 的方法名（≤40）、消息列表类、可见 cell 数、左侧方形视图（类名、大小、是否名称匹配、有无图）。`avatarDownload` 为下载状态。
  - 设置（WXGExtraSpecs）：`avatarSize` 60（32–88）、`avatarOffsetY` 0（−24–24）、`avatarBorderWidth` 1.5（0–4）、`avatarBorderHex` #80808052、`avatarDarkBorderHex` #9E9E9E6B。在“基本设置 → 头像模式”。
  - 头像按自己的中心缩放（中心 = 原 60 pt 时的中心 + 偏移），标题胶囊位置按 60 pt 不变。描边 `borderWidth` 不超过头像宽的 1/4。

## FIX94（测试版 ABC）

- 用户：首页下拉仍被压；透镜黑边在圆角处最细（应在上下两端最细）；问是否读到对方头像；头像模式改成无玻璃的对方头像。
- 首页下拉：
  - FIX93 的 `homePullHosts`：下拉时 MainFrameLeftBarView 与 NewMainFrameRightTopMenuBtn 都在 `MainFrameTableView → WAMainFrameTopHeaderView → WAMainFrameTaskBarView(→ WAMainFrameTaskBarCloseArea)` 里。原生按钮进了列表，就落在 WXGEdgeFade 的列表遮罩和顶部模糊带下面。
  - `WXGIntegrationHost followHomeTopBar`（tick 里，紧跟 `updateHomePullFloor`）：首页时找 `_scrollViews` 里的 MainFrameTableView，`topBarViewsInList:` 查 `homeGestureHosts` 和 `_buttons` 的 motionHost/original 是否在它里面。
  - 视图本身及到列表之间的父视图 hidden 或 alpha < .01 的不算（`WXGShownInside`；conceal 只换遮罩，不改 alpha / hidden）。
  - 只在 `homePull > .5 || homePanel > 0` 时，以及之后 1 s 内生效（`homeTopBarPulledAt`），存 `homeTopBarInList` / `homeTopBarList` / `homeTopBarPage`（weak）。变化时调 `WXGEdgeFadeSyncController(_route.leaf)`，离开首页时也同步原来那个首页。
  - 静止时仍在列表里，则 `homeTopBarInListAtRest` = YES（诊断）。日志前 6 次。
  - `WXGHomeTopBarInList(list)`（WXGIntegration.h）= `homeTopBarInList && homeTopBarList == list`。
  - WXGEdgeFade：`maskTopSolid`（遮罩里覆盖顶部渐隐区 `_fadeTop+1` 的白层）在 `topBarInList` 时 opacity 1。顶部模糊带的 cover = `topBarInList ? 1 : panel`（半径 × (1 − cover)，> .99 隐藏）。底部不变。
- 透镜里的底栏贴边（`WXGLensBarZoom`，WXGLensOptics.h，Metal 与 C 共用）：
  - 镜内每一列，底栏竖直方向放大 z，让底栏边缘落在“透镜该列边缘 − margin × 该点折射带宽 `WXGLensEdgeWidth`”处。
  - x 先夹到底栏直段（端帽取直段末端的比例）。端帽列再取 `WXGLensBarColumnZoom` 在真实 x 处允许的比例（该列底栏高 hb、切线、inset 的竖直分量）中较小的一个，透镜一端压在端帽上时也不越过边缘（审查发现的问题，旧做法越过 4–8 pt）。z 用 softplus 下限 1（k = (z − 1)/.04）。
  - 着色器的 `dd` 除以 `length(float2(s.nx, s.ny/zf))`（只在竖直方向放大，端帽侧面的描边不再变细），zf = 1 时与原来完全相同。
  - 只有 render-server 分支有（readback / hybrid 没有），设置说明里写了“只在同步渲染模式下生效”。
  - Metal（render-server 透镜 pass）：`u.extra.w` > 0 时 `bend = wxgBasePoint(float2(p.x, barMid.y + (p.y − barMid.y)/zf))`，`dd` 也乘 zf。`u.extra.w` = `_dockSurface && lensBarFollow ? lensBarMargin : 0`。
  - CPU 点按动画轮廓：`WXGTravelVeilOutline(..., const WXGLensFollow *)`，WXGDemoBar `newTravelVeilPathForLens` 传 side（随 press 插值）/ ratio / sharpness / margin。
  - 配置：`lensBarFollow`（b，默认 1）、`lensBarMargin`（.5，.2–1）。已有存档没有这个键时 = `lensTopEdgeRatio < .99`。设置在“透镜（按压时）”。
  - 测试 `Tests/LensBarZoomTests.c`。
  - 早期模拟在 scratchpad `lens2/sim7.py`（x 夹住的版本）。
- 头像：
  - `a.plain = YES`（无玻璃 / fallback）。WXGSurface `layoutSubviews` 里 avatar && plain：iconView = 整个 materialRect，AspectFill，圆角 = h/2（circular）。
  - `styleAvatarRing`：borderWidth 1.5，浅色 white .5 α .32，深色 white .62 α .42。trait 变化时经 `resolveSourceImage` 重设。
  - buildNavigation 里放好标题胶囊后，若 a 在 t 下面就 `insertSubview:a aboveSubview:t`。
  - 占位图：渲染的 120 pt 灰底（white .78）+ 白色 person.fill（非模板）。
  - FIX93 诊断里 avatarTitle 关着（avatarLookups 0），读头像的路径没走到，尚未验证。

## FIX93（测试版 ABC）

- 用户：FIX92 没解决；发来 17:09 的参数导出，要作为默认值，但不强制覆盖别人已装旧版的设置。
- 默认值：`tools/bake_defaults.py` 写入 `WXGBuildProfile.h` 的 `WXG_DEFAULT_OPTICS_JSON`。参数 253/253 项、开关 12、ui 1，与导出逐项比对一致（sizeScale 四舍五入到 6 位）。
  - 加载顺序：`loadDefaults`（内置值 + 这份）→ 旧 suite → `optics.test4` 存档覆盖。存档是全量键，所以已有存档的手机不变。
  - 存档里没有的表键（新版本新加的），从它自己的来源键推出，不用这份。开关 / 卡片圆角只在没有存档时用这份。
- 顶栏：
  - FIX92 诊断：`navigationRaises` = 0；外层只记到常驻的 `MinimizeBaseView`（iConsoleWindow 里，全屏，第一次进首页时就有，与下拉无关）。层级没被盖。
  - 新判断：`followNativePresentation` 把原生宿主链的 opacity 乘到玻璃上，下拉时微信淡出自己的标题栏，玻璃跟着变淡，透出列表的渐隐 / 模糊。
  - 修改：`WXGSurface.alphaFloor`（以及记录用的 `nativeAlpha` / `nativeHidden`）。tick 里先 `updateHomePullFloor`：首页最大列表下拉量 `homePull` > 1 时，除 nativeGesture 以外的按钮 floor = 1 − homePanel；离开的按钮 floor 置 0。然后才 `followNativePresentation`，floor 也会顶掉 hidden。
  - 左按钮（nativeGesture，挂在 MainFrameLeftBarView 里）继承原生透明度，没处理。
  - 诊断：`followHomePull` 在下拉 / 面板打开时每 0.1 s 记一条，留最近 60 条（`homePullTrace`）。每条有 t、pull、panel、导航栏 alpha / hidden / y，以及每个按钮的 alpha、原生链 alpha、hidden、y、宿主 y。`homePullHosts` 是宿主的父链类名。原生链 alpha < 0.95 时记日志（前 6 次）。
  - 外层扫描改为每个视图 / 图层只记一次、继续往下扫，并加了不属于视图的 CALayer。

## FIX92（测试版 ABC）

- 用户：首页下拉想进顶部小程序时，标题和左右按钮的图层临时被压到模糊和渐隐下面，延迟后恢复；要顶部元素的优先级比模糊高。
- 判断：`_navigationOverlay` 在 `_route.nav.view` 里，只在 `ensureOverlay`（每次 refresh）时 `bringSubviewToFront`。下拉进小程序面板时，有视图（连同首页列表和它的渐隐遮罩、模糊带）排到了它上面，直到下一次 refresh。没有拿到当时的视图层级，是从“延迟后恢复”推断的。
- 修改：
  - overlay 的 `layer.zPosition = 10000`（同级里总在最上面画）；
  - tick 里 `keepNavigationOnTop`：每帧检查 overlay 是不是容器的最后一个子视图，不是就提回去（计数 `navigationRaises`，前 12 次记下盖上来的类）。
  - 再往外逐级检查：容器之外排在 overlay 所在分支上面、可见、非插件、宽度过半、在顶部 120 pt 内的视图，记日志和 `navigationCovers` / `lastNavigationCover`，同一个视图只记一次。这一层只记录，不改，封面 / 原生转场时不查。
- 若用户还看到，按 `lastNavigationCover` 记下的那一层再处理（可能要把 overlay 临时挪到更高的容器）。

## FIX91（测试版 ABC）

- 用户：底栏标题的字又粗又大（微信原本的太细太小，但现在的也太粗太大）。
- 原因：`WXGRenderDockIcons` 固定 `systemFontOfSize:10.5`，未选中 Medium、选中 Semibold；选中图集在透镜里再按 lensZoom 放大。
- 修改：表里 `dockTitleSize`（10，8–13）、`dockTitleWeight`（2，0–4：Light −.4 / Regular 0 / Medium .23 / Semibold .3 / Bold .4）、`dockTitleBolderSelected`（0）。`WXGIconJob.titleSize / titleWeight / bolderSelected`；`iconLayoutKey` 带上这三项，变了就重画图集。设置：底栏“图标与文字”分组加文字大小（滑块）、文字粗细（`WXGChoice3` 分段）、选中的文字加粗一档（开关）。
- 诊断：`WXGNativeIcons` 读到微信标题 UILabel 时记下字体名、字号和 `UIFontWeightTrait`，写在 `nativeIconSummary` 第一行（“微信标题字体 …”），以后可按它定默认值。

## FIX90（测试版 ABC）

- 用户：FIX89 可以了。问导出参数是不是全局的（是的话下次备份一份参数）；要能调底栏图标和标题之间的距离，以及整体上下位置（微信原来的不适合悬浮底栏）。
- 导出：`WXGSharePayload` 本来就是全部 `parameterValues`（整张表，含 FIX89 两道高光和本次的键）+ `WXGPreferences`（除 enabled / homeSearch / perfMonitor / perfHUD）+ 卡片圆角和强调色；没有改代码。用户说下次会备份一份发来，可以用 `tools/bake_defaults.py` 写成默认值。
- 图标位置：表里 `dockIconTitleGap`（5，0–16）、`dockIconOffset`（0，−12–12，+ 向下）。`WXGIconJob.iconShift / titleShift`：icon 中心 midY−8+iconShift，标题顶 midY+10+titleShift；iconShift = offset − (gap−5)/2，titleShift = offset + (gap−5)/2（gap 是 26 pt 图标框下沿到标题顶）。`applyConfig` 比较 `iconLayoutKey`，变了就 `rebuildIcons` + `layoutBadges`；角标 y 加 iconShift。设置：底栏页新分组“图标与文字”。

## FIX89（测试版 ABC）

- **用户对 FIX88 的反馈**（附 iOS 27 浅色 / 深色两组设置截图和 FIX88 诊断）：
  1. 两个方向的高光颜色本来就不一样，只加“另一方向高光”没意义。要的是两道各自颜色、各自角度的渐隐描边同时存在，比如截图里浅色那组（黑、90°）和深色那组（白、0°）一起画；不用分深浅色，也不要左下 / 右上渐隐。
  2. 在别的标签上长按能呼出透镜了，但按不久就弹回原标签，而不是一直跟着手指、松手切换。
- **iOS 27 两道高光**：
  - `WXGRimGlowLevel` 回到 FIX87 的单道形式（去掉 cross），`Tests/RimGlowTests.c` 也回到 FIX87。
  - `WXGRimGlowShape` 加颜色 red / green / blue / alpha（alpha = 颜色 alpha × 不透明度），去掉 cross；`WXGRimGlowCount` = 2。
  - `rimGlowForScope:index:`：0 用原浅色键（Rim27*），1 用原深色键（darkRim27* / dockDarkRim27* / bubbleDarkRim27*），与外观无关。新键 darkRim27Sharpness、dockDarkRim27Sharpness、bubbleDarkRim27Sharpness 继承原来共用的 Sharpness。删掉 Rim27Cross、Rim27Fade 各 6 个键；导入时未知键本来就忽略。
  - glow 样式的 `rimForScope` 返回 opacity 1、fade 0（透镜边框也不渐隐）；`rimHexForScope` 返回高光一的颜色。
  - CA：新类 `WXGRimGlowLayer`（嵌套光带 + `WXGRimLevelLayer` 遮罩 + 组不透明度 = alpha，按 key 缓存），`WXGRimView configureGlows:count:` 按顺序叠两个（高光二在上）；`WXGRimLevelLayer setEndLevel:sharpness:angle:`。诊断里每个边框的 `glow` 是两道的数组。
  - 着色器：`WXGUniforms` 加 `glow2`、`glowColor2`，18 个 float4 = 288 字节（静态断言已改）；`extra.x` 改为高光二的宽度。glow 时 `borderColor` = 高光一的颜色，透镜段和本体段在高光一之后再叠高光二。`wxgGlowStroke` 去掉 cross。
  - 点按动画：`_travelOutlines` 两条线；glass 的 `lensOutlineColors` / `lensOutlineWidths` 为数组（普通样式 1 条，glow 2 条，各取上下边处的亮度 `WXGRimGlowLevel(0,1,…)`，线宽 MAX(.75, MIN(宽·.5, 2))）。
  - 设置：“iOS 27 · 高光一 / 高光二”两组各 7 行（颜色、不透明度、渐隐宽度、向内渐隐曲线、高光方向、最暗处亮度、过渡速度），删掉“过渡”组；样式选择的说明文字改了。
- **长按弹回**：
  - 诊断：4 次取消都在按下整 0.90 s，`settingsEntryReady` = true。
  - 原因：`buildDock` 给底栏加的 `UILongPressGestureRecognizer`（0.9 s，FIX35 的设置备用入口）。入口已加入时处理函数直接返回，但识别器照样识别成功，`cancelsTouchesInView` 默认 YES，UIKit 取消了 WXGDemoBar 的 tracking（`cancelTrackingWithEvent:` → 回到原标签）。FIX87 的“长按松手不切换”也是它。
  - 修复：`cancelsTouchesInView=NO`、`delaysTouchesEnded=NO`；host 作 delegate，`gestureRecognizerShouldBegin:` 只在 `!WXGSettingsEntryReady && _dockView.restingOnSelectedTab` 时开始（新属性：手指按着、没有 travel、没拖动、按下和当前都是原选中的标签）。`continueTrackingWithTouch:` 在 `_fingerDown` 为 NO 时不再处理移动（识别器不再取消触摸后，打开设置时手指再滑也不会改底栏的标签）。
- 审查：独立只读审查一轮，1 处已改（上面最后一句）；结构体布局、键名（3 范围 × 2 道 × 7 项全部存在）、CA 图层和合成顺序检查无误。

## FIX88（测试版 ABC）

- **用户对 FIX87 的反馈**（附草图、微信底栏透镜截图、iOS 26 文件 App 透镜截图和录屏）：
  1. 表情换成实心笑脸，原来的比右侧大太多。
  2. iOS 27 边框其实两个方向都有高光，只是深浅色时另一个不明显，要加上。
  3. 平稳背景加强材质加回来再试。
  4. 顶栏头像模式一直读不到当前聊天的头像，要加读取。
  5. 底栏：
     - 在别的未选中标签上按压时透镜没被呼出；
     - 长按后松手不选中（和单点不同）；
     - 普通点按切换要和拖动呼出的透镜一样，底栏微微放大、透镜内底栏高度减小。
  6. 透镜：
     - 不开折射色散时，底栏与透镜边的连线是直角，折射后成了“平底的切圆”；要 45° 再折射，但到底栏末端仍要正常脱离（斜率不断变低甚至变负）。
     - 收窄折射范围后上下边框会比圆角转弯处“胖回去”。
     - iOS 26 的色散有自己的渐变范围，不限在折射范围里，上下同样收敛，要加。
- **表情**：`face.smiling.fill`（退回 `face.smiling`）。`WXGSurface` 的 emoji 角色 iconMax 由 MIN(26,h·.92) 改为 MIN(19,h·.67)：约 19 pt，对齐 dictation 角色约 17 pt 的麦克风。
- **另一方向高光**：
  - `WXGRimGlowLevel(nx,ny,angle,cross,endLevel,sharpness)`：a=|nx sin r+ny cos r|，b=|nx cos r−ny sin r|，返回 e+(1−e)·max(a^k, c·b^k)；cross 夹到 0..1，NaN 当 0。
  - 表里 `Rim27Cross` 每范围×浅深，默认 0.3，0..1，排在 Angle 行后面。`WXGRimGlowShape.cross`；`WXGRimLevelLayer setEndLevel:sharpness:angle:cross:`。
  - 着色器 `u.extra.x` = cross，`wxgGlowStroke(...,cross)`。`WXGUniforms` 加 `float4 extra`，256 字节（16 个 float4），静态断言已改。
  - 设置：两组 iOS 27 各加“另一方向高光”（`WXGSlider3`）。
- **平稳背景**：从 fix85 原样恢复：
  - 文件 `WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c`；Makefile、`WXGIntegration.h` 的 `WXGCalm*` 声明；
  - 表里 calm 七个键、`calmFactor`、`WXGCalmRegister`、诊断 `calm`、启动时 `WXGCalmApplyPreferences()`、材质页的平稳背景组和 `calmShow`。
  - 新增：着色器的 `u.tintColor`（透镜内底栏的材质）也按 calmFactor 往平稳值移，和 `_veilFallback` 一致。
- **头像**：
  - `-avatarImageForTitle:`（buildNavigation 传入它算好的标题）。每页状态 `WXGAvatarState` 用关联对象挂在页面上：image、source、fromService、attempts、refreshes、lookupAt。
  - 顺序：页面 / titleView 的头像视图键 → 联系人（`GetContact` 等方法，或 `m_contact` 等实例变量，取 `m_nsUsrName`）→ `MMHeadImageMgr`（经 `MMServiceCenter defaultCenter` / `MMContext currentContext` 的 `getService:`）。
  - 类型检查：
    - `getService:` 返回 @、参数 # 或 @；
    - `getHeadImage:withCategory:` 返回 @、第一参 @、第二参整型：q/Q/l/L 按 64 位传，i/I/s/S/c/C/B 按 32 位，空编码拒绝；类别 0、1 各试一次；
    - 单参数的几个变体返回 @、参数 @。
  - 消息列表兜底（`-visibleIncomingAvatarIn:`，大 UITableView 的可见 cell 里类名含 HeadImage / Avatar、24–72 pt 方形、x 在左 30% 内）。只在确定单聊时用：
    - userName 已知且不以 “chatroom” 结尾（含 WeCom 的 @im.chatroom）；
    - 或者 userName 未知、标题非空，且标题不以 “(数字)” / “（数字）” 结尾。
  - 没找到：每 0.5 s 一次，每页最多 24 次（`retryAvatarAfter:` 用 dispatch_after 置 navigationDirty 再 schedule，同时只挂一个）。离开再回来，没图的页重新计数。
  - 头像服务的图：之后每 0.75 s 再问，共 8 次，CGImage 变了就替换（可能先给默认头像）。
  - 诊断 `avatarStatus`（来源或失败原因）、`avatarLookups`。
- **底栏点按动画**（render server 的 travel）：
  - `prepareTravelToIndex` 的 lift / mesh 用真实 `barGrowth`（之前是 1）；prewarm 同样，key 一致。
  - `animateTravelExtras` 改成密集线性关键帧（每 1/60 s，最多 121 帧）。`WXGKeyframeAt` 按关键时间和每段的 CAMediaTimingFunction 在 CPU 上算出 size / press，和 CA 对稀疏关键帧的求值一致；透镜中心用 `travelCentreAt:`（滑动曲线 .40,0,.30,1）。
  - 每帧加的动画：
    - 底栏放大 s=1+(barGrowth−1)·p，以 additive transform 加在 `_glass.layer` 和 `_travelNormalIcons` 上，绕底栏中心；
    - 洞（在图标层未缩放的空间）：位移 (L−bc)(1/s−1)，大小 lens·K/s；
    - 选中图标：缩放 z·s，`_travelIconImage` additive 位移 (L−bc)(1−1/s)，即先绕 bc 放大底栏、再绕 L 放大透镜；
    - 角标：以左上角绕 bc 位移（和 `layoutBadges` 一致）；
    - 透镜内底栏的各层 path。
  - zoom 和洞大小从稀疏动画挪到这里；`setTravelShapeModel` 的模型值同样带 s。
  - 透镜内底栏（`WXGTravelVeil.h`）：`WXGTravelVeilOutline` 用和着色器同一个 `WXGInnerInsetAlong` / `WXGLensDepthAlongBar`，偏移夹到 r−0.01（深层不交叉）；`WXGTravelVeilBands` 把材质边缘减弱拆成最多 8 层嵌套。轮廓线颜色 / 宽度取玻璃的 `lensOutlineColor` / `lensOutlineWidth`：
    - 普通边框：WXGRimStrengthTLBR 上下平均 × rim.opacity；
    - glow：再乘平均亮度，线宽 MAX(.75, MIN(光宽·.5, 2))。
  - 只在 travel backdrop 与玻璃共用捕获组（`backdropGroupName`，渲染模式 ≥2）时画。backdrop 的组改为每次 travel 用 `applyTravelGroup:` 设置，key 不再带组；prewarm 用自己的组 “wxg.travel”，避免在 opacity 0.001 下加入玻璃的组。
  - `loadTravelVeil` 持有 UIColor（之前 CGColorRef 可能悬空）。
- **按住别的标签**：
  - tick 里 phase 1 且手指按着、过了 `_travelPlanEnd+.02` → `handOverTravelToFinger`，计数 `holdHandovers`。
  - hand-over / cancelGlide：press 由当前尺寸反推；`_lensX` 由 `anchorForLensCentreX:press:` 反推（布局对锚点在首末标签间是线性的，可精确反解），所以真透镜接在动画透镜的同一个中心；`_elasticMotion` 清零。
  - 松手没切换（在外面，或按在别的标签、松手时回到原标签）记日志（前 20 次，含按下时长、按下 / 松手 / 原来的标签），系统取消也记；计数 `uncommittedEnds`。长按不切换的根因没找到。
- **透镜 45°**：
  - `WXGOptics.h`：`WXGInnerInsetAlong(barHeight,press,reduction,along)` = full·u·(2−u)，u=clamp(along/(2·full))，起点斜率 1（45°），到 2·full 处变平；`WXGLensDepthAlongBar(ld,tx,ty,lnx,lny)` = max(0,−ld)/max(|t·n|,.3)。
  - 着色器 `wxgLensInset`：底栏轮廓点 q（缩放后）在透镜场里的深度沿底栏切向换算；render-server 透镜段的 `dd` / `em` 用弯曲后的点。旧 `WXGInnerInset` 只留给测试。
  - 端头：法向转向时 |t·n| 变小，深度换算变大，收窄量一直到端头离开透镜，不会卡住。测试 `Tests/LensInsetAlongTests.c`（端头在透镜里收进去的情况在 `Tests/TravelVeilTests.c`）。
- **上下边框“胖回去”**：沿透镜轮廓数值检查了折射带宽度（各配置都单调，上下 ≤ 圆角处）。判断是直角台阶被折射放大的那一条，45° 后应消失；已请用户新版里再确认，有的话截图标位置。
- **色散范围**：
  - 表里 `lensDispersionWidth`（默认 10，1–60，继承 lensEdgeWidth）、`lensDispersionTopRatio`（默认 1，0.1–1，继承 lensTopEdgeRatio）。
  - `WXGMeshOptics` 末尾加 `dispersionWidth` / `dispersionTopRatio`（0 = 用折射带）。`WXGMeshDispersionSide` / `Ratio` / `BandWidth`；`WXGMeshSource` 的色散位移用 dwidth；环带和轮廓带取 max(折射, 色散)。
  - 底栏透镜（`applySyncMode`）和 `WXGMakeTravelLensBackdrops` 都是 edgeWidth→色散范围按 press 插值，**只在分色打开且 dispersion>0 时设置**。mesh 缓存 key 和 `WXGMeshOpticsClose` 含新字段。
  - 着色器：`u.extra.y/z`，`dispSide=mix(bodyEdge,extra.y,press)`，`WXGLensEdgeWidthAtBar` 用 extra.z。
- **审查**：
  - 第一轮独立只读审查 11 条，已改：
    - 悬空 CGColor；
    - 群聊兜底；
    - 头像不再重试；
    - 深层 path 交叉；
    - 关键帧间漂移；
    - hand-over 尺寸跳变（barGrowth、zoom×s、图标位移）；
    - 默认头像被缓存；
    - 类型编码检查；
    - glow 时轮廓为空、平稳背景和着色器材质不一致；
    - prewarm 把组成员放在 0.001 透明度下；
    - 色散关闭时也设置色散宽度。
  - 第二轮审查 7 条，已改：
    - @im.chatroom；
    - 群判断用实际显示的标题；
    - 头像状态和缓存改为每页关联对象（NSMapTable weak→strong 的值不及时释放，回到旧页还会停在默认头像）；
    - hand-over 清 elastic；
    - 轮廓亮度用 TLBR；
    - 角标按左上角。

## FIX87（测试版 ABC）

- 用户对 FIX86 的反馈：①iOS 27 边框在浅色模式应该反过来，两端最强、上下弱，或者更自由，深浅色各自决定渐隐方向；②两种输入栏里输入文字的胶囊在点击升起键盘时放大、键盘出来后又缩小，要固定不动；③两段式输入栏：表情换成苹果的笑脸，语音转文字要有状态提示（现在完全看不出是不是在听写）。键盘升起问题和默认参数用户说暂时不重要。
- 边框方向：`WXGRimGlowLevel(nx,ny,angle,endLevel,sharpness)` = e+(1−e)|n·d|^k，d=(sin a, cos a)，y 向下；0° 上下、90° 两端、45° 左上/右下、135° 右上/左下。表里 Rim27Angle 每范围×浅深（浅 90、深 0，0–180）。`WXGRimGlowShape.angle`；`WXGRimLevelLayer setEndLevel:sharpness:angle:`（上下直边、左右直边各自按方向取值，角场按方向，缓存 key 带角度）。着色器 `glow.x` = 1 + 角度（弧度），`wxgGlowStroke` 多了 nx。设置里“两端亮度”改名“最暗处亮度”（键名不变 Rim27EndLevel），加“高光方向”。
- 输入胶囊：`WXGSurface.pressFixed`（`observedTouchBegan:` 直接不接、`setExternalPressed:` 不按下、`stretches` 为 NO）。两段式 pill、三段式 center 设 YES。原因判断：按下时 _target=1，松手后弹簧回落要靠显示链接逐帧走，键盘调出时主线程被占住，所以放大一直留到键盘出来。plain 的 mic / emoji 仍有自己图标的按下效果（pressProxy 到 pill 后不再放大 pill）。`pressStretchNative` 的开关改名“首页左上角和三段输入两侧也拉伸”。
- 两段式表情：`face.smiling` / `keyboard`（静态缓存，`setImage` 不会每次重算）。面板状态：微信表情按钮图片 16×16 alpha 指纹（`WXGInputImagePrint`），输入栏静止在底部且不在编辑、并且按钮图片 0.4 s 没变时学为笑脸；当前指纹与笑脸平均差 > 0.06 视为面板开着（显示键盘）。没学到时一律笑脸。
- 听写：mic 在听写角色时 `perform` = `dictationTapped`，转发前记下微信听写图标（`MMGrowDictationIconView`，被插件隐藏）此刻的信号作为参照：子树 layer 的动画数、正在动画的 UIImageView、按钮 selected，以及**只属于微信二进制的类**（`class_getImageName` 含 “.app/”）里名字含 record/listen/dictat/recogn/work/start/run/activ/state/status/speak/voice/animat/play/busy/loading 的整型 / BOOL 实例变量。会话中 0.3 s 定时器（common modes）跑 `dictationTick`：先跑结束规则，再走宿主的 `layoutInput`（受键盘 / 遮挡 / 后台的门控）。与参照不同的信号持续 ≥1 s → “读得到”，记下这些信号的取值；之后只要其中任一仍是那个值（动画数仍高于参照、selected 仍为 YES）就算在听，停 1 s 结束。读得到且在听时右侧固定为听写按钮（会话开始时抓的那个控件），再点一次只先隐去提示（`stopAt`），微信停了才结束，1.5 s 后仍在听则恢复。读不到时：提示到出字（开始 1.5 s 后）为止，然后和 FIX86 一样变发送；另外收起键盘 0.5 s、图标离开窗口、12 s、90 s、离开聊天、再点一次都会结束。`endDictation` 立即去掉红色、脉动和“正在听写…”，再 `schedule`。提示标签放在 pill 里，位置取 `caretRectForPosition:beginningOfDocument`。dealloc 里停定时器。浮点实例变量只进诊断，NaN / 无穷记成字符串（JSON 不能存）。诊断 `input.dictation`（readable、onValues、changes、idle、last、lastEnd、icon 里有视图、动画 key、全部标量实例变量）和 `input.emoji`（distance、faceLearned）。
- 表情面板识别改用输入行 `_toolPanelView` 是否停在底部（容差 40 pt），按钮图片换了对象但形状差 ≤0.02 不算变化，学到的笑脸形状全局保存一次。
- 审查：独立只读审查一轮，按意见改了：诊断导出遇 NaN 会崩、听写状态与微信不同步时按钮会反着来（改为只在读得到时固定停止按钮，读不到时出字即结束）、UIKit 自己的实例变量混进比较、出字后听写按钮可能被微信移走（会话里用开始时抓的控件）、定时器绕过宿主门控 / 输入栏不布局时不会结束 / 适配器释放后定时器还在、提示位置没算滚动偏移、表情学习用了整个工具视图的位置。
- `WXGSurface.iconTint`（新）：覆盖图标颜色。

## FIX86（测试版 ABC）

- 用户对 FIX85 的反馈：①边框样式全局一个，选了就所有范围都变，要按范围分别生效；②部分玻璃圆角异常“没有拉伸而是两侧维持半圆”（多行气泡、设置卡片两端深色月牙）；③平稳背景加强材质调不出想要的效果，删掉；④iOS 27 边框胶囊圆角处比上下窄，要处处一样宽；⑤真正的 iOS 27 边框方向相反：高亮白边上下最亮、往两侧减弱，并且往内部渐隐，宽度可调（给了参考截图）；⑥视频号顶部按钮分开（不要胶囊），不覆盖材质，边框恒定用深色模式参数。
- 原因（②④）：FIX85 的 iOS 27 线的内边由 `UIBezierPath roundedRect` 展平后往里收，外边（裁剪）是 CA 的连续圆角，两条曲线不同：圆角矩形两端出现月牙、胶囊圆角处变窄。整个删掉（`WXGRimVariable.h`、`Tests/RimVariableTests.c`、`configureVariable:` / `layoutVariableRadius:`）。
- 新 iOS 27（`WXGRimGlow.h`，纯 C，`Tests/RimGlowTests.c`）：`WXGRimGlowBands(width,falloff,scale,max,…)` 每层约 1 px（最多 20 层），**嵌套**：第 j 层从轮廓开始、宽 (j+1)·宽/n（inset 都是 0），alpha b_j = 1−(1−A_j)/(1−A_{j+1})，叠起来第 j 段正好是 A_j = (1−(j+.5)/n)^falloff（取每段中点，总亮度几乎不随屏幕倍数变）；不用相接的层是因为相接处落在半像素上，两层的抗锯齿会留一圈暗线。`WXGRimGlowComposite` 给测试算叠加结果。`WXGRimGlowLevel(ny,endLevel,sharpness)` = e+(1−e)|ny|^k。`WXGRimView configureGlow:`（NULL 关）：`_glowHolder`（allowsGroupOpacity，opacity = 颜色 alpha）里用 `WXGRimPlaceBands` 放 CA 边框层（玻璃自己的连续圆角），holder.mask = `WXGRimLevelLayer`（上下直边 1、左右直边 endLevel、四角按方向的 256 px 场，和 `WXGRimFadeLayer` 同一套结构，角窗半径取 max(圆角, 光宽) —— 圆角比光宽小时侧边的光不会落进上下直边的全亮区）。两者都继承 `WXGRimFieldLayer`（四条直边 + 四个角窗 + 按 key 缓存的场图，`applyTop:bottom:left:right:fieldKey:level:`）。宽度不超过短边一半；glow 时自身 borderWidth 0、没有描边细节和背景取色；视图自己的对角渐隐照常。
- 着色器（底栏透镜里画的底栏轮廓）：`WXGUniforms` 加 `glow`（x 开、y 两端亮度、z 过渡速度、w 向内曲线；开时 `optics.y` = 光宽），`wxgGlowStroke` 按往里的深度和 ny 算，透镜段和本体段都用。结构 224 → 240 字节（静态断言已改）。改的是 `WXGGlass.metal`，`tools/embed_shader.py` 重新生成，`tools/check_msl.py` 通过。
- 配置：`rimStyle` + `dockRimStyle` / `bubbleRimStyle`（表里 inherit “rimStyle”，升级后等于原样式），`rimStyleForScope:`；`rimStyleValue` = 其余玻璃的，`rimSampleColor` 仍由它同步（旧导出兼容）。iOS 27 键：Rim27Hex / Opacity / Width（2，0.3–8）/ Falloff（1.6，0.5–4）/ EndLevel（0.15，0–1）/ Fade，每范围×浅深；Rim27Sharpness 每范围一个（2，0.5–6）。`rimGlowForScope:dark:` 返回 `WXGRimGlowShape`。FIX85 的 EndWidth / SideWidth 删除。
- 玻璃：样式按 `glassScope` 取；新属性 `rimAlwaysDark`（边框颜色、不透明度、宽度、渐隐、细节、取色参数、透镜边框、着色器里的 bar 轮廓颜色都按深色取；材质 / 选中色仍按实际外观）。着色器里“取自背景”判断改成本玻璃范围的样式。`WXGRimSummary` 输出 `styles`（dock / other / bubble）和每个边框的 `glow`。
- 设置：样式选择行有 dock / bubble 键（`WXGChoice3`），分组按当前范围的样式过滤（`scopeRimStyle`），换范围 / 恢复 / 导入后按该范围样式重建；iOS 27 三组按新参数重写。
- 平稳背景：`WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c` 删除；`calmFactor`、表里的 calm 键、材质页分组、诊断 `calm` 都删了；启动只剩 `WXGPerfApplyPreferences(); WXGKeyboardTraceStart();`。
- 视频号：`groupFinderButtons:` 删除（按钮不再 plain / pressProxy，没有胶囊）。`styleFinderButtons`（导航按钮布局末尾，对 `_buttons` 全部）：WCFinder 页 veilOverride = 透明、`rimAlwaysDark` = YES，其它页 nil / NO，只在变化时赋值。
- 导入 / build 默认值后的 `reinheritExtrasMissingFrom:` 改为：只有来源键在这次的值里（或本身刚被重新推出）时才重新继承；`rimStyle` 只在导入了 `rimSampleColor` 时由它推出。FIX85 的做法会让一个不带样式的部分导入把三个范围的样式都改回普通 / 取自背景，也会把用户自己调过的继承键（如气泡宽度）盖掉。
- 审查：独立只读审查一轮，6 处问题已修（相接层的暗线、按外沿取值的亮度和单层全亮、小圆角时两端亮度失效、部分导入重置样式、透镜里的轮廓还是普通线、SHA256SUMS 和视频号说明的位置）。
- 键盘：无新数据，FIX85 的日志还在。默认参数：仍在等用户发参数文件，`tools/bake_defaults.py` 已认新键（试过 dock/bubble 样式和 Rim27 新键，旧 EndWidth / calm 键会被丢掉）。

## FIX85（测试版 ABC）

- 用户要求：①壁纸写进 Library/Preferences 和 Documents 两处，NSFileProtectionNone + 原子写 + 读时互相自愈，防微信清缓存；②排查键盘异常升起（截图：聊天里输入栏离键盘约 200 pt，中间透出聊天背景图），查不到就加日志；③液态气泡单独的玻璃和边框参数；④视频号左右各两个按钮各合成一个胶囊，不加深浅色材质覆盖，只有模糊和折射；⑤新边框样式仿 iOS 27：两端最粗上下最细，两端 / 上下宽度、过渡速度、颜色可调，独立于前两种；取自背景的样式要有自己的不透明度、宽度等，不和普通样式共享；⑥平稳背景（变化小）时材质接近不透明，能否量化，加开关，壁纸 / 图片背景时用更透明的。
- 配置：`WXGConfig.m` 新增表 `WXGExtraSpecs`（81 个键，KVC 经 `valueForUndefinedKey:` / `setValue:forUndefinedKey:` 存在 `_extra`），带 `inherit`（从未保存过时取来源键的当前值；导入 / build 默认值之后对缺的键再取一次 `reinheritExtrasMissingFrom:`），`normalize` 里夹范围。`keys` = `baseKeys` + 表。`rimStyle`（0 普通 / 1 取自背景 / 2 iOS 27）首次取自 `rimSampleColor`，之后 `rimSampleColor` 由样式同步。作用范围 `WXGGlassScope`（其余 / 底栏 / 气泡），`opticsForScope:`、`rimForScope:dark:`（返回当前样式自己的不透明度 / 宽度 / 亮度 / 渐隐）、`rimHexForScope:dark:`、`rimVariableForScope:dark:`。键名规则见 `WXGScopedKey`（rimSampleOpacity / darkRimSampleOpacity / dockRimSampleOpacity / dockDarkRimSampleOpacity / bubbleRimSampleOpacity / bubbleDarkRimSampleOpacity；iOS 27 是 Rim27Hex / Opacity / EndWidth / SideWidth / Fade，Rim27Sharpness 每个范围一个；气泡普通样式 bubbleRimHex / bubbleRimOpacity / bubbleBorderWidth / bubbleRimBrightness / bubbleRimFade 及 Dark；气泡光学 bubbleRefraction / Dispersion / EdgeWidth / Blur / BlurCoverage / FullGlass；平稳 calmMaterial、calmMaterialOpacity(+dark/dock)、calmThreshold、calmRange）。
- 玻璃：`WXGGlassView.bubbleSurface`（液态气泡设 YES，轻量与否看 `bubbleFullGlass`）、`glassScope`、`calmFactor`（遮盖往平稳值移动）。`WXGRimView configureVariable:`：连续圆角裁剪层里一个 even-odd 的 CAShapeLayer（外矩形 − 内边），内边由 `UIBezierPath roundedRect` 展平后按 `WXGRimVariable.h` 往里收；iOS 27 样式没有描边细节、没有背景取色。
- 平稳背景：`WXGCalmBackdrop.m`（`WXGCalmMath.h` + 测试）：NSTimer 0.3 s（按耗时放宽到 0.6 / 1.2 s），滑动时跳过；按 sourceView 分组，`renderInContext` 到约 0.25 px/pt 的位图（插件自己的祖先视图 layer.hidden 暂藏，同一事务里恢复），每块玻璃区域外扩 6 pt 算 RGB 标准差；视频 / Metal 图层区域算不平稳；换页 / 久未测的玻璃直接取新值，其余每次走 45%。不测：气泡、视频号胶囊（有 veilOverride）、lightweight。
- 设置：边框页顶部样式选择（新的 choice 行，切换后整页按样式重建）；refraction / blur / border 三页 `scopes` 含 bubble（三段切换）；行多了 `bubble` 备用键；材质页“平稳背景”组和“查看当前背景变化程度”；液态气泡页加三个 `open:模块:bubble` 入口；恢复本页默认会带上 bubble 键并按新样式重建页面。
- 视频号：`groupFinderButtons:`（`WCFinder*` 页）每侧 ≥2 个按钮时一个池化的 `finderLeftGroup` / `finderRightGroup`（materialOnly、跟随第一个按钮的原生运动、插在最下面），按钮 plain + pressProxy；这些页的玻璃 veilOverride = 透明。值只在变化时赋（不再每次布局开关玻璃）。
- 存储：`WXGSettings.m` 的 `WXGSettingsRead/Write/Remove`（同一个串行队列，读用 dispatch_sync），两处目录，失败的那份删除，旧 Application Support 文件迁移。帧率日志也在 Library/Preferences。
- 键盘：没找到原因（插件不改输入栏 y；只有底栏搜索 4 s 交接会聚焦）。`WXGKeyboardTrace.m` 记录通知和输入栏 / 键盘间距快照。下次要用户在出现时导出诊断。
- 审查：另一个只读审查找出 7 处问题，均已修（存储竞争 / 失败删旧图、导入后新键不跟随、视频 / Metal 背景被当成平稳、复用玻璃沿用旧平稳值、视频号每次布局开关玻璃、恢复默认后页面不按样式重建、透明背景色当黑色）。

## FIX84（测试版 ABC，A / B / C 三个账号）

- 来历：另一个对话里先在 FIX81 A 上做了这些（当时叫 FIX82，已发给用户，但不含液态气泡），用户随后发来 FIX83 A（液态气泡，FIX82/83 在他那条线上），要求合并。FIX84 = FIX83 A + 下面这些，三方合并（基准 FIX81 A），冲突只在版本号、`WXGPreferences` 键、`WXGIsPluginView` 名单、`Makefile`。
- 用户：FIX81 偶尔出现“渐隐直接跟随滑动，将整个页面消息都接近隐去”（首页截图：第一行正常，第二行渐隐，下面全是底色）；要一个帧率性能检测日志模块和一个配置参数共享模块（如果现有日志能完全读出参数也行）；他有一套效果好的参数，想做成安装后的默认设置（**这次没有发参数文件，等他用 FIX84 导出后发来**）。
- 渐隐：`WXGEdgeFade.m` 的列表登记表是 16 个指针的数组，页面释放时 `_scrollView`（weak）已是 nil，登记永不清除；满了以后新列表写进第 0 格，挤掉最早登记的首页列表，首页列表的 setBounds: 钩子找不到页面，遮罩（在列表滚动坐标里）不再跟随，随内容滑走。改为列表上的关联对象 `WXGEdgeListLink`（weak page），无上限；`refresh:` 时核对 `WXGEdgePageForList(list)==self`，否则重新关联并计数 `relinks`。诊断：`linked`、`maskLag`、`maskSyncs`、`relinks`。
- 帧率：`WXGFrameStats.h`（纯 C，`Tests/FrameStatsTests.c`）+ `WXGPerfMonitor.m`：自己的 CADisplayLink（`WXGConfigureDisplayLink`，屏幕最高刷新率），开关 `pref.perfMonitor` / `pref.perfHUD`（WXGPreferences，默认关）。每秒记录、按页面×滑动/静止汇总（1 ms 直方图求百分位）、>50 ms 或 3 次刷新的卡顿事件、插件主线程耗时（`WXGProfileAdd` 的 Tick，以及 tick 外的 Refresh / Switch；渐隐跟随滚动单独计时）。每 15 s 与退到后台时写 `Application Support/WeChatLiquidGlass/perf_current.json`，下次运行改名 `perf_previous.json`。浮标 `WXGPerfHUDView` 是微信主窗口的子视图（zPosition 100000，盖在弹出页面上；在 `WXGIsPluginView` 名单里），可拖动，位置存 `perf.hudCenter`。没有用独立窗口：独立窗口会成为 `UIApplication.windows.lastObject`，微信若把提示加到最后一个窗口就会被塞进 200×42 的小窗。同一次运行里关掉再打开记录，本次会话继续（只有“清空本次记录”重来）。插件耗时：宿主 tick / refresh 用嵌套计数 `WXGHostTimedDepth`，只记最外层；渐隐跟随在其中时不另计。报告页 `WXGPerfReportController`，导出 JSON（current + previous + 报告文字）。
- 参数共享：`WXGSettingsShare.m`。格式 `{"schema":"wxg-settings-v1","config":WXGConfig 全部键（除 enabled）,"integration":WXGPreferences（除 enabled/homeSearch/perfMonitor/perfHUD）,"ui":{cardRadius,accentHex}}`。复制（紧凑 JSON）/导出文件/剪贴板导入/文件导入（UIDocumentPicker，Import 模式）。导入认：本格式、诊断 JSON 的 `settingsShare`、旧诊断的 `materialParameters`（优先 currentOrLastScene 的）、裸的 WXGConfig 对象。诊断 JSON 顶层新加 `settingsShare` 和 `frameRate`。
- 默认值：`WXG_DEFAULT_OPTICS_JSON` 可以是旧的裸 config，也可以是上面的格式；`WXGBuildDefaultSection(@"config"/@"integration"/@"ui")`。WXGPreferences、WXGSettingsStore 在没有存储（新装）时用 build 的 integration / ui。`tools/bake_defaults.py <导出或诊断 JSON>` 写入（96 字符一段的 C 字符串拼接），已用样例验证往返和 ObjC 编译。
- 设置首页“通用”多了第三张卡片“帧率与参数”（module `tools`）。
- `WXGHost.m`：`tick:` 拆成 `tick:` + `tickBody:begin:`（只为在 tick 内置 `WXGHostTicking`，避免把 tick 内的 refresh / 切换重复计入插件耗时），版本号 0.4.82 / FIX84，诊断文件名改 FIX84。
- 合并后：液态气泡的 `textCellLaidOut`（TextMessageCellView 布局钩子）和每次提交前的 `reassert` 也计入插件耗时（`WXGPerfTimePluginWork`，在宿主 tick / refresh 里时不重复计），渐隐跟随同样。`bubbles` 开关和气泡颜色、边缘减弱在参数共享里（WXGPreferences / WXGConfig 的键自动包含）。设置首页“通用”和“个性化”各三张卡片。
- 待办：用户发来参数后 `python3 tools/bake_defaults.py <file>`，出带默认值的包（FIX85）。


## FIX81 ABC（另一个对话，未发布）

- 用户要求：在 FIX81 A 的基础上把测试 B 和 wxid_12cm2d89f8ya22 也绑定进去，折射和色散参数也开放。只改了 `WXGBuildProfile.h`（三个哈希：A wxid_mpuxjt2kgy2s22、B wxid_wb0yvnj7a1m522、C wxid_12cm2d89f8ya22；标签“测试版 ABC”；`WXG_HIDDEN_MODULES` 保持 `@[]`）。B 的 FIX60 预设没有加。FIX84 沿用这个授权。

## FIX83（只出测试版 A）

- 用户：气泡颜色要像“其余玻璃”那样可选范围的边缘减弱，不要整块填充。
- 做法：玻璃的着色覆盖可带自己的减弱范围；气泡页加开关和范围（默认开、8 pt）。

## FIX82（只出测试版 A）

- 用户：他的 MixBubble（自己的气泡插件，源码 `MixBubble_2_8_Release93_PROBE_PRIVATE_source.zip`）有接管微信原生气泡绘制的方法，其中“无尾巴单行圆角”（圆角始终是单行高度的一半）想搬进本插件，做液态气泡模块，集成气泡和玻璃的绘制，以后需要再自定义。
- 从 MixBubble 只取了找气泡本体的方法和圆角规则（`WBPFindTextBodyView`、`WBPEffectiveBubbleCornerRadius`、单行参考高度的取法），没有搬尾巴几何、合并、引用、翻译等。MixBubble 的覆盖层放在 TextMessageCellView 里本体下面；这里把玻璃放进本体最底层（随本体一起动）。
- 风险：每个可见气泡一层背景（滚动性能）；与 MixBubble 同时接管会叠加；长按换图靠提交前重隐藏。

## FIX81（只出测试版 A）

- 用户对 FIX80：描边“马马虎虎”，深色模式想让边框明显不容易（他认为是这种做法的局限，能理解）；发来 FIX80 诊断 JSON，要求把参数推为新版默认，并在边框页最底部加“恢复默认”，后续再调整。
- 做法：边框页 53 个键写进 `loadDefaults`；新装直接用默认值；边框页加“恢复本页默认”（`resetKeys:`）。拉伸参数没改默认（用户只说描边）。
- 深色模式观察：他的深色取色增益 2.5、提亮 0.6 都在滑块上限、对比度 0.5 在下限，深色背景经处理后接近白色；开了加亮叠加，线条最多把玻璃提亮“深色不透明度”（其余玻璃 0.14、底栏 0.23），这是深色下明显程度的直接上限。

## FIX80（只出测试版 A）

- 用户对 FIX79：描边已能调出接近目标的效果。按压拉伸要加参数：胶囊（非圆）只能上下 / 左右微微拉伸，不能斜向；加回一定的跟手移动（固定太死板）；加最大可拉伸幅度，与变形程度相关。另：希望把他这次调好的描边参数作为默认值（以后可能不再开放这些参数）。
- 做法：见 `WXGPressStretch.h` 的 `WXGStretchStyle`；三个新键与滑块。
- 默认值：需要用户导出的诊断 JSON（`materialParameters` 里是全部配置），拿到后把“边框与渐隐”页的键写进 `WXGConfig.m` 的 `loadDefaults`（恢复默认也会回到这套）。FIX80 发出时还没收到。

## FIX79（只出测试版 A）

- 用户对 FIX78：有渐隐了（嵌套遮罩可用）；线两侧的消散基本只有宽度变化，看不出中间亮两边暗的渐变；希望 0.1 pt 一级的消失感（透明度减弱或亮度降低），区分内外侧；深浅色配置要分开设置；“仅做尝试，渲染有风险或失败了再想办法”。
- 做法：两侧各 N 级（每级 ≤ 0.1 pt），每级是一圈 CA 边框（原连续圆角），透明度模式用嵌套带、变暗模式用全宽颜色 + 黑带，均精确到每级强度（`WXGRimDetail.h` 有推导，测试逐点验证）。取色线条：遮罩为透明度阶梯；变暗时描边视图在下垫黑（不透明度同线条），取色层 plusL 叠上，等于“颜色 × 级强度”。细节与取色参数全部分浅色 / 深色，开关共用。删除“中间亮线宽度”。
- 风险：backdrop 上的 plusL（只在变暗 + 未开加亮叠加时用到）；0.1 pt 的带靠 CA 边框抗锯齿，是否平滑需真机看。

## FIX78（只出测试版 A）

- 用户对 FIX77：两种边框颜色似乎并存，要确定只有一种生效；只让改原边框的颜色形式，不该做出“安卓圆角”的边框和阴影；选中胶囊的切换被弄坏（描述不出来）；不要乱加东西。
- 做法：所有自绘几何（环形图、圆弧路径阴影）删除。取色线条 = backdrop 视图，遮罩 = 容器 → 持有层（CA 边框 + 居中 CA 边框，mask = 与描边相同的 `WXGRimFadeLayer`）。内侧阴影 = CA 厚边框投影（裁剪到线内侧）。透镜回到 FIX72 描边（无细节、无取色层）；取色开启时透镜描边、透镜里的底栏轮廓、设置卡片都用材质颜色经同一矩阵处理的颜色。
- 风险：嵌套遮罩（backdrop 的 mask 子树里再有 mask）在 iOS 15 未实测；若不生效，取色线条可能没有渐隐或不显示。选中胶囊损坏的确切现象未知，按最可能原因（透镜取色层）处理。

## FIX77（只出测试版 A）

- 用户对 FIX76：找不到“描边取色”设置；取色线条只在四条边上各画了一段不完整的直线（颜色是对的）；宽度不能自定义。
- 原因：设置组被插到材质模块；`renderInContext` 画大半径连续圆角（圆 / 胶囊）时在每边中间画直线段而无圆弧（截图：按钮外接方框四边中段的亮线，胶囊两端的竖线），FIX74 的四个尖同源。
- 修：设置组移到边框模块；半径 > 0.3 短边时用 CG 圆弧环。宽度来自各模式“宽度”滑块，回复里说明。

## FIX76（只出测试版 A）

- 用户：背景取色不能丢（FIX74 调过后能做到类 iOS 26 的颜色），要饱和度、对比度，再加鲜明度；只需要“比背景亮、浅、鲜艳”；对比度可能不影响；不确定要不要和边框颜色二选一。
- 做法：取色打开时边框颜色不用（二选一），其余设置照用。线条 = `WXGRimTintView`（backdrop + 模糊 + 颜色矩阵，普通合成默认，plusL 可选），遮罩是用 renderInContext 画出的原 CA 边框（含 FIX75 两侧 / 中间）× 原对角渐隐场，所以形状与原边框一致（FIX73/74 的距离场轮廓不圆）。鲜明度没做（颜色矩阵是线性的，做不出“越灰加越多”），在 README 里说明了。
- 用户“其余玻璃”边框不透明度为 0，取色线条也用它，需调回。

## FIX75（只出测试版 A）

- 用户对 FIX74（新描边已生效）：画不出正圆（圆按钮在上下左右四处发尖）、宽度像固定的、和旧边框像冲突、透镜边框变两条、顶部和底部按钮同参数效果完全不同。要求：撤掉“渐隐时中间收窄”，只做线两侧变暗 + 内侧阴影（颜色可自定义），渐隐用旧方式——不是新画法，只给旧边框加细节；另外按钮拉伸加个开关（比原版差太多）。
- 诊断：`filterTypes` 里没有 screenBlendMode 也没有 plusL（混合模式不列在这里，不能据此判断）；用户开了加亮叠加、强度 1.5、饱和度 3、内侧阴影宽 0.5；“其余玻璃”的浅色 / 深色边框不透明度被调成 0。
- 做法：删掉图像式描边，`WXGRimView` 回到 CA 边框 + 原渐隐遮罩，细节都是子图层（受同一遮罩）：自身边框 alpha = a·side，居中内缩 `w(1−core)/2` 的边框 alpha = (a − a·side)/(1 − a·side)；内侧阴影 = 裁剪层（inset w，连续圆角）里的 shadowPath 环。颜色不再取背景。
- 拉伸：总开关 `pressStretch` 早就有（用户截图里就是它），另加 `pressStretchNative` 只管输入框 / 首页左上角。用户说的“按钮拉伸加开关”含义不完全确定，回复里说明了。

## FIX74（只出测试版 A）

- 用户：FIX73 打开自适应描边后完全没效果，仍是旧边框（诊断在插件设置页导出，没有玻璃条目）。
- 原因：`WXGBuildRimImages` 用 `CGImageCreate(…, NULL colorspace, kCGImageAlphaOnly, …)` 建线图，Core Graphics 拒绝（工程里其他 alpha-only 图都走位图上下文），每个形状都失败并进 `WXGRimFailed`，`layoutAdaptiveRadius:` 没有图就一直 `showClassic:YES`。
- 修：位图上下文建图；覆盖改 RGBA 上下文；解析圆角覆盖兜底；失败表随 `WXGConfigRevision()` 清空；`WXGRimSummary()` → 诊断 `liveSamplingAtExport.rims`（各状态数量、requests / builds / analyticBuilds / failures / lastFailure、blend、filterTypes 里是否有 screenBlendMode / plusL、最多 8 个在屏描边的 evidence）。
- 还没确认：图生成后，带蒙版、加入玻璃 backdrop group、合成为 `screenBlendMode` 的 CABackdropLayer 在 iOS 15 上的实际效果。

## FIX73（只出测试版 A）

- 用户：①进入插件设置页偶尔上一页按钮不隐去、叠在新页按钮上（黑色折射边，录屏 FIX69）；②输入框拉伸超出原输入框区域就被切掉，要限制；③改进描边，像 iOS 26：截面两侧暗中间亮、内侧一圈很淡的阴影、颜色随背景（亮度 / 对比度 / 饱和度都加了的感觉：浅色近白、深色更浅、彩色更亮的同色）、渐隐时两侧先没中间亮线变细；给了 6 张图让我自己分析。
- ①：推入 WXG 页时 refresh 先把 `_buttons` 转成 `_departingButtons`，然后因 unsupported 走 `!available` 分支暂停 display link，离开页的按钮不再 `followNativePresentation`，冻在原位直到 coordinator completion。现在 `!available` 时先 `dropDepartingButtons`（隐藏、失活、复位变换）。
- ②：`WXGStretchFit`：变换后圆角矩形的支撑函数求外接范围，二分拉动比例，使其不超出 `stretchClip`（祖先 clipsToBounds 的 bounds 与 layer.mask.frame 的交，转到 surface 坐标），框先并上不拉动（含按压）时的范围。拉伸目标（按压满时）和每帧姿态都限制。假设切割来自微信输入面板的 clipsToBounds；诊断 `stretchClip` 可确认。
- ③：测量与模型见 `ReferenceAnalysis/FIX73_rim.md`。实现见 VALIDATION。关键风险：`screenBlendMode` 作为 CABackdropLayer 的 compositingFilter 没在真机验证过（`plusL` 在 FIX23 的色散里用过）；若 `+[CAFilter filterTypes]` 列出 plusL 却没有 screen 会自动退到 plusL，另有用户开关“改用加亮叠加”。线层加入玻璃的 backdrop group（共用采集，后面没有玻璃内部），合成在玻璃之上。形状用 `renderInContext` 画连续圆角（与 refreshBodyMask 同法）。
- 用户的配置：流畅模式开着；描边宽度约 0.93–0.99 pt、渐隐约 0.64–0.69。新描边的强度等是新键，默认值由四组截图数据拟合（饱和度 1.8、对比度 1.15、提亮 0.16、强度 0.55）。

## FIX72（只出测试版 A）

- 用户：FIX71 完全不跟随。原因：`observedTouchBegan:` 收集 followers 后立刻 `updateContentTransform`，此时姿态仍是静止，`poseFollowers:` 在静止时清空名单。改为 `_followTouching` 期间不清空，触摸结束且静止后才清空；去掉按下时的立即刷新。诊断 `stretchFollowers`（类名，最多 8 个）。

## FIX71（只出测试版 A）

- 用户：输入框 / 首页左上角拉伸时，上面的图标和文字不动很奇怪。
- 做法：materialOnly 玻璃在被旁听的触摸开始时，从识别器所在视图（输入工具栏 / MainFrameLeftBarView）往下找完全落在玻璃区域（外扩 2 pt）里的最外层视图（不含玻璃自己和包含它的视图，最多看 400 个），存为弱引用 followers；每次姿态更新给它们的图层加 `transform` 的叠加动画（`additive`、`fillMode forwards`、超长时长），数值 = 同一姿态按图层 position 相对玻璃中心换算（`WXGStretchChildOffset`）；静止时移除并清空。只影响渲染，不改 frame / 命中 / 文字选择。
- 没确认：叠加的 transform 动画与微信自己在这些视图上的动画同时存在时的表现。

## FIX70（只出测试版 A）

- 用户对 FIX69：朋友圈仍黑；拉伸跟手正常（不再自己弹回）但玻璃离开原位太多，应几乎不动、只变形（胶囊更明显）；两个输入框和首页左上角按钮不会变形。
- 朋友圈：FIX69 诊断 `WCTimelineTableView` 背景 #111111（不透明），单元格白色，`backgroundPlate.source=list` 垫的就是 #111111。改为 `WXGEdgeCellPaint`（可见的整行单元格：backgroundColor / contentView / backgroundView 的不透明色），与列表色亮度差 > 0.35 时用单元格色（source=cells）。
- 拉伸姿态：平移 = 按压偏移 + 方向 × 拉长量 × 0.45（`WXG_STRETCH_SHIFT`），远端几乎不动。
- materialOnly 玻璃（`nativeGesture` 首页左上、`input` 输入框、`nativeInput*` 三端）：`observeTouchesInView:`（首页挂在 MainFrameLeftBarView，输入挂在 `_tool`）加 `WXGTouchObserver`（一直 possible、不能阻止 / 被阻止、不取消不延迟，触摸结束置 failed），从玻璃上开始的触摸驱动同一套按压与拉伸；只变形玻璃（文字 / 图标是微信的视图）。`setActive:NO` 时移除识别器。
- 没确认：用户说的“两个输入框”是否就是这两种输入栏（也可能指底栏搜索框，它展开后在底栏胶囊或搜索按钮玻璃上，这版没处理）。

## FIX69（只出测试版 A）

- 用户对 FIX68：拉伸会自己脱手弹回（应只在放弃点按 / 抬起手指时弹回）；朋友圈上下渐隐也变黑；融合不做了。
- 拉伸：FIX68 在手指离玻璃 40 pt 外时就释放（回弹 + 取消按下）。现在拉伸开启时整个触摸都按下并跟手，抬起时 40 pt 内才 `activateOriginal`。`gestureRecognizerShouldBegin:` 在跟踪中拒绝非 `UIScreenEdgePanGestureRecognizer` 的拖动手势（防止列表 / 全屏返回抢走触摸；不确定 UIKit 是否对祖先的手势也问被触摸的视图，问了就生效）。
- 渐隐底板：`WXGEdgeListPaint`（列表背景色 → table / collection 的 backgroundView 颜色），没有时 `WXGEdgeBackdropBehind`（从列表往上到页面：祖先不透明背景，或列表下方覆盖列表的不透明 / 有图片的兄弟视图）为否则用 `systemBackgroundColor`。诊断 `backgroundPlate.source`：list / backgroundView / systemBackground。
- 出包：从这版起直接给 deb。`/home/claude/build_deb.sh <工程> <输出.deb>`：按 Makefile 的文件和框架用 clang 18 编译、ld64.lld 链接（`-mlinker-version=711`，SDK 里补了 theos/sdks 的 .tbd）、`/home/claude/tools/ldid -S`、dpkg-deb（rootless：`/var/jb/...`、`iphoneos-arm64`）。用户偏好直接拿 deb。

## FIX68（只出测试版 A）

- 用户要 iOS 26 的按住拖动拉伸 + 回弹、相邻玻璃融合。商定分两步：这一版只做拉伸（导航按钮、标题胶囊、输入栏按钮、底栏搜索按钮）+ 底栏拖过两端拉长；下一步先只做“底栏 + 搜索按钮”的融合，再扩展。
- 拉伸（`WXGPressStretch.h`）：位移 = 橡皮筋 `L(1 − 1/(1 + 0.8d/L))`，L = 跟手距离 × clamp(短边/44, 0.75, 1.25)；拉伸矩阵 S = s·uuᵀ + p·vvᵀ，s = 1 + amount·|o|/沿向尺寸，p = max(0.6, 1 − 0.5·amount·|o|/横向尺寸)；姿态 = S × 按压缩放，平移 = 按压偏移 + o；子视图平移 = t + (M − I)·r。弹簧：跟手 600/41，松手 300/14（过冲约 23%）。开启拉伸时按住 / 点击范围为玻璃外 40 pt；`plain` 的 surface 不拉伸。全靠视图变换，玻璃内部（网格、边框、材质）不重建。
- 底栏两端：`trackPoint` 里手指越过首 / 末标签中心 8 pt 后，橡皮筋位移 o（上限为设置值，搜索按钮那侧再限到间距 × 0.75，由宿主设 `endStretchRoomLeft/Right`）；`WXGDockEndStretchPose`：sx = 1 + o/W，远端为锚点，sy = 1 − 0.2·o/h。变换加在 `_glass` 和 `_travelView` 上（它们改为 bounds + center 放置），角标按同一映射摆放。
- 没确认：斜向剪切变换下 CABackdropLayer 的表现（按压原来只有轴向缩放）；拉伸量和弹簧手感。

## FIX67（只出测试版 A）

- 用户对 FIX66：首页下拉出的小程序页上有不该有的渐隐和模糊，底栏也不该显示；从搜索进入的聊天所有效果都是原生的。
- 小程序页：它是 `MainFrameTableView` 里的 `WAMainFrameTopHeaderView`（FIX65 诊断：静止时窗口坐标 y −720、高 808，下边缘 88 = 导航栏下沿）。展开程度 = smoothstep((下边缘 / 窗口高 − 0.18) / 0.24)（`WXGHomePanelProgress`）。渐隐：遮罩里的白色子层不透明度 = 展开程度（遮罩合成 alpha = k + a(1−k)）；模糊带半径 × (1−k)，k>0.99 隐藏。底栏：`updateHomePanel`（每帧，只在首页、主路由、底栏静止、没有转场和遮盖时）→ `_dockRow` 下移 k ×（覆盖层高 − 底栏顶 + 16），和键盘上移合成（`setKeyboardLift` 的目标位移加上 `homePanelDrop`），k>0 时整行不接触摸。
- 搜索进入的聊天：`WXGRouteForWindow` 遇到弹出页时原来一律 `presented → unsupported`（刷新时挂起，保留下面的场景）。微信搜索是整屏弹出的导航，聊天推在里面。现在：叶子是 `BaseMsgContentViewController`、最后一个导航有 `presentingViewController`、弹出根视图正好铺满窗口 → `presentedStack`（不算 presented、不 unsupported、不 primary）。从这种聊天回到搜索页（presented）时不挂起，走 unsupported 复原。
- 没确认：小程序页类名在用户的版本上（FIX65 诊断里有 `WAMainFrameTopHeaderView` / `WAMainFrameTaskBarView`）；展开时这块的下边缘是否真在屏幕下方；搜索页确实是整屏模态（如果是 UISearchController 盖在首页上，路由本来就不是 presented，那原因另有，需要那时的诊断）。

## FIX66（只出测试版 A）

- 用户对 FIX65：没设壁纸的聊天页和微信“设置”页，上下渐隐处是黑的；其他页面不会。FIX65 诊断：聊天页 `MMTableView`、设置页 `WCTableView` 的背景色是不透明的 #EDEDED，页面视图本身没有不透明背景；首页的 `MMUIHookView`（页面视图）是不透明 #EDEDED。列表 mask 连列表背景色一起渐隐 → 露出后面的黑色窗口。
- 改动：列表 `backgroundColor` 不透明时，在列表正下方放 `WXGEdgePlateView`（同色，frame = 列表在父视图里的可见区域），在 `syncGeometry` 里跟随位置 / 大小 / 颜色（`isEqual` 比较）/ 隐藏；插件设置页（壁纸覆盖模式）不需要。

## FIX65（只出测试版 A）

- 用户对 FIX64：模糊强度默认太高；上下强度要分开（两边距离一般不同）；范围最大 8 就够；“其余页面”要加上我们自己的设置页和微信的设置页。
- 改动：
  - `WXGConfig`：`edge{Chat,Other}BlurRadius` 换成 `edge{Chat,Other}Blur{Top,Bottom}Radius`，0–8，默认 3（旧键不迁移，用户说旧值太高）。设置每组 6 行：顶部渐隐 / 模糊距离 / 模糊强度，底部同样。
  - 其余页面加 `NewSettingViewController` 和 `WXGSettingsPage`（`isKindOfClass`）。宿主的 `viewWillAppear:` / `viewDidAppear:` 钩子原来对 `WXG` 前缀的页面直接 return，`WXGEdgeFadeNoteController(c,YES)` 移到这个判断之前。
  - 插件设置页：列表是 `WXGSettingsScrollView`，里面是玻璃卡片（`CABackdropLayer`），列表加 mask 会破坏卡片的背景采样（和“背景层不能放在 alpha<1 下”同一类问题）。所以不加列表遮罩，改为在列表之上放 `WXGEdgeCoverView`（`UIImageView`，壁纸图、同 frame、同 contentMode，mask = 1 − 渐隐曲线，只在列表范围内），模糊带在它之上。`WXGSettingsPage.wallpaperView` 提供壁纸视图。深浅色切换时覆盖层在下一次滚动 / 布局时换图。
  - 设置变更通知改为 `refresh:NO`（不强制重新找列表，值变化照样重建遮罩 / 改强度），插件设置页里拖滑杆当前页即时生效。
  - 列表尺寸变化（键盘等）时 `syncGeometry` 直接整套重算（`appliedSize`），模糊带长度和遮罩一起更新。
- 没确认：强度 3 的观感；微信“设置”页找到的列表（诊断 `edgeFade.pages[]`）；“设置”的子页面（通用、隐私等）没有加，用户只说了设置页。

## FIX64（只出测试版 A）

- 用户给了两份工程：自己的 WeChatFade 1.1（页面渐隐，“我的渐隐可以”）和别人的渐隐 + 模糊（WCLG*，“渐隐 bug 多”）。要求：用自己的渐隐 + 别人的模糊做一个模块，聊天页和其余页面（首页、通讯录、朋友圈、聊天设置）分别设上下的渐隐和模糊距离。
- `WXGEdgeFade.m`：
  - 渐隐 = WeChatFade 原样：找列表（属性 `m_tableView` 等 +100，再整页打分：宽 ≥55%、高 ≥220、table +90、collection +75、类名 table/list/mmtableview/msg/main…），列表 `layer.mask` = 129 段 smoothstep 的 `CAGradientLayer`（`WXGEdgeFadeMath.h`），遮罩随 `layer.bounds.origin` 移动，原遮罩关闭时放回。不再用 60 fps 计时器：列表的类第一次被管理时挂 `setBounds:` / `setFrame:` / `setCenter:` / `layoutSubviews`（类自己没有实现的，加一个调用父类当前实现的版本），里面用 16 个指针的数组预筛再找页面；页面出现时强制重新找列表，布局时最多每秒一次，列表丢失时立即。
  - 模糊 = WCLG 的 `variableBlur`：`WXGEdgeBlurView` 的 layerClass 就是 `CABackdropLayer`（scale 0.5），滤镜 `variableBlur`（`inputRadius` = 设置的强度，`inputMaskImage` = 4×256 的表图，按 Telegram 表 k/255 @ n/287，边缘 1 → 内侧 0，`inputNormalizeEdges`）。没有 `variableBlur` 时退回 `gaussianBlur` + 同一张表的 `CAGradientLayer` 遮罩。两条带插在列表父视图里、紧贴列表之上，frame = 列表可见区域的上 / 下一段；列表就是页面根视图时不加模糊。没有用 WCLG 的同色色板。
  - 页面分组按类（`isKindOfClass`）：聊天 `BaseMsgContentViewController`（及 `MMMsgContentViewController`）；其余 `NewMainFrameViewController`、`ContactsViewController`、`WCTimeLineViewController`、`AddContactToChatRoomViewController`（单聊信息）、`ChatRoomInfoViewController`（群聊信息）。
  - 入口：宿主的 `viewWillAppear:` / `viewDidAppear:` 钩子末尾 `WXGEdgeFadeNoteController(c,YES)`，`viewDidLayoutSubviews` 钩子里 `(c,NO)`；设置变更（`WXGSettingsChanged` / `WXGIntegrationChanged`）刷新全部页面。
- 设置：`WXGPreferences.edgeFade`（默认开）；`WXGConfig` `edgeChat*` / `edgeOther*` 各 5 项（渐隐上 / 下 96 / 112、模糊上 / 下 96 / 112、强度 10；范围 0–320 / 0–360 / 0–30）。模块 id `fade`（检查脚本只认小写 id），首页卡片在“个性化”。
- 诊断：`edgeFade`（每页的列表类名、frame、遮罩是否挂上、模糊带 frame、模糊方式、找列表 / 换列表 / 重建遮罩次数）。
- 没确认：`variableBlur` 的遮罩图按图层拉伸（WCLG 用整幅图，开源 VariableBlur 用 100×100，都能用，所以按拉伸处理）；模糊强度 10 的观感；各页面列表是否就是要的那个（看诊断 `edgeFade.pages[].list`）。用户手机上如果还装着 WeChatFade 会和这里抢同一个遮罩。

## FIX63（只出测试版 A）

- 用户对 FIX62：搜索已经触发（结果是对的），但搜索框里不显示词，删一格才出现 → 是 FIX62 填入后补的 `insertText:@"\n"`（模拟搜索键）留在了微信的输入框里。去掉了，只填文字（微信边输入边出结果）。
- 回弹在终点处“顿一下”：FIX60 的硬限制（变宽的一块最多挤进间距 65%）到头后停住。`WXGDockSearchSwapRight` 改为越过终点时变小的一块按越过量 × 0.35 被压扁（tanh 软上限为高度的 1/4），另一块跟着，间距不变。
- 用户要求展开后总是左搜索框、右关闭：按钮在左 = 交换（`WXGDockSearchSwapRight` 镜像）；按钮在右 = 不交换（`WXGDockSearchStay`：胶囊→搜索框、圆按钮→关闭按钮，两行插值）。
  - `WXGDockSearch` 的输入区拆成独立的 `fieldView`（放大镜 + 输入框），由宿主放在底栏行的最上层，跟着左边那块玻璃：按钮在左时放大镜随前缘移动；按钮在右时整个输入区在胶囊上淡入。按钮自己有放大镜和 × 两个图标（按钮在右时用）。`closesWhenOpen` / `onClose`：按钮在右时展开后点它就是关闭。`WXGDemoBar.showsClose`：按钮在右时底栏不显示 ×、搜索时不接触摸。
  - 搜索行加宽上限：按钮在左 64 pt；在右 min(64, 2×(30+搜索高度−底栏高度))，保证弹簧和外鼓仍在 40 pt 画布内。

## FIX62（只出测试版 A）

- FIX61 诊断：`lastHandoff` = “右上角搜索按钮：没有找到微信的搜索输入框”。用户截图：触发后是微信新的搜索页（左上返回、“搜索本地或网络结果”，键盘已弹出），文字没进去。结论：那个页面的输入框不是 UITextField（扫描窗口找不到，也没有 TextDidBeginEditing 通知），多半是网页输入框。
- 改动：
  - 用 `sendAction:to:nil` 找当前第一响应者（`UIResponder (WXGFirstResponder)` 分类）；不是我们的输入框且实现 `UIKeyInput`，持续 0.2 秒后 `insertText:` 填入，0.3 秒后按搜索键（UITextField：搜索栏代理 `searchBarSearchButtonClicked:` 或 return；其他：`insertText:@"\n"`）。最多等 4.2 秒，之后回退写入开始编辑的 UITextField。
  - 不在“微信”页时，切过去后每 0.03 秒检查首页右上角搜索按钮是否已在窗口里，在了就立刻触发（`pollHomeSearchEntry:`），不等刷新。
  - `WXGDockSearch` 的 `textFieldShouldBeginEditing:` 只在展开时返回 YES：系统关闭微信搜索页时会把焦点还给我们的输入框，导致键盘不落下。
  - `WXGDockSearchSwell`：整行外侧两端随弹簧外鼓（速度项 1.4% 行宽 + 越过终点的量 × 9% 行宽），高度加外扩量的 1/3。
- 没确认：“\n”提交在微信的网页输入框里是否等同按搜索；如果填入后没有搜索，看 `lastHandoff` 里的响应者类名。

## FIX61（只出测试版 A）

- 用户对 FIX60 的反馈：要看清展开动画，不要自动弹键盘；搜索框“又高又短”；两块玻璃的间距要能调；切换动画时有灰色遮罩闪一下（有一帧是矩形）；输入的文字没有转进微信搜索，只打开了搜索页。
- 改动：
  - `openDockSearch` 不再让输入框成为焦点；点输入框才弹键盘。
  - `WXGConfig` 新增 `dockSearchGap`（默认 12）、`dockSearchHeightRatio`（0.82）、`dockSearchWidthFraction`（0.94），在“底栏 → 搜索”。`WXGDockSearchLayout.h` 改成两行（平时一行、搜索一行）插值：边缘、高度随 t 过渡，形状上下居中；搜索行最多比平时宽 72 pt。
  - 交给微信搜索：诊断里 `lastHandoff` 是“UISearchBarTextField：不是焦点，未填入”。现在文字一直挂着，每 0.1 秒找当前聚焦的输入框（不是我们的）用 `insertText:` 填入，最多 2.6 秒；之后写入开始编辑的那个输入框（`text` + EditingChanged + 通知 + `searchBar:textDidChange:`）。微信搜索框在被隐藏的表头里开始编辑时只取消裁剪，不再重设 `tableHeaderView`（怀疑它让输入框失去焦点）。
  - 去掉了标签栏淡出时的 CAFilter 高斯模糊（怀疑灰色闪烁）；搜索按钮初始阴影路径为空。灰色闪烁的原因没有确认，要等用户说明出现在动画还是键盘弹出时。
- FIX60 的诊断确认首次切页的 `treeScanMS` 已降到 0.03–0.08 ms。

## FIX60（底栏搜索）

- **用户要求**：参照一段录屏和 React 的 DiscoverButton，把首页顶部的搜索移到底栏。底栏 = 标签栏胶囊 + 圆形搜索按钮；点搜索按钮，它用弹簧（刚度 230、阻尼 20、质量 1.2）展开成搜索框，标签栏收成 × 圆钮，内容淡出 / 模糊；点 × 反过来。材质用自己的玻璃，选中仍是透镜 + 选中胶囊。用户选了“方案 B”：底部是真的输入框（不是点按钮就直接打开微信搜索页，那样少了展开这一段）；按钮左右可选；顶部搜索栏可以开关隐藏。
- **结构**：
  - `WXGDockSearchLayout.h`：整行布局（`WXGDockSearchLayout(t,…)`，t 是弹簧值，0 标签栏 / 1 搜索），间隔 `WXGDockSearchGap`，淡入淡出曲线。“底栏宽度比例”现在是整行宽度。
  - `WXGDockSearch.m`：搜索按钮，`dockSurface` 玻璃（底栏那套参数），同步模式下 Metal 覆盖层隐藏（它在这个模式下什么都不画）。圆形时点按发 `UIControlEventPrimaryActionTriggered`；展开后是 `UITextField`，按“搜索”调 `onSubmit`。
  - `WXGDemoBar`：`searchMode`（整个底栏只是 × 按钮，发 `PrimaryActionTriggered`）和 `setSearchShape:progress:`。形变期间玻璃轮廓跟着宿主给的形状，透镜收起、Metal 覆盖层隐藏，标签栏由普通图层画（和点按滑行动画同一套静止画法：未选中图标挖洞、选中胶囊底色、胶囊里的选中图标），这些图层可以淡出、加模糊（不含背景层，FIX37 的限制不适用）。回到原形时先 `drawNow` 再一起切回覆盖层。
  - `WXGHost.m`：底栏和按钮放在同一个 `dockRow`（穿透触摸的 `WXGOverlay`），键盘出现时按键盘的时长和曲线整体上移。弹簧在宿主每帧里推进（先于底栏的 tick）。只在稳定的标签页根页面可用，转场、遮盖、设置页都会直接复原。
- **交给微信搜索**：按“搜索”后先找首页右上角那个被隐藏的 `onSearchButtonTapped` 按钮触发（找不到就让列表表头的 `WCSearchBar` 成为焦点）；不在“微信”页时先切过去。之后监听 `UITextFieldTextDidBeginEditingNotification`，微信的输入框一开始编辑，就全选并 `insertText:` 填入（等同键盘输入，微信会出结果）。0.45 / 1.2 / 3.3 秒各补查一次（找焦点输入框，或让可见的搜索框成为焦点），3.2 秒没成功就记下原因。结果在诊断 `dockOwnership.search.lastHandoff`。**没有在真机上验证过**。
- **隐藏顶部搜索栏**（默认关，开了底栏搜索才生效）：把只装着搜索栏的表头高度收成 0、裁剪，再赋回 `tableHeaderView`；微信的输入框在表头里开始编辑时放回来，编辑结束且清空后再收。关掉开关 / 底栏搜索 / 插件时恢复。
- **卡顿修复**：FIX59 诊断里第一次切到“我”页 `treeScanMS` 52.9 ms，第一次回“微信”页 27.5 ms，之后约 1 ms。判断是逐个视图 `NSStringFromClass`（Swift 类第一次取名要 demangle）。改成 `WXGIsPluginView`（按类判断自己的视图）、几个固定微信类按类比较、自定义导航栏先按位置筛再取名。下一份诊断要看 `treeScanMS` 是否降下来。
- **待确认**：B 的预设里流畅模式是开的（来自用户的导出），用户还没说要不要关。

## FIX59（测试版，按账号授权）

- **账号授权**：`WXGLicense.m` + 每份工程自己的 `WXGBuildProfile.h`。
  - 宿主每次刷新时，看到登录后的主界面（`r.tabs`）就开始读当前 wxid。读取方式依次是：`MMContext` / `MMServiceCenter` → `CContactMgr getSelfContact.m_nsUsrName`，`SettingUtil getLocalUsrName:` / `getCurUsrName`，`AccountStorageMgr.m_oSetting.m_nsUsrName`。
  - 读到后算 `SHA-256("WXGLiquidGlass.license.v1:"+wxid)`，和列表比对；每 3 秒复查一次。
  - 原来所有 `WXGPreferences.shared.enabled` 的判断都换成了 `WXGPluginEnabled()`（总开关且已授权）。刷新里 `available` 也要求已授权，未授权时走和总开关关闭相同的恢复路径。
  - 设置首页在未授权或读不到账号时，只显示状态卡（当前账号、复制账号、重新检测）。诊断里有 `license` 一项（wxid 已打码，含读取方式）。
- **两份工程**：A 绑定 wxid_mpuxjt2kgy2s22，B 绑定 wxid_wb0yvnj7a1m522，B 的 `WXG_HIDDEN_MODULES` 是 `@[@"refraction"]`。`WXG_DEFAULT_OPTICS_JSON` 是这一版的预设参数（新装和恢复默认时用），现在为空。
- **性能**：
  - 设置页卡片设为 `WXGGlassView.lightweight`：1 层背景，不做 RGB 色散和清晰环，最多 2 倍采样；设置页显示刷新降到 60 Hz；
  - 新增配置项 `performanceMode`（流畅模式）：所有玻璃同样处理，关闭时和 FIX58 相同。
- 配置导入导出这一版没有做。
- `tools/verify_fix58_scope.py` 是 FIX58 对 FIX57 的校验，FIX59 改过这些文件，它不再适用。


把这个压缩包和这份说明一起发给新对话即可。要排查问题，再附一份最新诊断（插件设置 → 基本设置 → 导出各页诊断 JSON）。

## 这一版是什么

FIX58 = **FIX57 + 新的设置界面 + 四类玻璃参数拆成“底栏 / 其余玻璃”两套**。用户对 FIX57 的评价是“基本没问题了”，然后要求重做设置界面。

用 `tools/verify_fix58_scope.py <FIX57 目录>` 校验：
- 拆分只改了 4 个文件：`WXGCommon.h`、`WXGConfig.m`、`WXGGlassView.m`、`WXGDemoBar.m`。撤回脚本里列出的改动后，与 FIX57 逐字相同。
- `WXGGlassView.m` 另有 2 处：清晰环遮罩改用新的 `WXGEdgeMaskBand.h`。结果逐字节相同，只是更快，用新测试 `EdgeMaskBandTests.c` 核对。
- 设置界面：`WXGSettings.m`、`WXGOpticalSettings.m` 重写，`WXGSettingsKit.h` 是新文件。
- `WXGHost.m` 只改了版本号。
- 其余文件（含透镜和着色器）与 FIX57 逐字相同；测试是 FIX57 的 41 个，加上新的 `EdgeMaskBandTests.c`。
- `Makefile` 加了 `PhotosUI`。

`tools/check_settings_coverage.py <FIX57 目录>` 检查 FIX57 的 71 项设置在新页面里都还在。

### FIX58 设置界面（用户的要求）

- **布局**：参照用户给的 Liquid UI 截图，但每行两张卡片（黄金比矩形）。没有搜索。
- **首页**：
  - 头部卡片：圆头像（可从相册换）、插件名、版本号、总开关；
  - 模块卡片：基本设置、底栏、折射强度和色散、模糊强度与范围、材质强度与范围、边框与渐隐、壁纸。
- **顶部**：没有底板。
  - 左边是返回按钮，位置、形状和宿主的玻璃返回按钮完全一样（`WXGMeasure`、`centerY`，与 `buildNavigation` 一致）；
  - 中间是标题胶囊；
  - 右边是强调色按钮，改设置页的文字和图标颜色。
- **卡片**：用“其余玻璃”参数的实时玻璃做背景，连续圆角。圆角可调（0–40，默认 26）。
- **壁纸模块**：设置页的浅色、深色壁纸可以分别导入。
- **作用范围**：除底栏和基本设置外，四个玻璃模块都有“底栏 / 其余玻璃”切换。用户说以后还要把“其余玻璃”再细分。
- 用户原话：“不要漏掉现有设置，做好我再看”。

### FIX57 是什么（透镜部分仍是这样）

FIX57 = **FIX47 的透镜 + FIX54 的其余部分 + 末端放松**。当时用 `tools/verify_fix57_scope.py <FIX54 目录> <FIX47 目录>` 逐文件校验（版本号除外）：

- 透镜 5 个文件（`WXGGlass.metal`、`WXGGlassView.m`、`WXGLensOptics.h`、`WXGMeshRefraction.h`、`WXGOptics.h`）：FIX47 的，加上 FIX57 的改动（撤回后与 FIX47 逐字相同）；`WXGShaderSource.h` 是重新嵌入的着色器；
- 其余 40 个源文件：FIX54 的（头像、置顶回到 FIX44；钱包顶部 = FIX47 底色 + FIX50 列表）；
- 测试：FIX47 的 5 个透镜测试、FIX54 的其余测试，加上新的 `LensEndRelaxTests.c`。

为什么从 FIX47 出发：用户对比 FIX56 后说“改的是对的”，但 FIX54 / FIX56 的透镜“唤起胶囊”有缺陷，比不上 FIX47（FIX47 的内缩以约 45° 接上外侧边框，FIX46 是 1.25 pt 的台阶）；FIX56 的末端处理“太机械、太狠”。FIX47 只在停到首尾标签时有一点粘连（截图里内部底栏连到透镜边、上下各一个小钩），用户要求“微修 47”。

FIX45–FIX57 每一版的说明都在 `ReferenceAnalysis/FIXnn_README_中文.md`，对应的压缩包用户手里都有。

## 项目是什么

微信（iOS 15.7 / 8.0.73，测试机 iPhone XS Max A12，60Hz）的 iOS 26 液态玻璃插件：底栏（4 个标签 + 透镜）、导航按钮、输入栏、菜单等改成液态玻璃。Theos 在手机上编译：`./build.sh rootless`。编译参数是 `-Wall -Wextra`，Theos 再加 `-Werror`：未使用的函数、变量，格式串与参数不符，结构体按位置初始化缺字段，都会直接编译失败（`WXGGlassView.m` 和网格测试按 FIX47 用文件级 pragma 关掉了缺字段警告，`WXGMeshOptics` 末尾的字段可以省略为 0）。不能用 `@available`（手机工具链缺 `__isPlatformVersionAtLeast`）。

## 架构（只剩同步模式）

- **玻璃** `WXGGlassView.m`：
  - 系统渲染的毛玻璃层（`CABackdropLayer`），每个颜色通道一层，带折射网格（`WXGMeshRefraction.h` 里的轮廓网格，按光学参数缓存）；
  - 材质遮盖：一层系统渲染的图层（FIX40 起常驻）；
  - 其上是 Metal 叠加层（`WXGGlass.metal`，运行时从 `WXGShaderSource.h` 编译），只画图标、描边、选中胶囊和透镜内容；
  - 同一块玻璃的底栏和透镜共用一个取样组（`_syncGroup`），取的是底栏下面的页面；
  - 图层顺序：底栏裁剪（毛玻璃 + 遮盖 + 叠加层）< 底栏边框 < 透镜裁剪（毛玻璃 + 叠加层）< 透镜边框。透镜里看不到底栏本身，透镜内的“内部底栏”全由着色器画。
- **底栏** `WXGDemoBar.m`：
  - 按下另一个标签：在渲染服务里浮起并滑到目标（`beginGlideToIndex`）；松手：落成胶囊（`dropTravel`）；拖动：交回逐帧跟手的透镜（`handOverTravelToFinger`）；拖到另一个标签松手：渲染服务里的落下动画（`beginTravelToIndex`）；
  - 动画期间 Metal 叠加层隐藏并停止绘制，结束时先画好静止状态，再瞬间交接；
  - 拖动形变见 `WXGElasticMotion.h`（FIX39 的手感，用户满意）。透镜停在首尾标签时外包底栏末端 `endWrap`（设置“首尾透镜外包距离”，2–10 pt，默认 4）。
- **宿主** `WXGHost.m`：路由和刷新、导航玻璃绑定、冷启动日志、逐帧归因（`dockProfile`）、预热、外观跟随页面、页面顶部底板清理（含钱包）。
- **图标** `WXGNativeIcons.m`。
- **设置**（FIX58 重写）：入口在微信“我 → 设置 → 微信 Liquid Glass”（推入页面），长按底栏会以弹出页打开。
  - `WXGSettingsKit.h`：共用接口。
  - `WXGSettings.m`：
    - `WXGSettingsStore`：强调色、卡片圆角、壁纸、头像；
    - `WXGSettingsCard`：玻璃卡片，`WXGGlassView` 设 `overlayHidden`，不用 Metal 画布；
    - `WXGSettingsPage`：页面框架，含壁纸、顶部三块玻璃、滚动内容、自己的显示刷新、取色器和图片选择器；
    - `WXGSettingsHome`：首页；
    - 原来的诊断页。
  - `WXGOpticalSettings.m`：
    - 7 个模块的规格表 `WXGModuleSpec`（每行带 `key`，分范围的行再带一个 `dock` 键）；
    - 行控件：滑杆、开关、颜色、操作、壁纸；
    - 模块页 `WXGSettingsModule`。
  - 键的前缀：`pref.` 写 `WXGPreferences`，`ui.` 写 `WXGSettingsStore`，没有前缀写 `WXGConfig`。
  - 页面类名都以 WXG 开头，宿主会当成“不支持”的页面，暂停自己的逐帧刷新。所以设置页从 `viewWillAppear` 到 `viewDidDisappear` 用自己的 `CADisplayLink`（`WXGSettingsTicker` 弱引用页面）驱动顶部按钮和卡片。卡片只在屏幕上时刷新玻璃（`WXGPresentedVisible`）；配置版本变了、尺寸变了而不在屏幕上的卡片会保持待刷新，滚进来时再更新。
  - 显示时隐藏微信导航栏。导航栏隐藏后系统左滑返回会失效，所以把它的代理换成 `WXGSettingsNavigationState`，只实现 `gestureRecognizerShouldBegin:`，有上一页就允许。微信原来的代理被强引用保存。
  - 这个对象挂在导航控制器上，还记着进入时导航栏是否隐藏。最后一个设置页离开时（顶部换成了非设置页；只是被弹出页盖住不算），把导航栏和代理都还原成进入前的样子；整个弹出页关闭时不处理。
  - 卡片刷新的规则：
    - 新出现的卡片立即刷新（`_glassNew`）；
    - 配置或尺寸变化引起的刷新每秒最多约 12 次（拖动滑杆时）；
    - 圆角按整数 pt 生效。
  - 取色器什么都不改就关闭时，不写入任何颜色。
  - 导入的图片在串行后台队列里缩放、编码、写文件。
  - 存储：
    - `com.runyu.WeChatLiquidGlass` 的 `settings.ui`：强调色、圆角；
    - 沙盒 `Library/Application Support/WeChatLiquidGlass/`：`settings-wallpaper-light.jpg`、`settings-wallpaper-dark.jpg`、`settings-avatar.png`。
- **底栏 / 其余玻璃拆分**（FIX58）：
  - `WXGConfig` 新增 15 个底栏参数：`dockRefraction`、`dockDispersion`、`dockEdgeWidth`、`dockBlur`、`dockBlurCoverage`，以及浅色、深色各一套的 `dock(Dark)RimHex`、`RimOpacity`、`BorderWidth`、`RimBrightness`、`RimFade`。原来的共用参数现在只给“其余玻璃”用。材质遮盖从 FIX29 起就分开了。
  - 读取方式：`opticsForDock:`、`rimForDock:dark:`、`rimHexForDock:dark:`；玻璃按 `_dockSurface` 选择。
  - 第一次启动时，底栏这套直接复制当时的共用值，所以外观不变。`reset` 两套都恢复。
  - 透镜的静止端（按压过渡的起点）、点按时滑过去的透镜（`WXGMakeTravelLensBackdrops`）都用底栏这一套。
  - 以后细分“其余玻璃”：再加一套属性和读取方法，在 `WXGModuleSpec` 里给行加对应的键，在模块页的范围切换里加一项。
- **清晰环遮罩**（FIX58）：`WXGGlassView updateEdgeMask` 用 `WXGFillRingMask`（`WXGEdgeMaskBand.h`）只算轮廓附近，其余填 0。结果与逐像素计算逐字节相同（`Tests/EdgeMaskBandTests.c`）。

## 当前效果

- **拖动 / 按住已选中标签时的透镜**（Metal 着色器 + 透镜的折射网格），FIX47：
  - 透镜里的底栏比外侧小（内缩，用户设置约 4.4 pt），内缩在“与内缩深度相同的距离”内完成，外侧边框以约 45° 接到内部边框（`WXGInnerInset`）；只被折射带弯曲、不放大；不做颜色分离；
  - 折射带：FIX21（两端宽、上下按比例窄；用户 FIX49 时两端 20.26、上下比例 0.305、透镜折射 4.21），每个像素在底栏外时 4 pt 内收到上下宽度（`WXGLensEdgeWidthAtBar`，图标、内部底栏、页面都用它）；
  - **FIX57 末端**：透镜外沿离底栏末端 10 pt 起，到越过末端 2 pt 止（smoothstep），这一半透镜弯曲**内部底栏和页面**的折射带放松到上下边宽度（`WXGLensEndReach` / `WXGLensEndRelax`），图标仍用 FIX47 的。停在首尾标签时总是完成：内部底栏露出圆头，和透镜边之间一圈缝。其余位置与 FIX47 逐像素相同。着色器每个像素从统一变量里算（统一变量结构没变），`WXGGlassView.m` 给页面网格算同一个值（1/8 取整，`WXGMeshOptics.endLeft/endRight`）。
- **点按另一个标签时滑过去的透镜、拖到另一个标签松手后的落下**（渲染服务里的 `_travelLens`）：FIX47 原样，里面的底栏和外面一样高，末端不放松。
- **头像、置顶**：FIX44 原样（FIX45–FIX47 的头像读取、无玻璃描边、置顶下移都撤掉了）。**钱包顶部**：FIX47 整页底色 + FIX50 列表可画到导航栏下方，用户已确认有效。

## 新对话先看：点按和拖动是两个不同的透镜

- **拖动 / 按住已选中的标签**：Metal 着色器画的透镜。毛玻璃层和底栏共用取样组，取的是底栏下面的页面，着色器在上面画内缩的底栏。
- **按下另一个标签（滑过去、按住不动）/ 松手落下**：`WXGDemoBar.m` 里渲染服务的透镜（为了滑动不掉帧）。毛玻璃层用自己的取样组 `wxg.travel`（`WXGMakeTravelLensBackdrops`，网格固定、整段动画不变），取到的是**含全高底栏**的画面，自己也不画内部底栏。
- **只改着色器或拖动透镜网格的效果，点按时都看不到**。FIX53 试过让点按透镜共用取样组、自己画内部底栏，用户说乱套了。

## 用户对透镜两端的要求（原话整理）

- 末端时应早已把缩小的内部底栏完全包进透镜，不能还延续到透镜外圈（“透镜外的部分”指透镜的外圈，也就是折射带，不是透镜外面）。
- 两端的折射范围要像上下边那样收敛；已经在折射的图标、文字按原来的范围完成折射，只有底栏不再参与新的折射。直线段结束后不再和透镜边框有连线；要“脱离原底栏的效果，而不是有粘连”。
- FIX56 之后：“改的是对的”，但“太机械、太狠”；以 FIX47 为底“微修”，FIX47“比较丝滑”，只需优化停到最右端时的那点粘连，“收敛折射范围到一个值就行”。
- 上下边的折射以 FIX43 / FIX44 为准，不要改坏。
- 参考：`ReferenceAnalysis/FIX52_iOS26_right_end_frames.png`、`FIX52_iOS26_separation_frames64-80.png`（iOS 26 录屏逐帧：第 70→74 帧右端折射带收掉）。

## FIX45–FIX57 试过什么（结论）

- FIX45：透镜内底栏边缘轻微色散开关 → 问题严重、关不掉（实为 FIX44 的分通道取样）。
- FIX46：去掉放大使内缩恢复、修锯齿、去掉底栏颜色分离。
- FIX47：内缩约 45°（外侧边框接到内部边框）、透镜端伸出底栏时折射带变窄 → 用户后来认为最丝滑，是 FIX57 的透镜底子；当时的头像 / 置顶改动无效，已撤回。
- FIX48：两端“交点进入圆弧即骤降”到 0。
- FIX49：45° 改为从交点列水平算，但把上下边一起改了 → 上下边折射带被改坏。
- FIX50：透镜整体回退到 FIX43 → 用户：不该整体回退；钱包列表可画到导航栏下方（保留）。
- FIX51：透镜只在首尾图标之间折射 → 太早停掉折射。
- FIX52：每侧“粘连 / 分离” → 用户指出内外同高（看的是点按透镜）。
- FIX53：点按透镜共用取样 + 自己画内部底栏 → 乱套。
- FIX54：FIX46 透镜 + FIX44 头像 / 置顶 + 钱包修复。
- FIX55：交点处 45° 连接曲线 + 末端吸入 + 收窄 → “差这么多”，连接和吸入都算粘连。
- FIX56：FIX54 + 交点进入圆弧后 3 pt 内把这一侧折射带收到上下宽度 → 方向对，但太机械、太狠；FIX54 透镜唤起胶囊不如 FIX47。
- FIX57：FIX47 + 末端放松 → 用户真机确认“基本没问题了”。
- FIX58：新设置界面 + 底栏 / 其余玻璃拆分（本版），待用户真机确认。

教训：先确认用户看到的是哪个透镜；按用户的尺寸和设置模拟出图（`tools/lens_ends_sim/`，用户截图的样子能复现出来）；一次只改一处；用户说“只改 X”就只改 X。

## 头像、置顶（待做，当前为 FIX44 原样）

- 聊天标题的头像模式：可以去掉头像背后的玻璃（或加开关）；读取对方或群聊的真实头像，大小可自定义；名字在头像下方（参照 iMessage）；关掉玻璃时描边画在头像圆形图片的边缘上，可调颜色、透明度、渐隐；
- 置顶栏要整体下移，不被头像和标题挡住，触摸和展开都要跟着走。
- 已知：首页会话的标题不是普通文字标签（名字可能是数学粗斜体字符）；FIX46 读到的“对方消息头像”是语音按钮；置顶栏 `MMMsgCommonTipsView` 不在聊天页控制器的视图里，位移变换、改位置、改安全区都失败过；`WXGDecorations.m` 已经找得到它（kind = `pinnedRow`），可以从那里入手。FIX45–FIX47 的做法见各自的 README。

## 已经定下来的（不要再改回去）

- 拖动形变：FIX39 的速度映射（900 pt/s）、范围 0.70–1.60、最窄到底栏高度的 90%。
- 点按切换：FIX95 起是真实透镜按脚本逐帧走（FIX43 时长和曲线），微信等透镜落下再切换；渲染服务里的做法（FIX33–FIX94）只作为“点按时用简化透镜”选项。用户明确说点按只是按设计好的速度和过程量自己走，不能换成别的东西。
- 冷启动：图标缓存、备用材质底板保留到第一帧、材质层层级检查。
- 透镜：FIX47 的 45° 内缩和伸出底栏变窄的折射带；钱包顶部：FIX47 + FIX50 的做法。

## 工作方式（每次改动后）

```bash
sh tools/test_geometry.sh                      # C 测试（-Wall -Wextra -Werror）
python3 tools/check_unused_statics.py          # 未使用的文件级 static（-Werror 下会编译失败）
python3 tools/embed_shader.py                  # 改了 WXGGlass.metal 后重新嵌入着色器
python3 tools/check_msl.py                     # 着色器的语法 / 类型检查（模拟 Metal 头文件，当 C++ 编译）
python3 tools/verify_fix58_scope.py <FIX57目录>     # 本版的来源校验
python3 tools/check_settings_coverage.py <FIX57目录> # FIX57 的设置项在新页面里都还在
python3 tools/settings_preview/render_fix58_preview.py   # 设置页布局示意图（与代码同一套尺寸）
python3 tools/lens_ends_sim/make_figures57.py  # 重画 ReferenceAnalysis/FIX57_* 对照图（numpy、scipy、Pillow、Noto CJK，约 2 分钟）
```

Objective-C 可以用真实 SDK 头文件做语义检查：`GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout https://github.com/theos/sdks`，稀疏检出 `iPhoneOS16.5.sdk` 的 `usr/include`、`Frameworks/**/Headers`、`Frameworks/**/Modules`（约 88 MB），然后对每个 `.m`：`clang -x objective-c -target arm64-apple-ios14.0 -isysroot <sdk> -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -fsyntax-only -ISources <file>`。

另外：新加的局部变量、格式串要逐一核对；`WXGMeshOptics` 现在 19 个字段（FIX47 的 4 个底栏字段 + FIX57 的 2 个末端字段，0 = 关闭）；静态函数若在定义之前使用，要加前置声明。
