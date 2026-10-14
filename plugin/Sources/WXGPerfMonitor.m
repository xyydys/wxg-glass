#import "WXGSettingsKit.h"
#import "WXGFrameStats.h"
#import <mach/mach.h>
#import <sys/utsname.h>

/* FIX84: 帧率检测 (基本设置 → 帧率与参数).
   - Measure: a display link of its own (the screen's fastest rate), running
     while 记录帧率 or 显示帧率浮标 is on, whether the plugin is on or off (to
     compare). Every callback is one frame the main thread could show; its
     interval against the display's frame (WXGFrameStats.h) gives missed
     frames, hitch time and a 1 ms histogram. Scrolling = the main run loop in
     UITrackingRunLoopMode. The plugin's own main-thread time (host tick and
     refresh, the edge fade following a list) is added by WXGPerfNotePluginWork.
   - Log: one record per second (fps, missed, hitch, worst frame, how late the
     main thread was, page, scrolling, plugin time, thermal state, low power,
     memory), the last 20 minutes; per page and scrolling / still, the totals
     with percentiles; every frame over 50 ms (or 3 refreshes) as an event.
   - Kept: written every 15 s and when WeChat leaves the foreground to
     Library/Preferences/WeChatLiquidGlass/perf_current.json; the next run
     moves it to perf_previous.json, so a session that ended in a hang or a
     kill is still in the next export.
   - HUD: a small draggable capsule on top of WeChat's window (a subview at a
     high zPosition, so presented pages do not cover it; no window of its
     own, which WeChat could mistake for its topmost window). */

static BOOL WXGPerfRunning;
static double WXGPerfFrameWork;   // the plugin's main-thread ms since the last frame
void WXGPerfNotePluginWork(double milliseconds) {if(WXGPerfRunning && milliseconds>0 && isfinite(milliseconds))WXGPerfFrameWork+=milliseconds;}
BOOL WXGPerfActive(void) {return WXGPerfRunning;}
void WXGPerfTimePluginWork(void (NS_NOESCAPE ^work)(void)) {
    if(!work)return;
    if(WXGHostTimingPlugin()){work();return;}
    // FIX102: always timed: the dock profile's hooksMS too (without nested
    // parts that count themselves).
    CFTimeInterval begin=CACurrentMediaTime();double inner=WXGProfileOursTotal();
    work();
    double ms=(CACurrentMediaTime()-begin)*1000;
    if(WXGPerfRunning)WXGPerfFrameWork+=ms;
    double spent=ms-(WXGProfileOursTotal()-inner);
    if(spent>0)WXGProfileAdd(WXGProfileHooks,spent);
}

static const NSUInteger WXGPerfSecondsKept=1200,WXGPerfEventsKept=100,WXGPerfWorstKept=20;

static double WXGRound(double value,double step) {return isfinite(value)?round(value/step)*step:0;}
static NSString *WXGPerfDuration(double seconds) {
    long s=lround(MAX(0,seconds));
    if(s<60)return [NSString stringWithFormat:@"%ld 秒",s];
    if(s<3600)return [NSString stringWithFormat:@"%ld 分 %02ld 秒",s/60,s%60];
    return [NSString stringWithFormat:@"%ld 小时 %02ld 分",s/3600,(s%3600)/60];
}
static NSString *WXGPerfClock(NSDate *date,BOOL millis) {
    static NSDateFormatter *plain,*precise;static dispatch_once_t once;
    dispatch_once(&once,^{
        plain=[NSDateFormatter new];plain.dateFormat=@"HH:mm:ss";plain.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        precise=[NSDateFormatter new];precise.dateFormat=@"HH:mm:ss.SSS";precise.locale=plain.locale;
    });
    return [(millis?precise:plain) stringFromDate:date];
}
static NSString *WXGPerfISODate(NSDate *date) {
    static NSDateFormatter *formatter;static dispatch_once_t once;
    dispatch_once(&once,^{formatter=[NSDateFormatter new];formatter.dateFormat=@"yyyy-MM-dd HH:mm:ss";formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];});
    return [formatter stringFromDate:date];
}
static NSString *WXGPerfDevice(void) {
    struct utsname name;
    if(uname(&name)!=0)return UIDevice.currentDevice.model;
    return [NSString stringWithUTF8String:name.machine]?:UIDevice.currentDevice.model;
}
static double WXGPerfFootprintMB(void) {
    task_vm_info_data_t info;mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)!=KERN_SUCCESS)return -1;
    return info.phys_footprint/1048576.;
}
// FIX85: in Library/Preferences, which WeChat's 清理缓存 leaves alone (as the
// settings page's pictures, WXGSettings.m).
static NSString *WXGPerfFile(NSString *name) {
    NSString *base=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES).firstObject?:NSTemporaryDirectory();
    NSString *directory=[base stringByAppendingPathComponent:@"Preferences/WeChatLiquidGlass"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:name];
}
static dispatch_queue_t WXGPerfQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.runyu.wxg.perf",DISPATCH_QUEUE_SERIAL);});
    return queue;
}

