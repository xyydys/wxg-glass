#import <UIKit/UIKit.h>

// Visible native quote preview, including its two-point margin, in root coordinates.
// A missing or unlaid-out preview returns CGRectNull.
FOUNDATION_EXPORT CGRect WXGBubbleQuotedEnvelope(UIView *root, UIView *body);

// Return the shared cell content view only for a sibling preview outside root.
// Inline or missing previews return nil.
FOUNDATION_EXPORT UIView *WXGBubbleQuotedContainer(UIView *root);

// The native preview found by the latest envelope measurement and its divider
// in message-root coordinates. NAN means the two sections have no clear gap.
FOUNDATION_EXPORT UIView *WXGBubbleQuotePreview(UIView *root);
FOUNDATION_EXPORT CGFloat WXGBubbleQuoteBoundary(UIView *root, UIView *mainRich, CGRect paddedEnvelope);
FOUNDATION_EXPORT void WXGBubbleInvalidateQuoteLookup(UIView *root);
