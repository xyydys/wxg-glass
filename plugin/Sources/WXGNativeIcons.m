#import "WXGNativeIcons.h"
#import "WXGNativeIconAnchors.h"
#import "WXGTabIconPreview.h"
extern BOOL WXGImageIsMonochrome(UIImage *image);
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@implementation WXGNativeIconPair
- (id)copyWithZone:(NSZone *)zone {
    WXGNativeIconPair *p=[[WXGNativeIconPair allocWithZone:zone] init];
    p.normalImage=_normalImage; p.selectedImage=_selectedImage;
    p.normalTint=_normalTint; p.selectedTint=_selectedTint;
    p.normalTextColor=_normalTextColor; p.selectedTextColor=_selectedTextColor;
    p.traits=_traits; p.title=_title;
    p.normalSource=_normalSource; p.selectedSource=_selectedSource;
    p.normalTemplate=_normalTemplate; p.selectedTemplate=_selectedTemplate;
    p.normalRank=_normalRank; p.selectedRank=_selectedRank;
    p.normalDisplaySize=_normalDisplaySize; p.selectedDisplaySize=_selectedDisplaySize;   // FIX115 D
    return p;
}
@end

static UIColor *WXGResolvedIconColor(UIColor *color,UITraitCollection *traits) {
    return [color isKindOfClass:UIColor.class]?[color resolvedColorWithTraitCollection:traits]:nil;
}
static BOOL WXGUsableNativeImage(UIImage *image) {
    return [image isKindOfClass:UIImage.class] && image.size.width>0 && image.size.height>0;
}
static NSString *WXGIconColorSignature(UIColor *color) {
    if(!color) return @"-";
    CGFloat r=0,g=0,b=0,a=0;
    if([color getRed:&r green:&g blue:&b alpha:&a])
        return [NSString stringWithFormat:@"%.5f,%.5f,%.5f,%.5f",r,g,b,a];
    return color.description;
}
static void WXGSetNativeImage(WXGNativeIconPair *pair,BOOL selected,UIImage *image,
                             UIColor *tint,BOOL automaticTemplate,CGFloat rank,NSString *source,CGSize display) {
    if(!WXGUsableNativeImage(image) || rank<(selected?pair.selectedRank:pair.normalRank)) return;
    BOOL templ=image.renderingMode==UIImageRenderingModeAlwaysTemplate ||
        (automaticTemplate && image.renderingMode!=UIImageRenderingModeAlwaysOriginal);
    if(selected) {
        pair.selectedImage=image; pair.selectedTint=tint; pair.selectedTemplate=templ;
        pair.selectedRank=rank; pair.selectedSource=source; pair.selectedDisplaySize=display;
    } else {
        pair.normalImage=image; pair.normalTint=tint; pair.normalTemplate=templ;
        pair.normalRank=rank; pair.normalSource=source; pair.normalDisplaySize=display;
    }
}
/* FIX115 D (user: a theme's PNG icons came out larger or smaller in the dock):
   the dock drew a picture at its own size (capped at 30 pt); a theme's PNG
   loaded at another scale than the screen's has a size unrelated to how big
   it shows. What is shown: an image view's box, the picture fitted into it
   when the view scales its content (fit / fill / stretch), the picture's own
   size when it does not (centre and the like). Bounds, not the frame on
   screen: a bounce animating the view's transform does not change it. */