#pragma mark - Page

/* The page on screen: from the key window's root through presentations,
   navigation and tabs. Named once per controller. */
static UIViewController *WXGPerfTopController(void) {
    UIViewController *vc=UIApplication.sharedApplication.keyWindow.rootViewController;
    for(NSUInteger i=0;i<16 && vc;i++) {
        UIViewController *presented=vc.presentedViewController;
        if(presented && !presented.isBeingDismissed){vc=presented;continue;}
        if([vc isKindOfClass:UINavigationController.class] && ((UINavigationController *)vc).topViewController){vc=((UINavigationController *)vc).topViewController;continue;}
        if([vc isKindOfClass:UITabBarController.class] && ((UITabBarController *)vc).selectedViewController){vc=((UITabBarController *)vc).selectedViewController;continue;}
        break;
    }
    return vc;
}
static NSString *WXGPerfPageName(UIViewController *vc) {
    if(!vc)return @"未知";
    static NSArray<NSArray *> *known;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableArray *list=[NSMutableArray array];
        NSArray *names=@[@[@"NewMainFrameViewController",@"首页"],@[@"BaseMsgContentViewController",@"聊天"],@[@"ContactsViewController",@"通讯录"],
                         @[@"FindFriendEntryViewController",@"发现"],@[@"MoreViewController",@"我"],@[@"WCTimeLineViewController",@"朋友圈"],
                         @[@"NewSettingViewController",@"设置"],@[@"ChatRoomInfoViewController",@"聊天信息"],@[@"AddContactToChatRoomViewController",@"聊天信息"]];
        for(NSArray *pair in names){Class cls=NSClassFromString(pair[0]);if(cls)[list addObject:@[cls,pair[1]]];}
        known=list;
    });
    for(NSArray *pair in known)if([vc isKindOfClass:pair[0]])return pair[1];
    NSString *name=NSStringFromClass(vc.class)?:@"未知";
    if([name hasPrefix:@"WXG"])return @"插件设置";
    return name;
}

#pragma mark - HUD

@interface WXGPerfHUDView : UIView   // in WXGIsPluginView's list: the host's scans skip it
@end
@implementation WXGPerfHUDView
@end

#pragma mark - Monitor

@interface WXGPerfMonitor : NSObject
+ (instancetype)shared;
- (void)apply;
- (void)clear;
- (NSDictionary *)snapshotWithSeconds:(NSUInteger)seconds;
- (NSString *)reportText;
@end

