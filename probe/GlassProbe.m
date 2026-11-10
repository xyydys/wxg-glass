// GlassProbe: an optical bench and a structure dump for the system's glass
// on iOS 26. A standalone dylib (plain Objective-C, no hooking library):
// inject it into any app where native glass works.
//
// It adds one small floating button. From its menu:
//   自动采集  native glass samples over controlled backdrops (solid greys and
//             colours, gradients, a black / white split, a fine grid), each
//             at 1x and magnified (a transform on the whole scene, so the
//             screen shows 24 px per point), light and dark; every scene is
//             captured to a PNG, with a manifest of what each file is.
//   手动截图  the key scenes one at a time, for real screenshots (the exact
//             composited pixels, should the automatic capture miss the glass).
//   导出结构  the sample glass' view and layer trees with every property the
//             runtime exposes (private layer classes, filters and their
//             inputs, effect objects), layer contents as PNGs, a keyed
//             archive and CAML of the tree, the runtime's glass-related
//             classes with their properties and methods, the CAFilter types.
// Everything goes to a folder under tmp, zipped and offered through the
// share sheet. Nothing runs until the button is tapped.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define GP_VERSION @"1"

#pragma mark Session, log

static NSString *gSession;      // the folder of the run in progress
// Unbuffered: every line reaches the file at once, so after a crash the log
// says how far it got, and the trace which property was being read.
static FILE *gLogFile,*gTraceFile;
static void GPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void GPLog(NSString *format, ...) {
    va_list args;va_start(args,format);
    NSString *line=[[NSString alloc] initWithFormat:format arguments:args];va_end(args);
    NSLog(@"[GlassProbe] %@",line);
    if(gLogFile)fprintf(gLogFile,"%s\n",line.UTF8String?:"");
}
static void GPTrace(NSString *what) {if(gTraceFile)fprintf(gTraceFile,"%s\n",what.UTF8String?:"");}
static NSString *GPRoot(void) {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:@"GlassProbe"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}
static NSString *GPBeginSession(NSString *kind) {
    NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyyMMdd_HHmmss";f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *name=[NSString stringWithFormat:@"GlassProbe_%@_%@",[f stringFromDate:NSDate.date],kind];
    gSession=[GPRoot() stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtPath:gSession withIntermediateDirectories:YES attributes:nil error:nil];
    if(gLogFile)fclose(gLogFile);
    if(gTraceFile)fclose(gTraceFile);
    gLogFile=fopen([gSession stringByAppendingPathComponent:@"log.txt"].fileSystemRepresentation,"w");
    gTraceFile=fopen([gSession stringByAppendingPathComponent:@"trace.txt"].fileSystemRepresentation,"w");
    if(gLogFile)setvbuf(gLogFile,NULL,_IONBF,0);
    if(gTraceFile)setvbuf(gTraceFile,NULL,_IONBF,0);
    GPLog(@"session %@ (probe %@)",name,GP_VERSION);
    return gSession;
}
static void GPWriteText(NSString *name,NSString *text) {
    if(!gSession || !text)return;
    NSString *path=[gSession stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void GPWriteJSON(NSString *name,id object) {
    @try {
        NSData *d=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        if(d)[d writeToFile:[gSession stringByAppendingPathComponent:name] atomically:YES];
    } @catch(NSException *e) {GPLog(@"json %@: %@",name,e.reason);}
}
static NSDictionary *GPDeviceInfo(UIWindow *window) {
    struct utsname u;uname(&u);
    UIScreen *screen=window.windowScene.screen?:UIScreen.mainScreen;
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    d[@"probe"]=GP_VERSION;
    d[@"system"]=UIDevice.currentDevice.systemVersion?:@"";
    d[@"machine"]=[NSString stringWithUTF8String:u.machine]?:@"";
    d[@"bundle"]=NSBundle.mainBundle.bundleIdentifier?:@"";
    d[@"appVersion"]=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"";
    d[@"screenScale"]=@(screen.scale);d[@"nativeScale"]=@(screen.nativeScale);
    d[@"screenPoints"]=@[@(screen.bounds.size.width),@(screen.bounds.size.height)];
    d[@"hasUIGlassEffect"]=@(NSClassFromString(@"UIGlassEffect")!=nil);
    d[@"designCompatibility"]=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIDesignRequiresCompatibility"]?:@"unset";
    d[@"reduceTransparency"]=@(UIAccessibilityIsReduceTransparencyEnabled());
    d[@"increaseContrast"]=@(UIAccessibilityDarkerSystemColorsEnabled());
    d[@"reduceMotion"]=@(UIAccessibilityIsReduceMotionEnabled());
    d[@"lowPower"]=@(NSProcessInfo.processInfo.lowPowerModeEnabled);
    d[@"brightness"]=@(screen.brightness);
    for(NSString *key in @[@"currentEDRHeadroom",@"potentialEDRHeadroom"]) {
        @try {id v=[screen valueForKey:key];if(v)d[key]=v;} @catch(__unused NSException *e) {}
    }
    uint32_t (*sdk)(void)=dlsym(RTLD_DEFAULT,"dyld_get_program_sdk_version");
    if(sdk){uint32_t v=sdk();d[@"programSDK"]=[NSString stringWithFormat:@"%u.%u.%u",v>>16,(v>>8)&255,v&255];}
    return d;
}

#pragma mark Samples of native glass

typedef NS_ENUM(NSInteger,GPKind) {GPKindGlass=0,GPKindClear,GPKindButton,GPKindCapsule,GPKindRound,GPKindToolbar,GPKindCount};
static NSString *GPKindName(GPKind k) {
    return @[@"glass44",@"clear44",@"button44",@"capsule120",@"round140",@"toolbar"][MIN((NSUInteger)k,(NSUInteger)GPKindCount-1)];
}
static const CGFloat GPRoundRadius=20;
static UIVisualEffect *GPGlassEffect(NSInteger style,NSMutableDictionary *note) {
    Class c=NSClassFromString(@"UIGlassEffect");
    if(!c){note[@"effect"]=@"no UIGlassEffect: blur";return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];}
    SEL maker=NSSelectorFromString(@"effectWithStyle:");
    id e=nil;
    if([c respondsToSelector:maker]){e=((id (*)(id,SEL,NSInteger))objc_msgSend)(c,maker,style);note[@"effect"]=[NSString stringWithFormat:@"effectWithStyle:%ld",(long)style];}
    if(!e){e=[[c alloc] init];note[@"effect"]=@"UIGlassEffect init";}
    return e;
}
// The corners as the system wants them told (cornerConfiguration), else the layer's.
static void GPCorners(UIView *v,CGFloat radius,BOOL capsule,NSMutableDictionary *note) {
    Class cc=NSClassFromString(@"UICornerConfiguration");SEL set=NSSelectorFromString(@"setCornerConfiguration:");
    id conf=nil;
    @try {
        if(cc && [v respondsToSelector:set]) {
            SEL cap=NSSelectorFromString(@"capsuleConfiguration");
            if(capsule && [cc respondsToSelector:cap]){conf=((id (*)(id,SEL))objc_msgSend)(cc,cap);note[@"corners"]=@"capsuleConfiguration";}
            if(!conf) {
                Class cr=NSClassFromString(@"UICornerRadius");SEL fixed=NSSelectorFromString(@"fixedRadius:");
                id r=[cr respondsToSelector:fixed]?((id (*)(id,SEL,CGFloat))objc_msgSend)(cr,fixed,radius):nil;
                for(NSString *name in @[@"configurationWithUniformRadius:",@"configurationWithRadius:"]) {
                    SEL s=NSSelectorFromString(name);
                    if(r && !conf && [cc respondsToSelector:s]){conf=((id (*)(id,SEL,id))objc_msgSend)(cc,s,r);note[@"corners"]=name;}
                }
            }
            if(conf)((void (*)(id,SEL,id))objc_msgSend)(v,set,conf);
        }
    } @catch(NSException *e) {conf=nil;note[@"cornersError"]=e.reason?:@"";}
    if(!conf){v.layer.cornerRadius=radius;v.layer.cornerCurve=kCACornerCurveContinuous;v.clipsToBounds=YES;note[@"corners"]=@"layer.cornerRadius";}
}
static UIView *GPMakeSample(GPKind kind,CGSize *sizeOut,NSMutableDictionary *note) {
    CGSize size=CGSizeMake(44,44);UIView *view=nil;
    UIImage *star=[UIImage systemImageNamed:@"star"];
    if(kind==GPKindButton) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
        Class bc=NSClassFromString(@"UIButtonConfiguration");SEL mk=NSSelectorFromString(@"glassButtonConfiguration");
        if([bc respondsToSelector:mk]) {
            UIButtonConfiguration *c=((id (*)(id,SEL))objc_msgSend)(bc,mk);
            c.image=star;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;b.configuration=c;note[@"button"]=@"glassButtonConfiguration";
        }else {
            UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];c.image=star;b.configuration=c;note[@"button"]=@"no glassButtonConfiguration: plain";
        }
        b.userInteractionEnabled=NO;view=b;
    }else if(kind==GPKindToolbar) {
        size=CGSizeMake(120,44);
        UIToolbar *t=[[UIToolbar alloc] initWithFrame:(CGRect){CGPointZero,size}];
        UIToolbarAppearance *a=[UIToolbarAppearance new];[a configureWithTransparentBackground];
        t.standardAppearance=a;t.scrollEdgeAppearance=a;t.compactAppearance=a;
        UIBarButtonItem *flex=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *item=[[UIBarButtonItem alloc] initWithImage:star style:UIBarButtonItemStylePlain target:nil action:nil];
        UIBarButtonItem *flex2=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        t.items=@[flex,item,flex2];t.userInteractionEnabled=NO;view=t;note[@"toolbar"]=@"one star item, centred";
    }else {
        if(kind==GPKindCapsule)size=CGSizeMake(120,44);
        if(kind==GPKindRound)size=CGSizeMake(140,90);
        UIVisualEffectView *v=[[UIVisualEffectView alloc] initWithEffect:GPGlassEffect(kind==GPKindClear?1:0,note)];
        v.frame=(CGRect){CGPointZero,size};
        GPCorners(v,kind==GPKindRound?GPRoundRadius:22,kind!=GPKindRound,note);
        v.userInteractionEnabled=NO;view=v;
    }
    view.frame=(CGRect){CGPointZero,size};
    if(sizeOut)*sizeOut=size;
    return view;
}

