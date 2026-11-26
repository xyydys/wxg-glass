#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const WXGBannerLibraryDidChangeNotification;

@interface WXGBannerItem : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, strong, readonly) NSURL *fileURL;
@property(nonatomic, strong, readonly, nullable) NSURL *thumbnailURL;
@property(nonatomic, readonly) BOOL isVideo;
@end

@interface WXGBannerLibrary : NSObject
@property(class, nonatomic, readonly) WXGBannerLibrary *shared;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
// Both getters read a published immutable snapshot. They never access storage.
@property(nonatomic, readonly) NSArray<WXGBannerItem *> *items;
@property(nonatomic, readonly, nullable) WXGBannerItem *selectedItem;
- (void)loadWithCompletion:(void (^)(NSError *_Nullable error))completion;
// Synchronous: call on a worker from the item provider's file callback.
- (nullable WXGBannerItem *)importFileURL:(NSURL *)url displayName:(nullable NSString *)name
                                 isVideo:(BOOL)isVideo error:(NSError * _Nullable * _Nullable)error;
- (BOOL)selectIdentifier:(nullable NSString *)identifier error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeIdentifier:(NSString *)identifier error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
