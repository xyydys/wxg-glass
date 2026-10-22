#import "WXGNativeIcons.h"
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
                             UIColor *tint,BOOL automaticTemplate,CGFloat rank,NSString *source) {
    if(!WXGUsableNativeImage(image) || rank<(selected?pair.selectedRank:pair.normalRank)) return;
    BOOL templ=image.renderingMode==UIImageRenderingModeAlwaysTemplate ||
        (automaticTemplate && image.renderingMode!=UIImageRenderingModeAlwaysOriginal);
    if(selected) {
        pair.selectedImage=image; pair.selectedTint=tint; pair.selectedTemplate=templ;
        pair.selectedRank=rank; pair.selectedSource=source;
    } else {
        pair.normalImage=image; pair.normalTint=tint; pair.normalTemplate=templ;
        pair.normalRank=rank; pair.normalSource=source;
    }
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
// FIX36: the last complete read of WeChat's tab icons, per light/dark style,
// is cached on disk and used from the very first frame of the next launch
// (WeChat's real icons, or a theme plugin's, instead of the built-in symbols).
static NSString *WXGIconCacheDirectory(NSInteger style) {
    NSString *caches=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
    return [caches stringByAppendingPathComponent:[NSString stringWithFormat:@"WXGLiquidGlass/TabIcons/%ld",(long)style]];
}
static NSArray<WXGNativeIconPair *> *WXGLoadCachedPairs(NSInteger style) {
    NSString *dir=WXGIconCacheDirectory(style);
    NSArray<NSDictionary *> *meta=[NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:@"meta.plist"]];
    if(meta.count!=4)return nil;
    NSMutableArray *pairs=[NSMutableArray array];CGFloat scale=UIScreen.mainScreen.scale;
    for(NSUInteger i=0;i<4;i++) {
        NSDictionary *m=meta[i];WXGNativeIconPair *pair=[WXGNativeIconPair new];
        NSData *normal=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"normal_%lu.png",(unsigned long)i]]];
        NSData *selected=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"selected_%lu.png",(unsigned long)i]]];
        UIImage *n=normal?[UIImage imageWithData:normal scale:[m[@"normalScale"] doubleValue]?:scale]:nil;
        UIImage *sel=selected?[UIImage imageWithData:selected scale:[m[@"selectedScale"] doubleValue]?:scale]:nil;
        if(!n)return nil;
        pair.normalTemplate=[m[@"normalTemplate"] boolValue];pair.selectedTemplate=[m[@"selectedTemplate"] boolValue];
        pair.normalImage=pair.normalTemplate?[n imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:n;
        pair.selectedImage=sel?(pair.selectedTemplate?[sel imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:sel):nil;
        pair.normalTint=WXGColorOfHex(m[@"normalTint"]);pair.selectedTint=WXGColorOfHex(m[@"selectedTint"]);
        pair.normalTextColor=WXGColorOfHex(m[@"normalText"]);pair.selectedTextColor=WXGColorOfHex(m[@"selectedText"]);
        pair.title=m[@"title"];pair.normalRank=1;pair.selectedRank=sel?1:0;
        pair.normalSource=@"上次读取的微信图标（缓存）";pair.selectedSource=sel?@"上次读取的微信图标（缓存）":nil;
        [pairs addObject:pair];
    }
    return pairs;
}
static void WXGSaveCachedPairs(NSArray<WXGNativeIconPair *> *pairs,NSInteger style) {
    if(pairs.count!=4)return;
    for(WXGNativeIconPair *pair in pairs)if(!pair.normalImage || pair.normalRank<20)return;   // complete real reads only
    NSMutableArray *meta=[NSMutableArray array];NSMutableDictionary<NSString *,NSData *> *files=[NSMutableDictionary dictionary];
    for(NSUInteger i=0;i<4;i++) {
        WXGNativeIconPair *pair=pairs[i];
        NSData *normal=UIImagePNGRepresentation(pair.normalImage),*selected=pair.selectedImage?UIImagePNGRepresentation(pair.selectedImage):nil;
        if(!normal)return;
        files[[NSString stringWithFormat:@"normal_%lu.png",(unsigned long)i]]=normal;
        if(selected)files[[NSString stringWithFormat:@"selected_%lu.png",(unsigned long)i]]=selected;
        NSMutableDictionary *m=[NSMutableDictionary dictionary];
        m[@"title"]=pair.title?:@"";m[@"normalTemplate"]=@(pair.normalTemplate);m[@"selectedTemplate"]=@(pair.selectedTemplate);
        m[@"normalScale"]=@(pair.normalImage.scale);m[@"selectedScale"]=@(pair.selectedImage.scale?:pair.normalImage.scale);
        NSString *v;
        if((v=WXGHexOf(pair.normalTint)))m[@"normalTint"]=v;
        if((v=WXGHexOf(pair.selectedTint)))m[@"selectedTint"]=v;
        if((v=WXGHexOf(pair.normalTextColor)))m[@"normalText"]=v;
        if((v=WXGHexOf(pair.selectedTextColor)))m[@"selectedText"]=v;
        [meta addObject:m];
    }
    NSString *dir=WXGIconCacheDirectory(style);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [files enumerateKeysAndObjectsUsingBlock:^(NSString *name,NSData *data,__unused BOOL *stop){[data writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];}];
        [meta writeToFile:[dir stringByAppendingPathComponent:@"meta.plist"] atomically:YES];
    });
}
static NSArray<WXGNativeIconPair *> *WXGEmptyNativePairs(void) {
    NSMutableArray *pairs=[NSMutableArray array];
    for(int i=0;i<4;i++) [pairs addObject:[WXGNativeIconPair new]];
    return pairs;
}