@implementation WXGPerfMonitor {
    CADisplayLink *_link;
    CFTimeInterval _last,_sessionStart,_secondStart,_lastSave,_lastFootprint;
    NSDate *_sessionDate;
    int _maximumFPS;
    WXGFrameStats _total,_second;
    double _secondLate,_secondScroll,_footprint;
    NSUInteger _gaps;
    NSMutableDictionary<NSString *,NSMutableData *> *_pages;
    NSMutableArray<NSString *> *_pageOrder;
    __weak UIViewController *_pageController;
    NSString *_page;
    BOOL _scrolling;
    WXGFrameStats *_pageStats;     // the current page and scrolling state's totals
    NSMutableArray<NSDictionary *> *_seconds,*_events,*_worst;
    NSDictionary *_previous;
    BOOL _rotated,_observing;
    WXGPerfHUDView *_hud;
    UILabel *_hudLabel;
    CGPoint _dragOffset;
}
+ (instancetype)shared {static WXGPerfMonitor *monitor;static dispatch_once_t once;dispatch_once(&once,^{monitor=[self new];});return monitor;}
- (instancetype)init {
    if((self=[super init])){[self resetSession];}
    return self;
}
- (void)resetSession {
    WXGFrameStatsReset(&_total);WXGFrameStatsReset(&_second);
    _pages=[NSMutableDictionary dictionary];_pageOrder=[NSMutableArray array];_pageStats=NULL;_page=nil;_pageController=nil;
    _seconds=[NSMutableArray array];_events=[NSMutableArray array];_worst=[NSMutableArray array];
    _sessionStart=CACurrentMediaTime();_sessionDate=NSDate.date;_secondStart=0;_last=0;_gaps=0;_secondLate=0;_secondScroll=0;
}
- (BOOL)wanted {WXGPreferences *p=WXGPreferences.shared;return p.perfMonitor || p.perfHUD;}
- (void)apply {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self apply];});return;}
    [self observe];
    BOOL wanted=[self wanted];
    if(wanted && !_link)[self start];
    else if(!wanted && _link)[self stop];
    [self updateHUDVisibility];
}
- (void)observe {
    if(_observing)return;
    _observing=YES;
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"WXGIntegrationChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){[self apply];}];
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){
        if(!self->_link)return;
        self->_link.paused=YES;[self closeSecond:CACurrentMediaTime()];self->_last=0;[self save];
    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){
        if(!self->_link)return;
        self->_last=0;self->_secondStart=CACurrentMediaTime();self->_link.paused=NO;
    }];
}
- (void)start {
    if(!_rotated) {
        // Once per WeChat run: the last run's log becomes the previous session.
        _rotated=YES;
        NSString *current=WXGPerfFile(@"perf_current.json"),*previous=WXGPerfFile(@"perf_previous.json");
        dispatch_async(WXGPerfQueue(),^{
            NSFileManager *files=NSFileManager.defaultManager;
            if([files fileExistsAtPath:current]){[files removeItemAtPath:previous error:nil];[files moveItemAtPath:current toPath:previous error:nil];}
            NSData *data=[NSData dataWithContentsOfFile:previous];
            id root=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            if([root isKindOfClass:NSDictionary.class])dispatch_async(dispatch_get_main_queue(),^{self->_previous=root;});
        });
        [self resetSession];
    }
    // Off and on again in the same run: the session goes on (清空本次记录 starts over).
    _last=0;_secondStart=0;WXGFrameStatsReset(&_second);
    _maximumFPS=(int)UIScreen.mainScreen.maximumFramesPerSecond;
    _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    WXGConfigureDisplayLink(_link,UIScreen.mainScreen);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _link.paused=UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    WXGPerfRunning=YES;WXGPerfFrameWork=0;_lastSave=CACurrentMediaTime();
    WXGLog(@"帧率检测：开始（屏幕最高 %d Hz）",_maximumFPS);
}
- (void)stop {
    [self closeSecond:CACurrentMediaTime()];
    [_link invalidate];_link=nil;WXGPerfRunning=NO;_last=0;
    [self save];
    WXGLog(@"帧率检测：停止（记录 %@）",WXGPerfDuration(_total.totalMS/1000));
}
- (void)clear {
    [self resetSession];WXGPerfFrameWork=0;
    if(_link)[self save];
    [self updateHUD];
}

#pragma mark Frames

