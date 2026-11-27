#import "WXGHomeCategories.h"
#import "WXGHomePagingMath.h"

@interface WXGHomePageTransition : UIView
@end
@implementation WXGHomePageTransition
@end

@interface WXGHomeGroupPager () <UIGestureRecognizerDelegate>
@end
@implementation WXGHomeGroupPager {
    __weak id<WXGHomePagerDelegate> _delegate;
    UIPanGestureRecognizer *_pan;
    WXGHomePageTransition *_overlay;
    UIView *_originPage,*_neighborPage;
    NSMutableDictionary<NSNumber *,UIView *> *_pages;
    NSMutableDictionary<NSNumber *,NSNumber *> *_depths;
    NSInteger _origin,_neighbor,_step;
    BOOL _settling,_cancelling,_directGesture,_snapshotMissing;
    CGFloat _fraction;
    CGSize _gestureSize;
    NSUInteger _generation;
    CFTimeInterval _beganAt;
}
- (instancetype)initWithTable:(UITableView *)table delegate:(id<WXGHomePagerDelegate>)delegate {
    if((self=[super init])) {
        _table=table;_delegate=delegate;_depths=[NSMutableDictionary dictionary];
        _pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        _pan.maximumNumberOfTouches=1;_pan.delegate=self;[table addGestureRecognizer:_pan];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (void)dealloc {[_table removeGestureRecognizer:_pan];[_overlay removeFromSuperview];}
- (void)invalidate {
    [self cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _pan.delegate=nil;[_pan removeTarget:self action:@selector(panned:)];[_table removeGestureRecognizer:_pan];_table=nil;
}
- (void)interrupted:(__unused NSNotification *)note {[self cancel];}
- (BOOL)busy {return _overlay!=nil;}
- (void)checkGestureOnHome:(BOOL)visible {
    if(!self.busy)return;
    if(!visible || !_table.window || !CGSizeEqualToSize(_gestureSize,_table.bounds.size)){[self cancel];return;}
    // A removed or reset recognizer can lose its terminal callback. The existing
    // Home tick can release its two temporary pages without a permanent timer.
    if(!_settling && CACurrentMediaTime()-_beganAt>.35 &&
       _pan.state!=UIGestureRecognizerStateBegan && _pan.state!=UIGestureRecognizerStateChanged)[self cancel];
}
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    UITableView *table=_table;
    if(_settling || ![_delegate canPageHome] || !table.window || table.editing)return NO;
    UIWindow *window=table.window;
    CGPoint screen=[touch locationInView:window];
    if(screen.x>=CGRectGetMaxX(window.bounds)-56)return NO;
    UIView *host=table.superview;
    if(!CGRectContainsPoint([_delegate homeMessageViewportIn:host],[touch locationInView:host]))return NO;
    for(UIView *v=touch.view;v && v!=table;v=v.superview)
        if([v isKindOfClass:UISlider.class] || [v isKindOfClass:UISwitch.class] || [v isKindOfClass:UITextField.class])return NO;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CGPoint p=[(UIPanGestureRecognizer *)g velocityInView:_table];
    return !_settling && [_delegate canPageHome] && WXGHomePageHorizontal(p.x,p.y);
}
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    // The vertical pan wins as soon as our initial velocity fails the axis test.
    // Once paging has won, a diagonal drag must not also move the live table behind it.
    return [other isKindOfClass:UIPanGestureRecognizer.class] &&
        ![other isKindOfClass:UIScreenEdgePanGestureRecognizer.class] && [other.view isDescendantOfView:_table];
}
- (CGFloat)depth {
    return MAX(0,_table.contentOffset.y+_table.adjustedContentInset.top);
}
- (void)restoreDepth:(NSInteger)index {
    UITableView *t=_table;
    [t layoutIfNeeded];
    NSNumber *saved=_depths[@(index)];
    // First visit keeps a collapsed header collapsed without inheriting the
    // originating group's arbitrary conversation depth.
    CGFloat depth=saved?saved.doubleValue:MIN([_depths[@(_origin)] doubleValue],t.tableHeaderView.bounds.size.height);
    CGFloat lo=-t.adjustedContentInset.top,hi=MAX(lo,t.contentSize.height+t.adjustedContentInset.bottom-t.bounds.size.height);
    CGFloat y=MIN(hi,MAX(lo,lo+depth));
    if(fabs(t.contentOffset.y-y)>.5/MAX(1.,t.window.screen.scale))
        [t setContentOffset:CGPointMake(t.contentOffset.x,y) animated:NO];
}
- (BOOL)loadPage:(NSInteger)index {
    if([_delegate homePageIndex]==index)return YES;
    if(![_delegate showHomePage:index])return NO;
    [self restoreDepth:index];return YES;
}
// Only snapshot the message area. Search, filter controls, navigation and dock
// retain their native owners throughout the interaction.
- (UIView *)snapshot:(BOOL)updated {
    UITableView *t=_table;UIView *host=t.superview;
    if(!host.window || _overlay.superview!=host)return nil;
    CGRect crop=[host convertRect:_overlay.frame toView:t];
    UIView *page=[[UIView alloc] initWithFrame:_overlay.bounds];
    page.backgroundColor=CGColorGetAlpha((t.backgroundColor?:UIColor.clearColor).CGColor)>.99?t.backgroundColor:UIColor.systemBackgroundColor;
    UIView *image=[t resizableSnapshotViewFromRect:crop afterScreenUpdates:updated withCapInsets:UIEdgeInsetsZero];
    if(!image)return nil;
    page.clipsToBounds=YES;image.frame=page.bounds;[page addSubview:image];return page;
}
- (BOOL)begin {
    UITableView *t=_table;UIView *host=t.superview;
    if(!host.window || ![_delegate canPageHome] || self.busy)return NO;
    CGRect rect=[_delegate homeMessageViewportIn:host];
    if(CGRectIsEmpty(rect))return NO;
    _beganAt=CACurrentMediaTime();_snapshotMissing=NO;
    _origin=[_delegate homePageIndex];_depths[@(_origin)]=@([self depth]);
    _gestureSize=t.bounds.size;_neighbor=_origin;_step=0;_fraction=0;
    _overlay=[[WXGHomePageTransition alloc] initWithFrame:rect];
    _overlay.clipsToBounds=YES;_overlay.userInteractionEnabled=NO;_overlay.accessibilityElementsHidden=YES;
    [host insertSubview:_overlay aboveSubview:t];
    _originPage=[self snapshot:NO];
    if(!_originPage){[self clear];return NO;}
    [_overlay addSubview:_originPage];_pages=[NSMutableDictionary dictionary];return YES;
}
- (BOOL)prepare:(NSInteger)index direction:(NSInteger)step {
    if(_neighborPage && _neighbor==index && _step==step)return YES;
    [_neighborPage removeFromSuperview];
    UIView *page=_pages[@(index)];
    if(!page) {
        if(![self loadPage:index]){[self cancel];return NO;}
        page=[self snapshot:YES];
        if(!page){_snapshotMissing=YES;[self cancel];return NO;}
        _pages[@(index)]=page;
    }
    _neighbor=index;_step=step;_neighborPage=page;
    [_overlay addSubview:page];return YES;
}
- (void)displayFraction:(CGFloat)f {
    _fraction=MIN(1,MAX(0,f));
    CGFloat width=_overlay.bounds.size.width;
    if(_paging) {
        _originPage.transform=CGAffineTransformMakeTranslation(-_step*width*_fraction,0);
        _neighborPage.transform=CGAffineTransformMakeTranslation(_step*width*(1-_fraction),0);
    }else _neighborPage.alpha=_fraction;
    [_delegate previewHomePageFrom:_origin to:_neighbor fraction:_fraction];
}
- (void)clear {
    ++_generation;[_overlay removeFromSuperview];_overlay=nil;_originPage=nil;_neighborPage=nil;_pages=nil;_settling=NO;
    NSInteger selected=[_delegate homePageIndex];
    [_delegate previewHomePageFrom:selected to:selected fraction:1];
}
- (void)cancel {
    if(!self.busy || _cancelling)return;
    _cancelling=YES;
    @try {if(!_settling)[self loadPage:_origin];}
    @finally {[self clear];_cancelling=NO;}
}
- (void)settle:(BOOL)commit {
    if(!self.busy || _settling)return;
    NSInteger index=commit?_neighbor:_origin;
    if(![self loadPage:index]){[self clear];return;}
    _settling=YES;_overlay.userInteractionEnabled=YES;
    if(commit)[_delegate rememberHomeCategory];
    NSUInteger token=++_generation;
    CGFloat goal=commit?1:0;
    NSTimeInterval duration=UIAccessibilityIsReduceMotionEnabled()?0:(_paging?WXGHomePageSettle(goal-_fraction):.20);
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self displayFraction:goal];
    } completion:^(__unused BOOL done){if(self->_generation==token)[self clear];}];
}
- (void)switchTo:(NSInteger)index direction:(NSInteger)direction {
    [self cancel];
    if(![self begin]) {
        _origin=[_delegate homePageIndex];_depths[@(_origin)]=@([self depth]);
        if([_delegate canPageHome] && [self loadPage:index])[_delegate rememberHomeCategory];
        return;
    }
    if(![self prepare:index direction:direction]) {
        if(_snapshotMissing && [_delegate canPageHome] && [self loadPage:index])[_delegate rememberHomeCategory];
        return;
    }
    [self displayFraction:0];[self settle:YES];
}
- (void)selectPage:(NSInteger)index {
    NSInteger current=[_delegate homePageIndex];
    [self switchTo:index direction:index>=current?1:-1];
}
- (void)panned:(UIPanGestureRecognizer *)pan {
    CGPoint shift=[pan translationInView:_table];
    CGFloat x=shift.x,v=[pan velocityInView:_table].x;
    NSInteger step=x<0?1:x>0?-1:(v<0?1:-1);
    if(pan.state==UIGestureRecognizerStateCancelled || pan.state==UIGestureRecognizerStateFailed) {
        if(self.busy && !_settling)[self settle:NO];return;
    }
    if(![_delegate canPageHome]){[self cancel];return;}
    if(!_paging) {
        if(pan.state==UIGestureRecognizerStateEnded && fabs(x)>fabs(shift.y) && WXGHomePageCommits(x,v,_table.bounds.size.width,false)) {
            NSInteger next=WXGHomeNeighbor((int)[_delegate homePageIndex],(int)[_delegate homePageCount],(int)step);
            [self switchTo:next direction:step];
        }
        return;
    }
    if(pan.state==UIGestureRecognizerStateBegan) {
        _origin=[_delegate homePageIndex];_depths[@(_origin)]=@([self depth]);
        _directGesture=![self begin];
    }
    if(_directGesture) {
        if(pan.state==UIGestureRecognizerStateEnded && fabs(x)>fabs(shift.y) && WXGHomePageCommits(x,v,_table.bounds.size.width,false)) {
            NSInteger next=WXGHomeNeighbor((int)_origin,(int)[_delegate homePageCount],(int)step);
            if([self loadPage:next])[_delegate rememberHomeCategory];
        }
        return;
    }
    if(!self.busy || _settling)return;
    if(!CGSizeEqualToSize(_table.bounds.size,_gestureSize)){[self cancel];return;}
    if(!_step || _step==step || fabs(x)>4) {
        NSInteger next=WXGHomeNeighbor((int)_origin,(int)[_delegate homePageCount],(int)step);
        if(![self prepare:next direction:step]){_directGesture=_snapshotMissing;return;}
    }
    CGFloat width=_overlay.bounds.size.width;
    [self displayFraction:step==_step?fabs(x)/MAX(1.,width):0];
    if(pan.state==UIGestureRecognizerStateEnded)[self settle:step==_step && WXGHomePageCommits(x,v,width,true)];
}
@end
