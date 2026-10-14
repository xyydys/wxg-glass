#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

@class WXGGlassView;

// A published region is immutable while leased by a consumer or a GPU command.
// The sampler reuses at most three buffers per region; it never waits for GPU work.
@interface WXGBackdropSample : NSObject
@property(nonatomic,strong,readonly) id<MTLTexture> texture;
@property(nonatomic,weak,readonly) UIView *coordinateView;
@property(nonatomic,readonly) CGRect rect;
@property(nonatomic,readonly) NSUInteger revision;
@property(nonatomic,readonly) CFTimeInterval capturedAt;
@property(nonatomic,readonly) CGFloat toneLevel;
- (void)acquireLease;
- (void)releaseLease;
@end
FOUNDATION_EXPORT id<MTLDevice> WXGSharedDevice(void);
/* FIX21: thread-safe icon atlas upload (any queue). */
FOUNDATION_EXPORT id<MTLTexture> WXGMakeIconTexture(UIImage *image);
FOUNDATION_EXPORT WXGBackdropSample *WXGBackdropForGlass(WXGGlassView *glass,CGRect *sourceRect,NSUInteger *revision);
// Mapping is fixed before the scene read and is returned only for covered pixels.
FOUNDATION_EXPORT WXGBackdropSample *WXGBackdropForGlassCopy(WXGGlassView *glass,CGAffineTransform *transform,CGFloat *scale,CGRect *canvasRect);
FOUNDATION_EXPORT CGAffineTransform WXGPresentedTransform(UIView *view,UIView *source);
FOUNDATION_EXPORT BOOL WXGPresentedVisible(UIView *view);
FOUNDATION_EXPORT CGRect WXGPresentedBounds(UIView *view,UIView *source);