- (void)notePage:(BOOL)force {
    UIViewController *top=WXGPerfTopController();
    if(!force && top==_pageController && _page)return;
    _pageController=top;
    NSString *page=WXGPerfPageName(top);
    if(![page isEqual:_page]){_page=page;_pageStats=NULL;}
}
- (WXGFrameStats *)statsForPage:(NSString *)page scrolling:(BOOL)scrolling {
    NSString *key=[page stringByAppendingString:scrolling?@" · 滑动":@" · 静止"];
    NSMutableData *data=_pages[key];
    if(!data) {
        data=[NSMutableData dataWithLength:sizeof(WXGFrameStats)];
        _pages[key]=data;[_pageOrder addObject:key];
    }
    return (WXGFrameStats *)data.mutableBytes;
}
- (void)frame:(CADisplayLink *)link {
    CFTimeInterval now=CACurrentMediaTime();
    double work=WXGPerfFrameWork;WXGPerfFrameWork=0;
    if(_last<=0) {
        _last=link.timestamp;
        if(_secondStart<=0)_secondStart=now;
        [self notePage:YES];
        return;
    }
    double interval=(link.timestamp-_last)*1000;_last=link.timestamp;
    if(interval>3000){++_gaps;[self closeSecond:now];return;}   // WeChat was away (locked, background)
    double expected=WXGFrameExpectedMS((link.targetTimestamp-link.timestamp)*1000,_maximumFPS);
    BOOL scrolling=[NSRunLoop.currentRunLoop.currentMode isEqualToString:UITrackingRunLoopMode];
    if(!_page)[self notePage:YES];
    if(!_pageStats || scrolling!=_scrolling){_scrolling=scrolling;_pageStats=[self statsForPage:_page scrolling:scrolling];}
    double late=MAX(0,(now-link.timestamp)*1000);
    WXGFrameStatsAdd(&_second,interval,expected);_second.pluginMS+=work;
    WXGFrameStatsAdd(&_total,interval,expected);_total.pluginMS+=work;
    WXGFrameStatsAdd(_pageStats,interval,expected);_pageStats->pluginMS+=work;
    if(scrolling)_secondScroll+=1;
    if(late>_secondLate)_secondLate=late;
    if(interval>=MAX(50,expected*3))[self noteHitch:interval expected:expected work:work late:late scrolling:scrolling];
    if(now-_secondStart>=1)[self closeSecond:now];
}
- (void)noteHitch:(double)interval expected:(double)expected work:(double)work late:(double)late scrolling:(BOOL)scrolling {
    NSDictionary *event=@{@"clock":WXGPerfClock(NSDate.date,YES),@"t":@(WXGRound(CACurrentMediaTime()-_sessionStart,.01)),
        @"intervalMS":@(WXGRound(interval,.1)),@"expectedMS":@(WXGRound(expected,.01)),@"missed":@(WXGFrameMissed(interval,expected)),
        @"page":_page?:@"未知",@"scrolling":@(scrolling),@"pluginMS":@(WXGRound(work,.01)),@"lateMS":@(WXGRound(late,.1)),@"plugin":@(WXGPluginEnabled())};
    [_events addObject:event];
    if(_events.count>WXGPerfEventsKept)[_events removeObjectAtIndex:0];
    [_worst addObject:event];
    [_worst sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"intervalMS"] compare:a[@"intervalMS"]];}];
    if(_worst.count>WXGPerfWorstKept)[_worst removeLastObject];
}
- (void)closeSecond:(CFTimeInterval)now {
    if(_second.frames) {
        if(now-_lastFootprint>5 || _lastFootprint<=0){_footprint=WXGPerfFootprintMB();_lastFootprint=now;}
        NSProcessInfo *process=NSProcessInfo.processInfo;
        NSDictionary *record=@{@"clock":WXGPerfClock(NSDate.date,NO),@"t":@(WXGRound(now-_sessionStart,1)),
            @"fps":@(WXGRound(WXGFrameStatsFPS(&_second),.1)),@"frames":@(_second.frames),@"missed":@(_second.dropped),
            @"hitchMS":@(WXGRound(_second.hitchMS,.1)),@"worstMS":@(WXGRound(_second.worstMS,.1)),@"lateMaxMS":@(WXGRound(_secondLate,.1)),
            @"scroll":@(WXGRound(_secondScroll/_second.frames,.01)),@"page":_page?:@"未知",@"pluginMS":@(WXGRound(_second.pluginMS,.01)),
            @"plugin":@(WXGPluginEnabled()),@"thermal":@((NSInteger)process.thermalState),@"lowPower":@(process.lowPowerModeEnabled),
            @"memMB":@(WXGRound(_footprint,.1))};
        [_seconds addObject:record];
        if(_seconds.count>WXGPerfSecondsKept)[_seconds removeObjectAtIndex:0];
    }
    if(WXGPreferences.shared.perfHUD && !_hud.superview)[self updateHUDVisibility];
    [self updateHUD];
    WXGFrameStatsReset(&_second);_secondLate=0;_secondScroll=0;_secondStart=now;
    [self notePage:NO];
    if(_link && now-_lastSave>15)[self save];
}

