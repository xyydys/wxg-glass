#import "WXGBubbleQuoteBackground.h"
#import <objc/runtime.h>

typedef NS_OPTIONS(NSUInteger, WXGQuotePaintTraits) {
    WXGQuotePaintContent = 1, WXGQuotePaintEffectRenderer = 2, WXGQuotePaintNativeRoot = 4
};

static WXGQuotePaintTraits WXGPaintTraits(UIView *view) {
    if (!view) return 0;
    static char key;
    Class cls = object_getClass(view);
    NSNumber *known = objc_getAssociatedObject(cls, &key);
    if (known) return known.unsignedIntegerValue;
    NSString *name = NSStringFromClass(cls);
    WXGQuotePaintTraits traits = 0;
    if ([view isKindOfClass:NSClassFromString(@"MMInputMsgReferView")] || [name containsString:@"MMInputMsgReferView"])
        traits |= WXGQuotePaintNativeRoot;
    if ([name hasPrefix:@"WXG"] || [name hasPrefix:@"WBP"] || [name hasPrefix:@"MBX"] || [name hasPrefix:@"MB3"] ||
        [view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] || [view isKindOfClass:UIImageView.class] ||
        [name containsString:@"RichText"] || [name containsString:@"Thumbnail"] || [name containsString:@"Avatar"])
        traits |= WXGQuotePaintContent;
    if (![name containsString:@"ContentView"] && ([name containsString:@"VisualEffectBackdrop"] ||
        [name containsString:@"VisualEffectFilter"] || [name containsString:@"VisualEffectSubview"]))
        traits |= WXGQuotePaintEffectRenderer;
    objc_setAssociatedObject(cls, &key, @(traits), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return traits;
}

// A native Refer/Reply wrapper may contain the hook target a level deeper.
// Leave the wrapper and its other children entirely in WeChat's ownership.
static UIView *WXGNativeQuoteIn(UIView *candidate, NSUInteger depth) {
    if (!candidate || depth > 12) return nil;
    WXGQuotePaintTraits traits = WXGPaintTraits(candidate);
    if (traits & WXGQuotePaintNativeRoot) return candidate;
    if ((traits & WXGQuotePaintContent) || candidate.hidden ||
        [candidate isKindOfClass:UITableViewCell.class] || [candidate isKindOfClass:UICollectionViewCell.class]) return nil;
    for (UIView *child in candidate.subviews) {
        UIView *root = WXGNativeQuoteIn(child, depth + 1);
        if (root) return root;
    }
    return nil;
}

// Keep the latest native values that actually painted. In particular, changing
// the effect or the background for dark mode while hidden must be reversible.
@interface WXGQuotePaintPart : NSObject {
@public
    __weak WXGBubbleQuoteBackground *owner;
    __weak CALayer *layer, *parent;
    __weak UIView *view;
    NSUInteger children, visit;
    WXGQuotePaintTraits traits;
}
- (void)applyForSize:(CGSize)size;
- (void)restore;
@end

static char WXGQuotePaintPartKey;
@implementation WXGQuotePaintPart {
    UIColor *_fill, *_layerFill, *_shapeFill, *_shapeStroke;
    UIVisualEffect *_effect;
    CGFloat _border;
    float _shadow;
    BOOL _opaque, _hidRenderer;
}
- (void)restoreShape:(CAShapeLayer *)shape {
    if (_shapeFill && !shape.fillColor) shape.fillColor = _shapeFill.CGColor;
    if (_shapeStroke && !shape.strokeColor) shape.strokeColor = _shapeStroke.CGColor;
    _shapeFill = _shapeStroke = nil;
}
- (void)applyForSize:(CGSize)size {
    UIView *v = view;
    CALayer *l = layer;
    if (!l) return;
    UIColor *fill = v.backgroundColor;
    CGColorRef layerFill = l.backgroundColor;
    if (layerFill && CGColorGetAlpha(layerFill) > 0 && (!fill || !CGColorEqualToColor(layerFill, fill.CGColor)))
        _layerFill = [UIColor colorWithCGColor:layerFill];
    if (fill && CGColorGetAlpha(fill.CGColor) > 0) {
        _fill = fill;
        if (layerFill && CGColorEqualToColor(layerFill, fill.CGColor)) _layerFill = nil;
        v.backgroundColor = UIColor.clearColor;
    }
    if (l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0) l.backgroundColor = nil;
    if (v.opaque) { _opaque = YES; v.opaque = NO; }
    if (l.borderWidth > 0) { _border = l.borderWidth; l.borderWidth = 0; }
    if (l.shadowOpacity > 0) { _shadow = l.shadowOpacity; l.shadowOpacity = 0; }
    if ([v isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *blur = (UIVisualEffectView *)v;
        if (blur.effect) { _effect = blur.effect; blur.effect = nil; }
    }
    if ((traits & WXGQuotePaintEffectRenderer) && !l.hidden) { _hidRenderer = YES; l.hidden = YES; }
    if ([l isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *shape = (CAShapeLayer *)l;
        // MixBubble's second native style draws its plate on a full-size shape.
        if (!l.contents && fabs(l.bounds.size.width - size.width) <= 1.5 && fabs(l.bounds.size.height - size.height) <= 1.5) {
            if (shape.fillColor) { _shapeFill = [UIColor colorWithCGColor:shape.fillColor]; shape.fillColor = nil; }
            if (shape.strokeColor) { _shapeStroke = [UIColor colorWithCGColor:shape.strokeColor]; shape.strokeColor = nil; }
        } else [self restoreShape:shape];
    }
}
- (void)restore {
    CALayer *l = layer;
    if (!l || objc_getAssociatedObject(l, &WXGQuotePaintPartKey) != self) return;
    UIView *v = view;
    BOOL nativeLayerPaint = l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0;
    if (_fill && !nativeLayerPaint && (!v.backgroundColor || CGColorGetAlpha(v.backgroundColor.CGColor) == 0))
        v.backgroundColor = _fill;
    if (_layerFill && !nativeLayerPaint) l.backgroundColor = _layerFill.CGColor;
    if (_opaque && !v.opaque) v.opaque = YES;
    if (_border && !l.borderWidth) l.borderWidth = _border;
    if (_shadow && !l.shadowOpacity) l.shadowOpacity = _shadow;
    if (_hidRenderer && l.hidden) l.hidden = NO;
    if ([l isKindOfClass:CAShapeLayer.class]) [self restoreShape:(CAShapeLayer *)l];
    if (_effect && [v isKindOfClass:UIVisualEffectView.class] && !((UIVisualEffectView *)v).effect)
        ((UIVisualEffectView *)v).effect = _effect;
    objc_setAssociatedObject(l, &WXGQuotePaintPartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    owner = nil;
}
@end

@implementation WXGBubbleQuoteBackground {
    __weak UIView *_preview, *_candidate;
    NSMutableArray<WXGQuotePaintPart *> *_parts;
    NSUInteger _visit;
    CFTimeInterval _nextPreviewScan;
    BOOL _applying;
}
- (void)scan:(CALayer *)l size:(CGSize)size {
    UIView *v = [l.delegate isKindOfClass:UIView.class] ? (UIView *)l.delegate : nil;
    if (v.layer != l) v = nil;
    WXGQuotePaintTraits traits = WXGPaintTraits(v);
    if ((traits & WXGQuotePaintContent) || [l isKindOfClass:CATextLayer.class]) return;
    // MixBubble mounts its custom plate as a plain UIView with a WBPQStripeView
    // child. Its fill is a standalone layer beside the stripe.
    if (v.superview == _preview && v.class == UIView.class) {
        Class stripe = NSClassFromString(@"WBPQStripeView");
        if (stripe) for (UIView *child in v.subviews) if ([child isKindOfClass:stripe]) return;
    }
    WXGQuotePaintPart *part = objc_getAssociatedObject(l, &WXGQuotePaintPartKey);
    if (!part || part->owner != self) {
        [part restore];
        part = [WXGQuotePaintPart new];
        part->owner = self; part->layer = l; part->view = v; part->traits = traits;
        objc_setAssociatedObject(l, &WXGQuotePaintPartKey, part, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_parts addObject:part];
    }
    part->visit = _visit; part->parent = l.superlayer;
    [part applyForSize:size];
    NSArray<CALayer *> *sublayers = l.sublayers;
    part->children = sublayers.count;
    for (CALayer *child in sublayers) [self scan:child size:size];
}
- (void)updatePreview:(UIView *)preview {
    if (_applying) return;
    UIView *candidate = preview;
    if (candidate && candidate == _candidate && [_preview isDescendantOfView:candidate])
        preview = _preview;
    else preview = WXGNativeQuoteIn(candidate, 0);
    if (preview != _preview || !preview) [self restore];
    if (!preview) {
        _candidate = candidate;
        _nextPreviewScan = CACurrentMediaTime() + .25;
        return;
    }
    WXGQuotePaintPart *rootPart = objc_getAssociatedObject(preview.layer, &WXGQuotePaintPartKey);
    WXGBubbleQuoteBackground *previous = rootPart ? rootPart->owner : nil;
    if (previous != self) [previous restore];
    _candidate = candidate; _preview = preview;
    if (!_parts) _parts = [NSMutableArray array];
    _applying = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    @try {
        ++_visit;
        [self scan:preview.layer size:preview.bounds.size];
        for (NSInteger i = (NSInteger)_parts.count - 1; i >= 0; --i) {
            WXGQuotePaintPart *part = _parts[(NSUInteger)i];
            if (part->visit == _visit) continue;
            [part restore]; [_parts removeObjectAtIndex:(NSUInteger)i];
        }
    } @finally { [CATransaction commit]; _applying = NO; }
}
- (void)reapply {
    if (_applying) return;
    if (!_parts.count) {
        if (_candidate && CACurrentMediaTime() >= _nextPreviewScan) [self updatePreview:_candidate];
        return;
    }
    UIView *preview = _preview;
    if (!preview || !_candidate || (preview != _candidate && ![preview isDescendantOfView:_candidate])) {
        [self updatePreview:_candidate]; return;
    }
    BOOL rescan = NO;
    _applying = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    @try {
        for (WXGQuotePaintPart *part in _parts) {
            CALayer *l = part->layer;
            if (!l || part->owner != self || l.superlayer != part->parent) { rescan = YES; break; }
            [part applyForSize:preview.bounds.size];
            if (part->children != l.sublayers.count) { rescan = YES; break; }
        }
    } @finally { [CATransaction commit]; _applying = NO; }
    if (rescan) [self updatePreview:preview];
}
- (void)restore {
    if (_applying) return;
    _applying = YES;
    _candidate = _preview = nil;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    @try {
        for (WXGQuotePaintPart *part in _parts.reverseObjectEnumerator) [part restore];
        [_parts removeAllObjects];
    } @finally { [CATransaction commit]; _applying = NO; }
}
- (void)dealloc { [self restore]; }
@end
