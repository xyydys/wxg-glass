#import <UIKit/UIKit.h>

@protocol WXGListGroupControl <NSObject>
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) BOOL active;
@property(nonatomic,copy) NSArray<NSString *> *titles;
- (void)returnToIndex:(NSInteger)index;
- (void)refreshLook;
- (CGFloat)currentLensX;
- (NSDictionary *)evidence;
@end

@interface WXGHomeCategoryBar : UIControl <WXGListGroupControl>
@property(nonatomic,readonly) NSInteger tappedIndex;
@property(nonatomic,copy) NSArray<NSNumber *> *unreadCounts; // -1 is a muted dot
@property(nonatomic,copy) NSString *deviceTitle;
- (void)showFrom:(NSInteger)source to:(NSInteger)destination progress:(CGFloat)fraction;
@end

@protocol WXGHomePagerDelegate <NSObject>
- (BOOL)canPageHome;
- (NSInteger)homePageIndex;
- (NSInteger)homePageCount;
- (void)rememberHomeCategory;
- (BOOL)showHomePage:(NSInteger)index;
- (CGRect)homeMessageViewportIn:(UIView *)parent;
- (void)previewHomePageFrom:(NSInteger)from to:(NSInteger)to fraction:(CGFloat)fraction;
@end

@interface WXGHomeGroupPager : NSObject
@property(nonatomic,weak,readonly) UITableView *table;
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic) BOOL paging;
- (instancetype)initWithTable:(UITableView *)table delegate:(id<WXGHomePagerDelegate>)delegate;
- (void)selectPage:(NSInteger)index;
- (void)invalidate;
- (void)checkGestureOnHome:(BOOL)visible;
- (void)cancel;
@end