#pragma mark Summary

static NSDictionary *WXGPerfStatsDictionary(const WXGFrameStats *s) {
    return @{@"seconds":@(WXGRound(s->totalMS/1000,.1)),@"frames":@(s->frames),@"fps":@(WXGRound(WXGFrameStatsFPS(s),.1)),
             @"missedFrames":@(s->dropped),@"dropRatePercent":@(WXGRound(WXGFrameStatsDropRate(s)*100,.01)),
             @"hitches":@(s->hitches),@"hitchMSPerSecond":@(WXGRound(WXGFrameStatsHitchRatio(s),.1)),@"worstMS":@(WXGRound(s->worstMS,.1)),
             @"p50MS":@(WXGFrameStatsPercentile(s,.5)),@"p90MS":@(WXGFrameStatsPercentile(s,.9)),@"p95MS":@(WXGFrameStatsPercentile(s,.95)),
             @"p99MS":@(WXGFrameStatsPercentile(s,.99)),@"pluginMSPerSecond":@(WXGRound(WXGFrameStatsPluginRatio(s),.01))};
}
- (NSArray<NSDictionary *> *)pageSummaries {
    NSMutableArray *pages=[NSMutableArray array];
    for(NSString *key in _pageOrder) {
        const WXGFrameStats *s=(const WXGFrameStats *)_pages[key].bytes;
        if(!s->frames)continue;
        NSMutableDictionary *d=[WXGPerfStatsDictionary(s) mutableCopy];d[@"page"]=key;[pages addObject:d];
    }
    [pages sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"seconds"] compare:a[@"seconds"]];}];
    return pages;
}
- (NSDictionary *)environment {
    WXGPreferences *p=WXGPreferences.shared;WXGConfig *c=WXGConfig.shared;
    return @{@"device":WXGPerfDevice(),@"system":UIDevice.currentDevice.systemVersion?:@"",
             @"wechat":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",
             @"plugin":[NSString stringWithFormat:@"%@ · %@",WXGIntegrationHost.shared.versionString,WXGBuildLabel()],
             @"screenMaximumFPS":@(UIScreen.mainScreen.maximumFramesPerSecond),@"pluginEnabled":@(WXGPluginEnabled()),
             @"switches":@{@"nav":@(p.nav),@"dock":@(p.dock),@"input":@(p.input),@"dockSearch":@(p.dockSearch),@"edgeFade":@(p.edgeFade),
                           @"performanceMode":@(c.performanceMode),@"captureFPS":@(c.captureFPS)}};
}
- (NSDictionary *)snapshotWithSeconds:(NSUInteger)seconds {
    NSArray *recent=_seconds;
    if(seconds && recent.count>seconds)recent=[recent subarrayWithRange:NSMakeRange(recent.count-seconds,seconds)];
    return @{@"schema":@"wxg-fps-v1",@"running":@(_link!=nil),@"startedAt":WXGPerfISODate(_sessionDate),
             @"elapsedSeconds":@(WXGRound(CACurrentMediaTime()-_sessionStart,1)),@"gaps":@(_gaps),
             @"environment":self.environment,@"total":WXGPerfStatsDictionary(&_total),@"pages":self.pageSummaries,
             @"hitches":_events.copy,@"worstFrames":_worst.copy,@"seconds":recent.copy};
}
- (void)save {
    NSDictionary *snapshot=[self snapshotWithSeconds:0];_lastSave=CACurrentMediaTime();
    NSString *path=WXGPerfFile(@"perf_current.json");
    dispatch_async(WXGPerfQueue(),^{
        NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        [data writeToFile:path atomically:YES];
    });
}

#pragma mark Report