#pragma mark Backdrops (vector layers: sharp at any magnification)

static NSArray<NSString *> *GPAllBackdrops(void) {
    return @[@"black",@"white",@"g25",@"g50",@"g75",@"slate",@"red",@"green",@"blue",@"yellow",@"hueH",@"lumV",@"splitV",@"splitH",@"grid",@"stripes"];
}
static UIColor *GPSolid(NSString *name) {
    NSDictionary *c=@{@"black":UIColor.blackColor,@"white":UIColor.whiteColor,@"g25":[UIColor colorWithWhite:.25 alpha:1],@"g50":[UIColor colorWithWhite:.5 alpha:1],
                      @"g75":[UIColor colorWithWhite:.75 alpha:1],@"slate":[UIColor colorWithRed:56/255. green:63/255. blue:71/255. alpha:1],
                      @"red":[UIColor colorWithRed:1 green:0 blue:0 alpha:1],@"green":[UIColor colorWithRed:0 green:1 blue:0 alpha:1],
                      @"blue":[UIColor colorWithRed:0 green:0 blue:1 alpha:1],@"yellow":[UIColor colorWithRed:1 green:.8 blue:0 alpha:1]};
    return c[name];
}
// Patterns are laid around the middle of the world, sized to the sample (the
// magnified scenes only show a few dozen points around it).
static UIView *GPMakeBackdrop(NSString *name,CGFloat S) {
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(0,0,S,S)];v.userInteractionEnabled=NO;
    UIColor *solid=GPSolid(name);
    if(solid){v.backgroundColor=solid;return v;}
    CGFloat c=S*.5;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if([name isEqual:@"hueH"] || [name isEqual:@"lumV"]) {
        CAGradientLayer *g=[CAGradientLayer layer];g.frame=v.bounds;
        BOOL hue=[name isEqual:@"hueH"];NSMutableArray *colors=[NSMutableArray array];
        if(hue)for(int i=0;i<=12;i++)[colors addObject:(id)[UIColor colorWithHue:i/12. saturation:1 brightness:1 alpha:1].CGColor];
        else [colors addObjectsFromArray:@[(id)UIColor.blackColor.CGColor,(id)UIColor.whiteColor.CGColor]];
        g.colors=colors;
        // The whole range across the 66 pt around the sample.
        if(hue){g.startPoint=CGPointMake((c-33)/S,.5);g.endPoint=CGPointMake((c+33)/S,.5);}
        else {g.startPoint=CGPointMake(.5,(c-33)/S);g.endPoint=CGPointMake(.5,(c+33)/S);}
        [v.layer addSublayer:g];
    }else if([name isEqual:@"splitV"] || [name isEqual:@"splitH"]) {
        v.backgroundColor=UIColor.blackColor;
        CALayer *w=[CALayer layer];w.backgroundColor=UIColor.whiteColor.CGColor;
        w.frame=[name isEqual:@"splitV"]?CGRectMake(c,0,c,S):CGRectMake(0,0,S,c);
        [v.layer addSublayer:w];
    }else if([name isEqual:@"grid"]) {
        v.backgroundColor=[UIColor colorWithWhite:.15 alpha:1];
        UIBezierPath *lines=[UIBezierPath bezierPath],*xAxis=[UIBezierPath bezierPath],*yAxis=[UIBezierPath bezierPath];
        for(int i=-22;i<=22;i++) {
            if(i==0)continue;
            [lines moveToPoint:CGPointMake(c+i*4,c-88)];[lines addLineToPoint:CGPointMake(c+i*4,c+88)];
            [lines moveToPoint:CGPointMake(c-88,c+i*4)];[lines addLineToPoint:CGPointMake(c+88,c+i*4)];
        }
        [xAxis moveToPoint:CGPointMake(c-88,c)];[xAxis addLineToPoint:CGPointMake(c+88,c)];
        [yAxis moveToPoint:CGPointMake(c,c-88)];[yAxis addLineToPoint:CGPointMake(c,c+88)];
        NSArray *paths=@[lines,xAxis,yAxis],*colors=@[UIColor.whiteColor,[UIColor colorWithRed:1 green:.25 blue:.2 alpha:1],[UIColor colorWithRed:.2 green:.9 blue:.3 alpha:1]];
        for(NSUInteger i=0;i<3;i++) {
            CAShapeLayer *s=[CAShapeLayer layer];s.frame=v.bounds;s.path=((UIBezierPath *)paths[i]).CGPath;
            s.strokeColor=((UIColor *)colors[i]).CGColor;s.fillColor=nil;s.lineWidth=.25;[v.layer addSublayer:s];
        }
    }else if([name isEqual:@"stripes"]) {
        v.backgroundColor=[UIColor colorWithWhite:.5 alpha:1];
        CALayer *box=[CALayer layer];box.bounds=CGRectMake(0,0,240,240);box.position=CGPointMake(c,c);
        NSArray *colors=@[[UIColor colorWithRed:1 green:.23 blue:.19 alpha:1],UIColor.whiteColor,[UIColor colorWithRed:0 green:.48 blue:1 alpha:1],
                          UIColor.blackColor,[UIColor colorWithRed:.2 green:.78 blue:.35 alpha:1],[UIColor colorWithRed:1 green:.8 blue:0 alpha:1]];
        for(int i=0;i<60;i++) {
            CALayer *s=[CALayer layer];s.frame=CGRectMake(i*4,0,4,240);s.backgroundColor=((UIColor *)colors[(NSUInteger)i%colors.count]).CGColor;[box addSublayer:s];
        }
        box.transform=CATransform3DMakeRotation(M_PI_4,0,0,1);
        [v.layer addSublayer:box];v.clipsToBounds=YES;
    }
    [CATransaction commit];
    return v;
}

#pragma mark Scenes

