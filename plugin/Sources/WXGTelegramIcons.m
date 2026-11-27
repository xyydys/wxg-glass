#import "WXGIntegration.h"
#import "WXGTelegramTabIcons.h"
#import "WXGTelegramInk.h"

/* FIX113: Telegram's four tab bar icons with their own animations, for the
   dock: 微信 = Chats, 通讯录 = Contacts, 发现 = Calls, 我 = Settings.
   The artwork is Telegram for iOS's (GPLv2, see WXGTelegramTabIcons.h):
   its Lottie files rendered frame by frame (60 fps, as Telegram plays them)
   and embedded as grey coverage masks. Decode coverage once per sheet.
   The static renderer uses white templates; animated layers take frames
   tinted directly at the source resolution. */

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
// Immutable coverage is shared by the resting art and both colours of the animation.
static NSData *WXGTelegramCoverage(NSInteger tab) {
    static NSData *sheets[4];static dispatch_once_t once[4];
    dispatch_once(&once[tab],^{
        WXGTelegramSheet sheet=WXGTelegramSheetFor(tab);
        NSData *data=[NSData dataWithBytesNoCopy:(void *)sheet.png length:sheet.length freeWhenDone:NO];
        UIImage *png=[UIImage imageWithData:data];
        size_t side=WXGTelegramFrameSide,height=side*sheet.frames;
        CGImageRef grey=png.CGImage;
        if(!grey || CGImageGetWidth(grey)!=side || CGImageGetHeight(grey)!=height)return;
        NSMutableData *coverage=[NSMutableData dataWithLength:side*height];
        CGColorSpaceRef gray=CGColorSpaceCreateDeviceGray();
        CGContextRef ctx=CGBitmapContextCreate(coverage.mutableBytes,side,height,8,side,gray,kCGImageAlphaNone);
        CGColorSpaceRelease(gray);
        if(!ctx)return;
        CGContextDrawImage(ctx,CGRectMake(0,0,side,height),grey);CGContextRelease(ctx);
        const uint8_t *bytes=coverage.bytes;
        size_t left=side,right=0;
        for(size_t y=0;y<side;y++)for(size_t x=0;x<side;x++)if(bytes[y*side+x]>8){left=MIN(left,x);right=MAX(right,x);}
        WXGTelegramRestInk[tab]=right>=left?(CGFloat)(right-left+1)/side:1;
        sheets[tab]=coverage;
    });
    return sheets[tab];
}
NSArray *WXGTelegramInkFrames(NSInteger tab,UIColor *ink) {
    if(tab<0 || tab>3)return @[];
    NSData *coverage=WXGTelegramCoverage(tab);
    if(!coverage.length)return @[];
    CGFloat r=0,g=0,b=0,a=1;
    if(![ink getRed:&r green:&g blue:&b alpha:&a]) {
        if(![ink getWhite:&r alpha:&a])return @[];
        b=g=r;
    }
    WXGTelegramPixel color={lround(WXGClamp(r,0,1)*255),lround(WXGClamp(g,0,1)*255),
                           lround(WXGClamp(b,0,1)*255),lround(WXGClamp(a,0,1)*255)};
    WXGTelegramPixel lut[256];
    for(int i=0;i<256;i++)lut[i]=WXGTelegramCoveredInk(color,(uint8_t)i);
    NSMutableData *rgba=[NSMutableData dataWithLength:coverage.length*sizeof(WXGTelegramPixel)];
    const uint8_t *bytes=coverage.bytes;WXGTelegramPixel *pixels=rgba.mutableBytes;
    for(size_t i=0;i<coverage.length;i++)pixels[i]=lut[bytes[i]];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
    CGColorSpaceRef rgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    size_t side=WXGTelegramFrameSide,count=coverage.length/(side*side);
    CGImageRef sheet=CGImageCreate(side,side*count,8,32,side*4,rgb,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,true,kCGRenderingIntentDefault);
    CGColorSpaceRelease(rgb);CGDataProviderRelease(provider);
    if(!sheet)return @[];
    NSMutableArray *frames=[NSMutableArray arrayWithCapacity:count];
    for(size_t i=0;i<count;i++) {
        CGImageRef frame=CGImageCreateWithImageInRect(sheet,CGRectMake(0,i*side,side,side));
        if(!frame)break;
        [frames addObject:CFBridgingRelease(frame)];
    }
    CGImageRelease(sheet);
    return frames.count==count?frames.copy:@[];
}
// Main thread only. The Metal renderer uses these template images for live patches.
NSArray<UIImage *> *WXGTelegramFrames(NSInteger tab) {
    static NSArray<UIImage *> *cache[4];
    tab=MAX(0,MIN(3,tab));
    if(!cache[tab]) {
        NSMutableArray *images=[NSMutableArray array];
        for(id frame in WXGTelegramInkFrames(tab,UIColor.whiteColor)) {
            UIImage *art=[UIImage imageWithCGImage:(__bridge CGImageRef)frame scale:3 orientation:UIImageOrientationUp];
            [images addObject:[art imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        }
        cache[tab]=images.copy;
    }
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
