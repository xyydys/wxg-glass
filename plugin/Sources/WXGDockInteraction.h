#import <UIKit/UIKit.h>
#import "WXGCommon.h"

// Only the native bar's own recognizers are gated. The dock's long press and
// UIKit control tracking keep their existing behavior.
FOUNDATION_EXPORT void WXGProtectDockTouches(UIView *dock,UITabBar *bar);
FOUNDATION_EXPORT void WXGRestoreDockTouchDelegates(UITabBar *bar);
FOUNDATION_EXPORT NSDictionary *WXGDockTouchProtectionMetrics(UITabBar *bar);

@interface WXGDemoBar (WXGDockInteractionMetrics)
- (NSDictionary *)dockInteractionMetrics;
@end
