#import "WXGIntegration.h"

/* FIX85: keyboard trace, for the "keyboard rises abnormally" report (a chat
   with the input bar floating about 200 pt above the keyboard). Nothing in
   the plugin moves the input bar vertically (it only resizes the text view's
   host sideways, WXGInput.m) or focuses a field outside the dock search's
   4-second handoff, so the cause is not known yet. This records, for the next
   diagnostics export (liveSamplingAtExport.keyboard):
   - every keyboard notification (will / did show, hide, change frame): its
     frames, duration, whether it is this app's keyboard, the first responder
     and its ancestors, the page on screen; and every text field / view that
     starts editing (what took the keyboard);
   - half a second after the keyboard settles, the chat input bar
     (MMInputToolView, found from the first responder) against the keyboard:
     when its bottom is more than 16 pt from the keyboard's top, a snapshot
     of the bar, its subviews and its ancestors (classes, frames, hidden,
     alpha), logged as 键盘：输入栏与键盘相差. */

static NSMutableArray<NSDictionary *> *WXGKeyboardEvents,*WXGKeyboardGaps;
static NSUInteger WXGKeyboardChecks,WXGKeyboardGapCount;
static CGRect WXGKeyboardLastEnd;

static NSString *WXGKeyboardClock(void) {
    static NSDateFormatter *f;static dispatch_once_t once;
    dispatch_once(&once,^{f=[NSDateFormatter new];f.dateFormat=@"HH:mm:ss.SSS";f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];});
    return [f stringFromDate:NSDate.date];
}
// The first responder, by an action sent to nil (as WXGHost.m's FIX62 helper).
static __weak UIResponder *WXGKeyboardCaptured;
@interface UIResponder (WXGKeyboardTrace)
- (void)wxg_keyboardCaptureResponder:(id)sender;
@end
@implementation UIResponder (WXGKeyboardTrace)
- (void)wxg_keyboardCaptureResponder:(id)sender {(void)sender;WXGKeyboardCaptured=self;}
@end
static UIResponder *WXGKeyboardResponder(void) {
    WXGKeyboardCaptured=nil;
    [UIApplication.sharedApplication sendAction:@selector(wxg_keyboardCaptureResponder:) to:nil from:nil forEvent:nil];
    UIResponder *responder=WXGKeyboardCaptured;WXGKeyboardCaptured=nil;
    return responder;
}
static NSArray<NSString *> *WXGKeyboardAncestors(UIView *view,NSUInteger limit) {
    NSMutableArray *names=[NSMutableArray array];
    for(UIView *v=view;v && names.count<limit;v=v.superview)[names addObject:NSStringFromClass(v.class)?:@"?"];
    return names;
}
static NSString *WXGKeyboardPage(void) {
    UIViewController *vc=UIApplication.sharedApplication.keyWindow.rootViewController;
    for(NSUInteger i=0;i<16 && vc;i++) {
        if(vc.presentedViewController && !vc.presentedViewController.isBeingDismissed){vc=vc.presentedViewController;continue;}
        if([vc isKindOfClass:UINavigationController.class] && ((UINavigationController *)vc).topViewController){vc=((UINavigationController *)vc).topViewController;continue;}
        if([vc isKindOfClass:UITabBarController.class] && ((UITabBarController *)vc).selectedViewController){vc=((UITabBarController *)vc).selectedViewController;continue;}
        break;
    }
    return vc?NSStringFromClass(vc.class):@"none";
}
static void WXGKeyboardRecord(NSDictionary *event) {
    if(!WXGKeyboardEvents)WXGKeyboardEvents=[NSMutableArray array];
    [WXGKeyboardEvents addObject:event];
    if(WXGKeyboardEvents.count>40)[WXGKeyboardEvents removeObjectAtIndex:0];
}
static NSDictionary *WXGKeyboardViewInfo(UIView *view,UIWindow *window) {
    return @{@"class":NSStringFromClass(view.class)?:@"?",@"frame":NSStringFromCGRect(view.frame),
             @"inWindow":NSStringFromCGRect(window?[view convertRect:view.bounds toView:window]:CGRectZero),
             @"hidden":@(view.hidden),@"alpha":@(round(view.alpha*100)/100),@"plugin":@(WXGIsPluginView(view))};
}
static void WXGKeyboardCheckGap(void) {
    ++WXGKeyboardChecks;
    UIResponder *responder=WXGKeyboardResponder();
    if(![responder isKindOfClass:UIView.class])return;
    UIView *tool=nil;Class toolClass=NSClassFromString(@"MMInputToolView");
    for(UIView *v=(UIView *)responder;v;v=v.superview)if(toolClass && [v isKindOfClass:toolClass]){tool=v;break;}
    UIWindow *window=tool.window;
    if(!tool || !window || CGRectIsEmpty(WXGKeyboardLastEnd))return;
    CGRect keyboard=[window convertRect:WXGKeyboardLastEnd fromCoordinateSpace:window.screen.coordinateSpace];
    CGFloat keyboardTop=CGRectGetMinY(keyboard);
    if(keyboardTop>=CGRectGetMaxY(window.bounds)-1)return;   // not up
    CGRect toolRect=[tool convertRect:tool.bounds toView:window];
    CGFloat gap=keyboardTop-CGRectGetMaxY(toolRect);
    if(fabs(gap)<=16)return;
    ++WXGKeyboardGapCount;
    NSMutableArray *children=[NSMutableArray array],*ancestors=[NSMutableArray array];
    for(UIView *child in tool.subviews)if(children.count<24)[children addObject:WXGKeyboardViewInfo(child,window)];
    for(UIView *v=tool.superview;v && ancestors.count<6;v=v.superview)[ancestors addObject:WXGKeyboardViewInfo(v,window)];
    NSDictionary *snapshot=@{@"clock":WXGKeyboardClock(),@"gap":@(round(gap*10)/10),@"keyboard":NSStringFromCGRect(keyboard),
        @"tool":WXGKeyboardViewInfo(tool,window),@"toolChildren":children,@"toolAncestors":ancestors,
        @"responder":NSStringFromClass(responder.class)?:@"?",@"page":WXGKeyboardPage(),
        @"safeArea":@[@(window.safeAreaInsets.top),@(window.safeAreaInsets.bottom)],@"window":NSStringFromCGRect(window.bounds),
        @"pluginEnabled":@(WXGPluginEnabled()),@"floatingInput":@(WXGPreferences.shared.input),@"nativeInputTest":@(WXGPreferences.shared.nativeInputTest)};
    if(!WXGKeyboardGaps)WXGKeyboardGaps=[NSMutableArray array];
    [WXGKeyboardGaps addObject:snapshot];
    if(WXGKeyboardGaps.count>6)[WXGKeyboardGaps removeObjectAtIndex:0];
    if(WXGKeyboardGapCount<=20)WXGLog(@"键盘：输入栏与键盘相差 %.0f pt（%@）",gap,WXGKeyboardPage());
}
static void WXGKeyboardNote(NSNotification *note) {
    NSDictionary *info=note.userInfo;
    CGRect end=[info[UIKeyboardFrameEndUserInfoKey] CGRectValue],begin=[info[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    if(info[UIKeyboardFrameEndUserInfoKey])WXGKeyboardLastEnd=end;
    UIResponder *responder=WXGKeyboardResponder();
    NSString *name=[note.name stringByReplacingOccurrencesOfString:@"UIKeyboard" withString:@""];
    name=[name stringByReplacingOccurrencesOfString:@"Notification" withString:@""];
    WXGKeyboardRecord(@{@"clock":WXGKeyboardClock(),@"event":name?:@"?",@"begin":NSStringFromCGRect(begin),@"end":NSStringFromCGRect(end),
        @"duration":info[UIKeyboardAnimationDurationUserInfoKey]?:@0,@"local":info[UIKeyboardIsLocalUserInfoKey]?:@NO,
        @"responder":responder?NSStringFromClass(responder.class):@"none",
        @"responderAncestors":[responder isKindOfClass:UIView.class]?WXGKeyboardAncestors((UIView *)responder,6):@[],@"page":WXGKeyboardPage()});
    if([note.name isEqual:UIKeyboardDidShowNotification] || [note.name isEqual:UIKeyboardDidChangeFrameNotification])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.45*NSEC_PER_SEC)),dispatch_get_main_queue(),^{WXGKeyboardCheckGap();});
}
void WXGKeyboardTraceStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
        for(NSString *name in @[UIKeyboardWillShowNotification,UIKeyboardDidShowNotification,UIKeyboardWillHideNotification,UIKeyboardDidHideNotification,
                                UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification])
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){WXGKeyboardNote(note);}];
        for(NSString *name in @[UITextFieldTextDidBeginEditingNotification,UITextViewTextDidBeginEditingNotification])
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
                UIView *view=[note.object isKindOfClass:UIView.class]?note.object:nil;
                WXGKeyboardRecord(@{@"clock":WXGKeyboardClock(),@"event":@"BeginEditing",@"responder":view?NSStringFromClass(view.class):@"?",
                                    @"responderAncestors":view?WXGKeyboardAncestors(view,6):@[],@"page":WXGKeyboardPage()});
            }];
    });
}
NSDictionary *WXGKeyboardTraceEvidence(void) {
    return @{@"events":WXGKeyboardEvents.copy?:@[],@"gaps":WXGKeyboardGaps.copy?:@[],@"checks":@(WXGKeyboardChecks),@"gapCount":@(WXGKeyboardGapCount)};
}
