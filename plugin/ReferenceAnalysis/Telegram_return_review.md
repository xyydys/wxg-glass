# Telegram iOS 交互返回与浮动底栏：只读源码核对

核对日期：2026-10-04。官方仓库 `TelegramMessenger/Telegram-iOS`，固定提交 `6ad963e5b62d354da79040f388ae2b9132fb17b8`（GitHub 返回的提交日期 2026-07-17）。仅下载 Git tree 和 7 个相关 Swift 文件；没有导入或复制 Telegram 实现到插件。以下结论来自源码，不代表在当前设备运行了 Telegram。

## 结论

Telegram 可以正确做到“底栏随返回目标页面平移，并由离开的页面自然遮挡”，因为它拥有整个导航容器、页面栈和交互转场，**底栏直接属于作为栈底第一页的 TabBarController 页面**。它并不是在系统 `UITabBar` 上加一个固定位置的遮罩，也不是返回一开始就把底栏移到整个 window 的最上层。

可以借鉴的是父子层级和生命周期原则；不能仅移植几个位移常数，就让微信内部 `MMTabBar` 与 Telegram 的独立导航容器等价。微信插件没有 Telegram 对所有页面、快照和转场取消的控制权。现有 FIX13 把自建底栏放进 `MMTabBar`，其可见性仍受微信原生 tabbar 的隐藏、背景及私有转场快照管理；截图中的完全缺失/被原底栏遮住说明这种假设不足。

## 精确证据

全部链接固定到同一提交：

1. **导航栈先装一个完整 tab 页面，而非让 tabbar 与页面共享 window 坐标。**
   - [`TelegramRootController.swift` 73、201–249](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TelegramUI/Sources/TelegramRootController.swift#L201-L249)：`TelegramRootController: NavigationController`；创建 `TabBarControllerImpl`，设置其子控制器，然后 `self.pushViewController(tabBarController, animated: false)`。
   - [`TabBarController.swift` 47–52、156–157](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TabBarUI/Sources/TabBarController.swift#L47-L52)：这是自定义 `ViewController`，其 `displayNode` 是 `TabBarControllerNode`。

2. **底栏是该 tab 页面内的浮动子视图。**
   - [`TabBarContollerNode.swift` 76–98](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TabBarUI/Sources/TabBarContollerNode.swift#L76-L98)：tab 内容放在本页底部层级，`bringSubviewToFront(tabBarView)` 只作用于本页 `self.view`，不是整个 window。
   - [同文件 291–298](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TabBarUI/Sources/TabBarContollerNode.swift#L291-L298)：在本页坐标里设置浮动底栏 frame，并 `self.view.addSubview(tabBarComponentView)`。

3. **交互返回两页整体移动，遮挡由真实视图层级产生。**
   - [`NavigationContainer.swift` 213–279](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/Navigation/NavigationContainer.swift#L213-L279)：手势 began 取得栈顶与前一页，更新目标页布局/生命周期；构造 `NavigationTransitionCoordinator`。changed 使用手势横向位移除以容器宽度得到 progress。
   - [`NavigationTransitionCoordinator.swift` 100–124](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/NavigationTransitionCoordinator.swift#L100-L124)：pop 时把 `bottomNode` 插入 `topNode` 下面。两者均是整页。暗层和阴影另放在 top 下方；圆角只临时裁剪 top 页。
   - [同文件 138–187](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/NavigationTransitionCoordinator.swift#L138-L187)：普通非 flat 返回，`top.x = progress × width`，`bottom.x = (progress - 1) × width × 0.3`；对两页整体 `updateFrame`。因此底栏会随目标页从 x=-0.3W 到 x=0，其右侧由前景聊天页遮挡，而非固定在最终位置只改变裁剪宽度。
   - flat 模式例外：bottom.x=-(1-progress)×width；不能将 0.3 当作微信通用数值。

4. **取消与完成均有明确归属恢复。**
   - [`NavigationContainer.swift` 281–317](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/Navigation/NavigationContainer.swift#L281-L317)：速度/进度判断完成还是取消；取消后恢复顶页 appearance 并结束目标页 appearance。完成时从栈删除离开的控制器。
   - [`NavigationTransitionCoordinator.swift` 233–262](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/NavigationTransitionCoordinator.swift#L233-L262)：取消动画将 progress 回到 0；pop 取消移除 bottomNode、移除暗层/阴影、自定义导航恢复、恢复 top 页圆角。
   - [同文件 307–347](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/NavigationTransitionCoordinator.swift#L307-L347)：完成到 progress=1，清理过渡节点，恢复原 `clipsToBounds`/圆角。动画时长按剩余距离和速度计算。

5. **容器裁剪是导航根边界，不是底栏单独的揭露 mask。**
   - [`NavigationController.swift` 1495–1500](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/Display/Source/Navigation/NavigationController.swift#L1495-L1500)：导航控制器根 `self.view.clipsToBounds = true`。
   - coordinator 仅将上层页面圆角化，最终恢复；在本次核对的转场代码里，没有按返回比例给底栏单独改裁剪宽度。

## 对微信插件能直接采用与不能保证的边界

可以考虑的完整做法：让自建底栏归属**真正参与本次转场的根页面/目标容器**，与该页面使用同一坐标系，在微信已有 coordinator 的完成/取消回调中恢复拥有者。保留原生导航动画，不自己跑一条全新的进度曲线。仅由两个完整页面的原有遮挡决定可见部分。同时必须处理微信生成的原 tabbar 快照，避免重复显示；玻璃背景也必须采样当前实际帧，而不是结束帧或旧页面。

这需要同时确认聊天返回和视频号返回的 native from/to view 层级。仅凭这次截图与普通诊断 JSON 无法保证两个私有路径共享父节点：其背景/快照/遮挡可能不同。特别是当前 `MMTabBar` 在 `UITabBarController` 内的移动，并不等于 Telegram 中整个 tab 根页面的移动。不能把 Telegram 的实现说成已验证的微信修复。

用户已明确允许求稳：若不能可靠得到 native 目标页归属，返回开始时将**已有自建底栏**放到受控前景层，完成返回后归还，取消后隐藏并恢复原归属。这个方案有意放弃“按页面比例部分显示”，换取稳定；不是 Telegram 做法。仍需：

- 仅在返回目标为四个首页 tab 的转场启用；聊天↔聊天设置不套用。
- 取消和完成均恢复；转场中底栏不接管返回手势，禁止意外 tab 切换。
- 原生底栏及快照仍隐藏，确保只有一套底栏。
- 不改导航 animator/delegate，不新加全屏手势，不固定显示在所有页面。

建议这轮不要为模仿 Telegram 重新接管微信导航栈。可先落实受控前景返回策略；若未来要恢复真实跟随效果，以明确的 native from/to view 证据单独开发，并保留稳定策略作为退路。
