// iOS host integration fixture: pass a readable still image and a short video.
// Uses a disposable support directory, never the app's active media library.
#import "../Sources/WXGBannerLibrary.h"
#import <Foundation/Foundation.h>
#import <assert.h>

@interface WXGBannerLibrary (Fixture)
- (instancetype)initWithSupport:(NSURL *)support;
@end

static WXGBannerItem *add(WXGBannerLibrary *store, NSURL *file, NSString *name, BOOL video) {
    NSError *error = nil;
    WXGBannerItem *item = [store importFileURL:file displayName:name isVideo:video error:&error];
    assert(item && !error);
    return item;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr,"usage: BannerLibraryTests image video\n"); return 2; }
        NSURL *image = [NSURL fileURLWithPath:@(argv[1])];
        NSURL *movie = [NSURL fileURLWithPath:@(argv[2])];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *root = [fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        assert([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *legacy = [root URLByAppendingPathComponent:@"meBanner.mov"];
        assert([fm copyItemAtURL:movie toURL:legacy error:nil]);

        WXGBannerLibrary *store = [[WXGBannerLibrary alloc] initWithSupport:root];
        WXGBannerItem *still = add(store,image,@"测试图片",NO);
        assert(store.items.count == 2 && store.selectedItem.isVideo);
        assert(still.thumbnailURL && [fm fileExistsAtPath:still.thumbnailURL.path]);
        assert(![fm fileExistsAtPath:legacy.path]);
        assert([fm contentsEqualAtPath:store.selectedItem.fileURL.path andPath:movie.path]);
        NSURL *alias = [root URLByAppendingPathComponent:@"temporary-image.jpg"];
        assert([fm createSymbolicLinkAtURL:alias withDestinationURL:image error:nil]);
        WXGBannerItem *fromLink = add(store,alias,@"provider link",NO);
        assert([fm removeItemAtURL:alias error:nil]);
        assert([fm contentsEqualAtPath:fromLink.fileURL.path andPath:image.path]);
        WXGBannerItem *video = add(store,movie,@"视频",YES);
        assert([store selectIdentifier:still.identifier error:nil]);
        assert([store removeIdentifier:video.identifier error:nil]);
        assert([store.selectedItem.identifier isEqual:still.identifier]);
        assert(![fm fileExistsAtPath:video.fileURL.path]);

        NSArray *before = store.items;
        NSURL *garbage = [root URLByAppendingPathComponent:@"bad.jpg"];
        assert([@"invalid" writeToURL:garbage atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        assert(![store importFileURL:garbage displayName:@"bad" isVideo:NO error:nil]);
        assert(![store importFileURL:garbage displayName:@"bad" isVideo:YES error:nil]);
        assert(![store selectIdentifier:NSUUID.UUID.UUIDString error:nil]);
        assert([store.items isEqualToArray:before]);

        // A failed atomic index write must leave the selected file and
        // published snapshot intact. Newly copied bytes must be rolled back.
        NSURL *folder = [root URLByAppendingPathComponent:@"BannerLibrary"];
        NSURL *index = [folder URLByAppendingPathComponent:@"index.plist"];
        NSURL *saved = [folder URLByAppendingPathComponent:@"saved"];
        assert([fm moveItemAtURL:index toURL:saved error:nil]);
        assert([fm createDirectoryAtURL:index withIntermediateDirectories:NO attributes:nil error:nil]);
        assert([@"locked" writeToURL:[index URLByAppendingPathComponent:@"guard"] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        assert(![store removeIdentifier:still.identifier error:nil]);
        assert([fm fileExistsAtPath:still.fileURL.path]);
        assert(![store importFileURL:image displayName:@"rollback" isVideo:NO error:nil]);
        assert([store.items isEqualToArray:before]);
        assert([fm removeItemAtURL:index error:nil]);
        assert([fm moveItemAtURL:saved toURL:index error:nil]);

        dispatch_apply(4,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t n) {
            @autoreleasepool { add(store,image,[NSString stringWithFormat:@"batch%zu",n],NO); }
        });
        assert(store.items.count == before.count + 4);
        WXGBannerLibrary *restarted = [[WXGBannerLibrary alloc] initWithSupport:root];
        // A nonexistent id forces a synchronous initial read without changing selection.
        assert(![restarted selectIdentifier:@"missing" error:nil]);
        assert([restarted.selectedItem.identifier isEqual:still.identifier]);
        assert(restarted.items.count == store.items.count);
        assert([restarted removeIdentifier:still.identifier error:nil]);
        assert(!restarted.selectedItem && ![fm fileExistsAtPath:still.fileURL.path]);
        assert([restarted selectIdentifier:fromLink.identifier error:nil]);
        assert([restarted selectIdentifier:nil error:nil]);
        assert(!restarted.selectedItem && [fm fileExistsAtPath:fromLink.fileURL.path]);
        assert([fm removeItemAtURL:root error:nil]);
        puts("PASS: banner migration, persistent selection, scoped deletion, provider links, batch imports and failed index writes.");
    }
    return 0;
}
