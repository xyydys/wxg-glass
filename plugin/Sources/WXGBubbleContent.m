#import "WXGBubbleContent.h"
#import "WXGBubbleCardFit.h"
#import "WXGIntegration.h"

// Physical message roots in MixBubble 2.9.4.6. Image/video, emoticon and
// Finder share cells are position-only there: their media keeps its own skin.
NSArray<NSString *> *WXGBubbleCardClassNames(void) {
    return @[@"VoiceMessageCellView", @"VoIPBubbleMessageCellView",
             @"AppFileMessageCellView", @"AppFileMessageCellViewV2",
             @"AppNoteMessageCellView", @"AppRecordMessageCellView",
             @"WCPayTransferMessageCellView", @"WCPayC2CMessageCellView", @"WCPayBaseMessageCellView",
             @"AppTrackRoomMessageCellView", @"AppUrlMessageCellView", @"LocationMessageCellView",
             @"BizAppTextContentMessageCellView", @"BizAppImageContentMessageCellView",
             @"ShareCardMessageCellView", @"WAAppPageCellView"];
}

typedef NS_OPTIONS(NSUInteger, WXGCardTraits) {
    WXGCardSupported = 1, WXGCardText = 2, WXGCardInset = 4, WXGCardStandby = 8,
    WXGCardVoice = 16, WXGCardContact = 32,
};

