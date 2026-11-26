#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// One owner per message entry. Only the paint inside its native quote is changed.
@interface WXGBubbleQuoteBackground : NSObject
- (void)updatePreview:(nullable UIView *)preview;
- (void)reapply;
- (void)restore;
@end

NS_ASSUME_NONNULL_END
