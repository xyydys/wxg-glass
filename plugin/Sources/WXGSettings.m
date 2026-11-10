#import "WXGSettingsKit.h"
#import "WXGButtonPress.h"
#import <PhotosUI/PhotosUI.h>

// FIX58: glass settings. The page frame, the glass cards and the home page are
// here; the module pages and their rows are in WXGOpticalSettings.m.

NSString * const WXGSettingsUIChanged=@"WXGSettingsUIChanged";

#pragma mark - Diagnostics (unchanged text view, native bar)

@interface WXGDiagnosticController : UIViewController
@end
@implementation WXGDiagnosticController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"图标 / 背景 / 动作诊断";
    UITextView *text=[[UITextView alloc]initWithFrame:self.view.bounds];text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO;text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];text.text=WXGIntegrationHost.shared.diagnostics;
    self.view.backgroundColor=UIColor.systemBackgroundColor;[self.view addSubview:text];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"导出" style:UIBarButtonItemStylePlain target:self action:@selector(export)];
}
- (void)export {[WXGIntegrationHost.shared exportDiagnosticsFrom:self];}
@end
UIViewController *WXGSettingsDiagnosticsPage(void) {return [WXGDiagnosticController new];}

#pragma mark - Store

NSString *WXGHexFromColor(UIColor *color) {
    CGFloat r=0,g=0,b=0,a=1;
    if(![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGColorSpaceRef srgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGColorRef converted=srgb?CGColorCreateCopyByMatchingToColorSpace(srgb,kCGRenderingIntentDefault,color.CGColor,NULL):NULL;
        if(converted && CGColorGetNumberOfComponents(converted)>=4){const CGFloat *c=CGColorGetComponents(converted);r=c[0];g=c[1];b=c[2];a=c[3];}
        if(converted)CGColorRelease(converted);
        if(srgb)CGColorSpaceRelease(srgb);
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",(int)lround(WXGClamp(r,0,1)*255),(int)lround(WXGClamp(g,0,1)*255),
            (int)lround(WXGClamp(b,0,1)*255),(int)lround(WXGClamp(a,0,1)*255)];
}
/* FIX85: the wallpapers and the avatar are kept twice, in
   Library/Preferences/WeChatLiquidGlass and Documents/WeChatLiquidGlass (never
   Caches or tmp, which WeChat's 清理缓存 empties; until FIX84 they were in
   Application Support, which it seems to clear too). Each copy is written
   atomically (a temporary file renamed over it) without file protection, so
   it is readable before the first unlock. A read checks both: a missing or
   unreadable copy is written again from the other; when they differ the
   first (written first) wins. A file left in Application Support by an
   older build is moved in once. */
static NSArray<NSString *> *WXGSettingsDirectories(void) {
    static NSArray *directories;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSString *library=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES).firstObject;
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSMutableArray *list=[NSMutableArray array];
        if(library)[list addObject:[library stringByAppendingPathComponent:@"Preferences/WeChatLiquidGlass"]];
        if(documents)[list addObject:[documents stringByAppendingPathComponent:@"WeChatLiquidGlass"]];
        directories=list;
    });
    // FIX115 C: another plugin (WCGlass) keeps its libraries in a directory of the
    // same name (Documents/WeChatLiquidGlass): one that is there is left as it
    // is; only a missing one is created (with no file protection, FIX85). In
    // these directories this plugin only ever writes, heals or removes its own
    // three files (settings-wallpaper-light.jpg / -dark.jpg / settings-avatar.png).
    BOOL isDirectory=NO;
    for(NSString *directory in directories)
        if(![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory)
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionNone} error:nil];
    return directories;
}
static NSString *WXGSettingsLegacyFile(NSString *name) {
    NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    return base?[[base stringByAppendingPathComponent:@"WeChatLiquidGlass"] stringByAppendingPathComponent:name]:nil;
}
static BOOL WXGSettingsImageData(NSData *data) {return data.length>32 && [UIImage imageWithData:data]!=nil;}
static BOOL WXGSettingsWriteFile(NSString *path,NSData *data) {
    NSError *error=nil;
    BOOL written=[data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionNone error:&error];
    if(written)[NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:path error:nil];
    else WXGLog(@"设置页图片写入失败：%@（%@）",path.lastPathComponent,error.localizedDescription?:@"?");
    return written;
}
// A copy that could not be written is removed, so an older picture there
// can never be read back over the new one.
static BOOL WXGSettingsWrite(NSString *name,NSData *data) {
    BOOL any=NO;
    for(NSString *directory in WXGSettingsDirectories()) {
        NSString *path=[directory stringByAppendingPathComponent:name];
        if(WXGSettingsWriteFile(path,data))any=YES;
        else [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
    return any;
}
// Reads, repairs, writes and removals all run on this one queue, in order.
static dispatch_queue_t WXGSettingsImageQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.runyu.wxg.settings-images",DISPATCH_QUEUE_SERIAL);});
    return queue;
}
static void WXGSettingsRemove(NSString *name) {
    for(NSString *directory in WXGSettingsDirectories())[NSFileManager.defaultManager removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
    NSString *legacy=WXGSettingsLegacyFile(name);
    if(legacy)[NSFileManager.defaultManager removeItemAtPath:legacy error:nil];
}
static NSUInteger WXGSettingsHeals;
static NSData *WXGSettingsRead(NSString *name) {
    NSArray<NSString *> *directories=WXGSettingsDirectories();
    NSMutableArray *copies=[NSMutableArray array];NSData *good=nil;
    for(NSString *directory in directories) {
        NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
        BOOL valid=WXGSettingsImageData(data);
        [copies addObject:valid?data:NSNull.null];
        if(valid && !good)good=data;
    }
    if(!good) {
        NSString *legacy=WXGSettingsLegacyFile(name);
        NSData *data=legacy?[NSData dataWithContentsOfFile:legacy]:nil;
        if(!WXGSettingsImageData(data))return nil;
        if(WXGSettingsWrite(name,data)){[NSFileManager.defaultManager removeItemAtPath:legacy error:nil];WXGLog(@"设置页图片已迁移：%@",name);}
        return data;
    }
    for(NSUInteger i=0;i<directories.count;i++)if(copies[i]==NSNull.null || ![copies[i] isEqualToData:good]) {
        if(WXGSettingsWriteFile([directories[i] stringByAppendingPathComponent:name],good)){++WXGSettingsHeals;WXGLog(@"设置页图片已从另一份恢复：%@",name);}
    }
    return good;
}
NSDictionary *WXGSettingsStorageEvidence(void) {
    __block NSDictionary *result=nil;
    dispatch_sync(WXGSettingsImageQueue(),^{
    NSMutableDictionary *files=[NSMutableDictionary dictionary];
    for(NSString *name in @[@"settings-wallpaper-light.jpg",@"settings-wallpaper-dark.jpg",@"settings-avatar.png"]) {
        NSMutableArray *copies=[NSMutableArray array];
        for(NSString *directory in WXGSettingsDirectories()) {
            NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
            [copies addObject:attributes?@{@"bytes":attributes[NSFileSize]?:@0,@"protection":attributes[NSFileProtectionKey]?:@"?"}:@"missing"];
        }
        NSString *legacy=WXGSettingsLegacyFile(name);
        files[name]=@{@"copies":copies,@"legacy":@(legacy && [NSFileManager.defaultManager fileExistsAtPath:legacy])};
    }
    result=@{@"directories":WXGSettingsDirectories(),@"heals":@(WXGSettingsHeals),@"files":files};
    });
    return result;
}
// At most `pixels` on the long side, orientation applied, scale 1.
static UIImage *WXGScaledImage(UIImage *image,CGFloat pixels,BOOL opaque) {
    CGSize px=CGSizeMake(image.size.width*image.scale,image.size.height*image.scale);
    if(px.width<1 || px.height<1)return nil;
    CGFloat f=MIN(1,pixels/MAX(px.width,px.height));
    CGSize size=CGSizeMake(MAX(1,round(px.width*f)),MAX(1,round(px.height*f)));
    // Runs on the image queue: a plain 8-bit format, no screen traits.
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat new];format.scale=1;format.opaque=opaque;
    format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    return [[[UIGraphicsImageRenderer alloc]initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [image drawInRect:(CGRect){CGPointZero,size}];
    }];
}
@implementation WXGSettingsStore {
    NSCache<NSString *,id> *_images;   // file name -> UIImage or NSNull; dropped under memory pressure
}
+ (instancetype)shared {static WXGSettingsStore *store;static dispatch_once_t once;dispatch_once(&once,^{store=[self new];[store adoptBuildDefaults];});return store;}
// FIX114 G: as WXGConfig's adoptBuildDefaults, for the settings page's look
// (corner radius, accent): still the previous build's default: this build's.
- (void)adoptBuildDefaults {
    NSUserDefaults *suite=[self defaults];NSString *stamp=WXGBuildDefaultsStamp();
    if(!stamp.length || [[suite stringForKey:@"defaultsStamp.ui"] isEqualToString:stamp])return;
    NSDictionary *stored=nil;
    NSDictionary *previous=WXGPreviousBuildDefaultSection(@"ui"),*current=WXGBuildDefaultSection(@"ui");
    NSUInteger moved=0,kept=0;NSString *failure=nil;
    @try {   // FIX114 G (review): inside +shared at launch: never throws out; the stamp written whatever happens
    stored=[suite dictionaryForKey:@"settings.ui"];
    if(stored.count && WXGPreviousBuildDefaultSection(@"config").count) {   // previous defaults known; no ui section: the built-in look
        id (^radius)(id)=^id(id v){return [v isKindOfClass:NSNumber.class] && isfinite([v doubleValue])?@(WXGClamp([v doubleValue],0,40)):@26;};
        id oldRadius=radius(previous[@"cardRadius"]),nowRadius=radius(current[@"cardRadius"]);
        if(!WXGSameSettingValue(oldRadius,nowRadius)) {
            if(WXGSameSettingValue(@(_cardRadius),oldRadius)){_cardRadius=[nowRadius doubleValue];++moved;}else ++kept;
        }
        NSString *oldAccent=WXGNormalizeHex(previous[@"accentHex"]),*nowAccent=WXGNormalizeHex(current[@"accentHex"]);
        if(!WXGSameSettingValue(oldAccent,nowAccent)) {
            if(WXGSameSettingValue(WXGNormalizeHex(_accentHex),oldAccent)){_accentHex=nowAccent;++moved;}else ++kept;
        }
        if(moved) {
            NSMutableDictionary *d=[NSMutableDictionary dictionaryWithObject:@(_cardRadius) forKey:@"cardRadius"];
            if(_accentHex)d[@"accentHex"]=_accentHex;
            [suite setObject:d forKey:@"settings.ui"];
        }
    }
    }@catch(NSException *error) {
        failure=error.reason?:error.name?:@"exception";
    }@finally {
        [suite setObject:stamp forKey:@"defaultsStamp.ui"];
    }
    WXGNoteDefaultsAdoption(@"ui",@{@"stored":@(stored.count>0),@"moved":@(moved),@"kept":@(kept),@"error":failure?:@""});
}
- (NSUserDefaults *)defaults {return [[NSUserDefaults alloc]initWithSuiteName:@"com.runyu.WeChatLiquidGlass"];}
- (instancetype)init {
    if((self=[super init])) {
        _cardRadius=26;_images=[NSCache new];
        NSDictionary *d=[[self defaults] dictionaryForKey:@"settings.ui"];
        if(!d)d=WXGBuildDefaultSection(@"ui");   // FIX84: a fresh install: this build's look, if any
        _accentHex=WXGNormalizeHex(d[@"accentHex"]);
        if([d[@"cardRadius"] isKindOfClass:NSNumber.class] && isfinite([d[@"cardRadius"] doubleValue]))_cardRadius=WXGClamp([d[@"cardRadius"] doubleValue],0,40);
    }return self;
}
- (void)save {
    _accentHex=WXGNormalizeHex(_accentHex);_cardRadius=isfinite(_cardRadius)?WXGClamp(_cardRadius,0,40):26;
    NSMutableDictionary *d=[NSMutableDictionary dictionaryWithObject:@(_cardRadius) forKey:@"cardRadius"];
    if(_accentHex)d[@"accentHex"]=_accentHex;
    [[self defaults] setObject:d forKey:@"settings.ui"];
    [NSNotificationCenter.defaultCenter postNotificationName:WXGSettingsUIChanged object:nil];
}
- (UIColor *)accentColor {return _accentHex?WXGColor(_accentHex):UIColor.labelColor;}
- (UIColor *)secondaryColor {return _accentHex?[WXGColor(_accentHex) colorWithAlphaComponent:.62]:UIColor.secondaryLabelColor;}
- (UIColor *)controlTint {return _accentHex?WXGColor(_accentHex):nil;}
- (UIImage *)imageNamed:(NSString *)name {
    id cached=[_images objectForKey:name];
    if(cached)return [cached isKindOfClass:UIImage.class]?cached:nil;
    __block NSData *data=nil;   // FIX85: two copies, each restoring the other
    dispatch_sync(WXGSettingsImageQueue(),^{data=WXGSettingsRead(name);});
    UIImage *image=data?[UIImage imageWithData:data scale:1]:nil;
    [_images setObject:image?:(id)NSNull.null forKey:name];return image;
}
// Decoding, scaling and encoding a camera photo takes a while: done on a
// serial queue (in order, so the last choice wins), shown when stored.
- (void)storeImage:(UIImage *)image name:(NSString *)name pixels:(CGFloat)pixels jpeg:(BOOL)jpeg {
    dispatch_async(WXGSettingsImageQueue(),^{
        UIImage *scaled=image?WXGScaledImage(image,pixels,jpeg):nil;
        NSData *data=scaled?(jpeg?UIImageJPEGRepresentation(scaled,.9):UIImagePNGRepresentation(scaled)):nil;
        BOOL stored=data && WXGSettingsWrite(name,data);
        // FIX85: removed only when clearing; a failed save keeps the old picture.
        if(!image)WXGSettingsRemove(name);
        else if(!stored){WXGLog(@"设置页图片没有保存：%@",name);return;}
        dispatch_async(dispatch_get_main_queue(),^{
            [self->_images setObject:stored?scaled:(id)NSNull.null forKey:name];
            [NSNotificationCenter.defaultCenter postNotificationName:WXGSettingsUIChanged object:nil];
        });
    });
}
- (UIImage *)wallpaperForDark:(BOOL)dark {return [self imageNamed:dark?@"settings-wallpaper-dark.jpg":@"settings-wallpaper-light.jpg"];}
- (void)setWallpaper:(UIImage *)image dark:(BOOL)dark {
    CGFloat pixels=MAX(UIScreen.mainScreen.nativeBounds.size.width,UIScreen.mainScreen.nativeBounds.size.height);
    [self storeImage:image name:dark?@"settings-wallpaper-dark.jpg":@"settings-wallpaper-light.jpg" pixels:MAX(1200,pixels) jpeg:YES];
}
- (UIImage *)avatar {return [self imageNamed:@"settings-avatar.png"];}
- (void)setAvatar:(UIImage *)image {[self storeImage:image name:@"settings-avatar.png" pixels:360 jpeg:NO];}
@end

#pragma mark - Built-in wallpaper and avatar

// FIX113 O (user: not the in-between colour fields any more; light grey in
// light mode, dark grey in dark mode): until a wallpaper is imported, a plain
// colour (壁纸 › 无壁纸时的背景色), as an image (the edge fade copies it).
static UIImage *WXGDefaultWallpaper(CGSize size,BOOL dark) {
    static NSCache<NSString *,UIImage *> *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=4;});
    NSString *hex=[WXGConfig.shared extraHex:dark?@"settingsDarkBackgroundHex":@"settingsBackgroundHex"];
    UIColor *color=WXGColor(hex)?:(dark?[UIColor colorWithRed:.11 green:.11 blue:.118 alpha:1]:[UIColor colorWithRed:.949 green:.949 blue:.969 alpha:1]);
    CGFloat r=0,g=0,b=0,a=1;if(![color getRed:&r green:&g blue:&b alpha:&a]){r=g=b=dark?.11:.95;}
    color=[UIColor colorWithRed:r green:g blue:b alpha:1];
    size=CGSizeMake(MAX(64,round(size.width)),MAX(64,round(size.height)));
    NSString *key=[NSString stringWithFormat:@"%.0fx%.0f/%@",size.width,size.height,hex];
    UIImage *image=[cache objectForKey:key];if(image)return image;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=1;format.opaque=YES;
    image=[[[UIGraphicsImageRenderer alloc]initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [color setFill];UIRectFill(context.format.bounds);
    }];
    [cache setObject:image forKey:key];return image;
}
static UIImage *WXGDefaultAvatar(void) {
    static UIImage *image;static dispatch_once_t once;
    dispatch_once(&once,^{
        CGSize size=CGSizeMake(120,120);
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=2;format.opaque=NO;
        image=[[[UIGraphicsImageRenderer alloc]initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
            CGContextRef cg=context.CGContext;CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            CGFloat colors[8]={.33,.74,.86,1,.32,.42,.88,1},locations[2]={0,1};
            CGGradientRef g=CGGradientCreateWithColorComponents(space,colors,locations,2);
            CGContextAddEllipseInRect(cg,(CGRect){CGPointZero,size});CGContextClip(cg);
            CGContextDrawLinearGradient(cg,g,CGPointZero,CGPointMake(size.width,size.height),0);CGGradientRelease(g);CGColorSpaceRelease(space);
            UIImage *drop=[UIImage systemImageNamed:@"drop.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightSemibold]];
            drop=[drop imageWithTintColor:[UIColor colorWithWhite:1 alpha:.92] renderingMode:UIImageRenderingModeAlwaysOriginal];
            if(drop)[drop drawInRect:CGRectMake((size.width-drop.size.width)*.5,(size.height-drop.size.height)*.5,drop.size.width,drop.size.height)];
        }];
    });
    return image;
}
static UIImage *WXGSymbol(NSArray<NSString *> *names,CGFloat size,UIImageSymbolWeight weight) {
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    for(NSString *name in names){UIImage *image=[UIImage systemImageNamed:name withConfiguration:config];if(image)return image;}
    return nil;
}
// A bar button icon as a bitmap in a resolved colour. The glass buttons crop
// the ink and scale it to their icon size; a plain bitmap keeps its colour
// through that (a symbol would be re-resolved from its asset).
static UIImage *WXGInkedSymbol(NSArray<NSString *> *names,UIColor *color) {
    // About the drawn size (half the 41 pt button), regular weight: the same
    // stroke as the glass back button's chevron scaled to that size.
    UIImage *symbol=WXGSymbol(names,21,UIImageSymbolWeightRegular);if(!symbol)return nil;
    UIImage *tinted=[symbol imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.opaque=NO;
    return [[[UIGraphicsImageRenderer alloc]initWithSize:tinted.size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [tinted drawInRect:(CGRect){CGPointZero,tinted.size}];
    }];
}

#pragma mark - Glass card

@implementation WXGSettingsCard {
    double _press,_velocity,_target,_touchX,_touchY,_touchTargetX,_touchTargetY,_touchVelocityX,_touchVelocityY;
    CFTimeInterval _lastTick;
    UIImpactFeedbackGenerator *_feedback;
    // The glass only updates while it is on screen: a card that was below the
    // fold (or on a covered page) when a setting changed catches up later.
    NSUInteger _appliedRevision;
    BOOL _glassDirty,_glassNew;
    CFTimeInterval _lastApply;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.clipsToBounds=NO;
        _glass=[[WXGGlassView alloc]initWithFrame:CGRectZero];
        // The card content is UIKit; the glass needs no Metal canvas (no
        // drawables are ever allocated), only its render-server layers.
        _glass.overlayHidden=YES;[self addSubview:_glass];
        // FIX59: one backdrop per card (no RGB channels, no clear ring, at most
        // 2x): a page holds up to ten large glass, six layers each was too much.
        _glass.lightweight=YES;
        _glass.glassScopeOverride=WXGGlassScopeCard;   // FIX113 O: the 设置页 range
        _contentView=[[UIView alloc]initWithFrame:CGRectZero];_contentView.backgroundColor=UIColor.clearColor;[self addSubview:_contentView];
        _cornerRadius=26;_feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];
    }return self;
}
- (void)setPressable:(BOOL)pressable {
    _pressable=pressable;_glass.buttonPressEffect=pressable;_contentView.userInteractionEnabled=!pressable;
    self.isAccessibilityElement=pressable;self.accessibilityTraits=pressable?UIAccessibilityTraitButton:UIAccessibilityTraitNone;
}
- (void)setCornerRadius:(CGFloat)radius {if(_cornerRadius==radius)return;_cornerRadius=radius;[self setNeedsLayout];}
- (void)setCapsule:(BOOL)capsule {if(_capsule==capsule)return;_capsule=capsule;[self setNeedsLayout];}
- (void)didMoveToWindow {[super didMoveToWindow];_glass.active=self.window!=nil;_glassNew=YES;}
- (void)layoutSubviews {
    [super layoutSubviews];
    _glassDirty=YES;   // new size or radius: new refraction mesh on the next tick
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.glass.transform=CGAffineTransformIdentity;self.contentView.transform=CGAffineTransformIdentity;
        CGRect b=self.bounds;
        self.glass.frame=CGRectInset(b,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
        self.glass.glassRect=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,b.size.width,b.size.height);
        // 0 would mean a capsule to the glass; a square corner is 0.5 pt.
        self.glass.maximumCornerRadius=MAX(.5,MIN(self.capsule?CGFLOAT_MAX:self.cornerRadius,MIN(b.size.width,b.size.height)*.5));
        self.contentView.frame=b;
        [self applyPose];
        [self.glass layoutIfNeeded];
        [CATransaction commit];
    }];
}
// The glass buttons' press, damped for a large card (about 3% instead of 6%).
- (void)applyPose {
    WXGButtonPressPose pose=WXGButtonPress(_press,_touchX,_touchY,UIAccessibilityIsReduceMotionEnabled());
    CGFloat k=WXGClamp(90/MAX(1,MAX(self.bounds.size.width,self.bounds.size.height)),.3,1);
    CGFloat sx=1+(pose.scaleX-1)*k,sy=1+(pose.scaleY-1)*k;
    _glass.transform=CGAffineTransformMake(sx,0,0,sy,pose.offsetX*k,pose.offsetY*k);
    _contentView.transform=CGAffineTransformMake(sx,0,0,sy,pose.offsetX*k,pose.offsetY*k);
}
- (void)aimAt:(CGPoint)point {
    _touchTargetX=WXGClamp((point.x-CGRectGetMidX(self.bounds))/MAX(1,self.bounds.size.width*.5),-1,1);
    _touchTargetY=WXGClamp((point.y-CGRectGetMidY(self.bounds))/MAX(1,self.bounds.size.height*.5),-1,1);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;if(!_pressable)return NO;
    [self aimAt:[touch locationInView:self]];_target=1;[_feedback prepare];return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;CGPoint p=[touch locationInView:self];[self aimAt:p];
    _target=CGRectContainsPoint(CGRectInset(self.bounds,-24,-24),p)?1:0;return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;BOOL inside=touch && CGRectContainsPoint(CGRectInset(self.bounds,-24,-24),[touch locationInView:self]);
    _target=0;_touchTargetX=_touchTargetY=0;
    if(inside && _action){if(WXGConfig.shared.haptics)[_feedback impactOccurred];_action();}
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {(void)event;_target=0;_touchTargetX=_touchTargetY=0;}
- (BOOL)accessibilityActivate {if(!_action)return NO;_action();return YES;}
- (void)tick:(CFTimeInterval)time force:(BOOL)force {
    double dt=_lastTick>0?MIN(time-_lastTick,.05):1./60;_lastTick=time;
    BOOL moving=fabs(_press-_target)>.0005 || fabs(_velocity)>.0005 || fabs(_touchX-_touchTargetX)>.0005 || fabs(_touchY-_touchTargetY)>.0005 ||
                fabs(_touchVelocityX)>.0005 || fabs(_touchVelocityY)>.0005;
    BOOL urgent=force || _glassNew;   // just shown: refraction from the first frame
    BOOL stale=urgent || _glassDirty || _appliedRevision!=WXGConfigRevision();
    if(!moving && !stale)return;
    // While a slider or the corner radius is dragged, every visible card would
    // rebuild its meshes and masks each frame: at most ~12 times a second,
    // the last value always lands.
    if(!moving && !urgent && time-_lastApply<.08)return;
    if(moving) {
        WXGSpring(&_press,&_velocity,_target,420,31,dt);
        WXGSpring(&_touchX,&_touchVelocityX,_touchTargetX,320,30,dt);
        WXGSpring(&_touchY,&_touchVelocityY,_touchTargetY,320,30,dt);
        _glass.barScale=1;_glass.lensRect=CGRectZero;
        _glass.pressAmount=_pressable && !UIAccessibilityIsReduceMotionEnabled()?WXGClamp(_press,0,1):0;
        [UIView performWithoutAnimation:^{[CATransaction begin];[CATransaction setDisableActions:YES];[self applyPose];[CATransaction commit];}];
    }
    if(!self.window)return;
    [self layoutIfNeeded];   // a card placed in this layout pass sizes its glass first
    [_glass layoutIfNeeded];
    // The glass skips a tick while it is off screen; stay stale until it runs.
    if(!WXGPresentedVisible(_glass))return;
    [_glass tick:time];
    _appliedRevision=WXGConfigRevision();_glassDirty=_glassNew=NO;_lastApply=time;
}
@end

#pragma mark - Page frame

// Drags that start on a card still scroll; a slider keeps the drag only when
// its thumb was taken (a swipe over the track scrolls the page).
@interface WXGSettingsScrollView : UIScrollView
@end
@implementation WXGSettingsScrollView
- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    for(UIView *v=view;v && v!=self;v=v.superview)if([v isKindOfClass:UISlider.class])return !((UISlider *)v).isTracking;
    return YES;
}
@end
// One per navigation controller while settings pages are on it: how WeChat
// had the bar (restored when the last settings page leaves) and the edge-swipe
// delegate used meanwhile. With the bar hidden UIKit's own delegate refuses
// the swipe; this one allows it whenever there is a page to go back to and
// overrides nothing else. WeChat's delegate is held strongly until restored.
@interface WXGSettingsNavigationState : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) UINavigationController *navigation;
@property(nonatomic,strong) id<UIGestureRecognizerDelegate> original;
@property(nonatomic) BOOL barWasHidden,installed;
@end
@implementation WXGSettingsNavigationState
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    (void)recognizer;UINavigationController *nav=_navigation;
    return nav.viewControllers.count>1 && !nav.transitionCoordinator;
}
@end
static char WXGNavigationStateKey;
static WXGSettingsNavigationState *WXGNavigationState(UINavigationController *nav,BOOL create) {
    if(!nav)return nil;
    WXGSettingsNavigationState *state=objc_getAssociatedObject(nav,&WXGNavigationStateKey);
    if(!state && create) {
        state=[WXGSettingsNavigationState new];state.navigation=nav;state.barWasHidden=nav.navigationBarHidden;
        objc_setAssociatedObject(nav,&WXGNavigationStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
// FIX106 I: whether the settings still hold this navigation's bar (diagnostics).
BOOL WXGSettingsHoldsNavigation(UINavigationController *nav,BOOL *barWasHidden) {
    WXGSettingsNavigationState *state=WXGNavigationState(nav,NO);
    if(state && barWasHidden)*barWasHidden=state.barWasHidden;
    return state!=nil;
}
// FIX106 I: a safety net (the host, on every page change): no settings page
// is in this navigation any more but what WeChat had is still held (a stack
// replaced without the pages being told, a pop whose completion never came):
// WeChat gets its bar and edge swipe back as they were. Not mid-transition.
BOOL WXGSettingsReleaseStaleNavigation(UINavigationController *nav) {
    WXGSettingsNavigationState *state=WXGNavigationState(nav,NO);
    if(!state || nav.transitionCoordinator || nav.isBeingDismissed)return NO;
    for(UIViewController *controller in nav.viewControllers)if([controller isKindOfClass:WXGSettingsPage.class])return NO;
    UIGestureRecognizer *pop=nav.interactivePopGestureRecognizer;
    if(state.installed && pop.delegate==state)pop.delegate=state.original;
    BOOL changed=nav.navigationBarHidden!=state.barWasHidden;
    if(changed)[nav setNavigationBarHidden:state.barWasHidden animated:NO];
    objc_setAssociatedObject(nav,&WXGNavigationStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WXGLog(@"顶栏：插件设置已不在导航里，交还微信的导航栏（%@）",changed?(state.barWasHidden?@"隐藏":@"重新显示"):@"状态本来就对");
    return YES;
}
// FIX106 I: one of WeChat's own pages that always show its title bar (设置,
// 聊天信息) has just appeared without it, nothing of the plugin's settings is
// in its navigation and nothing is presented over it: the settings' hold (if
// any) is given back, and the bar shown.
BOOL WXGSettingsShowBarForPage(UIViewController *page) {
    UINavigationController *nav=page.navigationController;
    if(!nav || nav.topViewController!=page || nav.transitionCoordinator || nav.isBeingDismissed ||
       page.presentedViewController || nav.presentedViewController)return NO;
    for(UIViewController *controller in nav.viewControllers)if([controller isKindOfClass:WXGSettingsPage.class])return NO;
    WXGSettingsReleaseStaleNavigation(nav);
    if(!nav.navigationBarHidden)return NO;
    [nav setNavigationBarHidden:NO animated:NO];
    WXGLog(@"顶栏：%@ 出现时微信的导航栏是隐藏的（插件设置已不在导航里），已重新显示",NSStringFromClass(page.class));
    return YES;
}
@interface WXGSettingsPage () <UIColorPickerViewControllerDelegate,PHPickerViewControllerDelegate>
- (void)step:(CADisplayLink *)link;
@end
// CADisplayLink retains its target; the page is only referenced weakly.
@interface WXGSettingsTicker : NSObject
@property(nonatomic,weak) WXGSettingsPage *page;
@end
@implementation WXGSettingsTicker
- (void)step:(CADisplayLink *)link {WXGSettingsPage *page=_page;if(page)[page step:link];else[link invalidate];}
@end
@implementation WXGSettingsPage {
    UIImageView *_wallpaper;
    WXGSurface *_back,*_titleGlass,*_accent;
    UILabel *_titleLabel;
    UIColor *_barInk;
    CADisplayLink *_link;
    __weak UINavigationController *_navigation;
    NSHashTable<WXGSettingsCard *> *_cards;
    BOOL _forceGlass;
    void (^_colorChange)(UIColor *color,BOOL finished);
    NSString *_colorStart;
    BOOL _colorChanged;
    CFTimeInterval _lastColorWrite;
    void (^_imageDone)(UIImage *image);
    CGFloat _rowEdge,_rowDown;   // FIX114 C: the title row's margin and move down as laid out
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    _wallpaper=[UIImageView new];_wallpaper.contentMode=UIViewContentModeScaleAspectFill;_wallpaper.clipsToBounds=YES;[self.view addSubview:_wallpaper];
    WXGSettingsScrollView *scroll=[WXGSettingsScrollView new];
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;scroll.alwaysBounceVertical=YES;
    scroll.delaysContentTouches=NO;scroll.canCancelContentTouches=YES;scroll.backgroundColor=UIColor.clearColor;
    _scrollView=scroll;[self.view addSubview:scroll];
    _content=[UIView new];[scroll addSubview:_content];
    _cards=[NSHashTable weakObjectsHashTable];
    __weak WXGSettingsPage *weakSelf=self;
    // Icons are set (in the accent colour) by applyLook.
    _back=[self barSurface:@"back"];_back.perform=^{[weakSelf goBack];};
    _titleGlass=[self barSurface:@"title"];_titleGlass.materialOnly=YES;_titleGlass.isAccessibilityElement=NO;
    _titleLabel=[UILabel new];_titleLabel.textAlignment=NSTextAlignmentCenter;_titleLabel.text=_pageTitle;
    _titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;_titleLabel.accessibilityTraits=UIAccessibilityTraitHeader;
    [self.view addSubview:_titleLabel];
    if(_showsAccentButton){_accent=[self barSurface:@"navigationAction"];_accent.perform=^{[weakSelf editAccent];};}
    [self buildContent];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lookChanged) name:WXGSettingsUIChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configLookChanged) name:WXGSettingsChanged object:nil];   // FIX113 O: the background colour
    // 截图比例微调 resizes the glass navigation buttons; these follow it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(integrationChanged) name:@"WXGIntegrationChanged" object:nil];
    [self applyLook];
}
- (void)integrationChanged {[self.view setNeedsLayout];}
- (UIImageView *)wallpaperView {return _wallpaper;}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_link invalidate];}
- (WXGSurface *)barSurface:(NSString *)role {
    WXGSurface *surface=[[WXGSurface alloc]initWithFrame:CGRectZero];surface.role=role;
    surface.glass.glassScopeOverride=WXGGlassScopeCard;   // FIX113 O: the 设置页 range
    surface.glass.overlayHidden=YES;   // icons are UIKit images; no Metal canvas
    // The icon bitmaps already carry the accent colour; keep them as drawn.
    [surface setNativeIconSource:nil preservingColors:YES];
    [self.view addSubview:surface];surface.active=YES;[surface applyConfig];
    return surface;
}
- (void)setPageTitle:(NSString *)title {_pageTitle=[title copy];_titleLabel.text=title;self.title=title;if(self.isViewLoaded)[self.view setNeedsLayout];}
- (void)buildContent {}
- (CGFloat)layoutContentForWidth:(CGFloat)width {(void)width;return 0;}
- (WXGSettingsCard *)addCard:(BOOL)pressable {
    WXGSettingsCard *card=[[WXGSettingsCard alloc]initWithFrame:CGRectZero];card.pressable=pressable;
    card.cornerRadius=round(WXGSettingsStore.shared.cardRadius);[_content addSubview:card];[_cards addObject:card];return card;
}
- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label=[UILabel new];label.text=text;label.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor=WXGSettingsStore.shared.secondaryColor;[_content addSubview:label];return label;
}
- (void)lookChanged {[self applyLook];[self.view setNeedsLayout];}
// FIX113 O: the plain background follows its colour setting (only the image; nothing else is rebuilt).
- (void)configLookChanged {
    WXGSettingsStore *store=WXGSettingsStore.shared;BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    if(![store wallpaperForDark:dark])_wallpaper.image=WXGDefaultWallpaper(self.view.bounds.size,dark);
    // FIX114 C: this page's own title row shows the row settings at once.
    if(self.isViewLoaded && (fabs(WXGTitleRowEdge(1)-_rowEdge)>.01 || fabs(WXGTitleRowOffset(1)-_rowDown)>.01))[self.view setNeedsLayout];
}
- (void)applyLook {
    WXGSettingsStore *store=WXGSettingsStore.shared;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    _wallpaper.image=[store wallpaperForDark:dark]?:WXGDefaultWallpaper(self.view.bounds.size,dark);
    _titleLabel.textColor=store.accentColor;
    UIColor *ink=[store.accentColor resolvedColorWithTraitCollection:self.traitCollection];
    if(![ink isEqual:_barInk]) {
        _barInk=ink;
        [_back setImage:WXGInkedSymbol(@[@"chevron.left"],ink) title:nil count:nil];_back.accessibilityLabel=@"返回";
        [_accent setImage:WXGInkedSymbol(@[@"paintpalette",@"paintbrush",@"eyedropper"],ink) title:nil count:nil];_accent.accessibilityLabel=@"字体与图标强调色";
    }
    // Whole points: dragging the radius rebuilds each card at most 40 times.
    for(WXGSettingsCard *card in _cards)card.cornerRadius=round(store.cardRadius);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    [self applyLook];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b=self.view.bounds;UIEdgeInsets safe=self.view.safeAreaInsets;
    _wallpaper.frame=b;_scrollView.frame=b;
    // The glass navigation buttons' metrics (WXGIntegrationHost buildNavigation):
    // same size, edge distance and centre line as on every WeChat page.
    WXGMetrics m=WXGMeasure(b.size.width-safe.left-safe.right,WXGPreferences.shared.sizeScale);
    if(m.button>44)m=WXGMeasure(440,1);
    CGFloat centerY=MAX(safe.top+22,safe.top+m.button*.5);
    if(safe.top<20)centerY=MAX(centerY,10+m.button*.5);   // a sheet: no status bar above
    // FIX114 C: the title row's margin and move down (顶部按钮离屏幕两边 / 往下移), as on WeChat's pages.
    // (review) The cards below stay where they are (the row moves into the gap
    // above them): the slider being dragged does not move under the finger.
    CGFloat pixel=self.view.window.screen.scale?:UIScreen.mainScreen.scale;
    _rowEdge=WXGTitleRowEdge(1);_rowDown=WXGTitleRowOffset(1);
    CGFloat rowDown=round(WXGTitleRowOffset(m.scale)*pixel)/pixel,contentRowBottom=centerY+m.button*.5;
    centerY+=rowDown;
    CGFloat edge=WXGTitleRowEdge(m.scale);
    CGFloat left=safe.left+edge,right=b.size.width-safe.right-edge,midX=b.size.width*.5;
    [_back placeMaterial:CGRectMake(left,centerY-m.button*.5,m.button,m.button) inParent:self.view];
    if(_accent)[_accent placeMaterial:CGRectMake(right-m.button,centerY-m.button*.5,m.button,m.button) inParent:self.view];
    _titleLabel.font=[UIFont systemFontOfSize:17*m.scale weight:UIFontWeightSemibold];
    CGFloat limit=2*MIN(midX-(left+m.button+m.gap),(right-(_accent?m.button+m.gap:0))-midX);
    CGFloat textWidth=[_pageTitle?:@"" sizeWithAttributes:@{NSFontAttributeName:_titleLabel.font}].width;
    CGFloat tw=WXGCapsuleWidth(textWidth,0,m.button,14*m.scale,MAX(m.button,limit));
    CGRect titleRect=CGRectMake(midX-tw*.5,centerY-m.button*.5,tw,m.button);
    [_titleGlass placeMaterial:titleRect inParent:self.view];
    _titleLabel.frame=CGRectInset(titleRect,12*m.scale,0);
    [self.view bringSubviewToFront:_titleLabel];
    _sideMargin=m.edge;_contentTop=contentRowBottom+18;
    CGFloat width=b.size.width-safe.left-safe.right;
    CGFloat height=[self layoutContentForWidth:width];
    _content.frame=CGRectMake(safe.left,_contentTop,width,height);
    _scrollView.contentSize=CGSizeMake(b.size.width,_contentTop+height+MAX(safe.bottom,12)+24);
    _scrollView.verticalScrollIndicatorInsets=UIEdgeInsetsMake(_contentTop,0,safe.bottom,0);
    // New or resized glass gets its refraction mesh in this same pass, not a
    // frame later (a range switch replaces the cards on screen).
    [self tickGlass:NO];
}
- (void)tickGlass:(BOOL)force {
    CFTimeInterval time=CACurrentMediaTime();
    [_back tick:time];[_titleGlass tick:time];[_accent tick:time];
    for(WXGSettingsCard *card in _cards)[card tick:time force:force];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationController *nav=self.navigationController;_navigation=nav;
    WXGNavigationState(nav,YES);   // remembers the bar as WeChat had it
    // A freshly presented sheet starts without the bar (no slide-away).
    if(nav && !nav.navigationBarHidden)[nav setNavigationBarHidden:YES animated:animated && !nav.isBeingPresented];
    [self applyLook];
    // WeChat's display link is paused on these pages: this one drives their
    // glass, from the first frame of the push (each card takes its refraction
    // mesh as it slides onto the screen) until the page has gone.
    if(!_link) {
        WXGSettingsTicker *ticker=[WXGSettingsTicker new];ticker.page=self;
        _link=[CADisplayLink displayLinkWithTarget:ticker selector:@selector(step:)];
        _link.preferredFramesPerSecond=60;   // FIX59: springs and checks only; 120 Hz bought nothing here
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    _forceGlass=YES;   // refresh every glass once
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UINavigationController *nav=self.navigationController;UIGestureRecognizer *pop=nav.interactivePopGestureRecognizer;
    WXGSettingsNavigationState *state=WXGNavigationState(nav,YES);
    if(state && pop && pop.delegate!=state){state.original=pop.delegate;pop.delegate=state;state.installed=YES;}
    _forceGlass=YES;
}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self leaveSettingsIfNeeded:animated];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];[_link invalidate];_link=nil;
    [self leaveSettingsIfNeeded:NO];   // in case the stack was replaced without a will-disappear
}
// Gives WeChat back its bar and edge-swipe delegate once no settings page is
// on top (a page pushed over, the last settings page popped). Not while only
// covered (a presented controller, top is still this page) or while the
// whole presented sheet goes away.
- (void)leaveSettingsIfNeeded:(BOOL)animated {
    UINavigationController *nav=_navigation;WXGSettingsNavigationState *state=WXGNavigationState(nav,NO);
    if(!state || nav.isBeingDismissed || self.isBeingDismissed)return;
    UIViewController *top=nav.topViewController;
    if(top==self || [top isKindOfClass:WXGSettingsPage.class])return;
    UIGestureRecognizer *pop=nav.interactivePopGestureRecognizer;
    if(state.installed && pop.delegate==state)pop.delegate=state.original;
    if(nav.navigationBarHidden!=state.barWasHidden)[nav setNavigationBarHidden:state.barWasHidden animated:animated];
    // FIX106 I (user: WeChat's settings page, and a plugin page opened from
    // it, sometimes lost their title and back button, the list moved up by
    // the bar's height): an interactive pop (the edge swipe, or iOS 26's
    // swipe anywhere on the page) can still be cancelled; UIKit then puts the
    // bar back as it was during the swipe - hidden - and this page appears
    // again. Forgetting what WeChat had right here let the page record the
    // hidden bar as WeChat's, and hand WeChat a hidden bar when it really
    // left. What WeChat had is kept until the pop has completed.
    id<UIViewControllerTransitionCoordinator> coordinator=nav.transitionCoordinator;
    if(coordinator.isInteractive) {
        __weak UINavigationController *weakNav=nav;
        BOOL queued=[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){
            UINavigationController *n=weakNav;
            if(context.isCancelled || !n)return;
            if(WXGNavigationState(n,NO)==state)objc_setAssociatedObject(n,&WXGNavigationStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
        if(queued)return;
    }
    objc_setAssociatedObject(nav,&WXGNavigationStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)step:(CADisplayLink *)link {(void)link;[self tickGlass:_forceGlass];_forceGlass=NO;}
- (void)goBack {
    UINavigationController *nav=self.navigationController;
    if(nav.viewControllers.firstObject==self && nav.presentingViewController)
        [nav dismissViewControllerAnimated:YES completion:^{[WXGIntegrationHost.shared schedule];}];
    else [nav popViewControllerAnimated:YES];
}
- (void)editAccent {
    WXGSettingsStore *store=WXGSettingsStore.shared;
    UIColor *current=store.accentHex?WXGColor(store.accentHex):[UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection];
    [self pickColorTitled:@"字体与图标强调色" current:current alpha:NO change:^(UIColor *color,BOOL finished){
        (void)finished;store.accentHex=WXGNormalizeHex(WXGHexFromColor(color));[store save];
    }];
}
- (void)pickColorTitled:(NSString *)title current:(UIColor *)current alpha:(BOOL)alpha change:(void (^)(UIColor *,BOOL))change {
    _colorChange=[change copy];_lastColorWrite=0;_colorChanged=NO;
    _colorStart=WXGNormalizeHex(WXGHexFromColor(current?:UIColor.whiteColor));
    UIColorPickerViewController *picker=[UIColorPickerViewController new];
    picker.title=title;picker.supportsAlpha=alpha;picker.delegate=self;picker.selectedColor=current?:UIColor.whiteColor;
    [self presentViewController:picker animated:YES completion:nil];
}
// Live while dragging (at most ~15 writes a second), final on close. Closing
// without picking writes nothing: "follow the system" stays as it is.
- (void)deliverColor:(UIColor *)color final:(BOOL)final {
    if(!_colorChange || !color)return;
    if(!_colorChanged && [WXGNormalizeHex(WXGHexFromColor(color)) isEqual:_colorStart])return;
    _colorChanged=YES;_colorChange(color,final);
}
- (void)colorPickerViewController:(UIColorPickerViewController *)picker didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    (void)picker;CFTimeInterval now=CACurrentMediaTime();
    if(continuously && now-_lastColorWrite<.066)return;
    _lastColorWrite=now;[self deliverColor:color final:NO];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    // iOS 15+ uses the continuous callback above. NSProcessInfo, not
    // @available: the on-device toolchain cannot link __isPlatformVersionAtLeast.
    if([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15,0,0}])return;
    [self deliverColor:picker.selectedColor final:NO];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    if(_colorChanged)[self deliverColor:picker.selectedColor final:YES];
    _colorChange=nil;_colorChanged=NO;
}
- (void)pickImage:(void (^)(UIImage *))done {
    _imageDone=[done copy];
    PHPickerConfiguration *configuration=[PHPickerConfiguration new];
    configuration.filter=PHPickerFilter.imagesFilter;configuration.selectionLimit=1;
    PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:configuration];picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    void (^done)(UIImage *)=_imageDone;_imageDone=nil;
    NSItemProvider *item=results.firstObject.itemProvider;
    if(!done || !item)return;   // cancelled
    __weak WXGSettingsPage *weakSelf=self;
    if(![item canLoadObjectOfClass:UIImage.class]){[self imageFailed];return;}
    [item loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object,NSError *error){
        (void)error;UIImage *image=[(NSObject *)object isKindOfClass:UIImage.class]?(UIImage *)object:nil;
        dispatch_async(dispatch_get_main_queue(),^{if(image)done(image);else[weakSelf imageFailed];});
    }];
}
- (void)showMessage:(NSString *)title detail:(NSString *)detail {   // (FIX115 H: WXGConfirmResetAll below presents the same way)
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *presenter=self;
    while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)presenter=presenter.presentedViewController;
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)rebuildContent {
    if(!self.isViewLoaded)return;
    for(UIView *view in self.content.subviews.copy)[view removeFromSuperview];
    [_cards removeAllObjects];
    [self buildContent];[self applyLook];[self.view setNeedsLayout];
}
- (void)imageFailed {
    if(!self.viewIfLoaded.window)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法读取这张图片"
        message:@"若照片只在 iCloud 中，请先在“照片”里打开一次让它下载，再重新选择。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *presenter=self;while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)presenter=presenter.presentedViewController;
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end

#pragma mark - Home

@interface WXGSettingsHome : WXGSettingsPage <UITextFieldDelegate>
@end
// FIX113 O: one search result (title over where it is).
@interface WXGSearchResultRow : UIControl
@property(nonatomic,strong,readonly) UIView *highlight;
@property(nonatomic,strong,readonly) UILabel *title,*path;
@end
@implementation WXGSearchResultRow
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        _highlight=[UIView new];_highlight.userInteractionEnabled=NO;_highlight.alpha=0;[self addSubview:_highlight];
        _title=[UILabel new];_title.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        _path=[UILabel new];_path.font=[UIFont systemFontOfSize:12.5];
        for(UILabel *label in @[_title,_path]){label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=.75;label.userInteractionEnabled=NO;[self addSubview:label];}
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.bounds.size.width;_highlight.frame=self.bounds;
    _title.frame=CGRectMake(16,_path.text.length?9:18,MAX(0,w-32),22);_path.frame=CGRectMake(16,32,MAX(0,w-32),17);
}
@end
@implementation WXGSettingsHome {
    WXGSettingsCard *_header;
    UIImageView *_avatar;
    UILabel *_name,*_version;
    UISwitch *_enabled;
    NSMutableArray<UILabel *> *_sectionLabels;
    NSMutableArray<NSArray<WXGSettingsCard *> *> *_sectionCards;
    NSMutableArray<UIImageView *> *_icons;
    NSMutableArray<UILabel *> *_titles,*_subtitles;
    // FIX59: an account this build is not made for sees only this card.
    WXGLicenseState _license;
    WXGSettingsCard *_licenseCard;
    UILabel *_licenseTitle,*_licenseText;
    UIButton *_copyAccount,*_recheck;
    // FIX104: an authorized account's "授权" card (重新检测 asks the server now).
    UILabel *_licenseSubtitle;
    BOOL _recheckPending,_recheckResultWaiting;   // waiting: the answer came while this page was not on screen
    // FIX113 O: the settings search (user: a search box for all of the settings).
    WXGSettingsCard *_searchCard,*_resultsCard;
    UITextField *_searchField;
    UIImageView *_searchIcon;
    UILabel *_resultsLabel;
    NSMutableArray<WXGSearchResultRow *> *_resultRows;
    CGFloat _keyboardOverlap;
    NSMutableArray<UIView *> *_resultLines;
    NSArray<NSDictionary *> *_results;
    NSMutableArray<NSArray *> *_searchModules;   // the home cards shown (module, title, subtitle, symbols)
}
- (instancetype)init {
    if((self=[super initWithNibName:nil bundle:nil])) {
        self.pageTitle=@"设置";self.showsAccentButton=YES;
        // FIX103: the unlock server answers later; show its answer when it comes.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(licenseChanged) name:WXGLicenseChangedNotification object:nil];
    }
    return self;
}
- (void)licenseChanged {
    if(!self.isViewLoaded)return;
    WXGLicenseState state=WXGLicenseCurrentState(NO);
    // FIX104: every answer comes here (renewals every few minutes too); only
    // the one after "重新检测" says how it went.
    BOOL pending=_recheckPending && !WXGUnlockAsking(WXGLicenseCode());
    if(pending)_recheckPending=NO;
    if(state!=_license){_recheckPending=NO;[self rebuildContent];return;}
    [self updateLicenseSubtitle];
    if(pending && state==WXGLicenseAuthorized) {
        if(self.viewIfLoaded.window)[self showRecheckResult];
        else _recheckResultWaiting=YES;   // a sub-page is open, or settings were closed: shown on return
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(_recheckResultWaiting){_recheckResultWaiting=NO;if(_license==WXGLicenseAuthorized)[self showRecheckResult];}
}
// FIX115 H (user, 10-26 09:43: this export the plugin's defaults; a global
// 恢复默认参数 where it fits): the card on the home page and 基本设置's button.
void WXGResetAllSettingsToDefaults(void) {
    [WXGConfig.shared resetAllKeeping:@[@"enabled",@"settingsFloat",@"diagnosticsFloat"]];
    [WXGPreferences.shared resetToBuildDefaults];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    id radius=WXGBuildDefaultSection(@"ui")[@"cardRadius"];
    store.cardRadius=[radius isKindOfClass:NSNumber.class] && isfinite([radius doubleValue])?WXGClamp([radius doubleValue],0,40):26;
    [store save];
    [WXGIntegrationHost.shared schedule];
}
void WXGConfirmResetAll(UIViewController *page,void (^done)(void)) {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"恢复全部默认参数？"
        message:@"所有玻璃参数（各范围的折射、模糊、材质、边框，底栏、分组、透镜、气泡、渐隐、菜单圆角……）和各项功能开关、整体比例、卡片圆角回到本版的标准参数。总开关、两个悬浮按钮、壁纸、头像、强调色和你自己建的分组不变。不能撤销。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
        WXGResetAllSettingsToDefaults();
        if(WXGConfig.shared.haptics)[[[UINotificationFeedbackGenerator alloc]init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        if(done)done();
    }]];
    UIViewController *presenter=page;
    while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)presenter=presenter.presentedViewController;
    [presenter presentViewController:alert animated:YES completion:nil];
}
// module, title, subtitle, symbols (first available).
// FIX130 (user: one module for every effect, the range chosen at its top;
// the features by page; then only the settings page itself and the licence).
+ (NSArray<NSDictionary *> *)sections {
    return @[
        @{@"title":@"效果 · 底栏、其余玻璃、分组栏、气泡、设置页分别设置",
          @"cards":@[@[@"effect",@"效果调整",@"折射 · 模糊 · 材质 · 边框 · 阴影 · 透镜",@[@"drop",@"drop.fill"]]]},
        @{@"title":@"功能",@"cards":@[@[@"chat",@"聊天页",@"输入栏 · 标题与头像 · 气泡 · 菜单",@[@"bubble.left.and.bubble.right.fill",@"bubble.left.and.bubble.right",@"message"]],
                                      @[@"home",@"首页",@"分组栏 · 加号菜单 · 搜索框",@[@"rectangle.split.3x1",@"square.split.2x1",@"rectangle.split.2x1",@"rectangle"]],
                                      @[@"me",@"个人页",@"头像头部 · 下拉横幅",@[@"person.crop.circle",@"person.circle",@"person"]],
                                      @[@"dock",@"底栏",@"尺寸 · 搜索 · 图标 · 切换动作",@[@"dock.rectangle",@"rectangle.bottomthird.inset.filled",@"rectangle.bottomthird.inset.fill",@"rectangle"]],
                                      @[@"fade",@"渐进式模糊",@"聊天页 · 其余页面 · 上下距离",@[@"rectangle.topthird.inset.filled",@"rectangle.topthird.inset.fill",@"square.tophalf.fill",@"square"]],
                                      @[@"general",@"通用",@"顶部按钮 · 交互 · 性能",@[@"gearshape",@"gear"]]]},
        // 授权行不是页面，点它会重新联网检测（FIX104）；未授权时不显示（FIX106）。
        @{@"title":@"设置与授权",@"cards":@[@[@"settingsPage",@"设置页调整",@"壁纸 · 强调色 · 参数导入导出 · 诊断 · 恢复默认",@[@"slider.horizontal.3",@"photo.on.rectangle",@"photo"]],
                                           @[@"license",@"授权",@"重新联网检测授权",@[@"checkmark.seal",@"checkmark.shield",@"checkmark.circle"]]]}
    ];
}
- (void)buildContent {
    __weak WXGSettingsHome *weakSelf=self;
    _header=[self addCard:NO];
    _avatar=[UIImageView new];_avatar.contentMode=UIViewContentModeScaleAspectFill;_avatar.clipsToBounds=YES;_avatar.userInteractionEnabled=YES;
    _avatar.layer.borderWidth=1;_avatar.accessibilityLabel=@"头像";
    [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(editAvatar)]];
    _name=[UILabel new];_name.text=@"微信 Liquid Glass";_name.font=[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    _name.adjustsFontSizeToFitWidth=YES;_name.minimumScaleFactor=.75;
    _version=[UILabel new];_version.text=[self versionText];_version.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    _version.adjustsFontSizeToFitWidth=YES;_version.minimumScaleFactor=.75;
    _enabled=[UISwitch new];_enabled.on=WXGPreferences.shared.enabled;_enabled.accessibilityLabel=@"开启微信玻璃";
    [_enabled addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged];
    for(UIView *v in @[_avatar,_name,_version,_enabled])[_header.contentView addSubview:v];
    _sectionLabels=[NSMutableArray array];_sectionCards=[NSMutableArray array];
    _icons=[NSMutableArray array];_titles=[NSMutableArray array];_subtitles=[NSMutableArray array];
    _licenseCard=nil;_licenseTitle=_licenseText=nil;_copyAccount=_recheck=nil;_licenseSubtitle=nil;
    _searchCard=_resultsCard=nil;_searchField=nil;_searchIcon=nil;_resultsLabel=nil;_results=nil;
    _resultRows=[NSMutableArray array];_resultLines=[NSMutableArray array];_searchModules=[NSMutableArray array];
    _license=WXGLicenseCurrentState(YES);
    // FIX106: 未授权的普通用户根本进不到设置页（入口只在授权后出现，见 WXGHost 的启动器 /
    // 微信设置行 / 底栏长按），所以这里不再因未授权就只显示“复制账号发给作者”的提示卡。真能
    // 走到这一页的只会是绕过授权判定的人：让他看到完整功能设置、开关照常可点，但折射 / 色散 /
    // 着色器这些要服务器着色器才生效的东西始终拿不到着色器、不出现（FIX103/106），看上去就是个
    // 平平无奇、最关键效果没生效的插件。授权行只在真正授权时出现（下面过滤掉）。
    _enabled.enabled=YES;
    // FIX106: 曾授权但现在连不上 / 需更新的正当用户（能进到这页的入口只给这两种 + 已授权），
    // 只给一张极简“重新检测”卡；其余（绕过判定进来的）照常走下面的完整诱捕设置。
    if(_license==WXGLicenseUnreachable || _license==WXGLicenseOutdated){[self buildRecheckCard];return;}
    [self buildSearch];
    NSArray<NSString *> *hidden=WXGHiddenSettingsModules();
    for(NSDictionary *section in WXGSettingsHome.sections) {
        NSMutableArray *specs=[NSMutableArray array];
        for(NSArray *spec in section[@"cards"]) {
            if([hidden containsObject:spec[0]])continue;
            if([spec[0] isEqual:@"license"] && _license!=WXGLicenseAuthorized)continue;   // FIX106: 未授权不露授权行
            [specs addObject:spec];
        }
        if(!specs.count)continue;
        [_sectionLabels addObject:[self sectionLabel:section[@"title"]]];
        NSMutableArray *cards=[NSMutableArray array];
        for(NSArray *spec in specs) {
            WXGSettingsCard *card=[self addCard:YES];card.accessibilityLabel=spec[1];
            NSString *module=spec[0];BOOL license=[module isEqual:@"license"];
            if(license)card.action=^{[weakSelf recheckLicense];};
            else if([module isEqual:@"resetAll"])card.action=^{[weakSelf confirmResetAll];};   // FIX115 H
            else {card.action=^{[weakSelf openModule:module];};[_searchModules addObject:spec];}
            UIImageView *icon=[[UIImageView alloc]initWithImage:[WXGSymbol(spec[3],22,UIImageSymbolWeightMedium) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            icon.contentMode=UIViewContentModeScaleAspectFit;
            UILabel *title=[UILabel new];title.text=spec[1];title.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            title.adjustsFontSizeToFitWidth=YES;title.minimumScaleFactor=.7;
            UILabel *subtitle=[UILabel new];subtitle.text=spec[2];subtitle.font=[UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
            if(license){_licenseSubtitle=subtitle;subtitle.text=[self licenseSubtitleText];}
            subtitle.adjustsFontSizeToFitWidth=YES;subtitle.minimumScaleFactor=.75;card.accessibilityHint=spec[2];
            for(UIView *v in @[icon,title,subtitle])[card.contentView addSubview:v];
            [_icons addObject:icon];[_titles addObject:title];[_subtitles addObject:subtitle];[cards addObject:card];
        }
        [_sectionCards addObject:cards];
    }
}
- (NSString *)versionText {return [NSString stringWithFormat:@"%@ · %@",WXGIntegrationHost.shared.versionString,WXGBuildLabel()];}
- (void)confirmResetAll {   // FIX115 H
    __weak WXGSettingsHome *weakSelf=self;
    WXGConfirmResetAll(self,^{WXGSettingsHome *me=weakSelf;[me rebuildContent];[me showMessage:@"已恢复默认参数" detail:@"现在用的是本版的标准参数。"];});
}
// FIX106: 旧的“未授权”提示卡（复制账号 / 把账号和授权码发给作者 / buildLicenseCard +
// copyAccount）已删除。未授权账号根本进不到设置页，这张卡拿不到；新买家的授权码走线下
// （作者按 wxid 用 license_hash.py 入名单）。_licenseCard / _licenseText / _copyAccount 等 ivar
// 保留但恒为 nil，applyLook 与布局里对它们的引用都是对 nil 的空操作，无副作用。
// FIX106: 过期 / 连不上 / 需更新的正当用户只给这张极简“重新检测”卡（没有“复制账号发给作者”）。
// 复用原授权卡的布局（if(_licenseCard) 分支）；_copyAccount 恒为 nil，布局里对它的定位是空操作。
- (void)buildRecheckCard {
    _licenseCard=[self addCard:NO];
    _licenseTitle=[UILabel new];_licenseTitle.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _licenseText=[UILabel new];_licenseText.font=[UIFont systemFontOfSize:14];_licenseText.numberOfLines=0;
    if(_license==WXGLicenseOutdated) {
        _licenseTitle.text=@"插件需要更新";
        _licenseText.text=@"服务器上的玻璃版本和这个插件不一致，玻璃暂时停用。请安装作者发布的最新版插件后，点“重新检测”。";
    } else {
        _licenseTitle.text=@"授权需要重新检测";
        _licenseText.text=@"玻璃暂时停用：联网确认一次即可恢复（成功后 7 天内不联网也能用）。确认网络与手机时间无误后，点“重新检测”。";
    }
    _recheck=[UIButton buttonWithType:UIButtonTypeSystem];[_recheck setTitle:@"重新检测" forState:UIControlStateNormal];
    _recheck.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_recheck addTarget:self action:@selector(recheckLicense) forControlEvents:UIControlEventTouchUpInside];
    for(UIView *v in @[_licenseTitle,_licenseText,_recheck])[_licenseCard.contentView addSubview:v];
}
// FIX103: reads the account again and asks the server now (whatever the
// back-off says); the answer arrives later (licenseChanged).
// FIX104: an authorized account too (the "授权" card): the subtitle shows the
// check under way, and its answer comes as a message (licenseChanged); an
// account taken off the list loses the glass at once and sees the card below.
- (void)recheckLicense {
    WXGLicenseState state=WXGLicenseRecheckServer();
    if(state!=_license){_recheckPending=NO;[self rebuildContent];if(state==WXGLicenseAuthorized)[WXGIntegrationHost.shared schedule];return;}
    if(state==WXGLicenseAuthorized) {
        if(_recheckPending)return;   // already asking; one answer, one message
        _recheckResultWaiting=NO;
        if(WXGUnlockAsking(WXGLicenseCode())){_recheckPending=YES;[self updateLicenseSubtitle];}
        else [self showMessage:@"现在无法联网检测" detail:WXGUnlockLastError()?:@"请稍后再试。本机保存的授权仍然有效。"];
        return;
    }
    if(state==WXGLicenseChecking)[self showMessage:@"正在验证" detail:@"正在连接授权服务器，结果出来后这一页会自动更新。"];
    else if(state==WXGLicenseUnknown)[self showMessage:@"仍未读到账号" detail:@"请确认已经登录微信。若一直读不到，导出诊断（基本设置不可用时可截图此页）发给作者。"];
    else [self showMessage:state==WXGLicenseDenied?@"仍未授权":state==WXGLicenseOutdated?@"插件需要更新":@"仍然连不上" detail:WXGUnlockLastError()?:WXGLicenseAccount()];
}
- (NSString *)licenseExpiryText:(BOOL)withTime {
    NSDate *expiry=WXGUnlockExpiry(WXGLicenseCode());if(!expiry)return nil;
    NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat=withTime?@"M月d日 HH:mm":@"M月d日";
    return [formatter stringFromDate:expiry];
}
- (NSString *)licenseSubtitleText {
    if(_recheckPending)return @"正在联网检测…";
    return @"已授权";   // FIX106: 只显示状态，不再露有效期
}
- (void)updateLicenseSubtitle {_licenseSubtitle.text=[self licenseSubtitleText];}
- (void)showRecheckResult {
    // FIX106: 只告诉用户是否已授权，不再显示有效期 / 续期等细节（showRecheckResult 只在已授权时被调用）。
    [self showMessage:@"已授权" detail:nil];
}
- (void)applyLook {
    [super applyLook];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    _licenseTitle.textColor=store.accentColor;_licenseText.textColor=store.secondaryColor;
    UIColor *tint=store.controlTint?:UIColor.systemBlueColor;_copyAccount.tintColor=tint;_recheck.tintColor=tint;
    _avatar.image=store.avatar?:WXGDefaultAvatar();
    _avatar.layer.borderColor=[[UIColor.labelColor colorWithAlphaComponent:.18] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    _name.textColor=store.accentColor;_version.textColor=store.secondaryColor;
    _enabled.onTintColor=store.controlTint;
    for(UIImageView *icon in _icons)icon.tintColor=store.accentColor;
    for(UILabel *title in _titles)title.textColor=store.accentColor;
    for(UILabel *subtitle in _subtitles)subtitle.textColor=store.secondaryColor;
    for(UILabel *label in _sectionLabels)label.textColor=store.secondaryColor;
    [self applySearchLook];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(WXGLicenseCurrentState(NO)!=_license)[self rebuildContent];
    else [self updateLicenseSubtitle];   // FIX104: renewed in the background meanwhile
    _enabled.on=WXGPreferences.shared.enabled;_version.text=[self versionText];
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    // The navigation buttons' edge distance; on a wide screen (iPad) the
    // column stays at most 620 pt and is centred.
    CGFloat inner=MIN(MAX(100,width-2*self.sideMargin),620),side=(width-inner)*.5,gap=12,y=0;
    // Header: avatar, name over version, the switch.
    CGFloat headerHeight=86;
    _header.frame=CGRectMake(side,y,inner,headerHeight);
    CGFloat avatar=58;_avatar.frame=CGRectMake(14,(headerHeight-avatar)*.5,avatar,avatar);_avatar.layer.cornerRadius=avatar*.5;
    CGSize switchSize=[_enabled sizeThatFits:CGSizeZero];
    _enabled.frame=CGRectMake(inner-16-switchSize.width,(headerHeight-switchSize.height)*.5,switchSize.width,switchSize.height);
    CGFloat textX=CGRectGetMaxX(_avatar.frame)+14,textW=MAX(40,CGRectGetMinX(_enabled.frame)-12-textX);
    _name.frame=CGRectMake(textX,headerHeight*.5-25,textW,26);_version.frame=CGRectMake(textX,headerHeight*.5+3,textW,18);
    y+=headerHeight+24;
    if(_licenseCard) {
        CGFloat pad=18,w=inner-2*pad;
        _licenseTitle.frame=CGRectMake(pad,pad,w,22);
        CGFloat textHeight=ceil([_licenseText sizeThatFits:CGSizeMake(w,CGFLOAT_MAX)].height);
        _licenseText.frame=CGRectMake(pad,CGRectGetMaxY(_licenseTitle.frame)+8,w,textHeight);
        CGFloat buttonsY=CGRectGetMaxY(_licenseText.frame)+10;
        _recheck.frame=CGRectMake(inner-pad-96,buttonsY,96,40);
        _copyAccount.frame=CGRectMake(pad-8,buttonsY,96,40);
        CGFloat height=buttonsY+40+10;
        _licenseCard.frame=CGRectMake(side,y,inner,height);
        return y+height+24;
    }
    if(_searchCard) {
        CGFloat h=46;_searchCard.frame=CGRectMake(side,y,inner,h);
        _searchIcon.frame=CGRectMake(15,(h-20)*.5,20,20);
        _searchField.frame=CGRectMake(44,0,MAX(40,inner-44-8),h);
        y+=h+24;
        if(self.searching) {
            _resultsLabel.frame=CGRectMake(side+6,y,inner-12,18);y+=18+8;
            CGFloat rowY=0,hairline=1/MAX(1,UIScreen.mainScreen.scale);
            for(NSUInteger i=0;i<_resultRows.count;i++) {
                if(i && i-1<_resultLines.count)_resultLines[i-1].frame=CGRectMake(16,rowY-hairline*.5,inner-16,hairline);
                CGFloat rh=58;_resultRows[i].frame=CGRectMake(0,rowY,inner,rh);rowY+=rh;
            }
            _resultsCard.frame=CGRectMake(side,y,inner,MAX(rowY,1));
            return y+rowY+24;
        }
    }
    // Two cards a row, golden-ratio rectangles (at least 98 pt high, room for
    // the icon over the title and subtitle on a 320 pt screen).
    CGFloat column=(inner-gap)*.5,height=MAX(98,round(column/1.618));
    NSUInteger index=0;
    for(NSUInteger s=0;s<_sectionCards.count;s++) {
        _sectionLabels[s].frame=CGRectMake(side+6,y,inner-12,18);y+=18+8;
        NSArray<WXGSettingsCard *> *cards=_sectionCards[s];
        for(NSUInteger i=0;i<cards.count;i++,index++) {
            WXGSettingsCard *card=cards[i];
            card.frame=CGRectMake(side+(i%2)*(column+gap),y+(i/2)*(height+gap),column,height);
            CGFloat pad=15;
            _icons[index].frame=CGRectMake(pad,pad-1,26,26);
            _subtitles[index].frame=CGRectMake(pad,height-pad-16,column-2*pad,16);
            _titles[index].frame=CGRectMake(pad,CGRectGetMinY(_subtitles[index].frame)-24,column-2*pad,22);
        }
        NSUInteger rows=(cards.count+1)/2;
        y+=rows*height+(rows?rows-1:0)*gap+26;
    }
    return y;
}
- (void)toggleEnabled:(UISwitch *)sender {WXGPreferences.shared.enabled=sender.on;[WXGPreferences.shared save];}
#pragma mark Search
// FIX113 O: a search box under the header; while it holds text the cards
// give way to the settings found (every page, group and row), a tap opens
// the page at that row.
- (void)buildSearch {
    _searchCard=[self addCard:NO];
    _searchIcon=[[UIImageView alloc]initWithImage:[WXGSymbol(@[@"magnifyingglass"],17,UIImageSymbolWeightMedium) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _searchIcon.contentMode=UIViewContentModeScaleAspectFit;
    _searchField=[UITextField new];_searchField.font=[UIFont systemFontOfSize:16];_searchField.delegate=self;
    _searchField.clearButtonMode=UITextFieldViewModeWhileEditing;_searchField.returnKeyType=UIReturnKeySearch;
    _searchField.autocorrectionType=UITextAutocorrectionTypeNo;_searchField.autocapitalizationType=UITextAutocapitalizationTypeNone;
    _searchField.accessibilityLabel=@"搜索设置";
    [_searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    for(UIView *v in @[_searchIcon,_searchField])[_searchCard.contentView addSubview:v];
    self.scrollView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
// The results can be scrolled out from under the keyboard.
- (void)keyboardChanged:(NSNotification *)note {
    if(!self.isViewLoaded || !self.view.window)return;
    NSValue *value=note.userInfo[UIKeyboardFrameEndUserInfoKey];if(![value isKindOfClass:NSValue.class])return;
    CGRect keyboard=[self.view convertRect:value.CGRectValue fromView:nil];
    CGFloat overlap=MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(keyboard));
    if(CGRectGetMinY(keyboard)>=CGRectGetMaxY(self.view.bounds)-.5)overlap=0;
    if(fabs(overlap-_keyboardOverlap)<.5)return;
    _keyboardOverlap=overlap;
    UIScrollView *scroll=self.scrollView;UIEdgeInsets inset=scroll.contentInset,bars=scroll.verticalScrollIndicatorInsets;
    inset.bottom=overlap;bars.bottom=MAX(overlap,self.view.safeAreaInsets.bottom);
    scroll.contentInset=inset;scroll.verticalScrollIndicatorInsets=bars;
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {[field resignFirstResponder];return NO;}
- (BOOL)searching {
    return [_searchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;
}
- (void)searchChanged {
    BOOL searching=self.searching;
    for(UILabel *label in _sectionLabels)label.hidden=searching;
    for(NSArray<WXGSettingsCard *> *cards in _sectionCards)for(WXGSettingsCard *card in cards)card.hidden=searching;
    for(UIView *v in _resultRows)[v removeFromSuperview];
    for(UIView *v in _resultLines)[v removeFromSuperview];
    [_resultRows removeAllObjects];[_resultLines removeAllObjects];
    _results=searching?WXGSettingsSearch(_searchField.text,_searchModules):@[];
    if(searching && !_resultsCard){_resultsLabel=[self sectionLabel:@""];_resultsCard=[self addCard:NO];}
    _resultsCard.hidden=!searching;_resultsLabel.hidden=!searching;
    if(searching) {
        NSUInteger shown=MIN(_results.count,(NSUInteger)80);
        _resultsLabel.text=!_results.count?@"没有找到":_results.count>shown?[NSString stringWithFormat:@"找到 %lu 项（显示前 %lu 项）",(unsigned long)_results.count,(unsigned long)shown]:
                           [NSString stringWithFormat:@"找到 %lu 项",(unsigned long)_results.count];
        for(NSUInteger i=0;i<MAX(shown,(NSUInteger)1);i++) {
            NSDictionary *result=i<shown?_results[i]:nil;
            WXGSearchResultRow *row=[WXGSearchResultRow new];row.tag=(NSInteger)i;
            UILabel *title=row.title,*path=row.path;
            if(result) {
                title.text=result[@"title"];path.text=result[@"path"];
                row.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",result[@"title"],result[@"path"]];row.isAccessibilityElement=YES;
                row.accessibilityTraits=UIAccessibilityTraitButton;
                [row addTarget:self action:@selector(resultTapped:) forControlEvents:UIControlEventTouchUpInside];
                [row addTarget:self action:@selector(resultPressed:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
                [row addTarget:self action:@selector(resultReleased:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
            } else {
                title.text=@"换个词试试，比如“边框”“透镜”“悬浮”";path.text=nil;row.userInteractionEnabled=NO;
            }
            if(_resultRows.count){UIView *line=[UIView new];line.userInteractionEnabled=NO;[_resultsCard.contentView addSubview:line];[_resultLines addObject:line];}
            [_resultsCard.contentView addSubview:row];[_resultRows addObject:row];
        }
    }
    [self applySearchLook];
    [self.view setNeedsLayout];
}
- (void)resultPressed:(WXGSearchResultRow *)row {row.highlight.alpha=1;}
- (void)resultReleased:(WXGSearchResultRow *)row {
    UIView *highlight=row.highlight;
    [UIView animateWithDuration:.25 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{highlight.alpha=0;} completion:nil];
}
- (void)resultTapped:(WXGSearchResultRow *)row {
    NSInteger i=row.tag;if(i<0 || i>=(NSInteger)_results.count)return;
    NSDictionary *result=_results[(NSUInteger)i];
    [_searchField resignFirstResponder];
    UIViewController *page=WXGSettingsModulePageFocused(result[@"module"],[result[@"group"] integerValue],[result[@"row"] integerValue]);
    if(page)[self.navigationController pushViewController:page animated:YES];
}
- (void)applySearchLook {
    if(!_searchCard)return;
    WXGSettingsStore *store=WXGSettingsStore.shared;
    _searchIcon.tintColor=store.secondaryColor;
    _searchField.textColor=store.accentColor;_searchField.tintColor=store.controlTint?:UIColor.systemBlueColor;
    _searchField.attributedPlaceholder=[[NSAttributedString alloc]initWithString:@"搜索设置" attributes:@{NSForegroundColorAttributeName:store.secondaryColor}];
    _resultsLabel.textColor=store.secondaryColor;
    UIColor *line=[UIColor.labelColor colorWithAlphaComponent:.12],*pressed=[UIColor.labelColor colorWithAlphaComponent:.08];
    for(UIView *separator in _resultLines)separator.backgroundColor=line;
    for(WXGSearchResultRow *row in _resultRows) {
        row.highlight.backgroundColor=pressed;
        row.title.textColor=row.userInteractionEnabled?store.accentColor:store.secondaryColor;
        row.path.textColor=store.secondaryColor;
    }
}
- (void)openModule:(NSString *)module {
    UIViewController *page=WXGSettingsModulePage(module);
    if(page)[self.navigationController pushViewController:page animated:YES];
}
- (void)editAvatar {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"头像" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak WXGSettingsHome *weakSelf=self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"从相册选择" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        [weakSelf pickImage:^(UIImage *image){[WXGSettingsStore.shared setAvatar:image];}];
    }]];
    if(WXGSettingsStore.shared.avatar)[sheet addAction:[UIAlertAction actionWithTitle:@"恢复默认头像" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        [WXGSettingsStore.shared setAvatar:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView=_avatar;sheet.popoverPresentationController.sourceRect=_avatar.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
UIViewController *WXGIntegrationSettings(void) {return [WXGSettingsHome new];}