static NSDictionary *GPScene(GPKind kind,NSString *bg,CGFloat mag,NSString *focus,BOOL dark,CGFloat dx,BOOL key) {
    return @{@"kind":@(kind),@"bg":bg,@"mag":@(mag),@"focus":focus,@"dark":@(dark),@"dx":@(dx),@"key":@(key)};
}
static NSArray<NSDictionary *> *GPBuildScenes(BOOL keyOnly) {
    NSMutableArray *all=[NSMutableArray array];
    for(int dark=1;dark>=0;dark--) {
        NSSet *key8=[NSSet setWithArray:@[@"slate",@"black",@"white",@"g50",@"hueH",@"grid",@"splitV"]];
        // Regular glass, the 44 pt round one: every backdrop, magnified and at 1x.
        for(NSString *bg in GPAllBackdrops()) {
            [all addObject:GPScene(GPKindGlass,bg,8,@"center",dark,0,[key8 containsObject:bg])];
            [all addObject:GPScene(GPKindGlass,bg,1,@"center",dark,0,[bg isEqual:@"slate"])];
        }
        // With room around it (its shadow, what it does just outside).
        for(NSString *bg in @[@"white",@"g75",@"slate",@"g50"])[all addObject:GPScene(GPKindGlass,bg,4,@"center",dark,0,[bg isEqual:@"white"] || [bg isEqual:@"slate"])];
        for(NSString *bg in @[@"black",@"white",@"g50",@"slate",@"red",@"hueH",@"splitV",@"grid"])[all addObject:GPScene(GPKindClear,bg,8,@"center",dark,0,NO)];
        for(NSString *bg in @[@"slate",@"black",@"white",@"g50",@"hueH",@"grid"]) {
            [all addObject:GPScene(GPKindButton,bg,8,@"center",dark,0,[bg isEqual:@"slate"] || [bg isEqual:@"grid"])];
            [all addObject:GPScene(GPKindButton,bg,1,@"center",dark,0,NO)];
        }
        for(NSString *bg in @[@"slate",@"black",@"white",@"g50",@"grid",@"hueH"])[all addObject:GPScene(GPKindCapsule,bg,8,@"left",dark,0,[bg isEqual:@"slate"])];
        for(NSString *bg in @[@"slate",@"grid"])[all addObject:GPScene(GPKindCapsule,bg,3,@"center",dark,0,NO)];
        for(NSString *bg in @[@"slate",@"black",@"white",@"g50",@"grid"])[all addObject:GPScene(GPKindRound,bg,8,@"corner",dark,0,[bg isEqual:@"slate"])];
        for(NSString *bg in @[@"slate",@"grid"])[all addObject:GPScene(GPKindRound,bg,2.5,@"center",dark,0,NO)];
        for(NSString *bg in @[@"slate",@"black",@"white",@"grid"])[all addObject:GPScene(GPKindToolbar,bg,8,@"center",dark,0,NO)];
        // Sub-pixel sweep at 1x: the sample moved in eighths of a pixel.
        if(dark)for(int k=1;k<8;k++)[all addObject:GPScene(GPKindGlass,@"slate",1,@"center",YES,k/24.,NO)];
    }
    if(!keyOnly)return all;
    return [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == YES"]];
}
static NSString *GPSceneName(NSDictionary *s) {
    NSString *name=[NSString stringWithFormat:@"%@_%@_%gx_%@_%@",GPKindName([s[@"kind"] integerValue]),s[@"bg"],[s[@"mag"] doubleValue],s[@"focus"],[s[@"dark"] boolValue]?@"dark":@"light"];
    double dx=[s[@"dx"] doubleValue];
    return dx>0?[name stringByAppendingFormat:@"_dx%d",(int)lround(dx*24)]:name;
}

#pragma mark Structure dump

static NSString *GPColorText(CGColorRef c) {
    if(!c)return @"nil";
    size_t n=CGColorGetNumberOfComponents(c);const CGFloat *v=CGColorGetComponents(c);
    NSMutableString *s=[NSMutableString stringWithString:@"("];
    for(size_t i=0;i<n;i++)[s appendFormat:@"%s%.4g",i?", ":"",v[i]];
    CFStringRef space=CGColorSpaceCopyName(CGColorGetColorSpace(c));
    [s appendFormat:@") %@",space?(__bridge NSString *)space:@""];
    if(space)CFRelease(space);
    return s;
}
static NSString *GPClip(NSString *s,NSUInteger max) {return s.length>max?[[s substringToIndex:max] stringByAppendingString:@"…"]:s;}

// A keyed archive of any NSCoding object, read back as plain text: every key
// it encodes with its value, whatever the class is (private filters and
// effects included).
static NSInteger GPUIDIndex(id o) {
    NSString *d=[o description];
    if(![d hasPrefix:@"<CFKeyedArchiverUID"])return -1;
    NSRange r=[d rangeOfString:@"value = "];
    return r.location==NSNotFound?-1:[[d substringFromIndex:NSMaxRange(r)] integerValue];
}
static void GPArchiveNode(NSMutableString *out,id node,NSArray *objects,NSString *indent,int depth,NSMutableSet *open) {
    NSInteger uid=GPUIDIndex(node);
    if(uid>=0) {
        if((NSUInteger)uid>=objects.count){[out appendString:@"<bad uid>"];return;}
        if([open containsObject:@(uid)]){[out appendFormat:@"<ref %ld>",(long)uid];return;}
        if(depth>14){[out appendString:@"<deep>"];return;}
        [open addObject:@(uid)];
        GPArchiveNode(out,objects[(NSUInteger)uid],objects,indent,depth+1,open);
        [open removeObject:@(uid)];
        return;
    }
    if([node isKindOfClass:NSDictionary.class]) {
        NSDictionary *d=node;NSString *cls=nil;NSInteger classUID=GPUIDIndex(d[@"$class"]);
        if(classUID>=0 && (NSUInteger)classUID<objects.count)cls=[objects[(NSUInteger)classUID] isKindOfClass:NSDictionary.class]?objects[(NSUInteger)classUID][@"$classname"]:nil;
        [out appendFormat:@"{%@",cls?:@""];
        NSString *inner=[indent stringByAppendingString:@"  "];
        for(NSString *key in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if([key isEqual:@"$class"])continue;
            [out appendFormat:@"\n%@%@ = ",inner,key];
            GPArchiveNode(out,d[key],objects,inner,depth+1,open);
        }
        [out appendFormat:@"\n%@}",indent];
    }else if([node isKindOfClass:NSArray.class]) {
        NSArray *a=node;[out appendString:@"["];
        NSString *inner=[indent stringByAppendingString:@"  "];
        NSUInteger i=0;
        for(id item in a) {
            if(i++>=400){[out appendFormat:@"\n%@… %lu more",inner,(unsigned long)(a.count-400)];break;}
            [out appendFormat:@"\n%@",inner];GPArchiveNode(out,item,objects,inner,depth+1,open);
        }
        [out appendFormat:@"\n%@]",indent];
    }else if([node isKindOfClass:NSData.class]) {
        NSData *d=node;
        if(d.length<=96)[out appendFormat:@"<data %@>",[d description]];
        else [out appendFormat:@"<data %lu bytes>",(unsigned long)d.length];
    }else if([node isKindOfClass:NSString.class])[out appendFormat:@"\"%@\"",GPClip(node,400)];
    else [out appendString:GPClip([node description]?:@"nil",400)];
}
static NSString *GPArchiveText(id object,NSData **rawOut) {
    if(!object || ![object conformsToProtocol:@protocol(NSCoding)])return nil;
    @try {
        NSError *error=nil;
        NSData *data=[NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
        if(!data)return [NSString stringWithFormat:@"<not archived: %@>",error.localizedDescription];
        if(rawOut)*rawOut=data;
        NSDictionary *plist=[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        NSArray *objects=plist[@"$objects"];id root=plist[@"$top"][@"root"];
        if(![objects isKindOfClass:NSArray.class] || !root)return @"<archive not understood>";
        NSMutableString *out=[NSMutableString string];
        GPArchiveNode(out,root,objects,@"",0,[NSMutableSet set]);
        return out;
    } @catch(NSException *e) {return [NSString stringWithFormat:@"<archive raised: %@>",e.reason];}
}

static NSSet<NSString *> *GPSkippedKeys(void) {
    static NSSet *s;static dispatch_once_t once;
    dispatch_once(&once,^{s=[NSSet setWithArray:@[@"superlayer",@"sublayers",@"mask",@"delegate",@"contents",@"presentationLayer",@"modelLayer",@"actions",@"style",
        @"superview",@"subviews",@"window",@"layer",@"description",@"debugDescription",@"hash",@"superclass",@"context",@"layoutManager",@"view",@"nextResponder"]];});
    return s;
}
static BOOL GPInteresting(id v) {
    NSString *n=NSStringFromClass([v class]);
    if([v isKindOfClass:CALayer.class] || [v isKindOfClass:UIView.class])return NO;
    return [n hasPrefix:@"CA"] || [n hasPrefix:@"_UI"] || [n hasPrefix:@"UIGlass"] || [n containsString:@"SDF"] || [n containsString:@"Glass"] || [n containsString:@"Effect"];
}
static void GPDumpProperties(NSMutableString *out,id object,Class stop,NSString *indent,int depth,NSHashTable *seen);
static NSString *GPValueText(id v,NSString *indent,int depth,NSHashTable *seen) {
    if(!v || v==NSNull.null)return @"nil";
    CFTypeRef ref=(__bridge CFTypeRef)v;
    if(CFGetTypeID(ref)==CGColorGetTypeID())return GPColorText((CGColorRef)ref);
    if(CFGetTypeID(ref)==CGImageGetTypeID())return [NSString stringWithFormat:@"<CGImage %zux%zu>",CGImageGetWidth((CGImageRef)ref),CGImageGetHeight((CGImageRef)ref)];
    if(CFGetTypeID(ref)==CGPathGetTypeID())return [NSString stringWithFormat:@"<CGPath bounds %@>",NSStringFromCGRect(CGPathGetBoundingBox((CGPathRef)ref))];
    if([v isKindOfClass:UIColor.class])return [NSString stringWithFormat:@"UIColor %@",GPColorText(((UIColor *)v).CGColor)];
    if([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class] || [v isKindOfClass:NSValue.class])return GPClip([v description],400);
    if([v isKindOfClass:NSArray.class]) {
        NSMutableString *s=[NSMutableString stringWithString:@"["];NSString *inner=[indent stringByAppendingString:@"  "];NSUInteger i=0;
        for(id item in (NSArray *)v){if(i++>=64){[s appendFormat:@"\n%@…",inner];break;}[s appendFormat:@"\n%@%@",inner,GPValueText(item,inner,depth+1,seen)];}
        [s appendFormat:@"\n%@]",indent];return s;
    }
    if(GPInteresting(v) && depth<4 && ![seen containsObject:v]) {
        [seen addObject:v];
        NSMutableString *s=[NSMutableString stringWithFormat:@"<%@ %p>",NSStringFromClass([v class]),v];
        NSString *inner=[indent stringByAppendingString:@"  "];
        GPDumpProperties(s,v,NSObject.class,inner,depth+1,seen);
        NSString *archive=GPArchiveText(v,NULL);
        if(archive)[s appendFormat:@"\n%@archive: %@",inner,[archive stringByReplacingOccurrencesOfString:@"\n" withString:[@"\n" stringByAppendingString:inner]]];
        return s;
    }
    return [NSString stringWithFormat:@"<%@> %@",NSStringFromClass([v class]),GPClip([v description]?:@"",300)];
}
// Every declared property from the object's class up to (not including) `stop`.
static void GPDumpProperties(NSMutableString *out,id object,Class stop,NSString *indent,int depth,NSHashTable *seen) {
    NSMutableSet *done=[NSMutableSet set];
    for(Class c=[object class];c && c!=stop && c!=NSObject.class;c=class_getSuperclass(c)) {
        unsigned int n=0;objc_property_t *list=class_copyPropertyList(c,&n);
        for(unsigned int i=0;i<n;i++) {
            NSString *name=@(property_getName(list[i]));
            if([done containsObject:name] || [GPSkippedKeys() containsObject:name])continue;
            [done addObject:name];
            NSString *text;
            GPTrace([NSString stringWithFormat:@"%@.%@",NSStringFromClass(c),name]);
            @try {text=GPValueText([object valueForKey:name],indent,depth,seen);} @catch(NSException *e) {text=[NSString stringWithFormat:@"<raised %@>",e.name];}
            [out appendFormat:@"\n%@%@.%@ = %@",indent,NSStringFromClass(c),name,text];
        }
        free(list);
    }
}
static NSUInteger gContentsCount;
static void GPDumpLayer(NSMutableString *out,CALayer *layer,NSString *indent,NSString *tag,NSString *prefix,NSHashTable *seen) {
    id delegate=layer.delegate;
    GPTrace([NSString stringWithFormat:@"layer %@",NSStringFromClass([layer class])]);
    [out appendFormat:@"\n%@%@<%@ %p>%@",indent,tag,NSStringFromClass([layer class]),layer,delegate?[NSString stringWithFormat:@" delegate=%@",NSStringFromClass([delegate class])]:@""];
    NSString *in2=[indent stringByAppendingString:@"    "];
    NSMutableString *chain=[NSMutableString string];
    for(Class c=class_getSuperclass([layer class]);c && c!=NSObject.class;c=class_getSuperclass(c))[chain appendFormat:@" : %@",NSStringFromClass(c)];
    [out appendFormat:@"\n%@class%@",in2,chain];
    [out appendFormat:@"\n%@frame=%@ bounds=%@ position=%@ anchor=%@",in2,NSStringFromCGRect(layer.frame),NSStringFromCGRect(layer.bounds),NSStringFromCGPoint(layer.position),NSStringFromCGPoint(layer.anchorPoint)];
    if(!CATransform3DIsIdentity(layer.transform))[out appendFormat:@"\n%@transform=%@",in2,[NSValue valueWithCATransform3D:layer.transform]];
    if(!CATransform3DIsIdentity(layer.sublayerTransform))[out appendFormat:@"\n%@sublayerTransform=%@",in2,[NSValue valueWithCATransform3D:layer.sublayerTransform]];
    [out appendFormat:@"\n%@opacity=%.4g hidden=%d masksToBounds=%d cornerRadius=%.4g cornerCurve=%@ maskedCorners=%lu",in2,layer.opacity,layer.hidden,layer.masksToBounds,
        layer.cornerRadius,layer.cornerCurve,(unsigned long)layer.maskedCorners];
    if(layer.name)[out appendFormat:@"\n%@name=%@",in2,layer.name];
    if(layer.backgroundColor)[out appendFormat:@"\n%@backgroundColor=%@",in2,GPColorText(layer.backgroundColor)];
    if(layer.borderWidth>0)[out appendFormat:@"\n%@border=%.4g %@",in2,layer.borderWidth,GPColorText(layer.borderColor)];
    if(layer.shadowOpacity>0)[out appendFormat:@"\n%@shadow opacity=%.4g radius=%.4g offset=%@ color=%@ path=%d",in2,layer.shadowOpacity,layer.shadowRadius,
        NSStringFromCGSize(layer.shadowOffset),GPColorText(layer.shadowColor),layer.shadowPath!=NULL];
    [out appendFormat:@"\n%@contentsScale=%.4g gravity=%@ contentsRect=%@ contentsCenter=%@ groupOpacity=%d edgeAA=%d rasterize=%d zPosition=%.4g",in2,layer.contentsScale,layer.contentsGravity,
        NSStringFromCGRect(layer.contentsRect),NSStringFromCGRect(layer.contentsCenter),layer.allowsGroupOpacity,layer.allowsEdgeAntialiasing,layer.shouldRasterize,layer.zPosition];
    id contents=layer.contents;
    if(contents) {
        CFTypeRef ref=(__bridge CFTypeRef)contents;
        if(CFGetTypeID(ref)==CGImageGetTypeID()) {
            NSString *file=[NSString stringWithFormat:@"%@_contents_%03lu_%@.png",prefix,(unsigned long)++gContentsCount,NSStringFromClass([layer class])];
            @try {
                NSData *png=UIImagePNGRepresentation([UIImage imageWithCGImage:(CGImageRef)ref]);
                if(png)[png writeToFile:[[gSession stringByAppendingPathComponent:@"dump"] stringByAppendingPathComponent:file] atomically:YES];
            } @catch(__unused NSException *e) {}
            [out appendFormat:@"\n%@contents=<CGImage %zux%zu bpp %zu> -> %@",in2,CGImageGetWidth((CGImageRef)ref),CGImageGetHeight((CGImageRef)ref),CGImageGetBitsPerPixel((CGImageRef)ref),file];
        }else {
            NSString *type=CFBridgingRelease(CFCopyTypeIDDescription(CFGetTypeID(ref)));
            [out appendFormat:@"\n%@contents=<%@> %@",in2,type,GPClip([contents description]?:@"",200)];
        }
    }
    for(NSString *key in @[@"compositingFilter",@"filters",@"backgroundFilters"]) {
        id v=nil;@try {v=[layer valueForKey:key];} @catch(__unused NSException *e) {}
        if(!v || ([v isKindOfClass:NSArray.class] && ![(NSArray *)v count]))continue;
        [out appendFormat:@"\n%@%@ = %@",in2,key,GPValueText(v,in2,0,seen)];
    }
    // What its class adds to CALayer (private layers: backdrops, SDF layers, portals…).
    if([layer class]!=CALayer.class)GPDumpProperties(out,layer,CALayer.class,in2,0,seen);
    if([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *s=(CAShapeLayer *)layer;
        [out appendFormat:@"\n%@shape fill=%@ stroke=%@ lineWidth=%.4g path=%@",in2,GPColorText(s.fillColor),GPColorText(s.strokeColor),s.lineWidth,
            s.path?NSStringFromCGRect(CGPathGetBoundingBox(s.path)):@"nil"];
    }
    if([layer isKindOfClass:CAGradientLayer.class]) {
        CAGradientLayer *g=(CAGradientLayer *)layer;
        [out appendFormat:@"\n%@gradient type=%@ start=%@ end=%@ locations=%@ colors=%@",in2,g.type,NSStringFromCGPoint(g.startPoint),NSStringFromCGPoint(g.endPoint),g.locations,GPValueText(g.colors,in2,0,seen)];
    }
    NSArray *animations=layer.animationKeys;
    if(animations.count)[out appendFormat:@"\n%@animations=%@",in2,[animations componentsJoinedByString:@", "]];
    NSString *in1=[indent stringByAppendingString:@"  "];
    if(layer.mask)GPDumpLayer(out,layer.mask,in1,@"mask ",prefix,seen);
    for(CALayer *sub in layer.sublayers)GPDumpLayer(out,sub,in1,@"",prefix,seen);
}
static void GPDumpView(NSMutableString *out,UIView *view,NSString *indent) {
    [out appendFormat:@"\n%@<%@ %p> frame=%@ alpha=%.3g hidden=%d clips=%d layer=%@",indent,NSStringFromClass([view class]),view,NSStringFromCGRect(view.frame),view.alpha,view.hidden,
        view.clipsToBounds,NSStringFromClass([view.layer class])];
    if([view isKindOfClass:UIVisualEffectView.class])[out appendFormat:@" effect=%@",GPClip([((UIVisualEffectView *)view).effect description]?:@"nil",300)];
    for(UIView *sub in view.subviews)GPDumpView(out,sub,[indent stringByAppendingString:@"  "]);
}
static NSString *GPDebugText(id object,NSString *selector) {
    SEL s=NSSelectorFromString(selector);
    if(![object respondsToSelector:s])return nil;
    @try {id r=((id (*)(id,SEL))objc_msgSend)(object,s);return [r isKindOfClass:NSString.class]?r:[r description];} @catch(__unused NSException *e) {return nil;}
}
static void GPCollectPrivate(UIView *view,NSMutableArray *into) {
    NSString *n=NSStringFromClass([view class]);
    if([n hasPrefix:@"_UI"] || [view isKindOfClass:UIVisualEffectView.class])[into addObject:view];
    for(UIView *sub in view.subviews)GPCollectPrivate(sub,into);
}
// One sample, in its window: its views, its layers, the debug descriptions
// of its private objects, a keyed archive and CAML of the layer tree.
static void GPDumpSample(UIView *sample,NSString *name) {
    NSString *dir=[gSession stringByAppendingPathComponent:@"dump"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    GPLog(@"dump %@: views",name);
    NSMutableString *out=[NSMutableString stringWithFormat:@"== %@ ==\n\n-- views --",name];
    @try {GPDumpView(out,sample,@"");} @catch(NSException *e) {[out appendFormat:@"\n<raised %@>",e.reason];}
    GPLog(@"dump %@: layers",name);
    [out appendString:@"\n\n-- layers --"];
    @try {GPDumpLayer(out,sample.layer,@"",@"",name,[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);} @catch(NSException *e) {[out appendFormat:@"\n<raised %@>",e.reason];}
    GPWriteText([NSString stringWithFormat:@"dump/%@_tree.txt",name],out);
    GPLog(@"dump %@: private objects",name);
    NSMutableString *priv=[NSMutableString string];NSMutableArray *views=[NSMutableArray array];GPCollectPrivate(sample,views);
    if([sample isKindOfClass:UIVisualEffectView.class] && ((UIVisualEffectView *)sample).effect)[views addObject:((UIVisualEffectView *)sample).effect];
    for(id object in views) {
        [priv appendFormat:@"\n\n==== %@ %p ====\n%@",NSStringFromClass([object class]),object,GPDebugText(object,@"_ivarDescription")?:@"(no _ivarDescription)"];
        NSString *props=GPDebugText(object,@"_propertyDescription");if(props)[priv appendFormat:@"\n%@",props];
    }
    NSString *recursive=GPDebugText(sample,@"recursiveDescription");
    if(recursive)[priv appendFormat:@"\n\n==== recursiveDescription ====\n%@",recursive];
    GPWriteText([NSString stringWithFormat:@"dump/%@_private.txt",name],priv);
    GPLog(@"dump %@: archive",name);
    NSData *raw=nil;NSString *archive=GPArchiveText(sample.layer,&raw);
    if(archive)GPWriteText([NSString stringWithFormat:@"dump/%@_archive.txt",name],archive);
    if(raw)[raw writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@"_layers.keyedarchive"]] atomically:YES];
    GPLog(@"dump %@: caml",name);
    @try {
        Class writer=NSClassFromString(@"CAMLWriter");SEL make=NSSelectorFromString(@"writerWithData:"),encode=NSSelectorFromString(@"encodeObject:");
        if([writer respondsToSelector:make]) {
            NSMutableData *data=[NSMutableData data];
            id w=((id (*)(id,SEL,id))objc_msgSend)(writer,make,data);
            if([w respondsToSelector:encode])((void (*)(id,SEL,id))objc_msgSend)(w,encode,sample.layer);
            if(data.length)[data writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@"_layers.caml"]] atomically:YES];
            GPLog(@"dump %@: caml %lu bytes",name,(unsigned long)data.length);
        }else GPLog(@"no CAMLWriter");
    } @catch(NSException *e) {GPLog(@"caml raised %@",e.reason);}
}
// The runtime's own description of everything glass-like in the system
// frameworks: classes, their properties and their methods.
static void GPDumpRuntime(void) {
    GPLog(@"runtime: classes");
    NSArray *anywhere=@[@"Glass",@"SDF",@"Lens",@"Solarium",@"Liquid",@"Refraction",@"Specular"];
    NSArray *inQuartz=@[@"Highlight",@"Displacement",@"Backdrop",@"Portal",@"Material",@"Filter",@"Effect",@"Mesh"];
    unsigned int count=0;Class *classes=objc_copyClassList(&count);
    NSMutableArray<NSString *> *names=[NSMutableArray array];
    for(unsigned int i=0;i<count;i++) {
        const char *image=class_getImageName(classes[i]);if(!image)continue;
        NSString *path=@(image);
        if(![path hasPrefix:@"/System/"] && ![path hasPrefix:@"/usr/lib/"])continue;
        NSString *name=@(class_getName(classes[i]));BOOL hit=NO;
        for(NSString *k in anywhere)if([name containsString:k]){hit=YES;break;}
        if(!hit && [path containsString:@"QuartzCore"])for(NSString *k in inQuartz)if([name containsString:k]){hit=YES;break;}
        if(hit)[names addObject:name];
    }
    free(classes);
    [names sortUsingSelector:@selector(compare:)];
    NSMutableString *out=[NSMutableString stringWithFormat:@"%lu classes\n",(unsigned long)names.count];
    for(NSString *name in names) {
        if(out.length>6*1024*1024){[out appendString:@"\n… cut\n"];break;}
        Class c=NSClassFromString(name);if(!c)continue;
        const char *image=class_getImageName(c);
        [out appendFormat:@"\n@interface %@ : %@   // %@",name,NSStringFromClass(class_getSuperclass(c)),image?[@(image) lastPathComponent]:@"?"];
        unsigned int n=0;objc_property_t *props=class_copyPropertyList(c,&n);
        for(unsigned int i=0;i<n;i++)[out appendFormat:@"\n  @property %s  (%s)",property_getName(props[i]),property_getAttributes(props[i])?:""];
        free(props);
        Method *methods=class_copyMethodList(object_getClass(c),&n);
        for(unsigned int i=0;i<n && i<300;i++)[out appendFormat:@"\n  + %s  %s",sel_getName(method_getName(methods[i])),method_getTypeEncoding(methods[i])?:""];
        free(methods);
        methods=class_copyMethodList(c,&n);
        for(unsigned int i=0;i<n && i<500;i++)[out appendFormat:@"\n  - %s  %s",sel_getName(method_getName(methods[i])),method_getTypeEncoding(methods[i])?:""];
        free(methods);
        [out appendString:@"\n@end\n"];
    }
    GPWriteText(@"dump/classes.txt",out);
    GPLog(@"runtime: filters");
    NSMutableString *filters=[NSMutableString string];
    @try {
        Class filter=NSClassFromString(@"CAFilter");SEL types=NSSelectorFromString(@"filterTypes");
        if([filter respondsToSelector:types]) {
            NSArray *list=((id (*)(id,SEL))objc_msgSend)(filter,types);
            [filters appendFormat:@"CAFilter filterTypes (%lu):\n%@\n",(unsigned long)list.count,[list componentsJoinedByString:@"\n"]];
            SEL make=NSSelectorFromString(@"filterWithType:");
            for(NSString *type in list) {
                if(![type isKindOfClass:NSString.class] || ![filter respondsToSelector:make])continue;
                id f=((id (*)(id,SEL,id))objc_msgSend)(filter,make,type);
                NSString *archive=GPArchiveText(f,NULL);
                [filters appendFormat:@"\n---- %@ (defaults) ----\n%@\n",type,archive?:@""];
            }
        }
    } @catch(NSException *e) {[filters appendFormat:@"\n<raised %@>",e.reason];}
    GPWriteText(@"dump/filters.txt",filters);
    GPLog(@"runtime: images and frameworks");
    NSMutableString *images=[NSMutableString string];
    NSArray *words=@[@"Glass",@"Material",@"SDF",@"Lens",@"Liquid",@"Solarium",@"QuartzCore",@"UIKitCore",@"CoreUI",@"SwiftUICore"];
    for(uint32_t i=0;i<_dyld_image_count();i++) {
        const char *n=_dyld_get_image_name(i);if(!n)continue;NSString *name=@(n);
        for(NSString *w in words)if([name.lastPathComponent containsString:w]){[images appendFormat:@"%@\n",name];break;}
    }
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *base in @[@"/System/Library/PrivateFrameworks",@"/System/Library/Frameworks"]) {
        for(NSString *item in [fm contentsOfDirectoryAtPath:base error:nil]?:@[]) {
            BOOL hit=NO;for(NSString *w in words)if([item containsString:w]){hit=YES;break;}
            if(!hit)continue;
            NSString *dir=[base stringByAppendingPathComponent:item];
            [images appendFormat:@"\n%@/\n",dir];
            NSUInteger listed=0;
            for(NSString *sub in [fm subpathsOfDirectoryAtPath:dir error:nil]?:@[]) {
                if(listed++>400){[images appendString:@"  …\n"];break;}
                NSString *path=[dir stringByAppendingPathComponent:sub];
                NSDictionary *attr=[fm attributesOfItemAtPath:path error:nil];
                if([attr[NSFileType] isEqual:NSFileTypeDirectory])continue;
                unsigned long long size=[attr[NSFileSize] unsignedLongLongValue];
                [images appendFormat:@"  %@  %llu\n",sub,size];
                NSString *ext=sub.pathExtension.lowercaseString;
                BOOL small=[@[@"plist",@"json",@"materialrecipe",@"visualstyleset",@"caml",@"strings",@"txt"] containsObject:ext] && size>0 && size<=300*1024;
                BOOL named=NO;for(NSString *w in @[@"lass",@"aterial",@"ens",@"SDF",@"olarium"])if([sub containsString:w])named=YES;
                if(small && (named || ![ext isEqual:@"strings"]) && ![sub containsString:@".lproj/"]) {
                    NSString *to=[[[gSession stringByAppendingPathComponent:@"dump/resources"] stringByAppendingPathComponent:item] stringByAppendingPathComponent:[sub stringByReplacingOccurrencesOfString:@"/" withString:@"__"]];
                    [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [fm copyItemAtPath:path toPath:to error:nil];
                }
            }
        }
    }
    GPWriteText(@"dump/images_and_frameworks.txt",images);
}

#pragma mark Capture

static UIImage *GPCapture(UIWindow *window,CGRect rect,BOOL *drew) {
    UIScreen *screen=window.windowScene.screen?:UIScreen.mainScreen;CGFloat scale=screen.scale;
    rect=CGRectMake(round(rect.origin.x*scale)/scale,round(rect.origin.y*scale)/scale,round(rect.size.width*scale)/scale,round(rect.size.height*scale)/scale);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.scale=scale;format.opaque=YES;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:rect.size format:format];
    __block BOOL ok=NO;
    UIImage *image=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        ok=[window drawViewHierarchyInRect:CGRectMake(-rect.origin.x,-rect.origin.y,window.bounds.size.width,window.bounds.size.height) afterScreenUpdates:YES];
    }];
    if(drew)*drew=ok;
    return image;
}
// The brightest and darkest channel values of an image, and how much of it
// differs from its top-left pixel (does the capture show the glass at all).
static NSDictionary *GPImageStats(UIImage *image) {
    CGImageRef cg=image.CGImage;if(!cg)return @{};
    size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg);if(!w || !h || w*h>4000*4000)return @{};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,w,h,8,w*4,space,(CGBitmapInfo)kCGImageAlphaNoneSkipLast);CGColorSpaceRelease(space);
    if(!ctx)return @{};
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    const uint8_t *p=CGBitmapContextGetData(ctx);size_t stride=CGBitmapContextGetBytesPerRow(ctx);
    int lo=255,hi=0;size_t differing=0;const uint8_t *first=p;
    for(size_t y=0;y<h;y+=2)for(size_t x=0;x<w;x+=2) {
        const uint8_t *q=p+y*stride+x*4;
        for(int c=0;c<3;c++){if(q[c]<lo)lo=q[c];if(q[c]>hi)hi=q[c];}
        if(abs(q[0]-first[0])+abs(q[1]-first[1])+abs(q[2]-first[2])>6)++differing;
    }
    NSDictionary *out=@{@"min":@(lo),@"max":@(hi),@"differing":@((double)differing/((double)(w/2)*(double)(h/2)))};
    CGContextRelease(ctx);
    return out;
}