static NSString *WXGPerfStatsLine(NSDictionary *s) {
    return [NSString stringWithFormat:@"%@  %.1f fps  掉帧 %.1f%%  卡顿 %.1f ms/s  p95 %.0f ms  最长 %.0f ms  插件 %.1f ms/s",
            WXGPerfDuration([s[@"seconds"] doubleValue]),[s[@"fps"] doubleValue],[s[@"dropRatePercent"] doubleValue],[s[@"hitchMSPerSecond"] doubleValue],
            [s[@"p95MS"] doubleValue],[s[@"worstMS"] doubleValue],[s[@"pluginMSPerSecond"] doubleValue]];
}
static void WXGPerfAppendSession(NSMutableString *text,NSDictionary *session,BOOL detailed) {
    NSDictionary *total=session[@"total"],*environment=session[@"environment"];
    if(![total isKindOfClass:NSDictionary.class] || ![total[@"frames"] unsignedIntegerValue]){[text appendString:@"  还没有数据。\n"];return;}
    if([environment isKindOfClass:NSDictionary.class])
        [text appendFormat:@"  %@ · iOS %@ · 微信 %@ · 屏幕最高 %@ Hz · 插件%@\n",environment[@"device"],environment[@"system"],environment[@"wechat"],
            environment[@"screenMaximumFPS"],[environment[@"pluginEnabled"] boolValue]?@"开启":@"关闭"];
    [text appendFormat:@"  平均 %.1f fps，掉帧 %.1f%%（%@ 帧），卡顿 %.1f ms/s（%@ 次）\n",[total[@"fps"] doubleValue],[total[@"dropRatePercent"] doubleValue],
        total[@"missedFrames"],[total[@"hitchMSPerSecond"] doubleValue],total[@"hitches"]];
    [text appendFormat:@"  每帧 p50 %.0f ms · p95 %.0f ms · p99 %.0f ms · 最长 %.0f ms\n",[total[@"p50MS"] doubleValue],[total[@"p95MS"] doubleValue],
        [total[@"p99MS"] doubleValue],[total[@"worstMS"] doubleValue]];
    [text appendFormat:@"  插件主线程 %.2f ms/s（%.2f%%）\n",[total[@"pluginMSPerSecond"] doubleValue],[total[@"pluginMSPerSecond"] doubleValue]/10];
    NSArray *pages=session[@"pages"];
    if([pages isKindOfClass:NSArray.class] && pages.count) {
        [text appendString:@"\n按页面（滑动 / 静止）\n"];
        for(NSDictionary *page in pages)if([page isKindOfClass:NSDictionary.class])
            [text appendFormat:@"  %@\n    %@\n",page[@"page"],WXGPerfStatsLine(page)];
    }
    if(!detailed)return;
    NSArray *events=session[@"hitches"];
    [text appendString:@"\n最近的卡顿（一帧超过 50 ms 或 3 次刷新）\n"];
    if(![events isKindOfClass:NSArray.class] || !events.count)[text appendString:@"  没有。\n"];
    else for(NSDictionary *e in [events.reverseObjectEnumerator.allObjects subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)30,events.count))])
        [text appendFormat:@"  %@  %@%@  %.0f ms（少显示 %@ 帧，插件 %.1f ms，主线程晚 %.0f ms）\n",e[@"clock"],e[@"page"],[e[@"scrolling"] boolValue]?@" · 滑动":@"",
            [e[@"intervalMS"] doubleValue],e[@"missed"],[e[@"pluginMS"] doubleValue],[e[@"lateMS"] doubleValue]];
    NSArray *seconds=session[@"seconds"];
    if([seconds isKindOfClass:NSArray.class] && seconds.count) {
        [text appendString:@"\n最近 20 秒\n"];
        NSUInteger from=seconds.count>20?seconds.count-20:0;
        for(NSUInteger i=from;i<seconds.count;i++) {
            NSDictionary *r=seconds[i];
            [text appendFormat:@"  %@  %5.1f fps  掉 %@  最长 %.0f ms  %@%@  插件 %.1f ms\n",r[@"clock"],[r[@"fps"] doubleValue],r[@"missed"],[r[@"worstMS"] doubleValue],
                r[@"page"],[r[@"scroll"] doubleValue]>.5?@" 滑动":@"",[r[@"pluginMS"] doubleValue]];
        }
    }
}
- (NSString *)reportText {
    NSMutableString *text=[NSMutableString string];
    NSDictionary *session=[self snapshotWithSeconds:20];
    [text appendFormat:@"本次记录 · %@ 开始 · %@%@\n",session[@"startedAt"],WXGPerfDuration(_total.totalMS/1000),_link?@"":@"（已停止）"];
    WXGPerfAppendSession(text,session,YES);
    if(_previous) {
        [text appendFormat:@"\n上次运行微信时的记录 · %@ 开始\n",_previous[@"startedAt"]?:@"?"];
        WXGPerfAppendSession(text,_previous,NO);
    }
    [text appendString:@"\n说明\n"
        "  掉帧：应该刷新却没有新画面的次数占全部刷新的比例。\n"
        "  卡顿 ms/s：每秒里画面多等的时间。低于 5 很流畅，5–10 能感觉到，超过 10 明显卡。\n"
        "  p95：95% 的帧在这个时间内完成（60 Hz 是 17 ms，120 Hz 是 9 ms）。\n"
        "  插件：本插件在主线程上的时间（每帧刷新玻璃、页面适配、渐隐跟随滚动）。\n"
        "  只量主线程能否按时出帧；系统渲染（玻璃本身的合成）慢不在这里。\n"];
    return text;
}

