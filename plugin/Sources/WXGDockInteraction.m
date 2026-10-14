#import "WXGDockInteraction.h"
#import "WXGIntegration.h"
#include <stdlib.h>
#include <string.h>

static char WXGDockDelegateKey,WXGDockRecognizersKey;

@interface WXGDockGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> original;
@property(nonatomic,weak) UIView *dock;
@property(nonatomic,weak) UITabBar *bar;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMethodSignature *> *signatures;
@end

static BOOL WXGDockTouchGateActive(UIView *dock,UITabBar *bar,UIGestureRecognizer *recognizer) {
    WXGPreferences *preferences=WXGPreferences.shared;
    return [dock isKindOfClass:WXGDemoBar.class] && ((WXGDemoBar *)dock).active &&
        ((WXGDemoBar *)dock).enabled && dock.userInteractionEnabled && !dock.hidden && dock.alpha>.01 &&
        dock.window && dock.superview==bar && recognizer.view==bar && !bar.hidden && bar.alpha>.01 &&
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive && preferences.enabled && preferences.dock;
}

@implementation WXGDockGestureDelegate
- (instancetype)init {
    if((self=[super init]))_signatures=[NSMutableDictionary dictionary];
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *dock=_dock;UITabBar *bar=_bar;UIView *target=touch.view;
    BOOL active=WXGDockTouchGateActive(dock,bar,recognizer);
    if(active && target && (target==dock || [target isDescendantOfView:dock]))return NO;
    id<UIGestureRecognizerDelegate> original=_original;
    return [original respondsToSelector:_cmd]?[original gestureRecognizer:recognizer shouldReceiveTouch:touch]:YES;
}
- (BOOL)respondsToSelector:(SEL)selector {
    if([super respondsToSelector:selector])return YES;
    id original=_original;
    if(![original respondsToSelector:selector])return NO;
    // UIKit can cache optional delegate capabilities. Retain the signature so
    // an already-cached callback stays safe if its weak native delegate dies.
    NSMethodSignature *signature=[original methodSignatureForSelector:selector];
    if(signature)_signatures[NSStringFromSelector(selector)]=signature;
    return YES;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature=[super methodSignatureForSelector:selector];
    if(signature)return signature;
    id original=_original;signature=[original methodSignatureForSelector:selector];
    if(signature){_signatures[NSStringFromSelector(selector)]=signature;return signature;}
    return _signatures[NSStringFromSelector(selector)];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    id original=_original;
    if([original respondsToSelector:invocation.selector]){[invocation invokeWithTarget:original];return;}
    NSUInteger length=invocation.methodSignature.methodReturnLength;
    if(!length)return;
    void *result=calloc(1,length);
    // These optional delegate decisions default to YES when no delegate exists;
    // simultaneous recognition and failure requirements default to NO.
    SEL selector=invocation.selector;
    if(length==sizeof(BOOL) && (selector==@selector(gestureRecognizerShouldBegin:) ||
       selector==@selector(gestureRecognizer:shouldReceivePress:) ||
       selector==@selector(gestureRecognizer:shouldReceiveEvent:))){BOOL allow=YES;memcpy(result,&allow,sizeof allow);}
    [invocation setReturnValue:result];free(result);
}
@end

void WXGProtectDockTouches(UIView *dock,UITabBar *bar) {
    if(!dock || !bar || dock.superview!=bar)return;
    NSHashTable<UIGestureRecognizer *> *installed=objc_getAssociatedObject(bar,&WXGDockRecognizersKey);
    for(UIGestureRecognizer *recognizer in bar.gestureRecognizers) {
        WXGDockGestureDelegate *proxy=objc_getAssociatedObject(recognizer,&WXGDockDelegateKey);
        if(proxy) {
            // A later native/foreign assignment owns this recognizer now. Keep
            // a different delegate intact. Native layout may restore the same
            // original delegate; wrapping that same binding remains safe.
            id current=recognizer.delegate;
            if(current!=proxy && current!=proxy.original)continue;
            if(proxy.bar==bar){proxy.dock=dock;if(current!=proxy)recognizer.delegate=proxy;continue;}
            // UIKit moved the recognizer to another bar. Retire the old wrapper
            // before installing this bar's wrapper; old-bar teardown skips it.
            recognizer.delegate=proxy.original;
            objc_setAssociatedObject(recognizer,&WXGDockDelegateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        proxy=[WXGDockGestureDelegate new];proxy.original=recognizer.delegate;proxy.dock=dock;proxy.bar=bar;
        objc_setAssociatedObject(recognizer,&WXGDockDelegateKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!installed){installed=[NSHashTable weakObjectsHashTable];objc_setAssociatedObject(bar,&WXGDockRecognizersKey,installed,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        [installed addObject:recognizer];recognizer.delegate=proxy;
    }
}

void WXGRestoreDockTouchDelegates(UITabBar *bar) {
    if(!bar)return;
    NSHashTable<UIGestureRecognizer *> *installed=objc_getAssociatedObject(bar,&WXGDockRecognizersKey);
    for(UIGestureRecognizer *recognizer in installed) {
        WXGDockGestureDelegate *proxy=objc_getAssociatedObject(recognizer,&WXGDockDelegateKey);
        if(!proxy || proxy.bar!=bar)continue;
        if(recognizer.delegate==proxy)recognizer.delegate=proxy.original;
        objc_setAssociatedObject(recognizer,&WXGDockDelegateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(bar,&WXGDockRecognizersKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSDictionary *WXGDockTouchProtectionMetrics(UITabBar *bar) {
    NSArray<UIGestureRecognizer *> *recognizers=bar.gestureRecognizers;
    NSUInteger active=0,changed=0;NSMutableArray<NSString *> *classes=[NSMutableArray arrayWithCapacity:MIN(recognizers.count,8)];
    for(UIGestureRecognizer *recognizer in recognizers) {
        if(classes.count<8)[classes addObject:NSStringFromClass(recognizer.class)];
        WXGDockGestureDelegate *proxy=objc_getAssociatedObject(recognizer,&WXGDockDelegateKey);
        if(!proxy || proxy.bar!=bar)continue;
        if(recognizer.delegate!=proxy)++changed;
        else if(WXGDockTouchGateActive(proxy.dock,bar,recognizer))++active;
    }
    return @{@"recognizerCount":@(recognizers.count),@"wrappedActive":@(active),@"delegateChanged":@(changed),@"classes":classes};
}
