#import "WXGBannerLibrary.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

NSNotificationName const WXGBannerLibraryDidChangeNotification = @"WXGBannerLibraryDidChange";

static NSError *WXGBannerError(NSString *message) {
    return [NSError errorWithDomain:@"WXGBannerLibrary" code:1
                           userInfo:@{NSLocalizedDescriptionKey:message}];
}

static BOOL WXGBannerMissing(NSError *error) {
    return [error.domain isEqualToString:NSCocoaErrorDomain] &&
           (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError);
}

static BOOL WXGBannerSafeExtension(NSString *extension) {
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:
                    @"abcdefghijklmnopqrstuvwxyz0123456789"] invertedSet];
    });
    return [extension isKindOfClass:NSString.class] && extension.length && extension.length <= 12 &&
           [extension rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

@interface WXGBannerItem ()
@property(nonatomic, copy, readwrite) NSString *identifier, *displayName, *fileExtension;
@property(nonatomic, strong, readwrite) NSURL *fileURL, *thumbnailURL;
@property(nonatomic, readwrite) BOOL isVideo;
@end

@implementation WXGBannerItem
- (NSDictionary *)record {
    return @{@"id":self.identifier, @"name":self.displayName, @"ext":self.fileExtension,
             @"video":@(self.isVideo), @"preview":@(self.thumbnailURL != nil)};
}
@end

@interface WXGBannerSnapshot : NSObject
@property(nonatomic, copy) NSArray<WXGBannerItem *> *items;
@property(nonatomic, strong) WXGBannerItem *selected;
@end
@implementation WXGBannerSnapshot
@end

static BOOL WXGBannerJPEG(CGImageRef image, NSURL *url) {
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (!dest) return NO;
    NSDictionary *options = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@.84};
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)options);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    if (!ok) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    return ok;
}

// The original file is kept for playback or full-size display. Only the
// preview is decoded during import, including EXIF / track orientation.
static BOOL WXGBannerPreparePreview(NSURL *file, NSURL *thumbnail, BOOL video, BOOL *hasPreview, NSError **error) {
    CGImageRef image = NULL;
    if (video) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
        if (![asset tracksWithMediaType:AVMediaTypeVideo].count) {
            if (error) *error = WXGBannerError(@"此文件没有可读取的视频轨道。");
            return NO;
        }
        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.maximumSize = CGSizeMake(360,360);
        generator.appliesPreferredTrackTransform = YES;
        image = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    } else {
        NSDictionary *read = @{(__bridge NSString *)kCGImageSourceShouldCache:@NO};
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)file, (__bridge CFDictionaryRef)read);
        if (source) {
            NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                      (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                      (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@360};
            if (CGImageSourceGetCount(source))
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            CFRelease(source);
        }
        if (!image) {
            if (error) *error = WXGBannerError(@"此图片无法解码。");
            return NO;
        }
    }
    *hasPreview = image && WXGBannerJPEG(image, thumbnail);
    if (image) CGImageRelease(image);
    return YES;
}

@interface WXGBannerLibrary ()
@property(atomic, strong) WXGBannerSnapshot *snapshot;
@end

@implementation WXGBannerLibrary {
    dispatch_queue_t _queue;
    NSURL *_assets, *_incoming, *_index, *_legacy;
    BOOL _loaded;
}

+ (instancetype)shared {
    static WXGBannerLibrary *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        library = [[self alloc] initWithSupport:[support URLByAppendingPathComponent:@"WeChatLiquidGlass" isDirectory:YES]];
        [library loadWithCompletion:^(__unused NSError *error) {}];
    });
    return library;
}

- (instancetype)initWithSupport:(NSURL *)support {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.runyu.wxg.banner-index", DISPATCH_QUEUE_SERIAL);
        NSURL *root = [support URLByAppendingPathComponent:@"BannerLibrary" isDirectory:YES];
        _assets = [root URLByAppendingPathComponent:@"Assets" isDirectory:YES];
        _incoming = [root URLByAppendingPathComponent:@"Incoming" isDirectory:YES];
        _index = [root URLByAppendingPathComponent:@"index.plist"];
        _legacy = [support URLByAppendingPathComponent:@"meBanner.mov"];
        _snapshot = [WXGBannerSnapshot new];
        _snapshot.items = @[];
    }
    return self;
}

- (NSArray<WXGBannerItem *> *)items { return self.snapshot.items; }
- (WXGBannerItem *)selectedItem { return self.snapshot.selected; }

- (void)publishItems:(NSArray<WXGBannerItem *> *)items selected:(WXGBannerItem *)selected {
    WXGBannerSnapshot *snapshot = [WXGBannerSnapshot new];
    snapshot.items = items;
    snapshot.selected = selected;
    self.snapshot = snapshot;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:WXGBannerLibraryDidChangeNotification object:self];
    });
}