#pragma mark HUD

- (void)updateHUDVisibility {
    BOOL show=_link && WXGPreferences.shared.perfHUD;
    if(!show){[_hud removeFromSuperview];return;}
    // On WeChat's own window; right after launch there may be none yet: tried
    // again every second.
    UIWindow *window=UIApplication.sharedApplication.keyWindow;
    if(!window || window.windowLevel!=UIWindowLevelNormal)return;
    if(!_hud) {
        _hud=[[WXGPerfHUDView alloc]initWithFrame:CGRectMake(0,0,200,42)];
        _hud.backgroundColor=[UIColor colorWithWhite:0 alpha:.66];_hud.layer.cornerRadius=12;_hud.layer.cornerCurve=kCACornerCurveContinuous;
        _hud.layer.zPosition=100000;_hud.accessibilityLabel=@"帧率浮标";
        _hudLabel=[[UILabel alloc]initWithFrame:CGRectInset(_hud.bounds,10,3)];_hudLabel.numberOfLines=2;
        _hudLabel.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _hudLabel.adjustsFontSizeToFitWidth=YES;_hudLabel.minimumScaleFactor=.7;
        [_hud addSubview:_hudLabel];
        [_hud addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(dragHUD:)]];
    }
    if(_hud.superview!=window) {
        [_hud removeFromSuperview];[window addSubview:_hud];
        NSArray *saved=[[[NSUserDefaults alloc]initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] arrayForKey:@"perf.hudCenter"];
        CGSize size=window.bounds.size;
        CGPoint center=saved.count==2?CGPointMake([saved[0] doubleValue],[saved[1] doubleValue]):CGPointMake(size.width*.5,size.height*.36);
        _hud.center=[self clampHUDCenter:center];
        [self updateHUD];
    }
    _hud.hidden=NO;
}
- (CGPoint)clampHUDCenter:(CGPoint)center {
    CGSize screen=(_hud.superview?:UIApplication.sharedApplication.keyWindow).bounds.size,size=_hud.bounds.size;
    return CGPointMake(WXGClamp(center.x,size.width*.5+4,MAX(size.width*.5+4,screen.width-size.width*.5-4)),
                       WXGClamp(center.y,size.height*.5+20,MAX(size.height*.5+20,screen.height-size.height*.5-20)));
}
- (void)dragHUD:(UIPanGestureRecognizer *)pan {
    UIView *window=_hud.superview;if(!window)return;
    CGPoint p=[pan locationInView:window];
    if(pan.state==UIGestureRecognizerStateBegan)_dragOffset=CGPointMake(_hud.center.x-p.x,_hud.center.y-p.y);
    _hud.center=[self clampHUDCenter:CGPointMake(p.x+_dragOffset.x,p.y+_dragOffset.y)];
    if(pan.state==UIGestureRecognizerStateEnded || pan.state==UIGestureRecognizerStateCancelled)
        [[[NSUserDefaults alloc]initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] setObject:@[@(_hud.center.x),@(_hud.center.y)] forKey:@"perf.hudCenter"];
}
- (void)updateHUD {
    if(!_hud.superview || _hud.hidden)return;
    NSDictionary *last=_seconds.lastObject;
    // By the refreshes missed in that second, not against the screen's
    // maximum: WeChat may run below it (120 Hz screens at 60, low power).
    double fps=[last[@"fps"] doubleValue],missed=[last[@"missed"] doubleValue],frames=[last[@"frames"] doubleValue];
    double drop=frames+missed>0?missed/(frames+missed):0;
    UIColor *dot=!last?UIColor.grayColor:drop<=.05?UIColor.systemGreenColor:drop<=.2?UIColor.systemOrangeColor:UIColor.systemRedColor;
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightSemibold];
    NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:@"● " attributes:@{NSForegroundColorAttributeName:dot,NSFontAttributeName:font}];
    NSString *body=last?[NSString stringWithFormat:@"%.0f fps  掉帧 %@  最长 %.0f ms\n%@  插件 %.1f ms  卡顿 %.0f ms",fps,last[@"missed"],[last[@"worstMS"] doubleValue],
                         last[@"page"],[last[@"pluginMS"] doubleValue],[last[@"hitchMS"] doubleValue]]:@"帧率检测中…\n ";
    [text appendAttributedString:[[NSAttributedString alloc]initWithString:body attributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:font}]];
    _hudLabel.attributedText=text;
}
@end

