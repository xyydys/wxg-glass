// Run WXGTestMenuMorphOwnershipInWindow on the main thread of a dedicated iOS
// test app with the plugin linked, a visible window, morph mode and the 26 rim.
#import "../Sources/WXGIntegration.h"
#import "../Sources/WXGMenuMorphView.h"
#import "../Sources/WXGMenuMorphMaterial.h"
#import "../Sources/WXGMenuMorphContent.h"
#import "../Sources/WXGMenuScrub.h"
#import <QuartzCore/QuartzCore.h>
#include <assert.h>

@class WXGDecoration;
@interface WXGDecorations (MenuMorphFixture)
- (void)prepareMenuMorph:(WXGDecoration *)entry;
- (void)renderMenuMorph:(WXGDecoration *)entry;
- (void)resetMenuMorph:(WXGDecoration *)entry;
@end

// These are the existing properties on the native menu's private entry.
@interface WXGDecoration : NSObject {
@public WXGMenuMorph _morphMotion; // Its public spring state in WXGDecorations.m.
    WXGMenuScrub _scrub;
}
@property(nonatomic) NSInteger phase;
@property(nonatomic) BOOL morphSettled, morphMode;
@property(nonatomic,weak) UIView *menuParent, *host;
@property(nonatomic,weak) WXGSurface *plusSurface;
@property(nonatomic) CGRect morphAnchor, morphRect;
@property(nonatomic,strong) WXGMenuMorphContent *morphContent;
@property(nonatomic,strong) WXGMenuMorphView *morphView;
@property(nonatomic,strong) UIView *morphForeground;
@end

static CGRect BoxRect(WXGMenuBox box) {return CGRectMake(box.x,box.y,box.w,box.h);}

static CALayer *LayerNamed(CALayer *root, NSString *name, NSUInteger *count) {
    CALayer *found = nil;
    if ([root.name isEqual:name]) {++*count; found = root;}
    for (CALayer *child in root.sublayers) {
        CALayer *candidate = LayerNamed(child,name,count);
        if (candidate) found = candidate;
    }
    return found;
}
static CALayer *OnlyLayer(CALayer *root, NSString *name) {
    NSUInteger count = 0;
    CALayer *layer = LayerNamed(root,name,&count);
    assert(count == 1);
    return layer;
}
static BOOL VisibleThrough(CALayer *layer, CALayer *ancestor) {
    for (CALayer *next=layer; next; next=next.superlayer) {
        if (next.hidden || next.opacity <= 0 || CGRectIsEmpty(next.bounds)) return NO;
        if (next == ancestor) return YES;
    }
    return NO;
}
static CALayer *OnlyPaint(CALayer *rim) {
    CALayer *paint = nil;
    for (CALayer *child in rim.sublayers) {
        if (child.hidden || child.opacity <= 0) continue;
        if ([child.name isEqual:@"morph.press.edge"]) {
            CAShapeLayer *touchStrip = (CAShapeLayer *)child.mask;
            assert([touchStrip isKindOfClass:CAShapeLayer.class] && touchStrip.path);
            assert(CGPathEqualToPath(touchStrip.path,((CAShapeLayer *)rim.mask).path));
            continue;
        }
        assert(!paint);
        paint = child;
    }
    assert(paint);
    return paint;
}
static void CheckLayers(WXGMenuMorphSurface *surface, CALayer *rim, CALayer *paint, UIWindow *window) {
    assert(OnlyLayer(window.layer,@"morph.surface") == surface.layer);
    assert(OnlyLayer(window.layer,@"morph.rim") == rim);
    assert(OnlyPaint(rim) == paint && VisibleThrough(paint,window.layer));
    CAShapeLayer *clip = (CAShapeLayer *)rim.mask;
    assert([clip isKindOfClass:CAShapeLayer.class] && clip.path);
    CGPathRef outline = surface.currentOutline.CGPath;
    assert(outline && !CGPathIsEmpty(outline));
    CGPathRef bodyPath = ((CAShapeLayer *)surface.inkHost.superview.layer.mask).path;
    assert(bodyPath && CGPathEqualToPath(bodyPath,outline));
    CGRect frame = [surface.layer convertRect:rim.bounds fromLayer:rim];
    CGRect expected = CGPathGetPathBoundingBox(outline);
    assert(fabs(frame.origin.x-expected.origin.x) < .02 && fabs(frame.origin.y-expected.origin.y) < .02);
    assert(fabs(frame.size.width-expected.size.width) < .02 && fabs(frame.size.height-expected.size.height) < .02);
    CGAffineTransform shift = CGAffineTransformMakeTranslation(-expected.origin.x,-expected.origin.y);
    CGPathRef local = CGPathCreateCopyByTransformingPath(outline,&shift);
    assert(CGPathEqualToPath(local,clip.path));
    if ([paint.name isEqual:@"morph.rim.paint"]) {
        assert(paint.filters.count && paint.mask.opacity > 0);
        NSUInteger bands = 0;
        CAShapeLayer *band = (CAShapeLayer *)LayerNamed(paint.mask,@"morph.rim.band",&bands);
        assert(bands && band && band.path && band.lineWidth > 0);
        assert(CGPathEqualToPath(local,band.path));
    } else {
        assert(paint.contents);
    }
    CGPathRelease(local);
}

