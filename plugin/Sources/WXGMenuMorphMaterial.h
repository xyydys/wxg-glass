#import <UIKit/UIKit.h>
#include "WXGMenuMorphField.h"

@interface WXGMenuMorphMaterial : UIView
@property(nonatomic,strong,readonly) UIView *rimView;
@property(nonatomic) CGFloat opticalSessionStep;
- (BOOL)needsRimBackdropImage;
- (void)setRimBackdropImage:(UIImage *)image inRect:(CGRect)rect;
- (void)applyField:(const WXGMenuMorphField *)field bounds:(CGRect)bounds outline:(UIBezierPath *)outline;
- (NSDictionary *)rimEvidence;
@end

// The navigation button lends this exact view, including its live backdrop
// and rim layers, to the window portal for the duration of an interaction.
@interface WXGMenuMorphSurface : UIView
@property(nonatomic,strong,readonly) UIView *inkHost;
- (void)setOpticalSessionStep:(CGFloat)step;
@property(nonatomic,strong,readonly) UIBezierPath *currentOutline;
- (void)placeButtonRect:(CGRect)button;
- (void)placeMenuRect:(CGRect)menu radiusX:(CGFloat)rx radiusY:(CGFloat)ry
           sourceRect:(CGRect)source radius:(CGFloat)radius smoothing:(CGFloat)smoothing;
- (BOOL)needsRimBackdropImage;
- (void)setRimBackdropImage:(UIImage *)image inRect:(CGRect)rect;
- (NSDictionary *)presentationEvidence;
@end