#pragma mark - Report page

@interface WXGPerfReportController : UIViewController
@end
@implementation WXGPerfReportController {UITextView *_text;}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"帧率报告";
    _text=[[UITextView alloc]initWithFrame:self.view.bounds];_text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _text.editable=NO;_text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.view.backgroundColor=UIColor.systemBackgroundColor;[self.view addSubview:_text];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc]initWithTitle:@"导出" style:UIBarButtonItemStylePlain target:self action:@selector(export)],
                                              [[UIBarButtonItem alloc]initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(reload)]];
    [self reload];
}
- (void)reload {_text.text=WXGPerfMonitor.shared.reportText;}
- (void)export {WXGPerfExportFrom(self);}
@end

#pragma mark - Entry points

void WXGPerfApplyPreferences(void) {[WXGPerfMonitor.shared apply];}
void WXGPerfClear(void) {[WXGPerfMonitor.shared clear];}
NSDictionary *WXGPerfEvidence(void) {
    WXGPerfMonitor *monitor=WXGPerfMonitor.shared;
    NSMutableDictionary *d=[[monitor snapshotWithSeconds:60] mutableCopy];
    d[@"monitor"]=@(WXGPreferences.shared.perfMonitor);d[@"hud"]=@(WXGPreferences.shared.perfHUD);
    return d;
}
void WXGPerfShowReport(UIViewController *from) {
    UIViewController *page=[WXGPerfReportController new];
    if(from.navigationController)[from.navigationController pushViewController:page animated:YES];
    else [from presentViewController:[[UINavigationController alloc]initWithRootViewController:page] animated:YES completion:nil];
}
void WXGPerfExportFrom(UIViewController *from) {
    WXGPerfMonitor *monitor=WXGPerfMonitor.shared;
    NSMutableDictionary *payload=[NSMutableDictionary dictionaryWithObject:[monitor snapshotWithSeconds:0] forKey:@"current"];
    NSString *previous=WXGPerfFile(@"perf_previous.json");
    NSData *data=[NSData dataWithContentsOfFile:previous];
    id root=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if([root isKindOfClass:NSDictionary.class])payload[@"previous"]=root;
    payload[@"report"]=monitor.reportText;
    NSData *json=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    static NSDateFormatter *stamp;static dispatch_once_t once;
    dispatch_once(&once,^{stamp=[NSDateFormatter new];stamp.dateFormat=@"yyyyMMdd_HHmmss";stamp.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];});
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"WeChatLiquidGlass_FIX84_fps_%@.json",[stamp stringFromDate:NSDate.date]]];
    if(![json writeToFile:path atomically:YES])return;
    UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView=from.view;share.popoverPresentationController.sourceRect=CGRectMake(from.view.bounds.size.width*.5,60,1,1);
    [from presentViewController:share animated:YES completion:nil];
}
