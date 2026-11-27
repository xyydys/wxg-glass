#import "WXGIntegration.h"
#import "WXGBubbleRules.h"

#import "WXGBubbleContent.h"
#import "WXGBubbleVoiceChange.h"
#import "WXGBubbleTranslation.h"
#import "WXGBubbleQuote.h"
#import "WXGBubbleQuoteBackground.h"
#import "WXGBubbleQuoteRules.h"
#import "WXGBubbleFamily.h"

@interface WXGBubbleGlass : UIView
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic) BOOL outgoing;
@property(nonatomic) CGFloat radius;
- (void)tick:(CFTimeInterval)time;
@end
@implementation WXGBubbleGlass {
    NSUInteger _appliedRevision;
    UIUserInterfaceStyle _appliedStyle;
    BOOL _appliedOutgoing,_dirty;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;
        self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        _glass=[[WXGGlassView alloc]initWithFrame:CGRectZero];
        _glass.overlayHidden=YES;_glass.userInteractionEnabled=NO;
        // FIX85: the bubbles' own optics and rim (the "气泡" range); one
        // backdrop unless 完整玻璃 is on.
        _glass.bubbleSurface=YES;_glass.lightweight=!WXGConfig.shared.bubbleFullGlass;
        [self addSubview:_glass];_dirty=YES;
    }return self;
}
- (UIColor *)tint {
    WXGConfig *c=WXGConfig.shared;BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    return WXGColor(dark?(_outgoing?c.darkBubbleOutgoingHex:c.darkBubbleIncomingHex):(_outgoing?c.bubbleOutgoingHex:c.bubbleIncomingHex));
}
// FIX83: the tint weakens toward the outline over the bubble page's range.
- (void)setOutgoing:(BOOL)outgoing {if(_outgoing==outgoing)return;_outgoing=outgoing;_dirty=YES;_glass.veilOverride=[self tint];}
- (void)setRadius:(CGFloat)radius {if(fabs(_radius-radius)<.01)return;_radius=radius;_dirty=YES;[self setNeedsLayout];}
- (void)didMoveToWindow {[super didMoveToWindow];_glass.active=self.window!=nil;_dirty=YES;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {[super traitCollectionDidChange:previous];_dirty=YES;_glass.veilOverride=[self tint];}
- (void)layoutSubviews {
    [super layoutSubviews];
    _dirty=YES;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        CGRect b=self.bounds;
        self.glass.frame=CGRectInset(b,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
        self.glass.glassRect=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,b.size.width,b.size.height);
        // 0 would mean a capsule to the glass; a square corner is 0.5 pt.
        self.glass.maximumCornerRadius=MAX(.5,MIN(self.radius,MIN(b.size.width,b.size.height)*.5));
        if(!self.glass.veilOverride)self.glass.veilOverride=[self tint];
        [self.glass layoutIfNeeded];
        [CATransaction commit];
    }];
}
// Only a new, resized, recoloured or re-themed bubble does any work; the
// render server keeps the glass live in between.
- (void)tick:(CFTimeInterval)time {
    if(!self.window || self.hidden)return;
    UIUserInterfaceStyle style=self.traitCollection.userInterfaceStyle;
    if(!_dirty && _appliedRevision==WXGConfigRevision() && _appliedStyle==style && _appliedOutgoing==_outgoing)return;
    _glass.veilOverride=[self tint];
    BOOL lean=!WXGConfig.shared.bubbleFullGlass;
    if(_glass.lightweight!=lean){_glass.lightweight=lean;[_glass invalidateBackdrop];[_glass setNeedsLayout];}
    [self layoutIfNeeded];[_glass layoutIfNeeded];
    if(!WXGPresentedVisible(_glass))return;   // stays stale until it is on screen
    [_glass tick:time];
    _appliedRevision=WXGConfigRevision();_appliedStyle=style;_appliedOutgoing=_outgoing;_dirty=NO;
}
@end

@interface WXGBubbleEntry : NSObject
@property(nonatomic,weak) UIView *host,*body,*rich,*translationPlate;
@property(nonatomic) CGRect textEnvelope;
@property(nonatomic) BOOL extendedText,hasQuote,quoteLayoutPending;
@property(nonatomic,weak) UIView *quotePreview;
@property(nonatomic,strong) WXGBubbleQuoteBackground *quoteBackground;
@property(nonatomic,strong) UIView *quoteDivider;
@property(nonatomic) CGFloat quoteDividerY;
@property(nonatomic,weak) UITableViewCell *cell;
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,weak) id model,family,renderKey,probeModel;
@property(nonatomic) NSUInteger children,index,count,attempts,generation;
@property(nonatomic) BOOL retryPending,layoutDirty,primaryHasContent;
@property(nonatomic) CGFloat appliedReference;
@property(nonatomic) BOOL outgoing,fragment,painted,applying;
@property(nonatomic) WXGBubbleKind kind;
@property(nonatomic,copy) NSArray<UIView *> *backgrounds;
@property(nonatomic,strong) WXGBubbleGlass *view;
@property(nonatomic,strong) WXGStateBag *states;
@end
@implementation WXGBubbleEntry
@end

@interface WXGBubbleTable : NSObject
@property(nonatomic) CGFloat incoming,outgoing;
@property(nonatomic) BOOL dirty;
@property(nonatomic) CGRect viewport;
@property(nonatomic,strong) NSMapTable<id,WXGBubbleGlass *> *groups;
@property(nonatomic,strong) NSHashTable<WXGBubbleEntry *> *entries;
@end
@implementation WXGBubbleTable
- (instancetype)init {
    if((self=[super init])) {
        _groups=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPointerPersonality
                                      valueOptions:NSPointerFunctionsStrongMemory];
        _entries=[NSHashTable weakObjectsHashTable];_dirty=YES;
    }
    return self;
}
@end

