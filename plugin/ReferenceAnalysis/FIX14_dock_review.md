# FIX14 dock overlay review

Read-only review of Sources/WXGHost.m and WXGDockPresentation.h. No source changes.

## Verified paths
- Current diagnostics route is MainTabBarViewController / StatusBarMonitorNavigationController / NewMainFrameViewController. isDockRoot checks navigation first controller and selected tab ancestry, so it fits the observed route. It excludes BaseMsgContentViewController and ChatRoomInfoViewController.
- observeTransition caches fromRoot and toRoot before any refresh changes route. A return to root is visible and non-interactive; a push away hides immediately. finish uses cancellation to choose the cached source rather than the destination. The C policy tests cover the state truth table.
- The dock owner stays the root overlay. No interpolation from native MMTabBar transform or partial-exposure mask remains. buildDock uses window safe-area geometry and the existing width/height/lift configuration.
- The complete native tab bar is paint-masked. Its hidden/alpha/transform are not overwritten. MMTabBar hitTest exits only for the known suppressed bar with enabled replacement in the overlay. Programmatic target-action dispatch remains valid because WXGCanForward checks enabled/action bindings and does not depend on hitTest or the paint mask.
- setActive:NO cancels outstanding dock interaction, so hiding on push cancels tracking.
- The root overlay is a child of the app root view, not a second UIWindow. UIKit presentations normally remain above this view. Refresh does not bring overlay forward while it has detected a presented controller.

## Recommended guard additions
1. refresh presented-controller early return and presentSettings currently pause the host but keep the last dock userInteractionEnabled state. Disable its interaction and cancel tracking while covered, retaining its material view to meet the existing persistence requirement. Stable refresh restores eligibility.
2. Add a final eligibility guard inside dockChanged: against covered, native transition, non-root route, disabled preferences, or non-Settled presentation. This rejects already-queued UIControl events after state changes.
3. Telemetry nativeExposureMask:NO refers to no partial dock clip, while the native bar is intentionally paint-masked. A nativePaintSuppressed or nativePaintMask boolean avoids confusing these two different masks. Existing foregroundChild and returnPolicy fields describe actual implementation correctly.

## Limits
- The C tests prove the state policy, not UIKit transition callback ordering or app visual stacking. A very fast pop before any root build remains dependent on the existing lazy dock creation.
- Original ThemeBox was unpacked, Mach-O symbols and 3190 ObjC methods parsed. Its actual navigation hook implementation was not established from disassembly because the user explicitly replaced that research scope with the simple foreground-return policy. Method names alone are not evidence that ThemeBox uses this implementation; do not claim its internals were replicated.
- This policy intentionally shows the entire dock in front during return. It does not claim Telegram-like page-bound parallax or partial tab motion.