- (WXGBannerItem *)itemWithID:(NSString *)identifier name:(NSString *)name extension:(NSString *)extension
                        video:(BOOL)video preview:(BOOL)preview {
    NSURL *folder = [_assets URLByAppendingPathComponent:identifier isDirectory:YES];
    WXGBannerItem *item = [WXGBannerItem new];
    item.identifier = identifier;
    item.displayName = name;
    item.fileExtension = extension;
    item.isVideo = video;
    item.fileURL = [folder URLByAppendingPathComponent:[@"original" stringByAppendingPathExtension:extension]];
    if (preview) item.thumbnailURL = [folder URLByAppendingPathComponent:@"preview.jpg"];
    return item;
}

- (BOOL)saveItems:(NSArray<WXGBannerItem *> *)items selected:(WXGBannerItem *)selected error:(NSError **)error {
    NSMutableArray *records = [NSMutableArray arrayWithCapacity:items.count];
    for (WXGBannerItem *item in items) [records addObject:item.record];
    NSDictionary *index = @{@"version":@1, @"items":records, @"selected":selected.identifier ?: @""};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:index format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToURL:_index options:NSDataWritingAtomic error:error]) return NO;
    [self publishItems:items selected:selected];
    return YES;
}

// Only files created by this library use UUID directory names. A committed
// index is authoritative after a crash between publishing and deleting a file.
static void WXGBannerClean(NSURL *root, NSSet<NSString *> *keep) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSURL *url in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil]) {
        NSString *name = url.lastPathComponent;
        if ([[NSUUID alloc] initWithUUIDString:name] && ![keep containsObject:name]) [fm removeItemAtURL:url error:nil];
    }
}

- (BOOL)loadLocked:(NSError **)error {
    if (_loaded) return YES;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSURL *dir in @[_assets,_incoming])
        if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:_index options:0 error:&readError];
    if (!data && !WXGBannerMissing(readError)) { if (error) *error = readError; return NO; }

    if (!data) {
        NSError *legacyError = nil;
        NSDictionary *attributes = [fm attributesOfItemAtPath:_legacy.path error:&legacyError];
        if (!attributes && !WXGBannerMissing(legacyError)) { if (error) *error = legacyError; return NO; }
        if (attributes && [attributes[NSFileType] isEqual:NSFileTypeRegular]) {
            // Link on the same volume; the old selection remains recoverable
            // until the new index has been atomically published.
            WXGBannerItem *item = [self itemWithID:NSUUID.UUID.UUIDString name:@"原横幅视频" extension:@"mov" video:YES preview:NO];
            NSURL *folder = item.fileURL.URLByDeletingLastPathComponent;
            if (![fm createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:error]) return NO;
            BOOL copied = [fm linkItemAtURL:_legacy toURL:item.fileURL error:nil] ||
                          [fm copyItemAtURL:_legacy toURL:item.fileURL error:error];
            if (copied) {
                NSURL *preview = [folder URLByAppendingPathComponent:@"preview.jpg"];
                BOOL hasPreview = NO;
                WXGBannerPreparePreview(item.fileURL, preview, YES, &hasPreview, NULL);
                if (hasPreview) item.thumbnailURL = preview;
            }
            if (!copied || ![self saveItems:@[item] selected:item error:error]) {
                [fm removeItemAtURL:folder error:nil];
                return NO;
            }
            [fm removeItemAtURL:_legacy error:nil];
        } else if (![self saveItems:@[] selected:nil error:error]) return NO;
    } else {
        id index = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
        if (!index) return NO;
        if (![index isKindOfClass:NSDictionary.class] || ![index[@"version"] isEqual:@1] ||
            ![index[@"items"] isKindOfClass:NSArray.class] || ![index[@"selected"] isKindOfClass:NSString.class]) {
            if (error) *error = WXGBannerError(@"无法读取此版本的横幅媒体库。");
            return NO;
        }
        NSMutableArray *items = [NSMutableArray array];
        NSMutableSet *identifiers = [NSMutableSet set];
        WXGBannerItem *selected = nil;
        for (id row in index[@"items"]) {
            if (![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] ||
                ![[NSUUID alloc] initWithUUIDString:row[@"id"]] || [identifiers containsObject:row[@"id"]] ||
                !WXGBannerSafeExtension(row[@"ext"]) || ![row[@"name"] isKindOfClass:NSString.class] ||
                ![row[@"video"] isKindOfClass:NSNumber.class] || ![row[@"preview"] isKindOfClass:NSNumber.class]) {
                if (error) *error = WXGBannerError(@"横幅媒体库记录损坏，无法载入。");
                return NO;
            }
            [identifiers addObject:row[@"id"]];
            WXGBannerItem *item = [self itemWithID:row[@"id"] name:row[@"name"] extension:row[@"ext"]
                                              video:[row[@"video"] boolValue] preview:[row[@"preview"] boolValue]];
            NSNumber *regular = nil; NSError *fileError = nil;
            if (![item.fileURL getResourceValue:&regular forKey:NSURLIsRegularFileKey error:&fileError]) {
                if (WXGBannerMissing(fileError)) continue;
                if (error) *error = fileError;
                return NO;
            }
            if (!regular.boolValue) continue;
            if (item.thumbnailURL && ![fm fileExistsAtPath:item.thumbnailURL.path]) item.thumbnailURL = nil;
            [items addObject:item];
            if ([item.identifier isEqual:index[@"selected"]]) selected = item;
        }
        [self publishItems:items selected:selected];
        WXGBannerClean(_assets,identifiers);
    }
    WXGBannerClean(_incoming,[NSSet set]);
    _loaded = YES;
    return YES;
}