static CGSize WXGShownSize(UIImageView *view,UIImage *image) {
    if(!view || !WXGUsableNativeImage(image))return CGSizeZero;
    CGSize box=view.bounds.size,size=image.size;
    if(box.width<1 || box.height<1)return CGSizeZero;
    UIViewContentMode mode=view.contentMode;
    if(mode==UIViewContentModeScaleToFill)return box;
    if(mode==UIViewContentModeScaleAspectFit || mode==UIViewContentModeScaleAspectFill) {
        CGFloat k=MIN(box.width/size.width,box.height/size.height);
        return CGSizeMake(size.width*k,size.height*k);
    }
    return size;
}
// FIX36: WeChat's own tab shows "微信", not "微信(359)": drop a trailing count.
static NSString *WXGCleanTabTitle(NSString *title) {
    if(![title isKindOfClass:NSString.class])return nil;
    NSRegularExpression *count=[NSRegularExpression regularExpressionWithPattern:@"\\s*[(（]\\s*[0-9]+\\+?\\s*[)）]\\s*$" options:0 error:nil];
    return [count stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0,title.length) withTemplate:@""];
}
// FIX108 D/E: what an icon looks like: an 8x8 brightness / coverage shape
// and its mean colour (a theme's tinted copy of the same outline), the same
// for the same artwork whatever image object carries it.
typedef struct {uint64_t shape;double r,g,b;BOOL valid;} WXGArtLook;
static WXGArtLook WXGArtLookOf(UIImage *image) {
    WXGArtLook look={0,0,0,0,NO};
    if(!WXGUsableNativeImage(image))return look;
    static NSMapTable<UIImage *,NSArray *> *cache;if(!cache)cache=[NSMapTable weakToStrongObjectsMapTable];
    NSArray *known=[cache objectForKey:image];
    if(known.count==4){look.shape=[known[0] unsignedLongLongValue];look.r=[known[1] doubleValue];look.g=[known[2] doubleValue];look.b=[known[3] doubleValue];look.valid=YES;return look;}
    uint8_t px[8*8*4]={0};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(px,8,8,8,32,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);if(!context)return look;
    UIGraphicsPushContext(context);[image drawInRect:CGRectMake(0,0,8,8)];UIGraphicsPopContext();CGContextRelease(context);
    double v[64],mean=0,a=0;
    for(int i=0;i<64;i++){v[i]=px[i*4+3]*2+(px[i*4]+px[i*4+1]+px[i*4+2])/3.0;mean+=v[i];look.r+=px[i*4];look.g+=px[i*4+1];look.b+=px[i*4+2];a+=px[i*4+3];}
    mean/=64;for(int i=0;i<64;i++)if(v[i]>mean)look.shape|=1ull<<i;
    if(a>0){look.r/=a;look.g/=a;look.b/=a;}   // premultiplied sums over coverage: the straight mean colour
    look.valid=YES;
    [cache setObject:@[@(look.shape),@(look.r),@(look.g),@(look.b)] forKey:image];
    return look;
}
// Clearly another artwork: more than 10 of 64 shape cells or the mean colour.
static BOOL WXGArtDiffers(UIImage *a,UIImage *b) {
    if(a==b)return NO;
    WXGArtLook x=WXGArtLookOf(a),y=WXGArtLookOf(b);if(!x.valid || !y.valid)return NO;
    int bits=__builtin_popcountll(x.shape^y.shape);
    double colour=fabs(x.r-y.r)+fabs(x.g-y.g)+fabs(x.b-y.b);
    return bits>10 || colour>.25;
}
static NSString *WXGHexOf(UIColor *color) {
    CGFloat r=0,g=0,b=0,a=0;
    if(!color || ![color getRed:&r green:&g blue:&b alpha:&a])return nil;
    return [NSString stringWithFormat:@"%.4f,%.4f,%.4f,%.4f",r,g,b,a];
}
static UIColor *WXGColorOfHex(NSString *text) {
    NSArray<NSString *> *parts=[text componentsSeparatedByString:@","];
    if(parts.count!=4)return nil;
    return [UIColor colorWithRed:parts[0].doubleValue green:parts[1].doubleValue blue:parts[2].doubleValue alpha:parts[3].doubleValue];
}
// Keep one complete, immutable publication per appearance, including slots whose
// other state has never been seen. The file is replaced in one atomic rename.
static NSString *WXGIconCacheDirectory(NSInteger style) {
    NSString *caches=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
    return [caches stringByAppendingPathComponent:[NSString stringWithFormat:@"WXGLiquidGlass/TabIcons/%ld",(long)style]];
}
static NSMutableDictionary<NSNumber *,NSArray<WXGNativeIconPair *> *> *WXGIconSnapshots(void) {
    static NSMutableDictionary *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once,^{ snapshots=[NSMutableDictionary dictionary]; });
    return snapshots;
}
static NSString *WXGCachedIconSource(NSString *source) {
    if (![source isKindOfClass:NSString.class] || !source.length) return @"缓存 · 微信图标";
    return [source hasPrefix:@"缓存 · "] ? source : [@"缓存 · " stringByAppendingString:source];
}
static UIImage *WXGDecodeCachedIcon(NSData *png,NSNumber *savedScale) {
    if (![png isKindOfClass:NSData.class] || !png.length) return nil;
    CGFloat scale=[savedScale respondsToSelector:@selector(doubleValue)] ? savedScale.doubleValue : 0;
    if (!isfinite(scale) || scale<=0) scale=UIScreen.mainScreen.scale;
    return [UIImage imageWithData:png scale:scale];
}
static NSArray<WXGNativeIconPair *> *WXGLoadCachedPairs(NSInteger style) {
    NSMutableDictionary *snapshots=WXGIconSnapshots();
    @synchronized(snapshots) {
        NSArray *cached=snapshots[@(style)];
        if (cached) return [[NSArray alloc] initWithArray:cached copyItems:YES];
    }
    NSString *dir=WXGIconCacheDirectory(style);
    NSString *snapshotPath=[dir stringByAppendingPathComponent:@"artwork-v2.plist"];
    NSData *data=[NSData dataWithContentsOfFile:snapshotPath];
    BOOL legacy=data==nil;
    NSArray *records;
    if (legacy) {
        records=[NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:@"meta.plist"]];
    } else {
        NSDictionary *snapshot=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"version"] isEqual:@2] ||
            ![snapshot[@"appearance"] isEqual:@(style)]) return nil;
        records=snapshot[@"slots"];
    }
    if (![records isKindOfClass:NSArray.class] || records.count!=4) return nil;
    NSMutableArray *pairs=[NSMutableArray arrayWithCapacity:4];
    for (NSUInteger i=0;i<records.count;i++) {
        NSDictionary *m=records[i];
        if (![m isKindOfClass:NSDictionary.class]) return nil;
        NSData *normal=m[@"normalPNG"], *selected=m[@"selectedPNG"];
        if (legacy) {
            normal=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"normal_%lu.png",(unsigned long)i]]];
            selected=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"selected_%lu.png",(unsigned long)i]]];
        }
        UIImage *n=WXGDecodeCachedIcon(normal,m[@"normalScale"]), *s=WXGDecodeCachedIcon(selected,m[@"selectedScale"]);
        // Old caches also saved a recoloured normal as selected. The tint was
        // separate from the PNG. Import only a clearly distinct selected asset.
        if (legacy && (!n || !WXGArtDiffers(n,s))) s=nil;
        WXGNativeIconPair *p=[WXGNativeIconPair new];
        p.normalTemplate=[m[@"normalTemplate"] boolValue];p.selectedTemplate=[m[@"selectedTemplate"] boolValue];
        p.normalImage=p.normalTemplate?[n imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:n;
        p.selectedImage=p.selectedTemplate?[s imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:s;
        p.normalRank=n?1:0;p.selectedRank=s?1:0;
        p.normalSource=n?WXGCachedIconSource(m[@"normalSource"]):nil;
        p.selectedSource=s?WXGCachedIconSource(m[@"selectedSource"]):nil;
        p.normalTint=WXGColorOfHex(m[@"normalTint"]);p.selectedTint=WXGColorOfHex(m[@"selectedTint"]);
        p.normalTextColor=WXGColorOfHex(m[@"normalText"]);p.selectedTextColor=WXGColorOfHex(m[@"selectedText"]);
        p.normalDisplaySize=CGSizeMake([m[@"normalShownW"] doubleValue],[m[@"normalShownH"] doubleValue]);
        p.selectedDisplaySize=CGSizeMake([m[@"selectedShownW"] doubleValue],[m[@"selectedShownH"] doubleValue]);
        p.title=m[@"title"];[pairs addObject:p];
    }
    return pairs;
}
static void WXGSaveCachedPairs(NSArray<WXGNativeIconPair *> *pairs,NSInteger style) {
    if (pairs.count!=4) return;
    NSArray<WXGNativeIconPair *> *snapshot=[[NSArray alloc] initWithArray:pairs copyItems:YES];
    for (WXGNativeIconPair *p in snapshot) {
        if (p.normalRank<=0) p.normalImage=nil;
        if (p.selectedRank<=0) p.selectedImage=nil;
        p.normalRank=p.normalImage?1:0;p.selectedRank=p.selectedImage?1:0;
        p.normalSource=p.normalImage?WXGCachedIconSource(p.normalSource):nil;
        p.selectedSource=p.selectedImage?WXGCachedIconSource(p.selectedSource):nil;
    }
    NSMutableDictionary *snapshots=WXGIconSnapshots();
    @synchronized(snapshots) { snapshots[@(style)]=snapshot; }
    static dispatch_queue_t writer;
    static dispatch_once_t once;
    dispatch_once(&once,^{ writer=dispatch_queue_create("wxg.tab-artwork-cache",DISPATCH_QUEUE_SERIAL); });
    dispatch_async(writer,^{ @autoreleasepool {
        @synchronized(snapshots) { if (snapshots[@(style)]!=snapshot) return; }
        NSMutableArray *records=[NSMutableArray arrayWithCapacity:4];
        for (WXGNativeIconPair *p in snapshot) {
            NSMutableDictionary *m=[@{@"title":p.title?:@"",@"normalTemplate":@(p.normalTemplate),@"selectedTemplate":@(p.selectedTemplate),
                @"normalScale":@(p.normalImage.scale),@"selectedScale":@(p.selectedImage.scale),
                @"normalShownW":@(p.normalDisplaySize.width),@"normalShownH":@(p.normalDisplaySize.height),
                @"selectedShownW":@(p.selectedDisplaySize.width),@"selectedShownH":@(p.selectedDisplaySize.height)} mutableCopy];
            if (p.normalImage) {
                NSData *png=UIImagePNGRepresentation(p.normalImage);
                if (!png.length) return;
                m[@"normalPNG"]=png;m[@"normalSource"]=p.normalSource;
            }
            if (p.selectedImage) {
                NSData *png=UIImagePNGRepresentation(p.selectedImage);
                if (!png.length) return;
                m[@"selectedPNG"]=png;m[@"selectedSource"]=p.selectedSource;
            }
            m[@"normalTint"]=WXGHexOf(p.normalTint);m[@"selectedTint"]=WXGHexOf(p.selectedTint);
            m[@"normalText"]=WXGHexOf(p.normalTextColor);m[@"selectedText"]=WXGHexOf(p.selectedTextColor);
            [records addObject:m];
        }
        NSDictionary *root=@{@"version":@2,@"appearance":@(style),@"slots":records};
        NSData *encoded=[NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (!encoded) return;
        NSString *dir=WXGIconCacheDirectory(style);
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [encoded writeToFile:[dir stringByAppendingPathComponent:@"artwork-v2.plist"] options:NSDataWritingAtomic error:nil];
    }});
}
static NSArray<WXGNativeIconPair *> *WXGEmptyNativePairs(void) {
    NSMutableArray *pairs=[NSMutableArray array];
    for(int i=0;i<4;i++) [pairs addObject:[WXGNativeIconPair new]];
    return pairs;
}

// All UI resolution happens on the main thread once per normal asset. The
// atlas queue receives the resolved preview exactly as it does a genuine icon.
static UIImage *WXGSelectedPreview(UIImage *normal,BOOL mono) {
    if (!WXGUsableNativeImage(normal)) return nil;
    static NSMapTable<UIImage *,UIImage *> *cache;
    if (!cache) cache=[NSMapTable weakToStrongObjectsMapTable];
    UIImage *known=[cache objectForKey:normal];
    if (known) return known;
    CGSize size=normal.size;
    CGFloat scale=MIN(MAX(1.,UIScreen.mainScreen.scale),160./MAX(size.width,size.height));
    int w=MAX(2,MIN(160,lround(size.width*scale))),h=MAX(2,MIN(160,lround(size.height*scale)));
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=1;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIImage *raster=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w,h) format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[normal drawInRect:CGRectMake(0,0,w,h)];}];
    if (!raster.CGImage) return nil;
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx=CGBitmapContextCreate(NULL,w,h,8,4*w,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),raster.CGImage);
    uint8_t *pixels=CGBitmapContextGetData(ctx);
    NSData *input=[NSData dataWithBytes:pixels length:(NSUInteger)4*w*h];
    CGImageRef rendered=WXGFillTabIcon(input.bytes,pixels,w,h,mono)?CGBitmapContextCreateImage(ctx):NULL;
    CGContextRelease(ctx);
    if (!rendered) return nil;
    UIImage *preview=[UIImage imageWithCGImage:rendered scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(rendered);
    [cache setObject:preview forKey:normal];
    return preview;
}

