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
    for(NSString *directory in directories)
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
+ (instancetype)shared {static WXGSettingsStore *store;static dispatch_once_t once;dispatch_once(&once,^{store=[self new];});return store;}
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

// Soft colour fields for the glass to refract until a wallpaper is imported.
static UIImage *WXGDefaultWallpaper(CGSize size,BOOL dark) {
    static NSCache<NSString *,UIImage *> *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=4;});
    size=CGSizeMake(MAX(64,round(size.width)),MAX(64,round(size.height)));
    NSString *key=[NSString stringWithFormat:@"%.0fx%.0f/%d",size.width,size.height,dark];
    UIImage *image=[cache objectForKey:key];if(image)return image;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=1;format.opaque=YES;
    image=[[[UIGraphicsImageRenderer alloc]initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        CGContextRef cg=context.CGContext;CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGFloat base[8]={0};
        if(dark){CGFloat d[8]={.043,.078,.090,1, .035,.055,.078,1};memcpy(base,d,sizeof d);}
        else{CGFloat l[8]={.925,.945,.975,1, .965,.930,.950,1};memcpy(base,l,sizeof l);}
        CGFloat locations[2]={0,1};
        CGGradientRef linear=CGGradientCreateWithColorComponents(space,base,locations,2);
        CGContextDrawLinearGradient(cg,linear,CGPointZero,CGPointMake(0,size.height),0);CGGradientRelease(linear);
        // x, y (fractions of the size), radius (of the width), r, g, b, a
        static const CGFloat light[][7]={{.18,.16,.62,.55,.78,1,.85},{.88,.32,.55,1,.74,.84,.80},{.24,.62,.60,.70,.95,.82,.75},
                                         {.82,.78,.55,1,.88,.62,.70},{.40,.95,.50,.62,.70,1,.60}};
        static const CGFloat night[][7]={{.20,.16,.62,.13,.48,.52,.80},{.90,.36,.55,.20,.26,.62,.65},{.22,.64,.60,.38,.20,.48,.55},
                                         {.82,.80,.55,.12,.42,.32,.65},{.45,.98,.52,.10,.28,.48,.60}};
        const CGFloat (*blobs)[7]=dark?night:light;
        for(int i=0;i<5;i++) {
            const CGFloat *b=blobs[i];
            CGFloat colors[8]={b[3],b[4],b[5],b[6],b[3],b[4],b[5],0};
            CGGradientRef radial=CGGradientCreateWithColorComponents(space,colors,locations,2);
            CGPoint centre=CGPointMake(b[0]*size.width,b[1]*size.height);
            CGContextDrawRadialGradient(cg,radial,centre,0,centre,b[2]*size.width,0);CGGradientRelease(radial);
        }
        CGColorSpaceRelease(space);
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
        _contentView=[[UIView alloc]initWithFrame:CGRectZero];_contentView.backgroundColor=UIColor.clearColor;[self addSubview:_contentView];
        _cornerRadius=26;_feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];
    }return self;
}
- (void)setPressable:(BOOL)pressable {
    _pressable=pressable;_glass.buttonPressEffect=pressable;_contentView.userInteractionEnabled=!pressable;
    self.isAccessibilityElement=pressable;self.accessibilityTraits=pressable?UIAccessibilityTraitButton:UIAccessibilityTraitNone;
}
- (void)setCornerRadius:(CGFloat)radius {if(_cornerRadius==radius)return;_cornerRadius=radius;[self setNeedsLayout];}
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
        self.glass.maximumCornerRadius=MAX(.5,MIN(self.cornerRadius,MIN(b.size.width,b.size.height)*.5));
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
    // 截图比例微调 resizes the glass navigation buttons; these follow it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(integrationChanged) name:@"WXGIntegrationChanged" object:nil];
    [self applyLook];
}
- (void)integrationChanged {[self.view setNeedsLayout];}
- (UIImageView *)wallpaperView {return _wallpaper;}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_link invalidate];}
- (WXGSurface *)barSurface:(NSString *)role {
    WXGSurface *surface=[[WXGSurface alloc]initWithFrame:CGRectZero];surface.role=role;
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
    CGFloat left=safe.left+m.edge,right=b.size.width-safe.right-m.edge,midX=b.size.width*.5;
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
    _sideMargin=m.edge;_contentTop=CGRectGetMaxY(titleRect)+18;
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
- (void)showMessage:(NSString *)title detail:(NSString *)detail {
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

@interface WXGSettingsHome : WXGSettingsPage
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
// module, title, subtitle, symbols (first available). Four glass modules are
// set separately for the dock and for the other glass (inside the module).
+ (NSArray<NSDictionary *> *)sections {
    return @[
        @{@"title":@"通用",@"cards":@[@[@"basic",@"基本设置",@"适配开关 · 比例 · 诊断",@[@"gearshape",@"gear"]],
                                      @[@"dock",@"底栏",@"尺寸 · 搜索 · 透镜 · 胶囊",@[@"dock.rectangle",@"rectangle.bottomthird.inset.filled",@"rectangle.bottomthird.inset.fill",@"rectangle"]],
                                      @[@"tools",@"帧率与参数",@"帧率日志 · 参数导入导出",@[@"speedometer",@"gauge",@"chart.bar"]],
                                      @[@"bubble",@"液态气泡",@"文字气泡 · 单行圆角 · 颜色",@[@"bubble.left.and.bubble.right.fill",@"bubble.left.and.bubble.right",@"message"]]]},
        @{@"title":@"玻璃 · 底栏与其余玻璃分别设置",@"cards":@[@[@"refraction",@"折射强度和色散",@"强度 · 色散 · 折射宽度",@[@"drop",@"drop.fill"]],
                                      @[@"blur",@"模糊强度与范围",@"半径 · 覆盖范围 · 清晰度",@[@"aqi.medium",@"sun.haze",@"circle.dashed"]],
                                      @[@"material",@"材质强度与范围",@"底色 · 遮盖 · 边缘减弱",@[@"circle.lefthalf.filled",@"circle.lefthalf.fill"]],
                                      @[@"border",@"边框与渐隐",@"颜色 · 宽度 · 亮度 · 渐隐",@[@"square.dashed",@"app",@"square"]]]},
        // FIX106: 授权行从“通用”挪到最下面这组、降低存在感；原本这组第一张是“液态气泡”，两者对调。
        // FIX104: 授权行不是页面，点它会重新联网检测（副标题显示有效期）。
        @{@"title":@"个性化",@"cards":@[@[@"license",@"授权",@"重新联网检测授权",@[@"checkmark.seal",@"checkmark.shield",@"checkmark.circle"]],
                                       @[@"fade",@"渐隐与模糊",@"聊天页 · 其余页面 · 上下距离",@[@"rectangle.topthird.inset.filled",@"rectangle.topthird.inset.fill",@"square.tophalf.fill",@"square"]],
                                       @[@"wallpaper",@"壁纸",@"深浅色壁纸 · 卡片圆角",@[@"photo.on.rectangle",@"photo"]]]}
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
            else card.action=^{[weakSelf openModule:module];};
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
