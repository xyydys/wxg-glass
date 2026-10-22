#import "WXGIntegration.h"

static char WXGDecorationKey;
@interface WXGDecoration : NSObject
@property(nonatomic,weak) UIView *host,*body;
@property(nonatomic,strong) WXGSurface *surface;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic,copy) NSString *kind;
@property(nonatomic) BOOL applying;
@property(nonatomic) BOOL validBody;
@property(nonatomic) CFTimeInterval lastPaint;
@property(nonatomic) NSUInteger bodyChildren,hostChildren;
@property(nonatomic) NSUInteger earlyRetries;
@property(nonatomic) UIUserInterfaceStyle appearance;
@end
@implementation WXGDecoration
@end

@interface WXGDecorations ()
@property(nonatomic,strong) NSHashTable<WXGDecoration *> *entries;
@property(nonatomic) NSUInteger mounts,reuses;
- (void)reassertVisiblePaint;
@end

@implementation WXGDecorations
+ (instancetype)shared {
    static WXGDecorations *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];manager.entries=[NSHashTable weakObjectsHashTable];
        // FIX29: just before every Core Animation commit, re-assert the cleared
        // native paint of on-screen menus. WeChat re-skins its reused plus
        // menu while opening it, outside any layout we hook; whatever it set
        // in this run-loop pass is undone before it can be drawn.
        __weak WXGDecorations *weakManager=manager;
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){WXGPerfTimePluginWorkAs("decorations",^{[weakManager reassertVisiblePaint];});});   // FIX102: timed
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
    });
    return manager;
}
- (void)reassertVisiblePaint {
    for(WXGDecoration *entry in _entries) {
        if(!entry.host.window || entry.applying)continue;
        @try {[entry.states reapply];} @catch(__unused NSException *error) {}
    }
}
- (NSString *)kindForHost:(UIView *)view {
    NSString *name=NSStringFromClass(view.class);
    if([name isEqual:@"MMMsgCommonTipsView"])return @"pinnedRow";
    if([name isEqual:@"MainFrameActionFloatView"])return @"homeMenu";
    if([name isEqual:@"MMMenuContentView"])return @"messageMenu";
    if([name isEqual:@"WCOperateFloatView"])return @"momentsMenu";   // FIX108 C: 朋友圈的 赞 / 评论
    return nil;
}
- (UIView *)bodyForHost:(UIView *)host kind:(NSString *)kind {
    if([kind isEqual:@"pinnedRow"]) {
        for(UIView *v in WXGViews(host,100))if([v isKindOfClass:UIControl.class] &&
            [WXGActionNames((id)v) containsObject:@"performBgAction"] && v.bounds.size.width>100)return v.superview;
        return nil;
    }
    NSString *item=[kind isEqual:@"homeMenu"]?@"RightTopMenuItemBtn":[kind isEqual:@"momentsMenu"]?@"WCLikeButton":@"MMMenuItemView";
    for(UIView *v in WXGViews(host,160))if([NSStringFromClass(v.class) isEqual:item] &&
        v.superview!=host && v.superview.bounds.size.width>60)return v.superview;
    return nil;
}
- (void)clearPaint:(WXGDecoration *)entry {
    UIView *host=entry.host,*body=entry.body;WXGStateBag *states=entry.states;
    NSMutableArray *content=[NSMutableArray array];
    NSArray *nodes=WXGViews(host,200);
    for(UIView *v in nodes)if([v isKindOfClass:UIControl.class] || [v isKindOfClass:UILabel.class]) [content addObject:v];
    [states stripChrome:host preserving:content];[states clear:body];
    // The plus menu has a UIImageView *container* around its real buttons.
    // Clear its image pixels, never its alpha or its descendants.
    for(UIView *v=body;v && v!=host.superview;v=v.superview) {
        if([v isKindOfClass:UIImageView.class])[states clearImagePaint:(id)v];else [states clear:v];
        if(v==host)break;
    }
    for(UIView *v in nodes) {
        if(WXGIsPluginView(v))continue;
        if(![entry.kind isEqual:@"pinnedRow"]) {
            if([v isKindOfClass:UILabel.class])[states adaptLabelColor:(id)v];
            if([v isKindOfClass:UIImageView.class] && v.bounds.size.width>4 && v.bounds.size.width<=48 && v.bounds.size.height<=48)
                [states adaptMonochromeImage:(id)v];
        }
        if([v isKindOfClass:UIControl.class]) {
            [states clear:v];id paint=WXGRead(v,@"_backgroundView");
            if([paint isKindOfClass:UIImageView.class] && [paint isDescendantOfView:v] &&
               ((UIView *)paint).bounds.size.width>=v.bounds.size.width*.85)[states clearImagePaint:paint];
        }
        // Native menu dividers and the small pointer are paint, not actions.
        if(![v isKindOfClass:UIControl.class] && ![v isKindOfClass:UILabel.class] && !v.gestureRecognizers.count && !v.subviews.count) {
            CGRect rect=[v convertRect:v.bounds toView:body];
            BOOL divider=rect.size.height<=1 && rect.size.width>body.bounds.size.width*.35;
            // FIX108 C: the Moments bar's upright line between 赞 and 评论 (black on glass: too hard).
            if([entry.kind isEqual:@"momentsMenu"] && rect.size.width<=1.5 && rect.size.height>body.bounds.size.height*.35)divider=YES;
            BOOL pointer=[entry.kind isEqual:@"messageMenu"] && [v isKindOfClass:UIImageView.class] &&
                rect.size.height<=22 && rect.size.width<=50 && CGRectGetMidY(rect)>CGRectGetMaxY(body.bounds);
            if(divider || pointer)[states hide:v];
        }
    }
    if([entry.kind isEqual:@"pinnedRow"]) {
        // Collapsed stacks have two uninteractive 12pt trailing sheets.
        for(UIView *parent=host.superview;parent;parent=parent.superview) {
            if([NSStringFromClass(parent.class) isEqual:@"MMNewMsgContentNavBar"])break;
            if(parent.bounds.size.height>260)break;
            if(![parent isKindOfClass:UIControl.class])[states clear:parent];
            for(UIView *v in parent.subviews)if(v!=host && !v.subviews.count && !v.gestureRecognizers.count &&
                ![v isKindOfClass:UIControl.class] && ![v isKindOfClass:UILabel.class] &&
                ![v isKindOfClass:UIImageView.class] && v.bounds.size.height<=16 && v.bounds.size.width>body.bounds.size.width*.8)[states clear:v];
        }
    }
    [states reapply];
}
- (void)nativeHostLaidOut:(UIView *)view {
    if(!NSThread.isMainThread)return;
    if([NSStringFromClass(view.class) isEqual:@"MMMsgTipsMixedListExpandView"]) {
        for(UIView *child in WXGViews(view,40))if([child isKindOfClass:UITableView.class])
            for(UITableViewCell *cell in ((UITableView *)child).visibleCells)
                for(UIView *row in WXGViews(cell.contentView,60))if([NSStringFromClass(row.class) isEqual:@"MMMsgCommonTipsView"])[self nativeHostLaidOut:row];
        return;
    }
    NSString *kind=[self kindForHost:view];if(!kind)return;
    WXGDecoration *entry=objc_getAssociatedObject(view,&WXGDecorationKey);
    // A menu owns this entry through an associated object. Release the temporary
    // capture exclusion on detachment, otherwise entry -> glass -> host forms
    // a retain cycle each time WeChat creates a fresh native menu instance.
    if(!view.window){entry.surface.active=NO;entry.surface.glass.backdropExclusions=@[];return;}
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav) {
        if(entry){[entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;entry.surface.glass.backdropExclusions=@[];}return;
    }
    if(entry.applying)return;
    if(!entry) {
        entry=[WXGDecoration new];entry.host=view;entry.kind=kind;entry.states=[WXGStateBag new];
        entry.surface=[WXGSurface new];entry.surface.role=kind;entry.surface.materialOnly=YES;
        entry.surface.userInteractionEnabled=NO;entry.surface.isAccessibilityElement=NO;
        objc_setAssociatedObject(view,&WXGDecorationKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_entries addObject:entry];++_mounts;
    }else ++_reuses;
    entry.applying=YES;
    @try {
        UIView *body=[self bodyForHost:view kind:kind];
        if(!body || body.bounds.size.width<40 || body.bounds.size.height<16) {
            entry.validBody=NO;entry.surface.active=NO;entry.surface.hidden=YES;
            // FIX28: WeChat lays the plus menu out once before adding its
            // buttons. Its own background must not render meanwhile: clear the
            // host's paint now and look again on the next main-queue turn.
            if(![kind isEqual:@"pinnedRow"]) {
                // FIX108 E: not for the Moments bar: its dark plate is what
                // keeps its white 赞 / 评论 readable until the glass is there
                // (stripped with no body found, it stayed bare on the white feed).
                if(![kind isEqual:@"momentsMenu"]) {
                    [entry.states stripChrome:view preserving:@[]];
                    for(UIView *v in WXGViews(view,80))
                        if([v isKindOfClass:UIImageView.class] && v.bounds.size.width>60)[entry.states clearImagePaint:(id)v];
                    [entry.states reapply];
                }else {
                    // FIX108 F: the same bar collapsing for a pass (opening from
                    // zero width, a quick close and reopen): its glass stays as it
                    // is; a new one never found: WeChat's plate back, and the
                    // paint cleared again in full once its body turns up.
                    if(entry.body && [entry.body isDescendantOfView:view] && entry.lastPaint>0){entry.validBody=YES;entry.surface.hidden=NO;return;}
                    [entry.states restore];entry.lastPaint=0;
                }
                if(entry.earlyRetries<6) {
                    ++entry.earlyRetries;__weak UIView *weakHost=view;
                    dispatch_async(dispatch_get_main_queue(),^{if(weakHost)[self nativeHostLaidOut:weakHost];});
                }
            }
            return;
        }
        entry.earlyRetries=0;
        if(entry.body!=body){[entry.states restore];entry.body=body;entry.lastPaint=0;}
        entry.validBody=YES;
        WXGSurface *surface=entry.surface;
        // FIX27: the message long-press menu radius is a setting; the plus menu keeps 18.
        surface.maximumCornerRadius=[kind isEqual:@"pinnedRow"]?MIN(body.bounds.size.height*.5,32):
            [kind isEqual:@"messageMenu"]?WXGConfig.shared.messageMenuCornerRadius:
            [kind isEqual:@"momentsMenu"]?body.bounds.size.height*.5:18;   // FIX108 C: the Moments bar is a capsule
        surface.glass.sourceView=[kind isEqual:@"pinnedRow"]?WXGContentSourceForView(view):(_source?:WXGContentSourceForView(view));
        surface.glass.backdropExclusions=@[view];
        UIView *parent=body;CGRect material=body.bounds;
        if([kind isEqual:@"pinnedRow"]) {
            // Probe: every native tips row has its own 44pt performBgAction.
            // Use that action's rectangle, not a shorter/clipped paint child.
            parent=view;material=[body convertRect:body.bounds toView:parent];
            for(UIView *child in WXGViews(body,80))if([child isKindOfClass:UIControl.class] &&
                [WXGActionNames((id)child) containsObject:@"performBgAction"] && child.bounds.size.height>=16) {
                material=[child convertRect:child.bounds toView:parent];break;
            }
            surface.maximumCornerRadius=MIN(material.size.height*.5,32);
        }
        [surface placeMaterial:material inParent:parent];
        if(parent.subviews.firstObject!=surface)[parent insertSubview:surface atIndex:0];
        CFTimeInterval now=CACurrentMediaTime();
        if(!entry.lastPaint || now-entry.lastPaint>.35 || entry.bodyChildren!=body.subviews.count ||
           entry.hostChildren!=view.subviews.count || entry.appearance!=view.traitCollection.userInterfaceStyle) {
            [self clearPaint:entry];entry.lastPaint=now;
            entry.bodyChildren=body.subviews.count;entry.hostChildren=view.subviews.count;
            entry.appearance=view.traitCollection.userInterfaceStyle;
        }else [entry.states reapply];
        surface.hidden=NO;surface.active=view.window && WXGVisible(body,view.window);
    } @catch(NSException *error) {
        WXGLog(@"局部材质 %@：%@",kind,error.reason);[entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;
    } @finally {entry.applying=NO;}
}
- (void)refresh {
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav){[self restore];return;}
    for(WXGDecoration *entry in _entries)if(entry.host.window)[self nativeHostLaidOut:entry.host];
}
- (void)applyConfiguration {
    for(WXGDecoration *entry in _entries)[entry.surface applyConfig];[self refresh];
}
- (NSArray<WXGSurface *> *)visibleSurfaces {
    NSMutableArray *out=[NSMutableArray array];
    BOOL enabled=WXGPluginEnabled() && WXGPreferences.shared.nav;
    for(WXGDecoration *entry in _entries) {
        BOOL visible=enabled && entry.validBody && entry.host.window && WXGVisible(entry.body,entry.host.window);
        entry.surface.active=visible;
        if(visible){entry.surface.hidden=NO;[entry.states reapply];entry.surface.glass.sourceView=[entry.kind isEqual:@"pinnedRow"]?WXGContentSourceForView(entry.host):(_source?:WXGContentSourceForView(entry.host));[out addObject:entry.surface];}
    }return out;
}
- (void)restore {
    for(WXGDecoration *entry in _entries){[entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;entry.surface.glass.backdropExclusions=@[];}
}
- (NSDictionary *)evidence {
    NSMutableArray *rows=[NSMutableArray array];
    for(WXGDecoration *entry in _entries)if(entry.host.window)[rows addObject:@{@"kind":entry.kind,@"host":NSStringFromClass(entry.host.class),
        @"visible":@(entry.surface.active),@"nativeActionsRetained":@YES,@"frame":NSStringFromCGRect(entry.body.bounds)}];
    return @{@"mounts":@(_mounts),@"reuses":@(_reuses),@"hosts":rows};
}
@end