static void WXGSetPreviewIfMissing(WXGNativeIconPair *pair,UIColor *accent) {
    if (pair.selectedImage || !pair.normalImage) return;
    BOOL mono=pair.normalTemplate || WXGImageIsMonochrome(pair.normalImage);
    pair.selectedImage=WXGSelectedPreview(pair.normalImage,mono);
    pair.selectedRank=-1; pair.selectedTemplate=mono; pair.selectedTint=mono?accent:nil;
    pair.selectedDisplaySize=pair.normalDisplaySize;
    pair.selectedSource=pair.selectedImage?@"临时填充（取自该项普通图）":@"临时系统实心图";
}

static BOOL WXGSkipIconView(UIView *view) {
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return view.hidden || view.alpha < .01 || [name containsString:@"badge"] ||
           [name containsString:@"reddot"] || [name containsString:@"unread"];
}

static NSArray<UIView *> *WXGWeChatItemAnchors(UITabBar *bar) {
    // UIKit can supply two copies of its buttons for the lens. WeChat's four
    // item views own the real artwork. Inspect only those roots once validated.
    Class itemClass = NSClassFromString(@"MMTabBarItemView");
    if (!itemClass || bar.subviews.count > 256) return nil;
    NSMutableArray<UIView *> *queue = [bar.subviews mutableCopy];
    NSMutableArray<UIView *> *items = [NSMutableArray arrayWithCapacity:4];
    double centers[4];
    for (NSUInteger cursor = 0; cursor < queue.count; ++cursor) {
        UIView *view = queue[cursor];
        if (WXGSkipIconView(view)) continue;
        if ([view isKindOfClass:itemClass]) {
            CGRect rect = [view convertRect:view.bounds toView:bar];
            if (CGRectIsEmpty(rect) || !CGRectIntersectsRect(bar.bounds, rect)) continue;
            if (items.count >= 4) return nil;
            centers[items.count] = CGRectGetMidX(rect) - CGRectGetMinX(bar.bounds);
            [items addObject:view];
        } else {
            if (view.subviews.count > 256 - queue.count) return nil;
            [queue addObjectsFromArray:view.subviews];
        }
    }
    unsigned order[4];
    if (!WXGOrderIconAnchors(centers, items.count, CGRectGetWidth(bar.bounds), order)) return nil;
    return @[items[order[0]], items[order[1]], items[order[2]], items[order[3]]];
}