static char WXGBubbleEntryKey,WXGBubbleTableKey,WXGVoiceRowNumberKey;
static BOOL WXGBubbleNamed(UIView *v,NSString *name) {
    return [NSStringFromClass(v.class) rangeOfString:name options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL WXGBubbleImageView(UIView *v){return WXGBubbleNamed(v,@"YYAsyncImageView");}
static UIView *WXGBubbleRich(UIView *body) {
    for(UIView *child in body.subviews)if(WXGBubbleNamed(child,@"RichTextView"))return child;
    return nil;
}
static void WXGBubbleCollectBody(UIView *node,NSUInteger depth,UIView *__strong *best,CGFloat *bestArea) {
    if(depth>5 || node.hidden || node.alpha<=.01 || WXGIsPluginView(node))return;
    CGSize size=node.bounds.size;
    if(size.width>8 && size.height>8 && size.width*size.height<*bestArea && WXGBubbleRich(node)) {
        for(UIView *child in node.subviews)if(WXGBubbleImageView(child)){
            *best=node;*bestArea=size.width*size.height;break;
        }
    }
    for(UIView *child in node.subviews)WXGBubbleCollectBody(child,depth+1,best,bestArea);
}
static UIView *WXGBubbleTextBody(UIView *host) {
    UIView *best=nil;CGFloat area=CGFLOAT_MAX;
    for(UIView *child in host.subviews)WXGBubbleCollectBody(child,0,&best,&area);
    return best;
}
static BOOL WXGBubbleValidRect(CGRect r) {
    return !CGRectIsNull(r) && !CGRectIsInfinite(r) && isfinite(r.origin.x) && isfinite(r.origin.y) &&
        isfinite(r.size.width) && isfinite(r.size.height) && r.size.width>0 && r.size.height>0;
}
static BOOL WXGBubbleSafeTextBody(UIView *body,UIView *host,UIView *rich) {
    CGRect r=[body convertRect:body.bounds toView:host];
    CGRect b=host.bounds;
    if(!rich || !WXGBubbleValidRect(r) || r.size.width<12 || r.size.height<12)return NO;
    CGFloat allowance=(r.size.height<=96 && b.size.height<=96)?14:3;
    if(!CGRectContainsRect(CGRectInset(b,-24,-allowance),r))return NO;
    if(r.size.height>80 && (rich.hidden || rich.alpha<=.01 || (b.size.width>200 && r.size.width<72) ||
        (rich.bounds.size.height>20 && rich.bounds.size.width<12)))return NO;
    return YES;
}
static NSArray<UIView *> *WXGBubbleTextBackgrounds(UIView *body) {
    NSMutableArray *images=[NSMutableArray array];
    for(UIView *child in body.subviews)if(WXGBubbleImageView(child)){
        // A theme may put its text inside the async view. Never hide that subtree.
        if(WXGBubbleRich(child))return @[];
        [images addObject:child];
    }
    return images;
}
static NSUInteger WXGBubbleChildren(UIView *body) {
    NSUInteger key=body.subviews.count;
    for(UIView *child in body.subviews)key=(key^(NSUInteger)(__bridge void *)child)*1099511628211ull;
    return key;
}
static id WXGBubbleHostModel(UIView *host) {
    return WXGBubbleModelField(host,@"viewModel")?:WXGBubbleModelField(host,@"m_viewModel")?:WXGBubbleModelField(host,@"_viewModel");
}
static BOOL WXGBubbleMemberIsCurrent(WXGBubbleEntry *entry) {
    if(!entry.fragment || !entry.count)return YES;
    id parent=WXGBubbleParentModel(entry.model);
    NSArray *parts=WXGBubbleModelField(parent,@"subViewModels");
    return [parts isKindOfClass:NSArray.class] && parts.count==entry.count &&
        entry.index<parts.count && parts[entry.index]==entry.model;
}
static void WXGBubbleLocate(UIView *host,UITableViewCell *__strong *cell,UITableView *__strong *table) {
    for(UIView *v=host;v;v=v.superview) {
        if(!*cell && [v isKindOfClass:UITableViewCell.class])*cell=(UITableViewCell *)v;
        if([v isKindOfClass:UITableView.class]){*table=(UITableView *)v;break;}
    }
}
static void WXGBubbleSetFrame(WXGBubbleGlass *glass,CGRect frame) {
    if(!CGRectEqualToRect(glass.frame,frame))[UIView performWithoutAnimation:^{glass.frame=frame;}];
}

// Track the native body/skin and the paths to voice text, including hidden
// placeholders. WeChat can reveal or resize a plate without another cell or
// text layout. Search the hierarchy only when its ownership or layout changes.
@interface WXGVoiceNode : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic) WXGBubbleVoiceState state;
@end
@implementation WXGVoiceNode
@end

static WXGBubbleVoiceState WXGVoiceNodeState(UIView *view, UIView *host) {
    if (!view) return (WXGBubbleVoiceState){0};
    BOOL root = view == host;
    CGRect frame = root ? view.bounds : view.frame;
    UIEdgeInsets caps=[view isKindOfClass:UIImageView.class] ? ((UIImageView *)view).image.capInsets : UIEdgeInsetsZero;
    BOOL stretchable=fabs(caps.top)+fabs(caps.left)+fabs(caps.bottom)+fabs(caps.right)>.5;
    uintptr_t signature=0;
    NSUInteger count=0;
    for(UIView *child in view.subviews) {
        if([child isKindOfClass:WXGBubbleGlass.class])continue;
        signature=signature*31U+(uintptr_t)(__bridge void *)child;
        ++count;
    }
    return (WXGBubbleVoiceState){
        .parent=(uintptr_t)(__bridge void *)view.superview,
        .content=root ? (uintptr_t)(__bridge void *)WXGBubbleVoiceContent(host) : 0,
        .skin=root ? (uintptr_t)(__bridge void *)WXGBubbleVoiceSkin(host) : 0,
        .x=frame.origin.x,.y=frame.origin.y,.width=frame.size.width,.height=frame.size.height,
        .children=count,.childSignature=signature,.visible=view && !view.hidden && view.alpha>.01,.stretchable=stretchable
    };
}

static void WXGVoiceCollectNodes(UIView *view, UIView *host, NSMutableOrderedSet<UIView *> *nodes,
                                 NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>9 || WXGIsPluginView(view))return;
    --*budget;
    // Empty native wrappers can acquire the entire transcript in one layout.
    // Watching only ancestors of an existing text/image misses that insertion.
    [nodes addObject:view];
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] ||
        [NSStringFromClass(view.class) containsString:@"RichText"])return;
    for (UIView *child in view.subviews) WXGVoiceCollectNodes(child,host,nodes,depth+1,budget);
}

static NSArray<WXGVoiceNode *> *WXGVoiceNodes(UIView *host) {
    NSMutableOrderedSet *views=[NSMutableOrderedSet orderedSetWithObject:host];
    NSUInteger budget=128;
    WXGVoiceCollectNodes(host,host,views,0,&budget);
    UIView *content=WXGBubbleVoiceContent(host), *skin=WXGBubbleVoiceSkin(host);
    if (content) [views addObject:content];
    if (skin) [views addObject:skin];
    NSMutableArray *nodes=[NSMutableArray arrayWithCapacity:views.count];
    for (UIView *view in views) {
        WXGVoiceNode *node=[WXGVoiceNode new];
        node.view=view;node.state=WXGVoiceNodeState(view,host);
        [nodes addObject:node];
    }
    return nodes;
}