static WXGCardTraits WXGCardTraitsForHost(UIView *host) {
    Class cls = host.class;
    if (!cls) return 0;
    static char traitsKey;
    NSNumber *cached = objc_getAssociatedObject(cls, &traitsKey);
    if (cached) return cached.unsignedIntegerValue;
    NSString *name = NSStringFromClass(cls);
    WXGCardTraits traits = 0;
    if ([name rangeOfString:@"TextMessageCellView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        traits = WXGCardText;
    } else if ([name hasPrefix:@"WAAppPageCellView"]) {
        traits = WXGCardSupported | WXGCardInset;
    } else if ([host isKindOfClass:NSClassFromString(@"VoiceMessageCellView")]) {
        traits = WXGCardSupported | WXGCardVoice | WXGCardStandby;
    } else if ([WXGBubbleCardClassNames() containsObject:name]) {
        traits = WXGCardSupported;
        if ([name isEqualToString:@"ShareCardMessageCellView"]) traits |= WXGCardContact | WXGCardStandby;
        if ([name isEqualToString:@"WCPayC2CMessageCellView"]) traits |= WXGCardStandby;
        if ([name hasPrefix:@"WCPay"] || [name hasPrefix:@"BizApp"] ||
            [name isEqualToString:@"LocationMessageCellView"] || [name isEqualToString:@"AppRecordMessageCellView"])
            traits |= WXGCardInset;
    }
    objc_setAssociatedObject(cls, &traitsKey, @(traits), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return traits;
}

WXGBubbleKind WXGBubbleKindForHost(UIView *host) {
    WXGCardTraits traits = WXGCardTraitsForHost(host);
    if (traits & WXGCardText) return WXGBubbleText;
    return (traits & WXGCardSupported) ? WXGBubbleNonText : WXGBubbleUnsupported;
}

static BOOL WXGCardStretchable(UIView *view) {
    if (![view isKindOfClass:UIImageView.class]) return NO;
    UIEdgeInsets caps = ((UIImageView *)view).image.capInsets;
    return fabs(caps.top) + fabs(caps.left) + fabs(caps.bottom) + fabs(caps.right) > .5;
}

static WXGCardImageFit WXGCardFit(UIView *image, UIView *body) {
    WXGCardImageFit fit = {0};
    CGRect bounds = body.bounds;
    CGRect frame = image.frame;
    if (CGRectIsEmpty(bounds) || CGRectIsInfinite(bounds) || CGRectIsInfinite(frame) ||
        CGRectGetWidth(image.bounds) < 40 || CGRectGetHeight(image.bounds) < 20 ||
        ![NSStringFromClass(image.class) containsString:@"YYAsyncImageView"] || image.subviews.count)
        return fit;
    CGRect intersection = CGRectIntersection(frame, bounds);
    if (CGRectIsEmpty(intersection)) return fit;
    BOOL overhang = CGRectGetMinX(frame) < CGRectGetMinX(bounds)-1 || CGRectGetMaxX(frame) > CGRectGetMaxX(bounds)+1;
    return WXGBubbleCardImageFit(CGRectGetWidth(intersection) / CGRectGetWidth(bounds),
                                 CGRectGetHeight(intersection) / CGRectGetHeight(bounds),
                                 CGRectGetWidth(image.bounds) * CGRectGetHeight(image.bounds),
                                 overhang, WXGCardStretchable(image));
}

static UIView *WXGCardPrimary(UIView *body, WXGCardTraits traits, CGFloat *scoreOut) {
    CGFloat bestScore = 0;
    UIView *best = nil;
    for (UIView *child in body.subviews) {
        WXGCardImageFit fit = WXGCardFit(child, body);
        CGFloat score = fit.score;
        if (!WXGBubbleCardAcceptFit(fit, traits & WXGCardInset)) {
            if (!(traits & WXGCardVoice) || !WXGBubbleCompactVoiceSkin(fit,
                    CGRectGetMinY(child.frame) - CGRectGetMinY(body.bounds), CGRectGetHeight(child.bounds))) continue;
            score = fit.area;
        }
        // Prefer the active skin. Concealing an image with the state bag
        // preserves its native alpha, including WeChat's standby state.
        score += (!child.hidden && child.alpha > .01) ? 100000 : 0;
        if (score > bestScore) { best = child; bestScore = score; }
    }
    if (scoreOut) *scoreOut = bestScore;
    return best;
}

// MixBubble identifies these two roles on VoiceMessageCellView. An old,
// still-visible body may retain a perfectly plausible skin during conversion.
static UIView *WXGVoiceOwnedView(UIView *host, const char *field) {
    Ivar ivar = class_getInstanceVariable(host.class, field);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    UIView *view = object_getIvar(host, ivar);
    return [view isKindOfClass:UIView.class] && view != host && [view isDescendantOfView:host] ? view : nil;
}

BOOL WXGBubbleIsVoiceHost(UIView *host) {
    return (WXGCardTraitsForHost(host) & WXGCardVoice) != 0;
}

UIView *WXGBubbleVoiceContent(UIView *host) { return WXGVoiceOwnedView(host, "m_contentView"); }
UIView *WXGBubbleVoiceSkin(UIView *host) {
    UIView *view = WXGVoiceOwnedView(host, "m_bgImageView");
    return [view isKindOfClass:UIImageView.class] ? view : nil;
}

UIView *WXGBubbleCardBody(UIView *host) {
    WXGCardTraits traits = WXGCardTraitsForHost(host);
    if (!(traits & WXGCardSupported)) return nil;
    if (traits & WXGCardVoice) {
        UIView *content = WXGBubbleVoiceContent(host);
        if (content && !content.hidden && content.alpha > .01 && !CGRectIsEmpty(content.bounds) &&
            (WXGBubbleVoiceSkin(host) || WXGCardPrimary(content, traits, NULL))) return content;
    }
    CGFloat bestScore = 0;
    UIView *best = nil;
    for (UIView *candidate in host.subviews) {
        NSString *name = NSStringFromClass(candidate.class);
        if (candidate.hidden || candidate.alpha <= .01 || WXGIsPluginView(candidate) ||
            [candidate isKindOfClass:UIImageView.class] || [name containsString:@"MMHeadImageView"] ||
            [name containsString:@"Label"] || CGRectGetWidth(candidate.bounds) < 40 || CGRectGetHeight(candidate.bounds) < 20)
            continue;
        CGFloat score = 0;
        UIView *primary = WXGCardPrimary(candidate, traits, &score);
        if (!primary) continue;
        if (traits & WXGCardContact) {
            CGSize size = candidate.bounds.size;
            WXGCardImageFit fit = WXGCardFit(primary, candidate);
            if (size.width >= 120 && size.width <= CGRectGetWidth(host.bounds)*.88 &&
                size.height >= 45 && size.height <= CGRectGetHeight(host.bounds)+12 &&
                fit.widthCoverage >= .88 && fit.heightCoverage >= .88 &&
                size.width/size.height >= 2.4 && size.width/size.height <= 4.4) score += 20000000;
        }
        if (score > bestScore) { best = candidate; bestScore = score; }
    }
    return best;
}

NSArray<UIView *> *WXGBubbleCardBackgrounds(UIView *host, UIView *body) {
    WXGCardTraits traits = WXGCardTraitsForHost(host);
    if (!(traits & WXGCardSupported) || !body || ![body isDescendantOfView:host]) return @[];
    UIView *primary = nil;
    if ((traits & WXGCardVoice) && body == WXGBubbleVoiceContent(host)) primary = WXGBubbleVoiceSkin(host);
    if (!primary) primary = WXGCardPrimary(body, traits, NULL);
    if (!primary) return @[];
    if (!(traits & WXGCardStandby)) return @[primary];
    NSMutableArray<UIView *> *skins = [NSMutableArray arrayWithObject:primary];
    CGFloat primaryArea = CGRectGetWidth(primary.bounds) * CGRectGetHeight(primary.bounds);
    for (UIView *candidate in body.subviews) {
        if (candidate == primary) continue;
        WXGCardImageFit fit = WXGCardFit(candidate, body);
        // The standby voice skin can have a different origin or height while
        // the compact bar changes into the wider transcription body.
        BOOL compactAlternate = (traits & WXGCardVoice) && WXGBubbleAlternateVoiceSkin(fit,primaryArea,
            CGRectGetMinY(candidate.frame)-CGRectGetMinY(body.bounds),CGRectGetHeight(candidate.bounds));
        if (WXGBubbleCardStandbyFit(fit, traits & WXGCardInset, primaryArea) || compactAlternate) [skins addObject:candidate];
    }
    return skins;
}

@interface WXGCardTreatment : NSObject
@property(nonatomic,strong) CALayer *insetMask, *originalMask;
@property(nonatomic,strong) NSHashTable<UIView *> *transcriptMaterials;
@property(nonatomic,weak) WXGStateBag *voiceOwner;
@property(nonatomic) CGRect voiceFrame;
@property(nonatomic) NSUInteger lowerTextCount;
@property(nonatomic,copy) NSString *textClass,*plateClass;
@end
@implementation WXGCardTreatment
@end
static char WXGCardTreatmentKey;
// The native text plate may move between two visible rows before either row
// is reused. Transfer its original paint before the destination snapshots it.
static NSMapTable<UIView *,WXGStateBag *> *WXGVoiceMaterialOwners;

static void WXGApplyCardMask(WXGCardTreatment *treatment, UIView *body, CGFloat radius) {
    if (!treatment.insetMask) {
        treatment.insetMask = [CALayer layer];
        treatment.insetMask.backgroundColor = UIColor.blackColor.CGColor;
        treatment.insetMask.cornerCurve = kCACornerCurveContinuous;
    }
    CALayer *mask = treatment.insetMask;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (body.layer.mask != mask) {
        treatment.originalMask = body.layer.mask;
        body.layer.mask = mask;
    }
    CGRect frame = CGRectInset(body.bounds, 1.35, 1.35);
    if (!CGRectEqualToRect(frame, mask.frame)) mask.frame = frame;
    CGFloat innerRadius = MAX(0, radius - 1.35);
    if (mask.cornerRadius != innerRadius) mask.cornerRadius = innerRadius;
    [CATransaction commit];
}

static BOOL WXGVoiceText(UIView *view) {
    return [view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] ||
        [NSStringFromClass(view.class) containsString:@"RichText"];
}

static void WXGCollectVoiceMaterial(UIView *node, NSHashTable<UIView *> *materials, NSUInteger depth, NSUInteger *budget) {
    if (depth > 8 || !*budget || WXGIsPluginView(node) || WXGVoiceText(node) ||
        [node isKindOfClass:UIButton.class] || [materials containsObject:node]) return;
    --*budget;
    if ([node isKindOfClass:UIImageView.class] && !WXGCardStretchable(node)) return;
    [materials addObject:node];
    for (UIView *child in node.subviews) WXGCollectVoiceMaterial(child, materials, depth+1, budget);
}

static void WXGCollectVoiceText(UIView *node, UIView *body, UIView *host, NSHashTable<UIView *> *materials,
                                CGRect *envelope, WXGCardTreatment *state, NSUInteger depth, NSUInteger *budget) {
    if (depth>9 || !*budget || node.hidden || node.alpha<=.01 || WXGIsPluginView(node) || [node isKindOfClass:UIButton.class]) return;
    --*budget;
    if (WXGVoiceText(node)) {
        CGRect text = [node convertRect:node.bounds toView:host];
        CGFloat bodyTop = CGRectGetMinY([body convertRect:body.bounds toView:host]);
        BOOL lower=!CGRectIsEmpty(text) && text.size.width>=16 && text.size.height>=12 && CGRectGetMinY(text)>=bodyTop+22;
        if(lower){++state.lowerTextCount;state.textClass=NSStringFromClass(node.class);}
        UIView *plate = nil;
        for (UIView *parent=node.superview; parent && parent!=body && parent!=host; parent=parent.superview) {
            if ([parent isKindOfClass:UIButton.class] || WXGIsPluginView(parent)) break;
            CGRect rect = [parent convertRect:parent.bounds toView:host];
            if (WXGBubbleVoicePlate(CGRectGetMinY(rect)-bodyTop, CGRectGetWidth(rect), CGRectGetHeight(rect),
                                    CGRectGetWidth(text), CGRectGetHeight(text),
                                    parent==node.superview && parent.superview==body)) plate=parent;
        }
        if(lower && (plate || node.superview==body || ([node isDescendantOfView:body] && [NSStringFromClass(node.class) containsString:@"RichText"]))) {
            *envelope=CGRectUnion(*envelope,CGRectInset(text,-10,-10));
            [materials addObject:node]; // Clear only its background. The transcript still draws and receives taps.
        }
        if (plate) {
            state.plateClass=NSStringFromClass(plate.class);
            NSUInteger materialBudget=96;
            WXGCollectVoiceMaterial(plate, materials, 0, &materialBudget);
            if (!lower)
                *envelope = CGRectUnion(*envelope, [plate convertRect:plate.bounds toView:host]);
        }
        return;
    }
    for (UIView *child in node.subviews) WXGCollectVoiceText(child, body, host, materials, envelope, state, depth+1, budget);
}

void WXGBubbleStyleCardContents(UIView *host, UIView *body, WXGStateBag *bag, CGFloat radius, UIView *siblingText) {
    WXGCardTraits traits = WXGCardTraitsForHost(host);
    if (!(traits & WXGCardSupported) || !body || ![body isDescendantOfView:host]) return;
    // Glass is a sibling underneath; keep all native content and hit targets in place.
    if (!(traits & WXGCardVoice)) [bag clear:body];
    if (!(traits & (WXGCardInset | WXGCardVoice))) return;
    WXGCardTreatment *state = objc_getAssociatedObject(body, &WXGCardTreatmentKey);
    if (!state) {
        state = [WXGCardTreatment new];
        objc_setAssociatedObject(body, &WXGCardTreatmentKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (traits & WXGCardInset) WXGApplyCardMask(state, body, radius);
    if (traits & WXGCardVoice) {
        if (state.voiceOwner != bag) {
            [state.voiceOwner restoreView:body];
            state.voiceOwner=bag;
        }
        [bag guardFill:body];
        CGRect envelope = [body convertRect:body.bounds toView:host];
        NSUInteger budget=128;
        NSHashTable<UIView *> *materials = [NSHashTable weakObjectsHashTable];
        state.lowerTextCount=0;state.plateClass=nil;state.textClass=nil;
        WXGCollectVoiceText(host, body, host, materials, &envelope, state, 0, &budget);
        if(siblingText) {
            // The owner has resolved this renderer to the same physical row.
            // Touch only its immediate lower plate, never the cell container.
            UIView *plate=siblingText.superview;
            CGRect text=[siblingText convertRect:siblingText.bounds toView:host];
            CGRect rect=[plate convertRect:plate.bounds toView:host];
            CGFloat top=CGRectGetMinY([body convertRect:body.bounds toView:host]);
            if(WXGBubbleVoicePlate(CGRectGetMinY(rect)-top,rect.size.width,rect.size.height,text.size.width,text.size.height,NO)) {
                NSUInteger remaining=96;
                WXGCollectVoiceMaterial(plate,materials,0,&remaining);
                [materials addObject:siblingText];++state.lowerTextCount;
                state.plateClass=NSStringFromClass(plate.class);state.textClass=NSStringFromClass(siblingText.class);
                envelope=CGRectUnion(envelope,CGRectInset(text,-10,-10));
            }
        }
        for (UIView *old in state.transcriptMaterials) {
            if ([materials containsObject:old] || [WXGVoiceMaterialOwners objectForKey:old] != bag) continue;
            [bag restoreView:old];
            [WXGVoiceMaterialOwners removeObjectForKey:old];
        }
        if (materials.count && !WXGVoiceMaterialOwners) WXGVoiceMaterialOwners = [NSMapTable weakToWeakObjectsMapTable];
        for (UIView *material in materials) {
            WXGStateBag *previous = [WXGVoiceMaterialOwners objectForKey:material];
            if (previous != bag) {
                [previous restoreView:material];
                [WXGVoiceMaterialOwners setObject:bag forKey:material];
            }
            if ([material isKindOfClass:UIVisualEffectView.class]) [bag clearEffect:(UIVisualEffectView *)material];
            if (WXGVoiceText(material)) [bag guardFill:material];
            else if ([material isKindOfClass:UIImageView.class] && material.subviews.count) [bag clearImagePaint:(UIImageView *)material];
            else if ([material isKindOfClass:UIImageView.class]) [bag conceal:material];
            else [bag guardFill:material];
        }
        state.transcriptMaterials = materials;
        state.voiceFrame = envelope;
    }
}

NSDictionary *WXGBubbleVoiceEvidence(UIView *host, UIView *body) {
    WXGCardTreatment *state=body?objc_getAssociatedObject(body,&WXGCardTreatmentKey):nil;
    UIView *nativeBody=WXGBubbleVoiceContent(host),*skin=WXGBubbleVoiceSkin(host);
    return @{@"nativeBody":nativeBody?NSStringFromClass(nativeBody.class):@"",
        @"nativeSkin":skin?NSStringFromClass(skin.class):@"", @"bodyFrame":NSStringFromCGRect(body.frame),
        @"skinFrame":NSStringFromCGRect(skin.frame),@"lowerTextCount":@(state.lowerTextCount),
        @"textClass":state.textClass?:@"",@"plateClass":state.plateClass?:@"",
        @"materialCount":@(state.transcriptMaterials.count),@"envelope":NSStringFromCGRect(state.voiceFrame)};
}

CGRect WXGBubbleCardGlassFrame(UIView *host, UIView *body) {
    WXGCardTreatment *state = objc_getAssociatedObject(body, &WXGCardTreatmentKey);
    if ((WXGCardTraitsForHost(host) & WXGCardVoice) && state && !CGRectIsEmpty(state.voiceFrame))
        return state.voiceFrame;
    return [body convertRect:body.bounds toView:host];
}

void WXGBubbleRestoreCardContents(UIView *body, WXGStateBag *bag) {
    WXGCardTreatment *state = objc_getAssociatedObject(body, &WXGCardTreatmentKey);
    if (!state || (state.voiceOwner && state.voiceOwner != bag)) return;
    for (UIView *material in state.transcriptMaterials)
        if ([WXGVoiceMaterialOwners objectForKey:material] == bag) [WXGVoiceMaterialOwners removeObjectForKey:material];
    if (state.insetMask && body.layer.mask == state.insetMask) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        body.layer.mask = state.originalMask;
        [CATransaction commit];
    }
    objc_setAssociatedObject(body, &WXGCardTreatmentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
