#import "WXGIntegration.h"
#import "WXGBubbleTranslation.h"
#import "WXGBubbleRules.h"

static BOOL WXGTranslationSkip(UIView *view) {
    if(view.hidden || view.alpha<=.01 || WXGIsPluginView(view) ||
        [view isKindOfClass:UIControl.class])return YES;
    NSString *name=NSStringFromClass(view.class);
    return [name containsString:@"ReferView"] || [name containsString:@"Quote"] ||
        [name isEqualToString:@"CellSourceView"] || [name hasPrefix:@"WBP"];
}

static BOOL WXGTranslationRich(UIView *view) {
    return [NSStringFromClass(view.class) rangeOfString:@"RichTextView" options:NSCaseInsensitiveSearch].location!=NSNotFound;
}

static BOOL WXGTranslationCue(UIView *view) {
    NSString *text=nil;
    if([view isKindOfClass:UILabel.class])text=((UILabel *)view).text;
    else if([view isKindOfClass:UITextView.class])text=((UITextView *)view).text;
    if(!text.length || text.length>48)return NO;
    for(NSString *word in @[@"翻译",@"译文",@"原文",@"translate",@"translation",@"view original"])
        if([text rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    return NO;
}

typedef struct {
    CGRect native, original, translated;
    NSUInteger budget;
    BOOL confirmed;
} WXGTranslationMeasure;

static BOOL WXGTranslationUsable(CGRect r) {
    return !CGRectIsNull(r) && !CGRectIsInfinite(r) && r.size.width>1 && r.size.height>1;
}

// Use the live renderers: font metrics and a reused plate's bounds can both
// be much larger than the visible translation after WeChat switches languages.
static void WXGTranslationMeasureViews(UIView *node,UIView *host,NSUInteger depth,
                                       WXGTranslationMeasure *m) {
    if(!m->budget || depth>10 || WXGTranslationSkip(node))return;
    --m->budget;
    BOOL rich=WXGTranslationRich(node);
    if(rich || [node isKindOfClass:UILabel.class] || [node isKindOfClass:UITextView.class]) {
        CGRect r=[node convertRect:node.bounds toView:host];
        if(!WXGTranslationUsable(r))return;
        CGRect overlap=CGRectIntersection(m->native,r);
        CGFloat ratio=CGRectIsNull(overlap)?0:overlap.size.height/r.size.height;
        if(ratio>=.55 && rich)m->original=CGRectUnion(m->original,r);
        WXGBubbleBox skin={m->native.origin.x,m->native.origin.y,m->native.size.width,m->native.size.height};
        WXGBubbleBox text={r.origin.x,r.origin.y,r.size.width,r.size.height};
        if(WXGBubbleTextBelowSkin(skin,text)) {
            m->translated=CGRectUnion(m->translated,r);
            m->confirmed|=rich || WXGTranslationCue(node);
        }
        return;
    }
    for(UIView *child in node.subviews)WXGTranslationMeasureViews(child,host,depth+1,m);
}

static UIView *WXGTranslationFindPlate(UIView *branch,UIView *host,CGRect native,NSUInteger depth,
                                       WXGTranslationMeasure *total) {
    if(WXGTranslationSkip(branch) || WXGTranslationRich(branch) || !branch.subviews.count || depth>2)return nil;
    CGRect r=[branch convertRect:branch.bounds toView:host];
    CGFloat gap=CGRectGetMinY(r)-CGRectGetMaxY(native);
    if(gap>=-4 && gap<=40 && r.size.width>=24 && r.size.height>=20) {
        WXGTranslationMeasure m={native,CGRectNull,CGRectNull,96,NO};
        WXGTranslationMeasureViews(branch,host,0,&m);
        if(m.confirmed && WXGTranslationUsable(m.translated)) {
            total->translated=CGRectUnion(total->translated,m.translated);
            total->confirmed=YES;
            return branch;
        }
    }
    for(UIView *child in branch.subviews) {
        UIView *plate=WXGTranslationFindPlate(child,host,native,depth+1,total);
        if(plate)return plate;
    }
    return nil;
}

CGRect WXGBubbleTranslatedEnvelope(UIView *host,UIView *body,UIView *skin,UIView **materialPlate) {
    *materialPlate=nil;
    if(!host || !body || skin.superview!=body)return CGRectNull;
    CGRect native=[skin convertRect:skin.bounds toView:host];
    if(!WXGTranslationUsable(native))return CGRectNull;
    WXGTranslationMeasure m={native,CGRectNull,CGRectNull,140,NO};
    UIView *plate=nil;
    BOOL lowerSibling=NO;
    // Short ordinary messages usually have just the background and RichTextView.
    for(UIView *branch in body.subviews) {
        if(branch==skin || WXGTranslationSkip(branch))continue;
        CGRect rect=[branch convertRect:branch.bounds toView:host];
        if(CGRectGetMaxY(rect)<=CGRectGetMaxY(native)+1)continue;
        lowerSibling=YES;
        if(!plate)plate=WXGTranslationFindPlate(branch,host,native,0,&m);
    }
    for(UIView *branch in host.subviews) {
        if(branch==body || [body isDescendantOfView:branch] || WXGTranslationSkip(branch))continue;
        CGRect rect=[branch convertRect:branch.bounds toView:host];
        if(CGRectGetMinY(rect)<CGRectGetMaxY(native)-4 || CGRectGetMaxY(rect)<=CGRectGetMaxY(native)+1)continue;
        lowerSibling=YES;
        if(!plate)plate=WXGTranslationFindPlate(branch,host,native,0,&m);
    }
    if(!lowerSibling)return CGRectNull;
    WXGTranslationMeasureViews(host,host,0,&m);
    if(!m.confirmed || !WXGTranslationUsable(m.translated))return CGRectNull;
    // Reject a stale translation subtree retained from a taller reused row.
    if(!CGRectContainsRect(CGRectInset(host.bounds,-24,-14),m.translated))return CGRectNull;
    CGFloat padX=12,padY=10;
    if(WXGTranslationUsable(m.original)) {
        CGFloat x=MIN(CGRectGetMinX(m.original)-CGRectGetMinX(native),CGRectGetMaxX(native)-CGRectGetMaxX(m.original));
        if(x>=6 && x<=24)padX=MAX(padX,MIN(18,x));
    }
    if(plate) {
        CGRect p=[plate convertRect:plate.bounds toView:host];
        CGFloat x=MIN(CGRectGetMinX(m.translated)-CGRectGetMinX(p),CGRectGetMaxX(p)-CGRectGetMaxX(m.translated));
        CGFloat y=MIN(CGRectGetMinY(m.translated)-CGRectGetMinY(p),CGRectGetMaxY(p)-CGRectGetMaxY(m.translated));
        if(x>=6 && x<=24)padX=MAX(padX,MIN(18,x));
        if(y>=5 && y<=24)padY=MAX(padY,MIN(16,y));
    }
    *materialPlate=plate;
    CGRect envelope=CGRectUnion(native,CGRectInset(m.translated,-padX,-padY));
    if(WXGTranslationUsable(m.original))envelope=CGRectUnion(envelope,CGRectInset(m.original,-padX,-padY));
    return envelope;
}

static void WXGTranslationClear(UIView *node,UIView *plate,WXGStateBag *states,NSUInteger depth) {
    if(depth>8 || WXGTranslationSkip(node))return;
    if([node isKindOfClass:UIImageView.class]) {
        // The broad stretchable skin is a background. Small icons and the
        // glyphs in the translation keep their native rendering.
        UIImage *image=((UIImageView *)node).image;
        if(node.bounds.size.width>=plate.bounds.size.width*.7 && image &&
           !UIEdgeInsetsEqualToEdgeInsets(image.capInsets,UIEdgeInsetsZero))
            [states clearImagePaint:(UIImageView *)node];
        return;
    }
    [states clear:node];
    if(WXGTranslationRich(node) || [node isKindOfClass:UILabel.class] || [node isKindOfClass:UITextView.class])return;
    for(UIView *child in node.subviews)WXGTranslationClear(child,plate,states,depth+1);
}
void WXGBubbleClearTranslationPlate(UIView *plate,WXGStateBag *states) {
    if(plate)WXGTranslationClear(plate,plate,states,0);
}