@implementation WXGBubbles {
    NSHashTable<UITableView *> *_tables;
    NSHashTable<UIView *> *_observedHosts;
    NSHashTable<UIView *> *_pendingVoiceHosts;
    NSMapTable<UIView *,UIView *> *_voiceTextOwners;
    NSMapTable<UITableViewCell *,UIView *> *_voiceHostByCell;
    NSMapTable<UIView *,WXGStateBag *> *_voiceSkinOwners;
    NSMapTable<UIView *,NSArray<WXGVoiceNode *> *> *_voiceNodes;
    NSUInteger _mounts,_layouts,_restores,_voiceAttachmentRefreshes,_voiceStateRefreshes,_nextVoiceRow;
    NSMutableArray<NSDictionary *> *_voiceHistory;
}
+ (instancetype)shared {
    static WXGBubbles *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];manager->_tables=[NSHashTable weakObjectsHashTable];manager->_observedHosts=[NSHashTable weakObjectsHashTable];
        manager->_pendingVoiceHosts=[NSHashTable weakObjectsHashTable];
        manager->_voiceTextOwners=[NSMapTable weakToWeakObjectsMapTable];
        manager->_voiceHostByCell=[NSMapTable weakToWeakObjectsMapTable];
        manager->_voiceSkinOwners=[NSMapTable weakToWeakObjectsMapTable];
        manager->_voiceNodes=[NSMapTable weakToStrongObjectsMapTable];
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){WXGPerfTimePluginWorkAs("bubbles",^{[manager reassert];});});
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
    });
    return manager;
}
- (BOOL)wanted {return WXGPluginEnabled() && WXGPreferences.shared.bubbles && WXGEffectiveRenderMode()>=2;}
- (void)unpaint:(WXGBubbleEntry *)entry {
    [entry.quoteBackground restore];
    entry.quoteBackground=nil;
    [entry.quoteDivider removeFromSuperview];
    entry.quoteDivider=nil;
    if(entry.painted){
        if(WXGBubbleIsVoiceHost(entry.host)) {
            for(UIView *skin in entry.backgrounds)if([_voiceSkinOwners objectForKey:skin]==entry.states)
                [_voiceSkinOwners removeObjectForKey:skin];
        }
        [entry.states restore];WXGBubbleRestoreCardContents(entry.body,entry.states);entry.painted=NO;++_restores;
    }
    [entry.view removeFromSuperview];
}
- (void)retire:(WXGBubbleEntry *)entry {
    if(!entry)return;
    [self unpaint:entry];
    if(entry.cell && [_voiceHostByCell objectForKey:entry.cell]==entry.host)[_voiceHostByCell removeObjectForKey:entry.cell];
    WXGBubbleTable *state=objc_getAssociatedObject(entry.table,&WXGBubbleTableKey);
    [state.entries removeObject:entry];state.dirty=YES;
    WXGBubbleInvalidateQuoteLookup(entry.host);
    entry.hasQuote=NO;entry.quotePreview=nil;entry.quoteLayoutPending=NO;
    entry.body=nil;entry.rich=nil;entry.backgrounds=nil;entry.model=nil;entry.family=nil;
    entry.table=nil;entry.cell=nil;entry.renderKey=nil;entry.translationPlate=nil;entry.extendedText=NO;
}
- (void)messageCellWillReuse:(UIView *)host {
    if(!NSThread.isMainThread || !host)return;
    [_pendingVoiceHosts removeObject:host];
    [_voiceNodes removeObjectForKey:host];
    objc_setAssociatedObject(host,&WXGVoiceRowNumberKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
    ++entry.generation;entry.retryPending=NO;entry.attempts=0;entry.probeModel=nil;
    [self retire:entry];
}
- (void)nativeQuoteLaidOut:(UIView *)preview {
    if(!_tables.count)return;
    UITableViewCell *cell=nil; UITableView *table=nil;
    WXGBubbleLocate(preview,&cell,&table);
    WXGBubbleTable *state=table?objc_getAssociatedObject(table,&WXGBubbleTableKey):nil;
    for(WXGBubbleEntry *entry in state.entries)if(entry.cell==cell && entry.kind==WXGBubbleText)
        entry.quoteLayoutPending=YES;
}
- (void)recordVoiceHost:(UIView *)host event:(NSString *)event siblingRenderer:(UIView *)sibling {
    WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
    NSDictionary *binding=WXGBubbleVoiceEvidence(host,entry.body);
    NSString *outcome=!entry.body?@"waitingForBody":!entry.view.superview?@"waitingForGlass":
        [binding[@"materialCount"] unsignedIntegerValue]?@"transcriptMaterialBound":
        [binding[@"lowerTextCount"] unsignedIntegerValue]?@"lowerTextWithoutPlate":@"audioOnly";
    NSNumber *row=objc_getAssociatedObject(host,&WXGVoiceRowNumberKey);
    if(!row){row=@(++_nextVoiceRow);objc_setAssociatedObject(host,&WXGVoiceRowNumberKey,row,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    NSMutableDictionary *state=[@{@"event":event,@"row":row,@"outcome":outcome,
        @"binding":binding,@"glass":NSStringFromCGRect(entry.view.frame)} mutableCopy];
    if(sibling)state[@"siblingRenderer"]=@{@"class":NSStringFromClass(sibling.class),
        @"parent":NSStringFromClass(sibling.superview.class)?:@"",@"frameInVoiceHost":NSStringFromCGRect([sibling convertRect:sibling.bounds toView:host])};
    if([_voiceHistory.lastObject[@"state"] isEqual:state])return;
    if(!_voiceHistory)_voiceHistory=[NSMutableArray array];
    if(_voiceHistory.count==32)[_voiceHistory removeObjectAtIndex:0];
    [_voiceHistory addObject:@{@"seconds":@(round(WXGSecondsSinceLoad()*100)/100),@"state":state}];
}
- (void)recordVoiceHost:(UIView *)host event:(NSString *)event {
    [self recordVoiceHost:host event:event siblingRenderer:nil];
}
- (void)refreshVoiceHost:(UIView *)host event:(NSString *)event {
    [self messageCellLaidOut:host];
    WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
    if(!entry.body || !entry.table || entry.kind!=WXGBubbleNonText){[self recordVoiceHost:host event:event];return;}
    WXGBubbleTable *state=objc_getAssociatedObject(entry.table,&WXGBubbleTableKey);
    [self renderLocal:entry reference:entry.outgoing?state.outgoing:state.incoming];
    [entry.view tick:CACurrentMediaTime()];
    [self recordVoiceHost:host event:event];
}
- (void)voiceTranscriptTextDidChange:(UIView *)textView {
    static Class voiceClass;
    if(!voiceClass)voiceClass=NSClassFromString(@"VoiceMessageCellView");
    UIView *owner=nil;UITableViewCell *cell=nil;
    for(UIView *v=textView.superview;v;v=v.superview) {
        if([v isKindOfClass:voiceClass]){owner=v;break;}
        if([v isKindOfClass:UITableViewCell.class]){cell=(UITableViewCell *)v;break;}
        if([v isKindOfClass:UITableView.class])break;
    }
    UIView *old=[_voiceTextOwners objectForKey:textView];
    if(!owner && !old) {
        // Some builds may attach a transcript beside VoiceMessageCellView.
        // Capture its geometry without taking ownership of an unproven sibling.
        UIView *voice=cell?[_voiceHostByCell objectForKey:cell]:nil;
        if(voice && textView.window && [voice isDescendantOfView:cell] && [NSStringFromClass(textView.class) containsString:@"RichText"])
            [self recordVoiceHost:voice event:@"rendererOutsideVoiceHost" siblingRenderer:textView];
        return;
    }
    if(![self wanted])return;
    BOOL hadPending=_pendingVoiceHosts.count>0;
    if(old!=owner) {
        if(old.window)[_pendingVoiceHosts addObject:old];
        if(owner)[_voiceTextOwners setObject:owner forKey:textView];
        else [_voiceTextOwners removeObjectForKey:textView];
    }
    if(owner.window)[_pendingVoiceHosts addObject:owner];
    if(!hadPending && _pendingVoiceHosts.count) {
        // Core Animation may have laid out this renderer after our run-loop
        // observer. Wake the queue even if this is the last frame in chat.
        dispatch_async(dispatch_get_main_queue(),^{
            NSArray *hosts=self->_pendingVoiceHosts.allObjects;
            [self->_pendingVoiceHosts removeAllObjects];
            for(UIView *host in hosts) {
                if(!host.window || ![self wanted])continue;
                [self->_voiceNodes removeObjectForKey:host];
                ++self->_voiceAttachmentRefreshes;
                [self refreshVoiceHost:host event:@"rendererAttachmentOrLayout"];
            }
        });
    }
}
// Some card classes attach their background below an already-laid-out cell.
// Retry that initial binding on the main queue and once after the async layout.
- (void)retryUnmeasured:(WXGBubbleEntry *)entry {
    if(entry.retryPending || entry.attempts>=2)return;
    NSTimeInterval delay=entry.attempts?0.12:0;
    NSUInteger generation=entry.generation;
    ++entry.attempts;entry.retryPending=YES;
    __weak WXGBubbleEntry *weakEntry=entry;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGBubbleEntry *live=weakEntry;
        if(!live || live.generation!=generation)return;
        live.retryPending=NO;
        if(live.host.window && !live.body && [self wanted])[self messageCellLaidOut:live.host];
    });
}
- (void)messageCellLaidOut:(UIView *)host {
    if(!NSThread.isMainThread || !host)return;
    WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
    if(entry.applying)return;
    if(!host.window){[_observedHosts removeObject:host];[self messageCellWillReuse:host];return;}
    [_observedHosts addObject:host];
    if(![self wanted]){[self retire:entry];return;}
    WXGBubbleKind kind=WXGBubbleKindForHost(host);
    if(kind==WXGBubbleUnsupported){[self retire:entry];return;}
    UITableViewCell *cell=nil;UITableView *table=nil;WXGBubbleLocate(host,&cell,&table);
    BOOL voice=kind==WXGBubbleNonText && WXGBubbleIsVoiceHost(host);
    if(!table || !cell){[self retire:entry];if(voice)[self recordVoiceHost:host event:@"waitingForCell"];return;}
    if(voice && ![_voiceNodes objectForKey:host])[_voiceNodes setObject:WXGVoiceNodes(host) forKey:host];
    id model=WXGBubbleHostModel(host);
    if(entry.table!=table || entry.model!=model)[self retire:entry];
    if(!entry) {
        entry=[WXGBubbleEntry new];entry.host=host;entry.states=[WXGStateBag new];
        objc_setAssociatedObject(host,&WXGBubbleEntryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(entry.probeModel!=model){entry.probeModel=model;++entry.generation;entry.attempts=0;entry.retryPending=NO;}
    entry.applying=YES;
    @try {
        UIView *body=entry.body;
        if(voice || !body || body.hidden || body.alpha<=.01 || ![body isDescendantOfView:host])
            body=kind==WXGBubbleText?WXGBubbleTextBody(host):WXGBubbleCardBody(host);
        UIView *rich=kind==WXGBubbleText?WXGBubbleRich(body):nil;
        NSArray *images=body?(kind==WXGBubbleText?WXGBubbleTextBackgrounds(body):WXGBubbleCardBackgrounds(host,body)):nil;
        if(!images.count || !WXGBubbleValidRect(body.bounds) || (kind==WXGBubbleText && !WXGBubbleSafeTextBody(body,host,rich))){
            [self retire:entry];if(voice)[self recordVoiceHost:host event:@"waitingForNativeSkin"];
            [self retryUnmeasured:entry];return;
        }
        entry.attempts=0;entry.layoutDirty=YES;
        UIView *plate=nil;
        CGRect textEnvelope=CGRectNull;
        CGFloat dividerY=NAN;
        UIView *quotePreview=nil;
        if(kind==WXGBubbleText) {
            CGRect translation=WXGBubbleTranslatedEnvelope(host,body,images.firstObject,&plate);
            CGRect quote=WXGBubbleQuotedEnvelope(host,body);
            if(!CGRectIsNull(quote)) {
                quotePreview=WXGBubbleQuotePreview(host);
                if([WXGConfig.shared extraNumber:@"bubbleQuoteDivider"]>.5)
                    dividerY=WXGBubbleQuoteBoundary(host,rich,quote);
                CGRect base=CGRectIsNull(translation)?[body convertRect:body.bounds toView:host]:translation;
                textEnvelope=CGRectUnion(base,quote);
            }else textEnvelope=translation;
        }
        BOOL extended=!CGRectIsNull(textEnvelope);
        BOOL primaryHasContent=voice && ((UIView *)images.firstObject).subviews.count>0;
        if(entry.primaryHasContent!=primaryHasContent || entry.body!=body || entry.rich!=rich || entry.translationPlate!=plate || entry.extendedText!=extended ||
           ![images isEqualToArray:entry.backgrounds])[self unpaint:entry];
        if(entry.quotePreview!=quotePreview)[entry.quoteBackground restore];
        entry.hasQuote=quotePreview!=nil;entry.quotePreview=quotePreview;entry.quoteDividerY=dividerY;
        entry.extendedText=extended;entry.textEnvelope=textEnvelope;entry.translationPlate=plate;
        entry.model=model;entry.cell=cell;entry.table=table;entry.kind=kind;
        if(voice)[_voiceHostByCell setObject:host forKey:cell];
        entry.body=body;entry.rich=rich;entry.backgrounds=images;entry.primaryHasContent=primaryHasContent;
        entry.fragment=kind==WXGBubbleText && WXGBubbleHasNativeLongHint(model);
        NSUInteger index=NSNotFound,count=0;
        entry.family=entry.fragment?WXGBubbleFamily(model,&index,&count):nil;
        if(entry.fragment && !entry.family)entry.family=WXGBubbleNativeLongWrap(model);
        entry.index=index;entry.count=count;
        NSNumber *side=model && [model respondsToSelector:NSSelectorFromString(@"isSender")]?WXGRead(model,@"isSender"):nil;
        entry.outgoing=[side isKindOfClass:NSNumber.class]?side.boolValue:WXGBubbleOutgoingFromImage(((UIView *)images.firstObject).frame.origin.x);
        entry.children=WXGBubbleChildren(body);
        WXGBubbleTable *state=objc_getAssociatedObject(table,&WXGBubbleTableKey);
        if(!state) {
            state=[WXGBubbleTable new];objc_setAssociatedObject(table,&WXGBubbleTableKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(![_tables containsObject:table])[_tables addObject:table];
        if(![state.entries containsObject:entry])[state.entries addObject:entry];state.dirty=YES;++_layouts;
    } @catch(NSException *error){WXGLog(@"液态气泡：%@",error.reason);[self retire:entry];}
    @finally {entry.applying=NO;}
}
- (void)paint:(WXGBubbleEntry *)entry radius:(CGFloat)radius {
    if(!entry.painted) {
        BOOL voice=WXGBubbleIsVoiceHost(entry.host);
        for(UIView *image in entry.backgrounds) {
            if(voice) {
                WXGStateBag *previous=[_voiceSkinOwners objectForKey:image];
                if(previous!=entry.states) {
                    [previous restoreView:image];
                    [_voiceSkinOwners setObject:entry.states forKey:image];
                }
            }
            if(image.subviews.count && [image isKindOfClass:UIImageView.class])
                [entry.states clearImagePaint:(UIImageView *)image];
            else [entry.states conceal:image];
        }
        if(entry.rich)[entry.states clear:entry.rich];
        entry.painted=YES;
    }
    if(entry.extendedText) {
        [entry.states clear:entry.body];
        WXGBubbleClearTranslationPlate(entry.translationPlate,entry.states);
    }
    if(entry.hasQuote && [WXGConfig.shared extraNumber:@"bubbleQuoteHideNativeBackground"]>.5){
        if(!entry.quoteBackground)entry.quoteBackground=[WXGBubbleQuoteBackground new];
        [entry.quoteBackground updatePreview:entry.quotePreview];
    }else if(entry.quoteBackground) {
        [entry.quoteBackground restore];entry.quoteBackground=nil;
    }
    if(entry.kind==WXGBubbleNonText)WXGBubbleStyleCardContents(entry.host,entry.body,entry.states,radius);
}
// Each physical quote owns its line, including when multiple rows share one
// glass. Only the line is mounted on the glass; native text and gestures stay put.
static CGFloat WXGBubbleQuoteYInGlass(WXGBubbleEntry *entry,WXGBubbleGlass *glass) {
    if(!entry.hasQuote || !isfinite(entry.quoteDividerY))return NAN;
    return [entry.host convertPoint:CGPointMake(0,entry.quoteDividerY) toView:glass].y;
}

static void WXGBubblePlaceQuoteDivider(WXGBubbleEntry *entry,WXGBubbleGlass *glass,CGFloat y) {
    WXGBubbleBox box=WXGBubbleQuoteDividerFrame(CGRectGetWidth(glass.bounds),CGRectGetHeight(glass.bounds),y,glass.window.screen.scale);
    if(!box.w){[entry.quoteDivider removeFromSuperview];entry.quoteDivider=nil;return;}
    UIView *line=entry.quoteDivider;
    if(!line) {
        line=[UIView new];line.userInteractionEnabled=NO;line.accessibilityElementsHidden=YES;
        line.backgroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            UIColor *ink=traits.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.whiteColor:UIColor.blackColor;
            return [ink colorWithAlphaComponent:.28];
        }];
        entry.quoteDivider=line;
    }
    CGRect frame=CGRectMake(box.x,box.y,box.w,box.h);
    [UIView performWithoutAnimation:^{
        if(line.superview!=glass)[glass addSubview:line];
        if(!CGRectEqualToRect(line.frame,frame))line.frame=frame;
    }];
}
- (void)renderLocal:(WXGBubbleEntry *)entry reference:(CGFloat)reference {
    if(entry.painted && !entry.layoutDirty && entry.view.superview && entry.appliedReference==reference)return;
    entry.layoutDirty=NO;entry.appliedReference=reference;
    UIView *body=entry.body;
    CGFloat radius=WXGBubbleRadius(body.bounds.size.width,body.bounds.size.height,reference);
    WXGBubbleGlass *glass=entry.view;
    if(!glass){glass=[[WXGBubbleGlass alloc] initWithFrame:CGRectZero];entry.view=glass;++_mounts;}
    BOOL card=entry.kind==WXGBubbleNonText;
    BOOL voiceMounted=card && !entry.view.superview && WXGBubbleIsVoiceHost(entry.host);
    [self paint:entry radius:radius];
    UIView *container=body;
    if(card)container=body.superview;
    else if(entry.extendedText)container=WXGBubbleQuotedContainer(entry.host)?:entry.host;
    if(card) {
        NSArray *siblings=container.subviews;NSUInteger pos=[siblings indexOfObjectIdenticalTo:body];
        if(pos==NSNotFound)return;
        if(pos==0 || siblings[pos-1]!=glass)[container insertSubview:glass belowSubview:body];
    }else if(container.subviews.firstObject!=glass)[container insertSubview:glass atIndex:0];
    glass.outgoing=entry.outgoing;glass.radius=radius;
    CGRect frame=entry.extendedText?[entry.host convertRect:entry.textEnvelope toView:container]:body.bounds;
    if(card)frame=[entry.host convertRect:WXGBubbleCardGlassFrame(entry.host,body) toView:container];
    WXGBubbleSetFrame(glass,frame);entry.children=WXGBubbleChildren(body);
    if(voiceMounted)[self recordVoiceHost:entry.host event:@"mounted"];
    WXGBubblePlaceQuoteDivider(entry,glass,WXGBubbleQuoteYInGlass(entry,glass));
}
static WXGBubbleBox WXGBubbleBoxFromRect(CGRect r) {
    return (WXGBubbleBox){r.origin.x,r.origin.y,r.size.width,r.size.height};
}

// An unindexed legacy wrap proves ownership, but carries no end indices.
// Near the viewport, prove termination at a table boundary or an attached
// neighbour belonging to a different message before drawing a rounded end.
static NSIndexPath *WXGBubbleNeighbourPath(UITableView *table,NSIndexPath *path,NSInteger step) {
    NSInteger section=path.section,row=path.row+step;
    while(section>=0 && section<table.numberOfSections) {
        NSInteger rows=[table numberOfRowsInSection:section];
        if(row>=0 && row<rows)return [NSIndexPath indexPathForRow:row inSection:section];
        section+=step;
        if(section<0 || section>=table.numberOfSections)break;
        row=step>0?0:[table numberOfRowsInSection:section]-1;
    }
    return nil;
}
static BOOL WXGBubbleKnownEnd(UITableView *table,WXGBubbleTable *state,NSIndexPath *path,NSInteger step,id wrap) {
    NSIndexPath *next=WXGBubbleNeighbourPath(table,path,step);
    if(!next)return YES;
    UITableViewCell *cell=[table cellForRowAtIndexPath:next];
    if(!cell)return NO;
    for(WXGBubbleEntry *entry in state.entries)if(entry.cell==cell) {
        id other=WXGBubbleModelWrap(entry.model);
        if(!other || other==wrap)return NO;
        uint64_t local=WXGBubbleIdentityNumber(wrap,@"m_uiMesLocalID"),otherLocal=WXGBubbleIdentityNumber(other,@"m_uiMesLocalID");
        uint64_t server=WXGBubbleIdentityNumber(wrap,@"m_n64MesSvrID"),otherServer=WXGBubbleIdentityNumber(other,@"m_n64MesSvrID");
        return (server && otherServer && server!=otherServer) || (local && otherLocal && local!=otherLocal);
    }
    return NO;
}

// All geometry is in the table's content coordinates. Native message rows,
// glyphs, hit testing and row heights stay owned by WeChat.
- (BOOL)renderFamily:(NSArray<WXGBubbleEntry *> *)members key:(id)key table:(UITableView *)table state:(WXGBubbleTable *)state {
    BOOL indexed=YES;
    for(WXGBubbleEntry *entry in members){
        if(![table indexPathForCell:entry.cell])return NO;
        if(!entry.count)indexed=NO;
    }
    if(!indexed && members.count<2)return NO;
    NSArray<WXGBubbleEntry *> *ordered=[members sortedArrayUsingComparator:^NSComparisonResult(WXGBubbleEntry *a,WXGBubbleEntry *b){
        if(!indexed)return [[table indexPathForCell:a.cell] compare:[table indexPathForCell:b.cell]];
        if(a.index==b.index)return NSOrderedSame;return a.index<b.index?NSOrderedAscending:NSOrderedDescending;
    }];
    WXGBubbleEntry *first=ordered.firstObject,*last=ordered.lastObject;
    NSIndexPath *start=[table indexPathForCell:first.cell];
    if(!start || start.section>=[table numberOfSections])return NO;
    UIView *container=first.cell.superview;
    if(!container)return NO;
    BOOL exactRows=indexed && [table numberOfRowsInSection:start.section]==(NSInteger)first.count && start.row==(NSInteger)first.index;
    CGRect bounds=CGRectNull,previous=CGRectNull;
    BOOL previousTranslated=NO;
    NSIndexPath *previousPath=nil;NSUInteger position=first.index;
    NSMutableSet<NSIndexPath *> *paths=[NSMutableSet set];
    for(WXGBubbleEntry *entry in ordered) {
        NSIndexPath *path=[table indexPathForCell:entry.cell];
        if(!path || entry.outgoing!=first.outgoing || entry.cell.superview!=container)return NO;
        if(indexed && (entry.index!=position || entry.count!=first.count))return NO;
        if(previousPath) {
            BOOL contiguous=path.section==previousPath.section && path.row==previousPath.row+1;
            if(!contiguous && !(path.section==previousPath.section+1 && path.row==0 &&
               previousPath.row==[table numberOfRowsInSection:previousPath.section]-1))return NO;
        }
        if(path.section!=start.section)exactRows=NO;
        CGRect rect=[entry.body convertRect:entry.body.bounds toView:table];
        if(!WXGBubbleValidRect(rect) || (!CGRectIsNull(previous) &&
           !WXGBubbleAdjacentBoxes(WXGBubbleBoxFromRect(previous),WXGBubbleBoxFromRect(rect),
                                   exactRows || entry.translationPlate || previousTranslated)))return NO;
        CGRect content=entry.extendedText?[entry.host convertRect:entry.textEnvelope toView:table]:rect;
        bounds=CGRectUnion(bounds,content);
        previousTranslated=entry.translationPlate!=nil;
        [paths addObject:path];previous=rect;previousPath=path;if(indexed)++position;
    }
    BOOL complete=indexed && first.index==0 && last.index+1==first.count;
    if(indexed && !complete && !exactRows) {
        WXGBubbleSpan span={CGRectGetMinY(bounds),CGRectGetMaxY(bounds)};
        WXGBubbleSpan viewport={CGRectGetMinY(table.bounds),CGRectGetMaxY(table.bounds)};
        if(!WXGBubbleExtendIndexedSpan(&span,viewport,first.index>0,last.index+1<first.count))return NO;
        bounds.origin.y=span.min;bounds.size.height=span.max-span.min;
    }
    if(!indexed) {
        CGFloat guard=MAX(120,table.bounds.size.height*.25);
        if(CGRectGetMinY(bounds)>=CGRectGetMinY(table.bounds)-guard && !WXGBubbleKnownEnd(table,state,start,-1,key))return NO;
        if(CGRectGetMaxY(bounds)<=CGRectGetMaxY(table.bounds)+guard && !WXGBubbleKnownEnd(table,state,previousPath,1,key))return NO;
    }
    if(exactRows){
        // An attached row that has not yet proved its body/owner must keep
        // its native art. The whole group becomes drawable together.
        for(NSIndexPath *path in table.indexPathsForVisibleRows)
            if(path.section==start.section && ![paths containsObject:path])return NO;
        if(!complete) {
            CGRect head=[table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:start.section]];
            CGRect tail=[table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)first.count-1 inSection:start.section]];
            if(!WXGBubbleValidRect(head) || !WXGBubbleValidRect(tail))return NO;
            CGFloat top=first.index?CGRectGetMinY(head)+5:CGRectGetMinY(bounds);
            CGFloat bottom=last.index+1<first.count?CGRectGetMaxY(tail)+1:CGRectGetMaxY(bounds);
            if(top>CGRectGetMinY(bounds)+2 || bottom<CGRectGetMaxY(bounds)-2)return NO;
            bounds.origin.y=top;bounds.size.height=bottom-top;
        }
    }
    WXGBubbleGlass *glass=[state.groups objectForKey:key];
    CGRect old=glass.superview?[glass convertRect:glass.bounds toView:table]:CGRectZero;
    WXGBubbleSpan span=WXGBubbleRenderSpan((WXGBubbleSpan){CGRectGetMinY(bounds),CGRectGetMaxY(bounds)},
        (WXGBubbleSpan){CGRectGetMinY(table.bounds),CGRectGetMaxY(table.bounds)},(WXGBubbleSpan){CGRectGetMinY(old),CGRectGetMaxY(old)});
    if(!(span.max>span.min))return NO;
    bounds.origin.y=span.min;bounds.size.height=span.max-span.min;
    CGFloat scale=MAX(1,table.window.screen.scale);
    CGRect aligned=CGRectMake(floor(CGRectGetMinX(bounds)*scale)/scale,floor(CGRectGetMinY(bounds)*scale)/scale,0,0);
    aligned.size=CGSizeMake(ceil(CGRectGetMaxX(bounds)*scale)/scale-aligned.origin.x,
                            ceil(CGRectGetMaxY(bounds)*scale)/scale-aligned.origin.y);
    if(!glass){
        glass=[[WXGBubbleGlass alloc]initWithFrame:CGRectZero];[state.groups setObject:glass forKey:key];++_mounts;
    }
    BOOL behind=NO;
    for(UIView *sibling in container.subviews){
        if(sibling==glass){behind=YES;break;}
        if([sibling isKindOfClass:UITableViewCell.class]){
            [container insertSubview:glass belowSubview:sibling];behind=YES;break;
        }
    }
    if(!behind)return NO;
    CGFloat reference=first.outgoing?state.outgoing:state.incoming;
    glass.outgoing=first.outgoing;glass.radius=WXGBubbleRadius(aligned.size.width,aligned.size.height,reference);
    WXGBubbleSetFrame(glass,[table convertRect:aligned toView:container]);
    NSMutableArray<WXGBubbleEntry *> *quotes=nil;
    for(WXGBubbleEntry *entry in ordered){
        [entry.view removeFromSuperview];[self paint:entry radius:glass.radius];
        if(entry.hasQuote && isfinite(entry.quoteDividerY)) {
            if(!quotes)quotes=[NSMutableArray array];
            [quotes addObject:entry];
        }else if(entry.quoteDivider)WXGBubblePlaceQuoteDivider(entry,glass,NAN);
    }
    // Reused or overlapping fragments can report the same physical section.
    // Compare positions in the common glass before snapping them to pixels.
    [quotes sortUsingComparator:^NSComparisonResult(WXGBubbleEntry *a,WXGBubbleEntry *b){
        CGFloat ya=WXGBubbleQuoteYInGlass(a,glass),yb=WXGBubbleQuoteYInGlass(b,glass);
        return ya<yb?NSOrderedAscending:(ya>yb?NSOrderedDescending:NSOrderedSame);
    }];
    CGFloat previousY=NAN;
    for(WXGBubbleEntry *entry in quotes) {
        CGFloat y=WXGBubbleQuoteYInGlass(entry,glass);
        BOOL distinct=WXGBubbleQuoteDividerDistinct(previousY,y);
        WXGBubblePlaceQuoteDivider(entry,glass,distinct?y:NAN);
        if(distinct)previousY=y;
    }
    return YES;
}
- (void)refreshTable:(UITableView *)table state:(WXGBubbleTable *)state {
    if(!table.window)return;
    // Ordinary scrolling carries the single overlay along with its table.
    // Only refresh its bounded texture when the viewport has moved far enough.
    BOOL moved=state.groups.count && (fabs(table.bounds.origin.y-state.viewport.origin.y)>=100 ||
        !CGSizeEqualToSize(table.bounds.size,state.viewport.size));
    if(!state.dirty && !moved)return;
    state.dirty=NO;state.viewport=table.bounds;
    CGFloat single[2]={0,0};
    NSMapTable *families=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPointerPersonality
                                                valueOptions:NSPointerFunctionsStrongMemory];
    for(WXGBubbleEntry *entry in state.entries) {
        if(!entry.host.window || !entry.body)continue;
        if(entry.fragment){
            if(!entry.family){[self unpaint:entry];continue;}
            id key=entry.family;
            if(entry.count && ![families objectForKey:key]) {
                // A rebuilt indexed parent can publish a cloned wrap. Validate
                // the message identity before adopting the existing surface.
                for(id candidate in state.groups)if(WXGBubbleSameFamilyKey(key,candidate)){key=candidate;break;}
                for(id candidate in families) {
                    WXGBubbleEntry *other=[[families objectForKey:candidate] firstObject];
                    if(other.count && WXGBubbleSameFamilyKey(key,candidate)){key=candidate;break;}
                }
            }
            entry.renderKey=key;
            NSMutableArray *members=[families objectForKey:key];
            if(!members){members=[NSMutableArray array];[families setObject:members forKey:key];}
            [members addObject:entry];continue;
        }
        if(entry.kind==WXGBubbleText && !entry.extendedText && WXGBubbleOneLine(entry.body.bounds.size.height) &&
           CGRectIntersectsRect([entry.body convertRect:entry.body.bounds toView:table],table.bounds)){
            CGFloat *candidate=&single[entry.outgoing?1:0];
            if(*candidate==0 || entry.body.bounds.size.height<*candidate)*candidate=entry.body.bounds.size.height;
        }
    }
    if(single[0]>0)state.incoming=WXGBubbleReference(single[0]);
    if(single[1]>0)state.outgoing=WXGBubbleReference(single[1]);
    NSHashTable *active=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for(id family in families){
        NSArray *members=[families objectForKey:family];
        if([self renderFamily:members key:family table:table state:state])[active addObject:family];
        else for(WXGBubbleEntry *entry in members)[self unpaint:entry];
    }
    for(id family in state.groups.keyEnumerator.allObjects)if(![active containsObject:family]){
        [[state.groups objectForKey:family] removeFromSuperview];[state.groups removeObjectForKey:family];
    }
    for(WXGBubbleEntry *entry in state.entries)if(entry.body && entry.host.window && !entry.fragment)
        [self renderLocal:entry reference:entry.outgoing?state.outgoing:state.incoming];
}
- (void)reassert {
    if(!_tables.count && !_voiceNodes.count)return;
    if(![self wanted]){[self restore];return;}
    for(UIView *host in _voiceNodes.keyEnumerator.allObjects) {
        if(!host.window){[_voiceNodes removeObjectForKey:host];continue;}
        BOOL dirty=NO;
        for(WXGVoiceNode *node in [_voiceNodes objectForKey:host]) {
            WXGBubbleVoiceState next=WXGVoiceNodeState(node.view,host);
            if(WXGBubbleVoiceHierarchyChanged(node.state,next)) {
                [_voiceNodes setObject:WXGVoiceNodes(host) forKey:host];
                dirty=YES;break;
            }
            if(WXGBubbleVoiceChanged(node.state,next)){dirty=YES;node.state=next;}
        }
        if(dirty){++_voiceStateRefreshes;[self refreshVoiceHost:host event:@"nativeTreeChanged"];}
    }
    for(UITableView *table in _tables){
        WXGBubbleTable *state=objc_getAssociatedObject(table,&WXGBubbleTableKey);
        if(!table.window)continue;
        for(WXGBubbleEntry *entry in state.entries.allObjects){
            if(!entry.host.window || entry.applying)continue;
            BOOL quoteChanged=entry.quoteLayoutPending || (entry.hasQuote && !WXGBubbleQuotePreview(entry.host));
            if(quoteChanged) {
                entry.quoteLayoutPending=NO;
                WXGBubbleInvalidateQuoteLookup(entry.host);
            }
            if(quoteChanged || WXGBubbleChildren(entry.body)!=entry.children || WXGBubbleHostModel(entry.host)!=entry.model ||
               !WXGBubbleMemberIsCurrent(entry))[self messageCellLaidOut:entry.host];
            if(entry.painted){[entry.states reapply];[entry.quoteBackground reapply];}
        }
        [self refreshTable:table state:state];
    }
}
- (void)tick:(CFTimeInterval)time {
    for(UITableView *table in _tables)if(table.window){
        WXGBubbleTable *state=objc_getAssociatedObject(table,&WXGBubbleTableKey);
        [self refreshTable:table state:state];
        for(WXGBubbleEntry *entry in state.entries)if(entry.painted && !entry.fragment)[entry.view tick:time];
        for(WXGBubbleGlass *glass in state.groups.objectEnumerator)[glass tick:time];
    }
}
- (void)applyConfiguration {
    if(![self wanted]){[self restore];return;}
    for(UIView *host in _observedHosts.allObjects)if(host.window)[self messageCellLaidOut:host];
}
- (void)restore {
    [_voiceNodes removeAllObjects];
    [_voiceTextOwners removeAllObjects];[_voiceHostByCell removeAllObjects];
    [_voiceSkinOwners removeAllObjects];
    [_pendingVoiceHosts removeAllObjects];
    for(UITableView *table in _tables){
        WXGBubbleTable *state=objc_getAssociatedObject(table,&WXGBubbleTableKey);
        for(WXGBubbleEntry *entry in state.entries.allObjects)[self retire:entry];
        for(WXGBubbleGlass *glass in state.groups.objectEnumerator)[glass removeFromSuperview];
        [state.groups removeAllObjects];state.dirty=NO;
    }
    [_tables removeAllObjects];
}
- (NSDictionary *)evidence {
    NSMutableArray *samples=[NSMutableArray array];NSUInteger shown=0,groups=0,nativeFragments=0;
    for(UITableView *table in _tables)if(table.window){
        WXGBubbleTable *state=objc_getAssociatedObject(table,&WXGBubbleTableKey);groups+=state.groups.count;
        for(WXGBubbleEntry *entry in state.entries){
            if(!entry.painted){if(entry.fragment)++nativeFragments;continue;}
            if(!entry.host.window)continue;
            WXGBubbleGlass *glass=entry.fragment?[state.groups objectForKey:entry.renderKey]:entry.view;
            ++shown;
            if(samples.count<10)[samples addObject:@{@"cell":NSStringFromClass(entry.host.class),@"outgoing":@(entry.outgoing),
                @"body":NSStringFromClass(entry.body.class),@"size":@[@(entry.body.bounds.size.width),@(entry.body.bounds.size.height)],
                @"oneLineReference":@(WXGBubbleReference(entry.outgoing?state.outgoing:state.incoming)),@"radius":@(glass.radius),
                @"fragments":@(entry.count),@"fragmentIndex":entry.index==NSNotFound?@(-1):@(entry.index),@"glassReady":@(glass.glass.ready)}];
        }
    }
    NSMutableArray *voiceBindings=[NSMutableArray array];
    for(UIView *host in _voiceNodes) {
        if(!host.window || voiceBindings.count>=6)continue;
        WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
        UIView *content=WXGBubbleVoiceContent(host), *skin=WXGBubbleVoiceSkin(host);
        [voiceBindings addObject:@{@"host":NSStringFromClass(host.class),@"transcript":WXGBubbleVoiceEvidence(host,entry.body),
            @"nativeContent":content?NSStringFromClass(content.class):@"",
            @"nativeSkin":skin?NSStringFromClass(skin.class):@"",
            @"boundBody":entry.body?NSStringFromClass(entry.body.class):@"",
            @"skinCount":@(entry.backgrounds.count),@"mounted":@(entry.view.superview!=nil),
            @"glassSize":@[@(entry.view.bounds.size.width),@(entry.view.bounds.size.height)]}];
    }
    return @{@"enabled":@([self wanted]),@"mounts":@(_mounts),@"layouts":@(_layouts),@"restores":@(_restores),
        @"voiceHistory":_voiceHistory.copy?:@[],@"voiceBindings":voiceBindings,@"voiceWatched":@(_voiceNodes.count),@"voiceNativeRefreshes":@(_voiceAttachmentRefreshes),
        @"voiceLayoutRefreshes":@(_voiceStateRefreshes),@"onScreen":@(shown),@"unifiedLongMessages":@(groups),@"nativeFragments":@(nativeFragments),@"samples":samples};
}
@end
