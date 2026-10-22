// FIX58: the glass settings pages (WXGSettings.m: store, glass cards, page
// frame and home; WXGOpticalSettings.m: the module pages and their rows).
#import "WXGIntegration.h"

FOUNDATION_EXPORT NSString * const WXGSettingsUIChanged;

/* Settings-page look: accent colour, card corner radius, wallpapers, avatar. */
@interface WXGSettingsStore : NSObject
+ (instancetype)shared;
@property(nonatomic,copy) NSString *accentHex;        // nil: follow the system text colour
@property(nonatomic) CGFloat cardRadius;              // continuous corners, 0..40 pt
- (UIColor *)accentColor;                             // labelColor when no accent is set
- (UIColor *)secondaryColor;
- (UIColor *)controlTint;                             // nil: system default control colours
- (UIImage *)wallpaperForDark:(BOOL)dark;             // the imported one, nil if none
- (void)setWallpaper:(UIImage *)image dark:(BOOL)dark;   // nil removes it
- (UIImage *)avatar;
- (void)setAvatar:(UIImage *)image;
- (void)save;                                         // stores and posts WXGSettingsUIChanged
@end

/* A glass card: WXGGlassView with the other-glass parameters as background,
   continuous corners, content on top. Pressable cards bulge like the glass
   buttons and run `action`; others only host interactive content. */
@interface WXGSettingsCard : UIControl
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic,strong,readonly) UIView *contentView;
@property(nonatomic) BOOL pressable;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) BOOL capsule;   // FIX114 E: round ends whatever the page's corner radius
@property(nonatomic,copy) void (^action)(void);
- (void)tick:(CFTimeInterval)time force:(BOOL)force;
@end

/* One settings page: wallpaper, top bar (back / title capsule / optional
   accent button, at the glass navigation buttons' size and place) and a
   scrolling content view. Subclasses build into `content` and lay it out. */
@interface WXGSettingsPage : UIViewController
@property(nonatomic,copy) NSString *pageTitle;
@property(nonatomic) BOOL showsAccentButton;
@property(nonatomic,strong,readonly) UIScrollView *scrollView;
@property(nonatomic,strong,readonly) UIImageView *wallpaperView;   // FIX65: the page's wallpaper (edge fade copies it)
@property(nonatomic,strong,readonly) UIView *content;
@property(nonatomic,readonly) CGFloat contentTop;     // below the top bar
@property(nonatomic,readonly) CGFloat sideMargin;     // the navigation buttons' edge distance
- (void)buildContent;                                 // subclass: create views (once)
- (CGFloat)layoutContentForWidth:(CGFloat)width;      // subclass: frames in `content`, returns height
- (void)applyLook;                                    // accent / radius / wallpaper changed
- (WXGSettingsCard *)addCard:(BOOL)pressable;         // a card in `content`, ticked by the page
- (UILabel *)sectionLabel:(NSString *)text;
- (void)pickColorTitled:(NSString *)title current:(UIColor *)current alpha:(BOOL)alpha
                 change:(void (^)(UIColor *color,BOOL finished))change;
- (void)pickImage:(void (^)(UIImage *image))done;
- (void)showMessage:(NSString *)title detail:(NSString *)detail;
- (void)rebuildContent;                               // content built again (e.g. after the license changed)
@end

FOUNDATION_EXPORT UIViewController *WXGSettingsModulePage(NSString *module);
FOUNDATION_EXPORT UIViewController *WXGChatGroupsPage(void);   // FIX113 R: 分组 › 管理分组 (WXGChatGroups.m)
// FIX113 O: the settings search. A module page opened at a group (spec index)
// and row (-1: the group); results of a query over the home cards (module,
// title, subtitle, ...): module, group, row, title, path.
FOUNDATION_EXPORT UIViewController *WXGSettingsModulePageFocused(NSString *module,NSInteger group,NSInteger row);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WXGSettingsSearch(NSString *query,NSArray<NSArray *> *cards);
FOUNDATION_EXPORT UIViewController *WXGSettingsDiagnosticsPage(void);
FOUNDATION_EXPORT NSString *WXGHexFromColor(UIColor *color);