#pragma mark The bench

@interface GPProbe : NSObject
+ (instancetype)shared;
- (void)install;
@end
@interface GPWindow : UIWindow
@end
@interface GPRootController : UIViewController
@end
@implementation GPRootController
- (BOOL)shouldAutorotate {return NO;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskPortrait;}
@end

@implementation GPProbe {
    GPWindow *_window;UIButton *_button;
    UIView *_bench,*_stage,*_world,*_sample;UILabel *_label;UIButton *_cancel;
    NSArray<NSDictionary *> *_scenes;NSUInteger _index;NSInteger _mode;   // 1 auto, 2 manual, 3 dump
    NSMutableArray *_records;NSMutableDictionary *_sampleNote;CGRect _captureRect;CGPoint _focus;
    BOOL _cancelled,_lastDark,_styleKnown;NSUInteger _token;
    @public BOOL benchVisible;
}
+ (instancetype)shared {static GPProbe *p;static dispatch_once_t once;dispatch_once(&once,^{p=[GPProbe new];});return p;}
- (UIButton *)floatingButton {return _button;}
- (void)install {
    if(_window)return;
    UIWindowScene *scene=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if([s isKindOfClass:UIWindowScene.class] && (s.activationState==UISceneActivationStateForegroundActive || !scene))scene=(UIWindowScene *)s;
    if(!scene)return;
    _window=[[GPWindow alloc] initWithWindowScene:scene];
    _window.frame=scene.coordinateSpace.bounds;_window.windowLevel=UIWindowLevelAlert+200;_window.backgroundColor=UIColor.clearColor;
    _window.rootViewController=[GPRootController new];_window.rootViewController.view.backgroundColor=UIColor.clearColor;
    _window.hidden=NO;
    _button=[UIButton buttonWithType:UIButtonTypeCustom];
    CGRect b=_window.bounds;
    _button.frame=CGRectMake(b.size.width-52,b.size.height*.42,44,44);
    _button.backgroundColor=[UIColor colorWithRed:.1 green:.5 blue:1 alpha:.9];_button.layer.cornerRadius=22;
    [_button setTitle:@"探" forState:UIControlStateNormal];_button.titleLabel.font=[UIFont boldSystemFontOfSize:17];
    [_button addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [_button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [_window.rootViewController.view addSubview:_button];
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    CGPoint t=[pan translationInView:_window];[pan setTranslation:CGPointZero inView:_window];
    CGPoint c=_button.center;c.x+=t.x;c.y+=t.y;
    c.x=MAX(22,MIN(_window.bounds.size.width-22,c.x));c.y=MAX(60,MIN(_window.bounds.size.height-60,c.y));
    _button.center=c;
}
- (void)openMenu {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"玻璃探针" message:[NSString stringWithFormat:@"iOS %@ · UIGlassEffect %@",UIDevice.currentDevice.systemVersion,
        NSClassFromString(@"UIGlassEffect")?@"有":@"没有（这个系统上抓不到原生玻璃）"] preferredStyle:UIAlertControllerStyleAlert];
    __weak GPProbe *weak=self;
    [menu addAction:[UIAlertAction actionWithTitle:@"① 自动采集（约 3 分钟）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[weak start:1];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"② 导出结构（约 15 秒）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[weak start:3];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"③ 手动截图（自动的图里没有玻璃时用）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[weak start:2];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"分享已有结果" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[weak shareAll];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"隐藏探针（重启 App 恢复）" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){[weak hide];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [_window.rootViewController presentViewController:menu animated:YES completion:nil];
}
- (void)hide {_window.hidden=YES;}

- (void)showBench {
    [_bench removeFromSuperview];
    CGRect b=_window.bounds;UIEdgeInsets safe=_window.safeAreaInsets;
    _bench=[[UIView alloc] initWithFrame:b];_bench.backgroundColor=UIColor.blackColor;
    CGFloat S=floor(MIN(MIN(b.size.width,(b.size.height-safe.top-safe.bottom)*.62),400)/2)*2;
    _stage=[[UIView alloc] initWithFrame:CGRectMake(floor((b.size.width-S)/2),ceil(safe.top)+6,S,S)];
    _stage.clipsToBounds=YES;_stage.backgroundColor=UIColor.blackColor;[_bench addSubview:_stage];
    _label=[[UILabel alloc] initWithFrame:CGRectMake(12,CGRectGetMaxY(_stage.frame)+10,b.size.width-24,90)];
    _label.textColor=UIColor.whiteColor;_label.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];_label.numberOfLines=0;
    [_bench addSubview:_label];
    _cancel=[UIButton buttonWithType:UIButtonTypeSystem];_cancel.frame=CGRectMake(b.size.width/2-60,b.size.height-safe.bottom-64,120,44);
    [_cancel setTitle:@"停止" forState:UIControlStateNormal];[_cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _cancel.backgroundColor=[UIColor colorWithWhite:.25 alpha:1];_cancel.layer.cornerRadius=22;
    [_cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[_bench addSubview:_cancel];
    [_window.rootViewController.view addSubview:_bench];
    _button.hidden=YES;benchVisible=YES;
    UIApplication.sharedApplication.idleTimerDisabled=YES;
}
- (void)closeBench {
    [_bench removeFromSuperview];_bench=nil;_stage=nil;_world=nil;_sample=nil;
    _button.hidden=NO;benchVisible=NO;_window.overrideUserInterfaceStyle=UIUserInterfaceStyleUnspecified;_styleKnown=NO;
    UIApplication.sharedApplication.idleTimerDisabled=NO;
}
- (void)cancel {_cancelled=YES;[self finish];}

// Builds scene `s` in the stage: backdrop, a fresh sample in its middle, the
// whole world magnified about the focus point.
- (void)buildScene:(NSDictionary *)s {
    [_world removeFromSuperview];
    CGFloat S=_stage.bounds.size.width,mag=[s[@"mag"] doubleValue],dx=[s[@"dx"] doubleValue];
    BOOL dark=[s[@"dark"] boolValue];
    _window.overrideUserInterfaceStyle=dark?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
    _world=[[UIView alloc] initWithFrame:_stage.bounds];_world.userInteractionEnabled=NO;
    [_world addSubview:GPMakeBackdrop(s[@"bg"],S)];
    CGSize size=CGSizeZero;_sampleNote=[NSMutableDictionary dictionary];
    GPKind kind=[s[@"kind"] integerValue];
    _sample=GPMakeSample(kind,&size,_sampleNote);
    _sample.frame=CGRectMake((S-size.width)/2+dx,(S-size.height)/2,size.width,size.height);
    [_world addSubview:_sample];
    CGPoint focus=CGPointMake(S/2,S/2);
    if([s[@"focus"] isEqual:@"left"])focus.x=S/2-size.width/2+size.height/2;
    if([s[@"focus"] isEqual:@"corner"])focus=CGPointMake(S/2-size.width/2+GPRoundRadius,S/2-size.height/2+GPRoundRadius);
    _focus=focus;
    _world.transform=CGAffineTransformTranslate(CGAffineTransformMakeScale(mag,mag),S/2-focus.x,S/2-focus.y);
    [_stage addSubview:_world];
    CGRect crop=_stage.bounds;
    if(mag<2) {
        CGFloat side=MIN(S,ceil(MAX(size.width,size.height)*mag)+76);
        crop=CGRectMake((S-side)/2,(S-side)/2,side,side);
    }
    _captureRect=[_stage convertRect:crop toView:_window];
}
- (void)start:(NSInteger)mode {
    if(benchVisible)return;
    _mode=mode;_cancelled=NO;_index=0;_records=[NSMutableArray array];++_token;
    GPBeginSession(mode==1?@"auto":mode==2?@"manual":@"dump");
    [self showBench];
    GPWriteJSON(@"device.json",GPDeviceInfo(_window));
    if(mode==3) {
        _scenes=@[GPScene(GPKindGlass,@"slate",1,@"center",YES,0,NO),GPScene(GPKindClear,@"slate",1,@"center",YES,0,NO),GPScene(GPKindButton,@"slate",1,@"center",YES,0,NO),
                  GPScene(GPKindToolbar,@"slate",1,@"center",YES,0,NO),GPScene(GPKindGlass,@"white",1,@"center",NO,0,NO)];
    }else _scenes=GPBuildScenes(mode==2);
    GPLog(@"mode %ld, %lu scenes",(long)mode,(unsigned long)_scenes.count);
    if(mode==2) {
        _cancel.hidden=YES;
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(manualTap:)];
        UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manualHold:)];hold.minimumPressDuration=.8;
        [_bench addGestureRecognizer:tap];[_bench addGestureRecognizer:hold];
        [self showManual];
    }else [self step];
}
- (void)showManual {
    NSDictionary *s=_scenes[_index];
    [self buildScene:s];
    _label.text=[NSString stringWithFormat:@"#%lu/%lu  %@\n等约 1 秒再截图 · 点右半屏下一张 · 点左半屏上一张 · 长按结束",(unsigned long)_index+1,(unsigned long)_scenes.count,GPSceneName(s)];
}
- (void)manualTap:(UITapGestureRecognizer *)tap {
    BOOL next=[tap locationInView:_bench].x>_bench.bounds.size.width/2;
    if(next && _index+1<_scenes.count)++_index;else if(!next && _index>0)--_index;else if(next){[self finish];return;}
    [self showManual];
}
- (void)manualHold:(UILongPressGestureRecognizer *)hold {if(hold.state==UIGestureRecognizerStateBegan)[self finish];}
- (void)step {
    if(_cancelled || _index>=_scenes.count){[self finish];return;}
    NSDictionary *s=_scenes[_index];
    BOOL dark=[s[@"dark"] boolValue],flipped=!_styleKnown || dark!=_lastDark;_lastDark=dark;_styleKnown=YES;
    [self buildScene:s];
    _label.text=[NSString stringWithFormat:@"%@ %lu/%lu\n%@",_mode==3?@"导出结构":@"自动采集",(unsigned long)_index+1,(unsigned long)_scenes.count,GPSceneName(s)];
    NSUInteger token=_token;__weak GPProbe *weak=self;
    // A fresh glass view settles (it fades in and adapts to what is under it).
    double wait=_mode==3?1.4:(flipped?1.6:.85);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(wait*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weak shoot:token];});
}
- (void)shoot:(NSUInteger)token {
    if(token!=_token || !_bench)return;
    NSDictionary *s=_scenes[_index];NSString *name=GPSceneName(s);
    @autoreleasepool {
        NSMutableDictionary *record=[s mutableCopy];
        record[@"name"]=name;record[@"note"]=[_sampleNote copy]?:@{};
        record[@"captureRect"]=@[@(_captureRect.origin.x),@(_captureRect.origin.y),@(_captureRect.size.width),@(_captureRect.size.height)];
        record[@"stage"]=@[@(_stage.frame.origin.x),@(_stage.frame.origin.y),@(_stage.frame.size.width),@(_stage.frame.size.height)];
        record[@"focusInWorld"]=@[@(_focus.x),@(_focus.y)];
        record[@"sampleInWorld"]=@[@(_sample.frame.origin.x),@(_sample.frame.origin.y),@(_sample.frame.size.width),@(_sample.frame.size.height)];
        if(_mode==3) {
            GPDumpSample(_sample,[NSString stringWithFormat:@"%02lu_%@",(unsigned long)_index+1,name]);
        }
        BOOL drew=NO;UIImage *image=GPCapture(_window,_captureRect,&drew);
        NSString *file=[NSString stringWithFormat:@"scenes/s%03lu_%@.png",(unsigned long)_index+1,name];
        NSString *path=[gSession stringByAppendingPathComponent:file];
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *png=image?UIImagePNGRepresentation(image):nil;
        [png writeToFile:path atomically:YES];
        record[@"file"]=file;record[@"drew"]=@(drew);
        record[@"pixels"]=@[@(image.size.width*image.scale),@(image.size.height*image.scale)];
        BOOL flat=GPSolid(s[@"bg"])!=nil;
        if(image && (flat || _index%8==0))record[@"stats"]=GPImageStats(image);
        [_records addObject:record];
        if(_index%10==0)GPLog(@"scene %lu %@ drew=%d %lu bytes",(unsigned long)_index+1,name,drew,(unsigned long)png.length);
    }
    ++_index;
    [self step];
}
- (void)finish {
    ++_token;
    NSInteger mode=_mode;NSUInteger shot=_records.count;
    // Did the captures show any glass: on a flat backdrop a capture with
    // glass in it has pixels that differ from the backdrop.
    NSUInteger flat=0,withGlass=0;
    for(NSDictionary *r in _records){NSNumber *d=r[@"stats"][@"differing"];if(d && GPSolid(r[@"bg"])){++flat;if(d.doubleValue>.002)++withGlass;}}
    if(mode!=2) {
        GPWriteJSON(@"manifest.json",@{@"device":GPDeviceInfo(_window),@"scenes":_records?:@[],@"cancelled":@(_cancelled),@"flatScenes":@(flat),@"flatScenesShowingGlass":@(withGlass)});
    }
    if(mode==3 && !_cancelled) {
        _label.text=@"导出结构：系统里和玻璃有关的类…";
        @try {GPDumpRuntime();} @catch(NSException *e) {GPLog(@"runtime raised %@",e.reason);}
    }
    GPLog(@"finished: %lu captures, flat %lu, showing glass %lu",(unsigned long)shot,(unsigned long)flat,(unsigned long)withGlass);
    NSString *session=gSession;
    [self closeBench];
    if(mode==2){[self message:@"手动截图结束" text:@"把刚才截的图原图发过来（相册里的 PNG，不要压缩、不要放大裁剪）。"];return;}
    NSString *text=mode==3?@"结构已导出。":[NSString stringWithFormat:@"拍了 %lu 张。纯色背景的 %lu 张里有 %lu 张能看到玻璃。%@",(unsigned long)shot,(unsigned long)flat,(unsigned long)withGlass,
        (flat>4 && withGlass*2<flat)?@"\n自动采集看起来没抓到玻璃：请再用“③ 手动截图”。":@""];
    [self share:session message:text];
}
- (void)message:(NSString *)title text:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [_window.rootViewController presentViewController:a animated:YES completion:nil];
}
// Zips a folder (the system does it for an upload read) and offers it.
- (NSURL *)zip:(NSString *)folder {
    NSURL *source=[NSURL fileURLWithPath:folder isDirectory:YES];
    NSURL *target=[NSURL fileURLWithPath:[[GPRoot() stringByAppendingPathComponent:folder.lastPathComponent] stringByAppendingPathExtension:@"zip"]];
    [NSFileManager.defaultManager removeItemAtURL:target error:nil];
    __block BOOL ok=NO;NSError *error=nil;
    [[NSFileCoordinator new] coordinateReadingItemAtURL:source options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *zipped) {
        ok=[NSFileManager.defaultManager copyItemAtURL:zipped toURL:target error:nil];
    }];
    return ok?target:nil;
}
- (void)share:(NSString *)folder message:(NSString *)text {
    NSURL *zip=[self zip:folder];
    if(!zip){[self message:@"没能打包" text:[NSString stringWithFormat:@"%@\n文件在 %@",text,folder]];return;}
    __weak GPProbe *weak=self;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"完成" message:[NSString stringWithFormat:@"%@\n把这个 zip 发过来（隔空投送、存到“文件”都行）。",text] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"分享 zip" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[weak present:@[zip]];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
    [_window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)present:(NSArray *)items {
    UIActivityViewController *vc=[[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    vc.popoverPresentationController.sourceView=_button;
    [_window.rootViewController presentViewController:vc animated:YES completion:nil];
}
- (void)shareAll {
    NSMutableArray *zips=[NSMutableArray array];
    for(NSString *item in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:GPRoot() error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *path=[GPRoot() stringByAppendingPathComponent:item];BOOL dir=NO;
        if([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&dir] && dir){NSURL *zip=[self zip:path];if(zip)[zips addObject:zip];}
    }
    if(!zips.count){[self message:@"还没有结果" text:@"先做一次自动采集或导出结构。"];return;}
    [self present:zips];
}
@end

@implementation GPWindow
- (BOOL)_canAffectStatusBarAppearance {return NO;}   // the app keeps its own status bar
// Only the probe's own button takes touches, unless its bench or a sheet is up.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    GPProbe *probe=GPProbe.shared;
    if(self.rootViewController.presentedViewController || probe->benchVisible)return hit;
    return hit==[probe floatingButton]?hit:nil;
}
@end

__attribute__((constructor)) static void GPStart(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[GPProbe.shared install];});
    }];
}
