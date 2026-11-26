#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Settled menu artwork and corresponding row geometry in menu-local points.
@interface WXGMenuMorphContent : NSObject
@property(nonatomic,readonly) CGSize size;
@property(nonatomic,readonly) CGFloat panelCornerRadius;
@property(nonatomic,copy,readonly) NSArray<NSString *> *titles;
@property(nonatomic,copy,readonly) NSArray<NSValue *> *rowFrames;
@property(nonatomic,strong,readonly) UIImage *image;
@property(nonatomic,strong,readonly) UIColor *highlightColor;

// Arrays retain the native action order. Use NSNull for missing native icons.
// Divider and submenu indices are zero-based and do not add action rows.
+ (nullable instancetype)contentWithTitles:(NSArray<NSString *> *)titles
                              nativeIcons:(NSArray *)nativeIcons
                             submenuRows:(nullable NSIndexSet *)submenuRows
                        dividerBeforeRows:(nullable NSIndexSet *)dividerBeforeRows
                               panelWidth:(CGFloat)panelWidth
                          traitCollection:(UITraitCollection *)traits
                                    scale:(CGFloat)scale;
@end

NS_ASSUME_NONNULL_END