@interface WXGNativeIcons ()
@property(nonatomic,strong) NSArray<WXGNativeIconPair *> *items;
@property(nonatomic,copy) NSString *diagnostics, *identity, *signature;
@property(nonatomic,weak) UITabBar *lastBar;
@property(nonatomic) NSInteger lastSelection, lastStyle, itemsStyle, previousStateSlot;
@property(nonatomic) CFTimeInterval selectionChangedAt;
@property(nonatomic,copy) NSString *snapshotSignature;
@property(nonatomic) CFTimeInterval nextSample;
@property(nonatomic) NSUInteger unlaidScans;
@property(nonatomic,copy) NSString *titleFont;   // FIX91: WeChat's own tab title font, for the diagnostics
@property(nonatomic) NSUInteger artworkChanges;  // FIX108 D
@end

@implementation WXGNativeIcons
- (instancetype)init {
    if((self=[super init])) {
        _itemsStyle=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        NSArray *cached=WXGLoadCachedPairs(_itemsStyle);
        _items=cached?:WXGEmptyNativePairs();
        for (WXGNativeIconPair *pair in cached) WXGSetPreviewIfMissing(pair,pair.selectedTextColor);
        _diagnostics=cached?@"使用上次读取的微信图标（缓存），等待原生底栏":@"等待微信原生底栏";
    }
    return self;
}
- (void)invalidateAppearance {_nextSample=0;_lastStyle=-1;_identity=nil;_signature=nil;}
- (void)expireSampling {_nextSample=0;_lastBar=nil;}
- (NSString *)signatureForPairs:(NSArray<WXGNativeIconPair *> *)pairs {
    NSMutableString *signature=[NSMutableString string];
    for(WXGNativeIconPair *p in pairs) {
        [signature appendFormat:@"%p/%p/%d/%d/%@/%@/%@/%@/%@/%ld/%.1f/%.1fx%.1f/%.1fx%.1f;",
            (__bridge void *)p.normalImage,(__bridge void *)p.selectedImage,p.normalTemplate,p.selectedTemplate,
            WXGIconColorSignature(p.normalTint),WXGIconColorSignature(p.selectedTint),
            WXGIconColorSignature(p.normalTextColor),WXGIconColorSignature(p.selectedTextColor),p.title,
            (long)p.traits.userInterfaceStyle,p.traits.displayScale,
            p.normalDisplaySize.width,p.normalDisplaySize.height,p.selectedDisplaySize.width,p.selectedDisplaySize.height];
        [signature appendFormat:@"%.0f/%.0f;",floor(p.normalRank),floor(p.selectedRank)];   // FIX115 D
    }
    return signature;
}
- (BOOL)updateFromTabController:(UITabBarController *)tabs {
    if(!tabs) { _diagnostics=@"未找到原生底栏；保留已取得图像，缺失项回退"; return NO; }
    UITabBar *bar=tabs.tabBar;
    NSInteger selected=(NSInteger)tabs.selectedIndex,style=bar.traitCollection.userInterfaceStyle;
    NSUInteger nativeIndex=bar.selectedItem?[bar.items indexOfObject:bar.selectedItem]:NSNotFound;
    if(nativeIndex!=NSNotFound && bar.items.count) selected=(NSInteger)nativeIndex;
    CFTimeInterval now=CACurrentMediaTime();
    if(bar==_lastBar && selected==_lastSelection && style==_lastStyle && now<_nextSample) return NO;
    BOOL continuingStyle=(_itemsStyle==style);
    if (!continuingStyle) {
        _items=WXGLoadCachedPairs(style)?:WXGEmptyNativePairs();
        for (WXGNativeIconPair *pair in _items) WXGSetPreviewIfMissing(pair,pair.selectedTextColor);
        _itemsStyle=style; _snapshotSignature=nil; _identity=nil;
    }
    NSInteger previousSelection=_lastSelection;
    if (continuingStyle && selected!=previousSelection && _identity) {
        _selectionChangedAt=now; _previousStateSlot=previousSelection;
    }
    _lastBar=bar; _lastSelection=selected; _lastStyle=style; _nextSample=now+.8;
    @try {
        NSArray<UITabBarItem *> *nativeItems=bar.items;
        if(!nativeItems.count && tabs.viewControllers.count) {
            NSMutableArray *fromControllers=[NSMutableArray array];
            for(UIViewController *vc in tabs.viewControllers) if(vc.tabBarItem) [fromControllers addObject:vc.tabBarItem];
            nativeItems=fromControllers;
        }
        if(nativeItems.count!=4) {
            // FIX38: not ready yet (cold start) is not "no icons": keep what we
            // have (the cached set from the last launch, or an earlier read).
            _diagnostics=[NSString stringWithFormat:@"原生底栏 %lu 项，未匹配四项；保留现有图标",(unsigned long)nativeItems.count];
            return !continuingStyle;
        }
        UITraitCollection *traits=bar.traitCollection;
        NSMutableString *identity=[NSMutableString stringWithFormat:@"%p/%ld/%.1f",(__bridge void *)bar,(long)style,traits.displayScale];
        for(UITabBarItem *item in nativeItems)
            [identity appendFormat:@"/%p/%p/%p/%@",(__bridge void *)item,(__bridge void *)item.image,(__bridge void *)item.selectedImage,item.title];
        BOOL sameIdentity=[_identity isEqual:identity];
        NSMutableArray<WXGNativeIconPair *> *pairs=[NSMutableArray array];
        UITabBarItemAppearance *appearance=bar.standardAppearance.stackedLayoutAppearance;
        UIColor *normalTint=WXGResolvedIconColor(bar.unselectedItemTintColor?:appearance.normal.iconColor,traits);
        UIColor *selectedTint=WXGResolvedIconColor(appearance.selected.iconColor?:bar.tintColor,traits);
        for(NSUInteger i=0;i<4;i++) {
            WXGNativeIconPair *pair=[WXGNativeIconPair new];
            WXGNativeIconPair *cached=sameIdentity?_items[i]:nil;
            UITabBarItem *item=nativeItems[i]; pair.title=WXGCleanTabTitle(item.title); pair.traits=traits;
            pair.normalTextColor=WXGResolvedIconColor(appearance.normal.titleTextAttributes[NSForegroundColorAttributeName],traits)?:cached.normalTextColor;
            pair.selectedTextColor=WXGResolvedIconColor(appearance.selected.titleTextAttributes[NSForegroundColorAttributeName],traits)?:cached.selectedTextColor;
            WXGSetNativeImage(pair,NO,item.image,normalTint,YES,20,@"UITabBarItem.image",CGSizeZero);
            if (item.selectedImage!=item.image)
                WXGSetNativeImage(pair,YES,item.selectedImage,selectedTint,YES,20,@"UITabBarItem.selectedImage",CGSizeZero);
            [pairs addObject:pair];
        }
        // Observe custom/native controls inside the existing tab bar. Read only
        // the currently displayed state, caching the other state from prior visits.
        NSMutableArray<UIView *> *views=[NSMutableArray arrayWithArray:bar.subviews];
        NSUInteger cursor=0;
        BOOL rtl=bar.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
        // FIX36: a view belongs to the tab button that contains it. At cold
        // start WeChat had not laid its buttons out yet (all at x≈0), so the
        // position rule put the 4th tab's icon into slot 1. Read views only
        // once the four buttons are actually spread across the bar.
        NSMutableArray<UIView *> *buttons=[NSMutableArray array];
        for(UIView *v in bar.subviews)if([NSStringFromClass(v.class) containsString:@"TabBarButton"])[buttons addObject:v];
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){return CGRectGetMidX(a.frame)<CGRectGetMidX(b.frame)?NSOrderedAscending:NSOrderedDescending;}];
        BOOL laidOut=buttons.count==4;
        for(NSUInteger i=1;laidOut && i<4;i++)if(CGRectGetMidX(buttons[i].frame)-CGRectGetMidX(buttons[i-1].frame)<bar.bounds.size.width/8)laidOut=NO;
        NSArray<UIView *> *weChatItems=WXGWeChatItemAnchors(bar);
        if (!laidOut) {
            buttons = [weChatItems mutableCopy];
            [views removeAllObjects];
            if (weChatItems) {laidOut=YES;[views addObjectsFromArray:weChatItems];}
            else ++_unlaidScans;
        }
        while(cursor<views.count && cursor<256) {
            UIView *view=views[cursor++];
            if (WXGSkipIconView(view)) continue;
            if(views.count<256) {
                for(UIView *child in view.subviews) { if(views.count>=256) break; [views addObject:child]; }
            }
            if(bar.bounds.size.width<1) continue;
            CGRect rect=[view convertRect:view.bounds toView:bar];
            CGFloat x=CGRectGetMidX(rect)-bar.bounds.origin.x;
            if(x<0 || x>=bar.bounds.size.width || !CGRectIntersectsRect(rect,bar.bounds)) continue;
            NSInteger slot=MIN(3,(NSInteger)(4*x/bar.bounds.size.width));
            BOOL owned=NO;
            for(UIView *a=view;a && a!=bar;a=a.superview){
                if(weChatItems){
                    NSUInteger owner=[weChatItems indexOfObjectIdenticalTo:a];
                    if(owner!=NSNotFound){slot=(NSInteger)owner;owned=YES;break;}
                }
                NSUInteger button=[buttons indexOfObjectIdenticalTo:a];
                if(button!=NSNotFound){slot=(NSInteger)button;if(!weChatItems)break;}
            }
            // UIKit can keep simultaneous rest/lens copies. The visible
            // state belongs to WeChat's item, while external buttons may
            // still explicitly provide a pair of named control states.
            if(weChatItems && !owned && ![view isKindOfClass:UIButton.class])continue;
            if(rtl) slot=3-slot;
            WXGNativeIconPair *pair=pairs[slot]; BOOL currentSelected=slot==selected;
            if([view isKindOfClass:UILabel.class]) {
                UILabel *label=(id)view;
                NSString *text=WXGCleanTabTitle(label.text);
                if(text.length && (text.length<10) && (!pair.title.length || [text isEqual:pair.title])) {
                    pair.title=text;
                    UIFont *font=label.font;
                    if(font)_titleFont=[NSString stringWithFormat:@"%@ %.1f pt，粗细 %.2f",font.fontName,font.pointSize,
                                        [[font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue]];
                    UIColor *color=WXGResolvedIconColor(label.textColor,traits);
                    if(currentSelected) pair.selectedTextColor=color; else pair.normalTextColor=color;
                }
            }
            if([view isKindOfClass:UIButton.class]) {
                UIButton *button=(id)view;
                // No setSelected:, sendActions..., or forced page switches.
                UIColor *tint=WXGResolvedIconColor(button.tintColor,traits);
                if(rect.size.width<=bar.bounds.size.width*.45 && rect.size.height<=100) {
                    UIImage *normal=[button imageForState:UIControlStateNormal],*chosen=[button imageForState:UIControlStateSelected];
                    WXGSetNativeImage(pair,NO,normal,tint,NO,60,@"UIButton.normal",WXGShownSize(button.imageView,normal));
                    // UIButton returns the normal image when no selected resource exists.
                    if(chosen && chosen!=normal)WXGSetNativeImage(pair,YES,chosen,tint,NO,60,@"UIButton.selected",WXGShownSize(button.imageView,chosen));
                }
            }
            if([view isKindOfClass:UIImageView.class]) {
                UIImageView *imageView=(id)view;
                CGFloat w=rect.size.width,h=rect.size.height;
                if(w<14 || h<14 || w>72 || h>72 || w/h<.45 || w/h>2.2) continue;
                CGFloat score=100+w*h/10000.f;
                UIColor *tint=WXGResolvedIconColor(imageView.tintColor,traits);
                UITabBarItem *item=nativeItems[slot];
                BOOL template=imageView.image && (imageView.image==item.image || imageView.image==item.selectedImage);
                if(imageView.highlightedImage && imageView.highlightedImage!=imageView.image) {
                    WXGSetNativeImage(pair,NO,imageView.image,tint,template,score,@"UIImageView.image",WXGShownSize(imageView,imageView.image));
                    BOOL highlightedTemplate=imageView.highlightedImage==item.selectedImage || imageView.highlightedImage==item.image;
                    WXGSetNativeImage(pair,YES,imageView.highlightedImage,tint,highlightedTemplate,score,@"UIImageView.highlightedImage",WXGShownSize(imageView,imageView.highlightedImage));
                } else {
                    // The model can commit first; a live image from the old
                    // state on this same tab is not a reading of its new state.
                    WXGNativeIconPair *prior=_items[slot];
                    UIImage *opposite=currentSelected?prior.normalImage:prior.selectedImage;
                    BOOL awaitingPaint=now-_selectionChangedAt<.4 && (currentSelected || slot==_previousStateSlot) &&
                        imageView.image && imageView.image==opposite;
                    if (!awaitingPaint) WXGSetNativeImage(pair,currentSelected,imageView.image,tint,template,score,@"微信当前图标视图",WXGShownSize(imageView,imageView.image));
                }
            }
        }
        // FIX108 D/E: a theme switched on / off (another set of icons): the
        // tabs that are neither selected now nor were at the last read (their
        // views settled: a tab being switched can show its old state for a
        // read) show, in their unselected state, artwork clearly different from
        // what was seen there before (in a view, or last launch's cache), on
        // every such tab (two at least). Never compared with a state the plugin
        // made up itself (the selected one from the outline, D compared those
        // and fired on nearly every switch). Then everything kept is stale: it
        // is dropped and made again from what is seen until each tab is visited.
        NSArray<WXGNativeIconPair *> *priors=_items;BOOL artworkChanged=NO;NSUInteger compared=0,differ=0;
        for(NSUInteger i=0;i<4 && i<_items.count;i++) {
            if((NSInteger)i==selected || (NSInteger)i==previousSelection)continue;
            WXGNativeIconPair *pair=pairs[i],*prior=_items[i];
            BOOL seenBefore=prior.normalRank>=60 || prior.normalRank==1;   // a view's, or the launch cache's
            if(pair.normalRank<100 || !prior.normalImage || !seenBefore)continue;
            ++compared;if(WXGArtDiffers(pair.normalImage,prior.normalImage))++differ;
        }
        artworkChanged=compared>=2 && differ==compared;
        if(artworkChanged) {
            NSMutableArray *kept=[NSMutableArray array];
            for(WXGNativeIconPair *prior in _items) {
                // The title colours went with the old artwork too (the accent / rest colour stand in).
                WXGNativeIconPair *p=[WXGNativeIconPair new];p.title=prior.title;p.traits=prior.traits;[kept addObject:p];
            }
            priors=kept;++_artworkChanges;sameIdentity=NO;
        }
        // A genuine themed view outranks generic item data on the next scan.
        // Reconstruct synthetic states from the current normal on each read.
        for(NSUInteger i=0;i<4;i++) {
            WXGNativeIconPair *pair=pairs[i],*prior=priors[i];
            UITabBarItem *item=nativeItems[i];
            // A theme can replace just this one glyph while UIKit keeps the
            // stock selected asset. Compare normal with normal before pairing.
            BOOL changedNormal=pair.normalRank>=60 && prior.normalRank>0 && WXGArtDiffers(pair.normalImage,prior.normalImage);
            UIImage *shownNormal=pair.normalRank>=60?pair.normalImage:prior.normalImage;
            if (pair.selectedRank==20 && item.image && shownNormal && WXGArtDiffers(item.image,shownNormal)) {
                pair.selectedImage=nil;pair.selectedSource=nil;pair.selectedRank=0;
            }
            if(prior.normalRank>0 && (!pair.normalImage || (sameIdentity && floor(prior.normalRank)>floor(pair.normalRank))))
                WXGSetNativeImage(pair,NO,prior.normalImage,prior.normalTint,prior.normalTemplate,prior.normalRank,prior.normalSource,prior.normalDisplaySize);
            if(!changedNormal && prior.selectedRank>0 && (!pair.selectedImage || (sameIdentity && floor(prior.selectedRank)>floor(pair.selectedRank))))
                WXGSetNativeImage(pair,YES,prior.selectedImage,prior.selectedTint,prior.selectedTemplate,prior.selectedRank,prior.selectedSource,prior.selectedDisplaySize);
            if(!pair.title.length && prior.title.length)pair.title=prior.title;
            if(!pair.normalTextColor)pair.normalTextColor=prior.normalTextColor;
            if(!pair.selectedTextColor)pair.selectedTextColor=prior.selectedTextColor;
        }
        UIColor *accent=(selected>=0 && selected<4)?pairs[selected].selectedTextColor:nil;
        accent=accent?:selectedTint?:[UIColor colorWithRed:.03 green:.72 blue:.38 alpha:1];
        UIColor *rest=normalTint?:[UIColor.labelColor resolvedColorWithTraitCollection:traits];
        for(WXGNativeIconPair *pair in pairs) {
            WXGSetPreviewIfMissing(pair,accent);
            if(!pair.normalImage && pair.selectedRank>0) {
                BOOL mono=WXGImageIsMonochrome(pair.selectedImage);
                pair.normalImage=pair.selectedImage;pair.normalTemplate=mono;pair.normalTint=mono?rest:nil;
                pair.normalRank=-1;pair.normalDisplaySize=pair.selectedDisplaySize;
                pair.normalSource=@"临时共用选中图（普通图未见）";
            }
            if(!pair.selectedTextColor)pair.selectedTextColor=accent;
            if(!pair.normalTextColor)pair.normalTextColor=rest;
        }
        for(WXGNativeIconPair *pair in pairs) {
            if(WXGImageIsMonochrome(pair.normalImage)){pair.normalTemplate=YES;pair.normalTint=pair.normalTextColor?:[UIColor.labelColor resolvedColorWithTraitCollection:traits];}
        }
        NSString *sig=[self signatureForPairs:pairs]; BOOL changed=![_signature isEqual:sig];
        _signature=sig; _identity=identity; _items=pairs;
        if(laidOut && ![_snapshotSignature isEqual:sig]) {
            WXGSaveCachedPairs(pairs,style);_snapshotSignature=sig;
        }
        NSUInteger normals=0,selecteds=0; NSMutableArray *sources=[NSMutableArray array];
        for(NSUInteger i=0;i<4;i++) {
            WXGNativeIconPair *p=pairs[i]; normals+=p.normalRank>0; selecteds+=p.selectedRank>0;
            [sources addObject:[NSString stringWithFormat:@"%lu：%@ / %@；图 %.0fx%.0f@%.0fx / %.0fx%.0f@%.0fx，显示 %.1fx%.1f / %.1fx%.1f",(unsigned long)i+1,p.normalSource?:@"未选中回退",p.selectedSource?:@"临时系统实心图",
                p.normalImage.size.width,p.normalImage.size.height,p.normalImage.scale,p.selectedImage.size.width,p.selectedImage.size.height,p.selectedImage.scale,
                p.normalDisplaySize.width,p.normalDisplaySize.height,p.selectedDisplaySize.width,p.selectedDisplaySize.height]];   // FIX115 D
        }
        _diagnostics=[NSString stringWithFormat:@"微信图标：实读或缓存普通 %lu/4，实读或缓存选中 %lu/4；按钮%@布局（未布局扫描 %lu 次）；图标换过 %lu 次（主题）；微信标题字体 %@\n%@",(unsigned long)normals,(unsigned long)selecteds,
            laidOut?@"已":@"未",(unsigned long)_unlaidScans,(unsigned long)_artworkChanges,_titleFont?:@"未读到",[sources componentsJoinedByString:@"\n"]];
        return changed;
    } @catch(NSException *e) {
        _diagnostics=[NSString stringWithFormat:@"微信图标读取回退：%@",e.reason?:e.name]; return NO;
    }
}
@end
