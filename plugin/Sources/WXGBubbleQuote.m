#import "WXGBubbleQuote.h"
#import "WXGBubbleQuoteRules.h"
#import "WXGIntegration.h"
#import <objc/runtime.h>

@interface WXGQuoteLookup : NSObject
@property(nonatomic,weak) UIView *body, *content, *preview;
@property(nonatomic) NSUInteger rootChildren, bodyChildren, contentChildren;
@property(nonatomic) CFTimeInterval lastScan;
@end
@implementation WXGQuoteLookup
@end

static char WXGQuoteLookupKey, WXGQuoteClassKey;

typedef NS_OPTIONS(NSUInteger, WXGQuoteTraits) {
    WXGQuoteContainer = 1,
    WXGMessageRoot = 2,
};

// Match the host classes used by MixBubble, including MMInputMsgReferView.
// Older clients use different names for the same preview. Classify each once.
static WXGQuoteTraits WXGQuoteTraitsFor(UIView *view) {
    Class cls=object_getClass(view);
    NSNumber *cached=objc_getAssociatedObject(cls,&WXGQuoteClassKey);
    if(cached)return cached.unsignedIntegerValue;
    NSString *name=NSStringFromClass(cls);
    WXGQuoteTraits traits=0;
    if([name containsString:@"MessageCellView"])traits|=WXGMessageRoot;
    if(![name hasPrefix:@"WXG"] && ![name hasPrefix:@"WBP"] && ![name hasPrefix:@"MBX"] &&
       (![name hasPrefix:@"UI"] || [name containsString:@"Msg"]) && ![view isKindOfClass:UIButton.class] &&
       ([name rangeOfString:@"Refer" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
        [name rangeOfString:@"Quote" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
        [name rangeOfString:@"Reply" options:NSCaseInsensitiveSearch].location!=NSNotFound))traits|=WXGQuoteContainer;
    objc_setAssociatedObject(cls,&WXGQuoteClassKey,@(traits),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return traits;
}

static BOOL WXGQuoteRectValid(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) &&
        isfinite(rect.size.height) && rect.size.width>.5 && rect.size.height>.5;
}

typedef struct {
    __unsafe_unretained UIView *preview;
    CGFloat score;
    NSUInteger remaining;
} WXGQuoteScan;

static void WXGFindPreview(UIView *node,UIView *root,UIView *body,CGRect bodyRect,
                           BOOL outsideRoot,NSUInteger depth,WXGQuoteScan *scan) {
    if(depth>12 || !scan->remaining)return;
    --scan->remaining;
    if(node.hidden || node.alpha<=.01 || WXGIsPluginView(node) ||
       [node isKindOfClass:UITableViewCell.class] || [node isKindOfClass:UICollectionViewCell.class] ||
       (outsideRoot && node==root))return;
    WXGQuoteTraits traits=WXGQuoteTraitsFor(node);
    if(node!=root && (traits&WXGMessageRoot))return;
    if((traits&WXGQuoteContainer) && node!=root && node!=body && ![body isDescendantOfView:node]) {
        CGRect rect=[node convertRect:node.bounds toView:root];
        if(WXGQuoteRectValid(rect) && rect.size.width>12 && rect.size.height>10) {
            CGFloat gap=MIN(fabs(CGRectGetMinY(rect)-CGRectGetMaxY(bodyRect)),
                            fabs(CGRectGetMaxY(rect)-CGRectGetMinY(bodyRect)));
            CGFloat score=gap*2.+fabs(CGRectGetMidX(rect)-CGRectGetMidX(bodyRect));
            if(score<scan->score){scan->score=score;scan->preview=node;}
            // Its native labels, thumbnails and background form one preview.
            return;
        }
    }
    if([node isKindOfClass:UILabel.class] || [node isKindOfClass:UITextView.class])return;
    for(UIView *child in node.subviews) {
        if(!scan->remaining)break;
        WXGFindPreview(child,root,body,bodyRect,outsideRoot,depth+1,scan);
    }
}

static BOOL WXGPreviewVisibleInCell(UIView *preview,UIView *owner,UIView *root) {
    for(UIView *v=preview;v;v=v.superview) {
        if(v.hidden || v.alpha<=.01)return NO;
        if(v==owner)return YES;
        if(v!=root && (WXGQuoteTraitsFor(v)&WXGMessageRoot))return NO;
    }
    return NO;
}

static void WXGExpandQuote(UIView *node,UIView *root,CGRect admissible,CGRect *envelope,
                           NSUInteger depth,NSUInteger *remaining) {
    if(depth>12 || !*remaining)return;
    --*remaining;
    if(node.hidden || node.alpha<=.01 || WXGIsPluginView(node))return;
    CGRect rect=[node convertRect:node.bounds toView:root];
    if(!WXGQuoteRectValid(rect))return;
    if(CGRectIntersectsRect(admissible,rect))*envelope=CGRectUnion(*envelope,rect);
    for(UIView *child in node.subviews) {
        if(!*remaining)break;
        WXGExpandQuote(child,root,admissible,envelope,depth+1,remaining);
    }
}

CGRect WXGBubbleQuotedEnvelope(UIView *root,UIView *body) {
    if(!root || !body || ![body isDescendantOfView:root])return CGRectNull;
    UIView *content=nil;
    for(UIView *p=root.superview;p;p=p.superview) {
        if([p isKindOfClass:UITableViewCell.class]){content=((UITableViewCell *)p).contentView;break;}
        if([p isKindOfClass:UITableView.class])break;
    }
    if(content && ![root isDescendantOfView:content])content=nil;
    UIView *owner=content?:root;
    WXGQuoteLookup *lookup=objc_getAssociatedObject(root,&WXGQuoteLookupKey);
    if(!lookup) {
        lookup=[WXGQuoteLookup new];
        objc_setAssociatedObject(root,&WXGQuoteLookupKey,lookup,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *preview=lookup.preview;
    CFTimeInterval now=CACurrentMediaTime();
    NSUInteger nr=root.subviews.count,nb=body.subviews.count,nc=content.subviews.count;
    BOOL changed=lookup.body!=body || lookup.content!=content || lookup.rootChildren!=nr ||
                 lookup.bodyChildren!=nb || lookup.contentChildren!=nc;
    if(preview && (!WXGPreviewVisibleInCell(preview,owner,root) || !WXGQuoteRectValid(preview.bounds))) {
        preview=nil;changed=YES;
    }
    // A quote can be inserted several levels down after the body finishes its
    // first layout. Recheck misses without traversing every plain row every frame.
    if(changed || (!preview && now-lookup.lastScan>=.25)) {
        CGRect rect=[body convertRect:body.bounds toView:root];
        if(!WXGQuoteRectValid(rect))return CGRectNull;
        WXGQuoteScan scan={nil,CGFLOAT_MAX,160};
        WXGFindPreview(root,root,body,rect,NO,0,&scan);
        if(content && !scan.preview) {
            scan.remaining=64;
            WXGFindPreview(content,root,body,rect,YES,0,&scan);
        }
        preview=scan.preview;
        lookup.preview=preview;lookup.body=body;lookup.content=content;
        lookup.rootChildren=nr;lookup.bodyChildren=nb;lookup.contentChildren=nc;lookup.lastScan=now;
    }
    if(!preview)return CGRectNull;
    CGRect bounds=[preview convertRect:preview.bounds toView:root];
    if(!WXGQuoteRectValid(bounds))return CGRectNull;
    CGRect envelope=bounds;
    CGRect admissible=CGRectInset(bounds,-80.,-600.);
    NSUInteger remaining=128;
    for(UIView *child in preview.subviews)WXGExpandQuote(child,root,admissible,&envelope,1,&remaining);
    return CGRectInset(envelope,-2.,-2.);
}

UIView *WXGBubbleQuotedContainer(UIView *root) {
    WXGQuoteLookup *lookup=objc_getAssociatedObject(root,&WXGQuoteLookupKey);
    UIView *preview=lookup.preview,*content=lookup.content;
    if(!preview || !content || [preview isDescendantOfView:root] || ![preview isDescendantOfView:content] ||
       ![root isDescendantOfView:content])return nil;
    return content;
}

UIView *WXGBubbleQuotePreview(UIView *root) {
    WXGQuoteLookup *lookup=objc_getAssociatedObject(root,&WXGQuoteLookupKey);
    UIView *preview=lookup.preview;
    return preview && WXGPreviewVisibleInCell(preview,lookup.content?:root,root)?preview:nil;
}

void WXGBubbleInvalidateQuoteLookup(UIView *root) {
    objc_setAssociatedObject(root,&WXGQuoteLookupKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *WXGQuoteOtherRichText(UIView *node,UIView *root,UIView *preview,NSUInteger depth,NSUInteger *remaining) {
    if(!*remaining || depth>12 || node==preview || node.hidden || node.alpha<=.01 || WXGIsPluginView(node))return nil;
    --*remaining;
    WXGQuoteTraits traits=WXGQuoteTraitsFor(node);
    if(node!=root && ((traits&WXGQuoteContainer) || (traits&WXGMessageRoot)))return nil;
    if([NSStringFromClass(node.class) containsString:@"RichTextView"] && WXGQuoteRectValid(node.bounds))return node;
    for(UIView *child in node.subviews){
        if(!*remaining)break;
        UIView *rich=WXGQuoteOtherRichText(child,root,preview,depth+1,remaining);
        if(rich)return rich;
    }
    return nil;
}

CGFloat WXGBubbleQuoteBoundary(UIView *root,UIView *mainRich,CGRect paddedEnvelope) {
    UIView *preview=WXGBubbleQuotePreview(root);
    if(!preview || !WXGQuoteRectValid(paddedEnvelope))return NAN;
    if(!mainRich || mainRich.hidden || mainRich.alpha<=.01 || [mainRich isDescendantOfView:preview]){
        NSUInteger remaining=128;
        mainRich=WXGQuoteOtherRichText(root,root,preview,0,&remaining);
        if(!mainRich)return NAN;
    }
    CGRect main=[mainRich convertRect:mainRich.bounds toView:root];
    CGRect raw=[preview convertRect:preview.bounds toView:root];
    if(!WXGQuoteRectValid(main) || !WXGQuoteRectValid(raw))return NAN;
    CGRect visual=CGRectInset(paddedEnvelope,2.,2.);
    return WXGBubbleQuoteDividerY((WXGBubbleSpan){CGRectGetMinY(main),CGRectGetMaxY(main)},
                                  (WXGBubbleSpan){CGRectGetMinY(visual),CGRectGetMaxY(visual)},
                                  (WXGBubbleSpan){CGRectGetMinY(raw),CGRectGetMaxY(raw)});
}
