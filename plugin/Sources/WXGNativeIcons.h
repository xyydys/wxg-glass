#import <UIKit/UIKit.h>

@interface WXGNativeIconPair : NSObject <NSCopying>
@property(nonatomic,strong) UIImage *normalImage, *selectedImage;
@property(nonatomic,strong) UIColor *normalTint, *selectedTint;
@property(nonatomic,strong) UIColor *normalTextColor, *selectedTextColor;
@property(nonatomic,strong) UITraitCollection *traits;
@property(nonatomic,copy) NSString *title, *normalSource, *selectedSource;
@property(nonatomic) BOOL normalTemplate, selectedTemplate;
@property(nonatomic) CGFloat normalRank, selectedRank;
@end

// Reads the existing native bar only. Never changes its selected state, sends
// control actions, moves views, or snapshots an icon together with a badge.
@interface WXGNativeIcons : NSObject
@property(nonatomic,readonly) NSArray<WXGNativeIconPair *> *items;
@property(nonatomic,readonly) NSString *diagnostics;
- (void)invalidateAppearance;
// FIX21: the next update rescans even within the 0.8 s sampling interval.
- (void)expireSampling;
- (BOOL)updateFromTabController:(UITabBarController *)tabs;
@end
