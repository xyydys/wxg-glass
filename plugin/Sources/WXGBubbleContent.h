#import <UIKit/UIKit.h>

@class WXGStateBag;

typedef NS_ENUM(NSUInteger, WXGBubbleKind) {
    WXGBubbleUnsupported,
    WXGBubbleText,
    WXGBubbleNonText,
};

FOUNDATION_EXPORT NSArray<NSString *> *WXGBubbleCardClassNames(void);
FOUNDATION_EXPORT WXGBubbleKind WXGBubbleKindForHost(UIView *host);
FOUNDATION_EXPORT BOOL WXGBubbleIsVoiceHost(UIView *host);
FOUNDATION_EXPORT UIView *WXGBubbleVoiceContent(UIView *host);
FOUNDATION_EXPORT UIView *WXGBubbleVoiceSkin(UIView *host);
FOUNDATION_EXPORT UIView *WXGBubbleCardBody(UIView *host);
FOUNDATION_EXPORT NSArray<UIView *> *WXGBubbleCardBackgrounds(UIView *host, UIView *body);
FOUNDATION_EXPORT void WXGBubbleStyleCardContents(UIView *host, UIView *body, WXGStateBag *bag, CGFloat radius);
// In host coordinates. Place the glass just below the body, outside its content mask.
FOUNDATION_EXPORT NSDictionary *WXGBubbleVoiceEvidence(UIView *host, UIView *body);
FOUNDATION_EXPORT CGRect WXGBubbleCardGlassFrame(UIView *host, UIView *body);
FOUNDATION_EXPORT void WXGBubbleRestoreCardContents(UIView *body, WXGStateBag *bag);