static void RunAppearance(UIWindow *window, UIUserInterfaceStyle style) {
    UIView *page = [[UIView alloc] initWithFrame:window.bounds];
    page.overrideUserInterfaceStyle = style;
    page.backgroundColor = style == UIUserInterfaceStyleDark ? UIColor.darkGrayColor : UIColor.lightGrayColor;
    [window addSubview:page];
    // Preserve the measured fractional corner even in a narrower test window.
    double x = CGRectGetWidth(page.bounds) - (440. - 379.67588);
    WXGMenuBox anchor = {x,57.59884,41.468988,41.468988};
    WXGMenuBox panel = {x+41.468988-225.33333,57.59884,225.33333,164};
    WXGSurface *button = [WXGSurface new];
    button.homePlusAnchor = YES; button.homePlusTrigger = YES; button.active = YES;
    [button placeMaterial:BoxRect(anchor) inParent:page];
    [button layoutIfNeeded];
    CALayer *surfaceLayer = OnlyLayer(button.layer,@"morph.surface");
    WXGMenuMorphSurface *surface = (WXGMenuMorphSurface *)surfaceLayer.delegate;
    assert([surface isKindOfClass:WXGMenuMorphSurface.class]);
    CALayer *rim = OnlyLayer(surfaceLayer,@"morph.rim"), *paint = OnlyPaint(rim);
    UIView *ink = surface.inkHost;
    CheckLayers(surface,rim,paint,window);
    assert(button.glass.hidden);

    WXGDecorations *manager = [WXGDecorations new];
    WXGDecoration *entry = [WXGDecoration new];
    UIView *host = [[UIView alloc] initWithFrame:BoxRect(panel)]; [page addSubview:host];
    entry.menuParent=page; entry.host=host; entry.plusSurface=button; entry.morphMode=YES;
    entry.morphAnchor=BoxRect(anchor); entry.morphRect=BoxRect(panel);
    entry.morphContent=[WXGMenuMorphContent contentWithTitles:@[@"发起群聊",@"添加朋友",@"扫一扫",@"收付款"]
        nativeIcons:@[NSNull.null,NSNull.null,NSNull.null,NSNull.null] submenuRows:nil dividerBeforeRows:nil
        panelWidth:panel.w traitCollection:page.traitCollection scale:window.screen.scale];
    [manager prepareMenuMorph:entry];
    WXGMenuMorphView *portal = entry.morphView;
    UIView *foreground = entry.morphForeground;
    assert(portal.window == window && foreground);
    WXGMenuMorph *motion = &entry->_morphMotion;
    CGFloat radius = entry.morphContent.panelCornerRadius + 2.85235;
    entry->_scrub = WXGMenuScrubInitial(window.screen.scale);
    WXGMenuMorphInitialize(motion,anchor,panel,radius,anchor,false);
    WXGMenuMorphSetAbsorbDuration(motion,.48);
    entry.phase=1; // WXGMenuPhaseOpen
    [manager renderMenuMorph:entry];
    BOOL usingMetal = foreground.hidden;
    CheckLayers(surface,rim,paint,window);
    bool targets[] = {true,false,true,false};
    for (int phase=0; phase<4; ++phase) {
        entry.phase=targets[phase]?1:2; // Open or exiting.
        WXGMenuMorphSetExpanded(motion,targets[phase]);
        BOOL settled=NO;
        for (int frame=1; frame<=360; ++frame) {
            settled=WXGMenuMorphAdvance(motion,.840334/120.);
            if (phase==0 && frame==12) {
                // Re-evaluate the real portal factory with changed fractional geometry.
                panel.x+=.125; anchor.x+=.125; anchor.y+=.25; panel.y+=.25;
                [button placeMaterial:BoxRect(anchor) inParent:page];
                entry.morphAnchor=BoxRect(anchor); entry.morphRect=BoxRect(panel);
                [manager prepareMenuMorph:entry];
                assert(entry.morphView==portal && entry.morphForeground==foreground);
                WXGMenuMorphUpdateSource(motion,anchor,anchor);
                WXGMenuMorphUpdateTarget(motion,panel,radius);
            }
            entry.morphSettled=settled;
            [manager renderMenuMorph:entry];
            assert(foreground.hidden==usingMetal);
            CheckLayers(surface,rim,paint,window);
            assert(button.glass.hidden && surface.inkHost==ink && [surface isDescendantOfView:portal]);
            assert([foreground isDescendantOfView:ink]);
            if (settled || (phase==1 && frame==14)) break;
        }
        if (phase!=1) assert(settled);
        if (phase!=0) continue;
        WXGMenuScrub *scrub = &entry->_scrub;
        NSArray<NSValue *> *rows = entry.morphContent.rowFrames;
        CGRect restingOutline = surface.currentOutline.bounds;
        if (usingMetal) {
            for (int attempt=0; attempt<12 && ![portal.presentationEvidence[@"cachedOpenInk"] boolValue]; ++attempt) {
                [CATransaction flush];
                [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1./60.]];
                [manager renderMenuMorph:entry];
            }
            assert([portal.presentationEvidence[@"cachedOpenInk"] boolValue]);
        }
        NSUInteger submissions=[portal.presentationEvidence[@"inkSubmissions"] unsignedIntegerValue];
        WXGMenuScrubDown(scrub, panel.x+panel.w*.5, panel.y+CGRectGetMidY(rows[0].CGRectValue));
        for (NSUInteger index=0; index<rows.count; ++index) {
            CGRect row = rows[index].CGRectValue;
            WXGMenuScrubMove(scrub,panel.x+panel.w*.5,panel.y+CGRectGetMidY(row));
            WXGMenuScrubSelect(scrub,row.origin.y,row.size.height,index==0);
            for (int tick=0;tick<12;++tick) {
                WXGMenuScrubAdvance(scrub,.840334/120.,false);
                [manager renderMenuMorph:entry];
                assert(foreground.hidden==usingMetal);
                assert(surface.inkHost==ink && [foreground isDescendantOfView:ink]);
                CheckLayers(surface,rim,paint,window);
                if (usingMetal) {
                    NSDictionary *shown=portal.presentationEvidence;
                    assert(fabs(CGRectFromString(shown[@"selectionRect"]).origin.y-scrub->top.value)<.02);
                    assert([shown[@"selectionOpacity"] doubleValue]>.99);
                    assert([shown[@"inkSubmissions"] unsignedIntegerValue]==submissions);
                    assert(VisibleThrough(OnlyLayer(surface.layer,@"morph.selection.plate"),surface.layer));
                }
            }
        }
        assert(fabs(surface.currentOutline.bounds.size.height-restingOutline.size.height)>1.);
        WXGMenuScrubRelease(scrub);
        WXGMenuScrubClear(scrub);
    }
    [manager resetMenuMorph:entry];
    [button layoutIfNeeded];
    assert(!entry.morphView && !portal.superview && !foreground.superview);
    assert([surface isDescendantOfView:button] && button.glass.hidden);
    CheckLayers(surface,rim,paint,window);
    [page removeFromSuperview];
}

void WXGTestMenuMorphOwnershipInWindow(UIWindow *window) {
    assert([NSThread isMainThread] && window && !window.hidden);
    RunAppearance(window,UIUserInterfaceStyleLight);
    RunAppearance(window,UIUserInterfaceStyleDark);
}
