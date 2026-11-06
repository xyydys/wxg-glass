#import "WXGIntegration.h"
#import "WXGTelegramTabIcons.h"

/* FIX113: Telegram's four tab bar icons with their own animations, for the
   dock: 微信 = Chats, 通讯录 = Contacts, 发现 = Calls, 我 = Settings.
   The artwork is Telegram for iOS's (GPLv2, see WXGTelegramTabIcons.h):
   its Lottie files rendered frame by frame (60 fps, as Telegram plays them)
   and embedded as grey coverage masks. Here each sheet is turned once into
   white premultiplied frames (template images), tinted when drawn: resting,
   the first frame (the same as the last); selected, the frames in order.
   Decoded only when the dock uses them (about 1.5 MB per icon). */

typedef struct {const unsigned char *png;unsigned int length,frames;} WXGTelegramSheet;
static WXGTelegramSheet WXGTelegramSheetFor(NSInteger tab) {
    switch(MAX(0,MIN(3,tab))) {
        case 0:return (WXGTelegramSheet){WXGTabChatsPNG,WXGTabChatsLength,WXGTabChatsFrames};
        case 1:return (WXGTelegramSheet){WXGTabContactsPNG,WXGTabContactsLength,WXGTabContactsFrames};
        case 2:return (WXGTelegramSheet){WXGTabCallsPNG,WXGTabCallsLength,WXGTabCallsFrames};
        default:return (WXGTelegramSheet){WXGTabSettingsPNG,WXGTabSettingsLength,WXGTabSettingsFrames};
    }
}
BOOL WXGDockThemeFirst(void) {return [WXGConfig.shared extraNumber:@"dockThemeFirst"]>.5;}   // FIX115 D
BOOL WXGTelegramTabIconsOn(void) {return [WXGConfig.shared extraNumber:@"dockTelegramIcons"]>.5 && !WXGDockThemeFirst();}   // FIX115 D: not with 主题优先
NSInteger WXGTelegramFrameCount(NSInteger tab) {return (NSInteger)WXGTelegramSheetFor(tab).frames;}
// FIX113 F: how wide the resting glyph's ink is, as a share of a frame (the
// frames leave room for the animation around it: 0.69 Calls .. 0.86 Chats).
static CGFloat WXGTelegramRestInk[4];
// Main thread only (the cache); the images it returns may be drawn anywhere.
NSArray<UIImage *> *WXGTelegramFrames(NSInteger tab) {
    static NSArray<UIImage *> *cache[4];
    tab=MAX(0,MIN(3,tab));
    if(cache[tab])return cache[tab];
    WXGTelegramSheet sheet=WXGTelegramSheetFor(tab);
    NSData *data=[NSData dataWithBytesNoCopy:(void *)sheet.png length:sheet.length freeWhenDone:NO];
    CGImageRef grey=[UIImage imageWithData:data].CGImage;
    size_t side=WXGTelegramFrameSide,height=side*sheet.frames;
    if(!grey || CGImageGetWidth(grey)!=side || CGImageGetHeight(grey)!=height){cache[tab]=@[];return cache[tab];}
    // The coverage, row 0 at the top (as the sheet).
    uint8_t *coverage=calloc(side*height,1);
    CGColorSpaceRef greySpace=CGColorSpaceCreateDeviceGray();
    CGContextRef context=coverage?CGBitmapContextCreate(coverage,side,height,8,side,greySpace,(CGBitmapInfo)kCGImageAlphaNone):NULL;
    CGColorSpaceRelease(greySpace);
    if(!context){free(coverage);cache[tab]=@[];return cache[tab];}
    CGContextDrawImage(context,CGRectMake(0,0,side,height),grey);CGContextRelease(context);
    // FIX113 F: the first frame's ink, left to right (rows 0 ..< side: the top of the sheet).
    size_t inkMin=side,inkMax=0;
    for(size_t y=0;y<side;y++)for(size_t x=0;x<side;x++)if(coverage[y*side+x]>8){if(x<inkMin)inkMin=x;if(x>inkMax)inkMax=x;}
    WXGTelegramRestInk[tab]=inkMax>=inkMin?(CGFloat)(inkMax-inkMin+1)/(CGFloat)side:1;
    // White, premultiplied: every channel is the coverage.
    NSMutableData *rgba=[NSMutableData dataWithLength:side*height*4];uint8_t *out=rgba.mutableBytes;
    for(size_t i=0;i<side*height;i++)out[4*i]=out[4*i+1]=out[4*i+2]=out[4*i+3]=coverage[i];
    free(coverage);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGImageRef all=CGImageCreate(side,height,8,32,side*4,rgb,(CGBitmapInfo)kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);
    CGColorSpaceRelease(rgb);CGDataProviderRelease(provider);
    NSMutableArray<UIImage *> *frames=[NSMutableArray array];
    for(size_t k=0;all && k<sheet.frames;k++) {
        CGImageRef frame=CGImageCreateWithImageInRect(all,CGRectMake(0,(CGFloat)(k*side),side,side));
        if(!frame)continue;
        // 96 px at 3x: 32 pt, drawn as the dock's 26 pt box (its 28 x 26 fit).
        [frames addObject:[[UIImage imageWithCGImage:frame scale:3 orientation:UIImageOrientationUp] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        CGImageRelease(frame);
    }
    if(all)CGImageRelease(all);
    cache[tab]=frames.count==sheet.frames?frames.copy:@[];
    return cache[tab];
}
CGFloat WXGTelegramRestInkWidth(NSInteger tab) {
    tab=MAX(0,MIN(3,tab));
    if(!WXGTelegramFrames(tab).count)return 1;
    return WXGTelegramRestInk[tab]>0?WXGTelegramRestInk[tab]:1;
}
// One frame of a tab's icon in a colour (0: resting). Main thread only.
// FIX113 C: a plain bitmap in that colour (not a tinted template): the dock
// atlas draws it on its own queue and an image view shows it as it is.
UIImage *WXGTelegramTabImage(NSInteger tab,NSInteger frame,UIColor *color) {
    NSArray<UIImage *> *frames=WXGTelegramFrames(tab);
    if(!frames.count)return nil;
    frame=MAX(0,MIN((NSInteger)frames.count-1,frame));
    color=color?:UIColor.labelColor;CGFloat r=0,g=0,b=0,a=0;[color getRed:&r green:&g blue:&b alpha:&a];
    static NSCache<NSString *,UIImage *> *cache;if(!cache){cache=[NSCache new];cache.countLimit=32;}
    NSString *key=[NSString stringWithFormat:@"%ld/%ld/%.3f/%.3f/%.3f/%.3f",(long)MAX(0,MIN(3,tab)),(long)frame,r,g,b,a];
    UIImage *cached=[cache objectForKey:key];if(cached)return cached;
    UIImage *image=frames[(NSUInteger)frame];
    UIImage *tinted=[image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=image.scale;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIImage *bitmap=[[[UIGraphicsImageRenderer alloc]initWithSize:image.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        (void)context;[tinted drawAtPoint:CGPointZero];
    }];
    if(bitmap)[cache setObject:bitmap forKey:key];
    return bitmap;
}
