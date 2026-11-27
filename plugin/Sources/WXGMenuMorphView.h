#import <UIKit/UIKit.h>
#include "WXGMenuMorph.h"

@class WXGSurface;

FOUNDATION_EXPORT void WXGPrewarmMenuMorphRenderer(void);

// A live Other-scope glass draws the menu body. A separate foreground layer
// distorts the trigger, row labels, icons and selection during the morph.
@interface WXGMenuMorphView : UIView
@property(nonatomic,copy) void (^requestFrame)(void);
@property(nonatomic,strong) UIView *fallbackForeground;
@property(nonatomic,copy,readonly) NSDictionary *sourceAtPickup;
@property(nonatomic,strong,readonly) UIBezierPath *currentOutline;
- (void)useSurfaceFromButton:(WXGSurface *)button;
- (void)setOpticalSessionBounds:(CGRect)windowBounds;
- (void)setSessionTriggerSide:(CGFloat)triggerSide menuSide:(CGFloat)menuSide;
- (NSDictionary *)returnSurfaceToButton;
- (NSDictionary *)presentationEvidence;
- (BOOL)captureBackdropFromView:(UIView *)source excludingViews:(NSArray<UIView *> *)excluded;
- (void)setForegroundRowsImage:(UIImage *)rowsImage triggerImage:(UIImage *)triggerImage;
- (void)setHighlightedRowRect:(CGRect)rect opacity:(CGFloat)opacity;
// Both values belong to the same interaction sample as the next morph frame.
- (void)stageHighlightedRowRect:(CGRect)rect opacity:(CGFloat)opacity;
- (void)stageMenuLightAtPoint:(CGPoint)point inParent:(UIView *)parent artworkX:(CGFloat)artworkX strength:(CGFloat)strength;
// YES while the current accepted drawable contains foreground artwork.
- (BOOL)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent settledOpen:(BOOL)settled showsForeground:(BOOL)showsForeground;
- (void)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent;
@end