- (void)loadWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(_queue, ^{
        NSError *error = nil;
        [self loadLocked:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

- (WXGBannerItem *)importFileURL:(NSURL *)url displayName:(NSString *)name isVideo:(BOOL)isVideo error:(NSError **)error {
    __block NSError *failure = nil;
    dispatch_sync(_queue, ^{ [self loadLocked:&failure]; });
    if (failure) { if (error) *error = failure; return nil; }
    if (!url.isFileURL) { if (error) *error = WXGBannerError(@"无法访问所选文件。"); return nil; }
    // File providers can hand us a temporary link. Copy the regular file
    // it names, so a persisted selection survives provider cleanup.
    NSURL *source = url.URLByResolvingSymlinksInPath;
    NSNumber *regular = nil;
    if (![source getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error]) return nil;
    if (!regular.boolValue) { if (error) *error = WXGBannerError(@"所选项目不是媒体文件。"); return nil; }
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSString *extension = url.pathExtension.lowercaseString;
    if (!WXGBannerSafeExtension(extension)) extension = isVideo ? @"mov" : @"img";
    NSString *displayName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!displayName.length) displayName = isVideo ? @"视频" : @"图片";
    NSURL *staging = [_incoming URLByAppendingPathComponent:identifier isDirectory:YES];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:staging withIntermediateDirectories:NO attributes:nil error:error]) return nil;
    NSURL *original = [staging URLByAppendingPathComponent:[@"original" stringByAppendingPathExtension:extension]];
    NSURL *thumbnail = [staging URLByAppendingPathComponent:@"preview.jpg"];
    BOOL hasPreview = NO;
    if (![fm copyItemAtURL:source toURL:original error:error] ||
        !WXGBannerPreparePreview(original,thumbnail,isVideo,&hasPreview,error)) {
        [fm removeItemAtURL:staging error:nil];
        return nil;
    }
    WXGBannerItem *item = [self itemWithID:identifier name:displayName extension:extension video:isVideo preview:hasPreview];
    __block BOOL committed = NO;
    dispatch_sync(_queue, ^{
        NSURL *destination = item.fileURL.URLByDeletingLastPathComponent;
        if (![fm moveItemAtURL:staging toURL:destination error:&failure]) return;
        WXGBannerSnapshot *current = self.snapshot;
        NSArray *items = [@[item] arrayByAddingObjectsFromArray:current.items];
        committed = [self saveItems:items selected:current.selected error:&failure];
        if (!committed) [fm removeItemAtURL:destination error:nil];
    });
    if (!committed) {
        [fm removeItemAtURL:staging error:nil];
        if (error) *error = failure;
    }
    return committed ? item : nil;
}

- (BOOL)selectIdentifier:(NSString *)identifier error:(NSError **)error {
    __block NSError *failure = nil;
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        if (![self loadLocked:&failure]) return;
        WXGBannerSnapshot *current = self.snapshot;
        WXGBannerItem *selected = nil;
        if (identifier) {
            for (WXGBannerItem *item in current.items)
                if ([item.identifier isEqualToString:identifier]) { selected = item; break; }
            if (!selected) { failure = WXGBannerError(@"所选横幅已从媒体库移除。"); return; }
        }
        success = selected == current.selected || [self saveItems:current.items selected:selected error:&failure];
    });
    if (!success && error) *error = failure;
    return success;
}

- (BOOL)removeIdentifier:(NSString *)identifier error:(NSError **)error {
    __block NSError *failure = nil;
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        if (![self loadLocked:&failure]) return;
        WXGBannerSnapshot *current = self.snapshot;
        WXGBannerItem *target = nil;
        for (WXGBannerItem *item in current.items)
            if ([item.identifier isEqualToString:identifier]) { target = item; break; }
        if (!target) { success = YES; return; }
        NSMutableArray *items = [current.items mutableCopy];
        [items removeObjectIdenticalTo:target];
        success = [self saveItems:items selected:target == current.selected ? nil : current.selected error:&failure];
        if (success) [NSFileManager.defaultManager removeItemAtURL:target.fileURL.URLByDeletingLastPathComponent error:nil];
    });
    if (!success && error) *error = failure;
    return success;
}
@end