@interface WXGNativeIcons ()
@property(nonatomic,strong) NSArray<WXGNativeIconPair *> *items;
@property(nonatomic,copy) NSString *diagnostics, *identity, *signature;
@property(nonatomic,weak) UITabBar *lastBar;
@property(nonatomic) NSInteger lastSelection, lastStyle;
@property(nonatomic) CFTimeInterval nextSample;
@property(nonatomic) NSUInteger unlaidScans;
@property(nonatomic,copy) NSString *titleFont;   // FIX91: WeChat's own tab title font, for the diagnostics
@property(nonatomic) NSUInteger artworkChanges;  // FIX108 D
@end

@implementation WXGNativeIcons
- (instancetype)init {
    if((self=[super init])) {
        NSArray *cached=WXGLoadCachedPairs(UIScreen.mainScreen.traitCollection.userInterfaceStyle);
        _items=cached?:WXGEmptyNativePairs();
        _diagnostics=cached?@"使用上次读取的微信图标（缓存），等待原生底栏":@"等待微信原生底栏";
    }
    return self;
}
- (void)invalidateAppearance {_nextSample=0;_lastStyle=-1;_identity=nil;_signature=nil;}
- (void)expireSampling {_nextSample=0;_lastBar=nil;}
- (NSString *)signatureForPairs:(NSArray<WXGNativeIconPair *> *)pairs {
    NSMutableString *signature=[NSMutableString string];
    for(WXGNativeIconPair *p in pairs) {
        [signature appendFormat:@"%p/%p/%d/%d/%@/%@/%@/%@/%@/%ld/%.1f;",
            (__bridge void *)p.normalImage,(__bridge void *)p.selectedImage,p.normalTemplate,p.selectedTemplate,
            WXGIconColorSignature(p.normalTint),WXGIconColorSignature(p.selectedTint),
            WXGIconColorSignature(p.normalTextColor),WXGIconColorSignature(p.selectedTextColor),p.title,
            (long)p.traits.userInterfaceStyle,p.traits.displayScale];
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
    NSInteger previousSelection=_lastSelection;   // FIX108 E
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
            return NO;
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
            WXGSetNativeImage(pair,NO,item.image,normalTint,YES,20,@"UITabBarItem.image");
            // UIKit uses the normal image when no separate selectedImage exists.
            WXGSetNativeImage(pair,YES,item.selectedImage?:item.image,selectedTint,YES,20,
                item.selectedImage?@"UITabBarItem.selectedImage":@"UITabBarItem.image（选中共用）");
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
        if(!laidOut){[views removeAllObjects];++_unlaidScans;}
        while(cursor<views.count && cursor<256) {
            UIView *view=views[cursor++];
            NSString *name=NSStringFromClass(view.class).lowercaseString;
            if(view.hidden || view.alpha<.01 || [name containsString:@"badge"] || [name containsString:@"reddot"] || [name containsString:@"unread"]) continue;
            if(views.count<256) {
                for(UIView *child in view.subviews) { if(views.count>=256) break; [views addObject:child]; }
            }
            if(bar.bounds.size.width<1) continue;
            CGRect rect=[view convertRect:view.bounds toView:bar];
            CGFloat x=CGRectGetMidX(rect)-bar.bounds.origin.x;
            if(x<0 || x>=bar.bounds.size.width || !CGRectIntersectsRect(rect,bar.bounds)) continue;
            NSInteger slot=MIN(3,(NSInteger)(4*x/bar.bounds.size.width));
            for(UIView *a=view;a && a!=bar;a=a.superview){NSUInteger b=[buttons indexOfObjectIdenticalTo:a];if(b!=NSNotFound){slot=(NSInteger)b;break;}}
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
                    WXGSetNativeImage(pair,NO,[button imageForState:UIControlStateNormal],tint,NO,60,@"UIButton.normal");
                    UIImage *normal=[button imageForState:UIControlStateNormal],*chosen=[button imageForState:UIControlStateSelected];
                    // UIButton returns the normal image when no selected resource exists.
                    if(chosen && (chosen!=normal || button.selected))WXGSetNativeImage(pair,YES,chosen,tint,NO,60,@"UIButton.selected");
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
                if(imageView.highlightedImage) {
                    WXGSetNativeImage(pair,NO,imageView.image,tint,template,score,@"UIImageView.image");
                    BOOL highlightedTemplate=imageView.highlightedImage==item.selectedImage || imageView.highlightedImage==item.image;
                    WXGSetNativeImage(pair,YES,imageView.highlightedImage,tint,highlightedTemplate,score,@"UIImageView.highlightedImage");
                } else {
                    WXGSetNativeImage(pair,currentSelected,imageView.image,tint,template,score,@"微信当前图标视图");
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
        // Keep an observed custom state when this scan only offers a generic
        // tab-item fallback. Fresh observations of the same class always win,
        // even if the icon's bounds became slightly smaller since the last scan.
        if(sameIdentity) for(NSUInteger i=0;i<4;i++) {
            WXGNativeIconPair *pair=pairs[i],*cached=_items[i];
            if(floor(cached.normalRank)>floor(pair.normalRank))
                WXGSetNativeImage(pair,NO,cached.normalImage,cached.normalTint,cached.normalTemplate,cached.normalRank,cached.normalSource);
            if(floor(cached.selectedRank)>floor(pair.selectedRank))
                WXGSetNativeImage(pair,YES,cached.selectedImage,cached.selectedTint,cached.selectedTemplate,cached.selectedRank,cached.selectedSource);
        }
        // FIX38: a read replaces only what it actually saw. At launch WeChat's
        // items have no images yet; that read used to replace the cached set
        // from the last launch, so the built-in symbols showed anyway.
        for(NSUInteger i=0;i<4 && i<priors.count;i++) {
            WXGNativeIconPair *pair=pairs[i],*prior=priors[i];
            if(!pair.normalImage && prior.normalImage) {
                pair.normalImage=prior.normalImage;pair.normalTint=prior.normalTint;pair.normalTemplate=prior.normalTemplate;
                pair.normalRank=prior.normalRank;pair.normalSource=prior.normalSource;
            }
            if(!pair.selectedImage && prior.selectedImage) {
                pair.selectedImage=prior.selectedImage;pair.selectedTint=prior.selectedTint;pair.selectedTemplate=prior.selectedTemplate;
                pair.selectedRank=prior.selectedRank;pair.selectedSource=prior.selectedSource;
            }
            if(!pair.title.length && prior.title.length)pair.title=prior.title;
            if(!pair.normalTextColor)pair.normalTextColor=prior.normalTextColor;
            if(!pair.selectedTextColor)pair.selectedTextColor=prior.selectedTextColor;
        }
        UIColor *accent=(selected>=0 && selected<4)?pairs[selected].selectedTextColor:nil;
        accent=accent?:selectedTint?:[UIColor colorWithRed:.03 green:.72 blue:.38 alpha:1];
        UIColor *rest=normalTint?:[UIColor.labelColor resolvedColorWithTraitCollection:traits];
        for(WXGNativeIconPair *pair in pairs) {
            if(pair.selectedRank<=20 && pair.normalRank>=60) {
                // FIX108 D: a theme's coloured artwork as it is (tinting it made
                // a flat green silhouette); a one-colour outline in the accent.
                BOOL mono=WXGImageIsMonochrome(pair.normalImage);
                pair.selectedImage=pair.normalImage;pair.selectedTemplate=mono;pair.selectedTint=mono?accent:nil;
                pair.selectedSource=mono?@"现有轮廓和原生选中色（未访问状态）":@"现有图（主题彩色图，未访问状态）";
            }
            // FIX108 D: the selected tab's other state unknown (dropped above,
            // or never seen): its selected artwork, the rest colour if one-colour.
            if(!pair.normalImage && pair.selectedImage && pair.selectedRank>=60) {
                BOOL mono=WXGImageIsMonochrome(pair.selectedImage);
                pair.normalImage=pair.selectedImage;pair.normalTemplate=mono;pair.normalTint=mono?rest:nil;pair.normalRank=10;
                pair.normalSource=@"选中图（未选中状态未见过）";
            }
            if(!pair.selectedTextColor)pair.selectedTextColor=accent;
            if(!pair.normalTextColor)pair.normalTextColor=rest;
        }
        for(WXGNativeIconPair *pair in pairs) {
            if(WXGImageIsMonochrome(pair.normalImage)){pair.normalTemplate=YES;pair.normalTint=pair.normalTextColor?:[UIColor.labelColor resolvedColorWithTraitCollection:traits];}
        }
        NSString *sig=[self signatureForPairs:pairs]; BOOL changed=![_signature isEqual:sig];
        _signature=sig; _identity=identity; _items=pairs;
        if(changed && laidOut)WXGSaveCachedPairs(pairs,style);
        NSUInteger normals=0,selecteds=0; NSMutableArray *sources=[NSMutableArray array];
        for(NSUInteger i=0;i<4;i++) {
            WXGNativeIconPair *p=pairs[i]; normals+=p.normalImage!=nil; selecteds+=p.selectedImage!=nil;
            [sources addObject:[NSString stringWithFormat:@"%lu：%@ / %@",(unsigned long)i+1,p.normalSource?:@"未选中回退",p.selectedSource?:@"选中回退"]];
        }
        _diagnostics=[NSString stringWithFormat:@"微信图标：未选中 %lu/4，选中 %lu/4；按钮%@布局（未布局扫描 %lu 次）；图标换过 %lu 次（主题）；微信标题字体 %@\n%@",(unsigned long)normals,(unsigned long)selecteds,
            laidOut?@"已":@"未",(unsigned long)_unlaidScans,(unsigned long)_artworkChanges,_titleFont?:@"未读到",[sources componentsJoinedByString:@"\n"]];
        return changed;
    } @catch(NSException *e) {
        _diagnostics=[NSString stringWithFormat:@"微信图标读取回退：%@",e.reason?:e.name]; return NO;
    }
}
@end
