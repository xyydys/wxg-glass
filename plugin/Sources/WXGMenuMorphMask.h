#ifndef WXG_MENU_MORPH_MASK_H
#define WXG_MENU_MORPH_MASK_H

#import <UIKit/UIKit.h>
#include "WXGMenuMorphField.h"

typedef struct {
    CGMutablePathRef path;
    CGPoint first, firstMidpoint, last;
    unsigned count;
} WXGMenuMorphPathBuilder;

static inline CGPoint WXGMenuMorphMidpoint(CGPoint a, CGPoint b) {
    return CGPointMake((a.x + b.x) * 0.5, (a.y + b.y) * 0.5);
}

static void WXGMenuMorphAppendContour(WXGMenuMorphContourAction action, float x, float y, void *context) {
    WXGMenuMorphPathBuilder *builder = context;
    CGPoint point = CGPointMake(x, y);
    if (action == WXGMenuMorphContourMove) {
        builder->first = builder->last = point;
        builder->count = 1;
        return;
    }
    if (action == WXGMenuMorphContourClose) {
        if (builder->count < 3) return;
        CGPoint midpoint = WXGMenuMorphMidpoint(builder->last, builder->first);
        CGPathAddQuadCurveToPoint(builder->path, NULL, builder->last.x, builder->last.y, midpoint.x, midpoint.y);
        CGPathAddQuadCurveToPoint(builder->path, NULL, builder->first.x, builder->first.y, builder->firstMidpoint.x, builder->firstMidpoint.y);
        CGPathCloseSubpath(builder->path);
        return;
    }
    CGPoint midpoint = WXGMenuMorphMidpoint(builder->last, point);
    if (builder->count == 1) {
        builder->firstMidpoint = midpoint;
        CGPathMoveToPoint(builder->path, NULL, midpoint.x, midpoint.y);
    } else {
        CGPathAddQuadCurveToPoint(builder->path, NULL, builder->last.x, builder->last.y, midpoint.x, midpoint.y);
    }
    builder->last = point;
    builder->count++;
}

static inline UIBezierPath *WXGMenuMorphRoundedRect(CGRect rect, CGFloat radius) {
    if (CGRectIsEmpty(rect)) return [UIBezierPath bezierPath];
    radius = MAX(0.0, MIN(radius, MIN(rect.size.width, rect.size.height) * 0.5));
    return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
}

static inline WXGMenuMorphFieldBox WXGMenuMorphFieldBoxFromRect(CGRect rect, CGFloat radius) {
    return (WXGMenuMorphFieldBox){(float)rect.origin.x, (float)rect.origin.y, (float)rect.size.width, (float)rect.size.height, (float)radius};
}

static inline UIBezierPath *WXGMenuMorphMaskPath(const WXGMenuMorphField *field) {
    WXGMenuMorphPathBuilder builder = {.path = CGPathCreateMutable()};
    WXGMenuMorphFieldTrace(field, WXGMenuMorphAppendContour, &builder);
    UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:builder.path];
    CGPathRelease(builder.path);
    return path;
}

#endif
