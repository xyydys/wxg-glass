#import "WXGMenuMorphContent.h"

static const CGFloat WXGMenuContentInset=10.;
static const CGFloat WXGMenuRowInset=10.;
static const CGFloat WXGMenuRowHeight=36.;
static const CGFloat WXGMenuDividerHeight=21.;
static const CGFloat WXGMenuDividerInset=24.;
static const CGFloat WXGMenuIconCenter=37.;
static const CGFloat WXGMenuTitleInset=58.;
static const CGFloat WXGMenuTrailingInset=26.;
static const CGFloat WXGMenuChevronSpace=14.;

typedef NS_ENUM(NSUInteger,WXGMenuAction) {
    WXGMenuActionOther,
    WXGMenuActionGroupChat,
    WXGMenuActionAddFriend,
    WXGMenuActionScan,
    WXGMenuActionPay,
    WXGMenuActionLive,
    WXGMenuActionDock,
    WXGMenuActionDisplay,
};

static WXGMenuAction WXGActionForMenuTitle(NSString *title) {
    static NSDictionary<NSString *,NSNumber *> *actions;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        actions=@{
            @"发起群聊":@(WXGMenuActionGroupChat), @"發起群聊":@(WXGMenuActionGroupChat),
            @"new chat":@(WXGMenuActionGroupChat), @"new group chat":@(WXGMenuActionGroupChat),
            @"start a group chat":@(WXGMenuActionGroupChat),
            @"添加朋友":@(WXGMenuActionAddFriend), @"add contacts":@(WXGMenuActionAddFriend),
            @"add friends":@(WXGMenuActionAddFriend), @"add friend":@(WXGMenuActionAddFriend),
            @"扫一扫":@(WXGMenuActionScan), @"掃一掃":@(WXGMenuActionScan), @"扫描":@(WXGMenuActionScan),
            @"scan":@(WXGMenuActionScan), @"scan qr code":@(WXGMenuActionScan),
            @"收付款":@(WXGMenuActionPay), @"pay":@(WXGMenuActionPay), @"money":@(WXGMenuActionPay),
            @"payment":@(WXGMenuActionPay), @"payments":@(WXGMenuActionPay),
            @"直播":@(WXGMenuActionLive), @"live":@(WXGMenuActionLive), @"live stream":@(WXGMenuActionLive),
            @"显示模式":@(WXGMenuActionDisplay), @"顯示模式":@(WXGMenuActionDisplay),
            @"display mode":@(WXGMenuActionDisplay),
        };
    });
    NSString *key=[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if([key hasPrefix:@"底栏形变"] || [key hasPrefix:@"底欄形變"])return WXGMenuActionDock;
    return (WXGMenuAction)actions[key].unsignedIntegerValue;
}

static UIImage *WXGMenuIcon(WXGMenuAction action,UIImage *nativeIcon,CGFloat *size) {
    NSString *symbol=nil;
    UIImageSymbolWeight weight=UIImageSymbolWeightRegular;
    switch(action) {
        case WXGMenuActionGroupChat: symbol=@"bubble.left.and.bubble.right.fill";*size=20.5;break;
        case WXGMenuActionAddFriend: symbol=@"person.badge.plus";*size=17.;break;
        case WXGMenuActionScan: symbol=@"qrcode.viewfinder";*size=15.;break;
        case WXGMenuActionPay: symbol=@"qrcode";*size=14.5;break;
        case WXGMenuActionLive: symbol=@"dot.radiowaves.left.and.right";*size=17.;break;
        case WXGMenuActionDock: symbol=@"capsule";*size=17.5;weight=UIImageSymbolWeightLight;break;
        case WXGMenuActionDisplay: symbol=@"list.bullet";*size=15.5;break;
        default: *size=18.;break;
    }
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:*size weight:weight];
    UIImage *image=symbol?[UIImage systemImageNamed:symbol withConfiguration:config]:nil;
    return image?:nativeIcon;
}

static void WXGMenuDrawImage(UIImage *image,CGPoint center,CGFloat size,UIColor *color) {
    if(image.size.width<=0 || image.size.height<=0)return;
    CGFloat fit=size/MAX(image.size.width,image.size.height);
    CGSize dimensions=CGSizeMake(image.size.width*fit,image.size.height*fit);
    CGRect rect=CGRectMake(center.x-dimensions.width*.5,center.y-dimensions.height*.5,dimensions.width,dimensions.height);
    [[image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:rect];
}

static void WXGMenuDrawDivider(CGContextRef context,CGFloat width,CGFloat y,CGFloat scale,BOOL dark) {
    CGFloat inset=MIN(WXGMenuDividerInset,width*.2);
    CGRect line=CGRectMake(inset,floor(y*scale)/scale,width-2.*inset,1./scale);
    UIColor *color=dark?UIColor.whiteColor:UIColor.blackColor;
    NSArray *colors=@[(__bridge id)[color colorWithAlphaComponent:dark?.12:.10].CGColor,
                      (__bridge id)[color colorWithAlphaComponent:0.].CGColor];
    CGGradientRef gradient=CGGradientCreateWithColors(NULL,(__bridge CFArrayRef)colors,NULL);
    if(!gradient)return;
    CGContextSaveGState(context);
    CGContextClipToRect(context,line);
    CGContextDrawLinearGradient(context,gradient,CGPointMake(inset,y),CGPointMake(width-inset,y),0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
}

@interface WXGMenuMorphContent ()
@property(nonatomic,readwrite) CGSize size;
@property(nonatomic,readwrite) CGFloat panelCornerRadius;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *titles;
@property(nonatomic,copy,readwrite) NSArray<NSValue *> *rowFrames;
@property(nonatomic,strong,readwrite) UIImage *image;
@property(nonatomic,strong,readwrite) UIColor *highlightColor;
@end

@implementation WXGMenuMorphContent
+ (instancetype)contentWithTitles:(NSArray<NSString *> *)titles
                       nativeIcons:(NSArray *)nativeIcons
                      submenuRows:(NSIndexSet *)submenuRows
                 dividerBeforeRows:(NSIndexSet *)dividerBeforeRows
                        panelWidth:(CGFloat)panelWidth
                   traitCollection:(UITraitCollection *)traits
                             scale:(CGFloat)scale {
    if(!titles.count || !isfinite(panelWidth) || panelWidth<1.)return nil;
    if(!isfinite(scale) || scale<1.)scale=1.;
    BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *foreground=[(dark?UIColor.whiteColor:UIColor.blackColor) colorWithAlphaComponent:dark?245./255.:235./255.];
    CGFloat fontScale=MIN(1.35,[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledValueForValue:1. compatibleWithTraitCollection:traits]);
    UIFont *font=[UIFont systemFontOfSize:14.*fontScale weight:UIFontWeightRegular];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];
    paragraph.alignment=NSTextAlignmentLeft;
    paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    NSDictionary *attributes=@{NSFontAttributeName:font,NSForegroundColorAttributeName:foreground,
                               NSParagraphStyleAttributeName:paragraph,NSKernAttributeName:@(-.012*font.pointSize)};

    NSMutableIndexSet *dividers=dividerBeforeRows?[dividerBeforeRows mutableCopy]:[NSMutableIndexSet indexSet];
    NSMutableArray<NSNumber *> *actions=[NSMutableArray arrayWithCapacity:titles.count];
    for(NSString *title in titles)[actions addObject:@(WXGActionForMenuTitle(title))];
    if(!dividerBeforeRows && actions.count>4 && actions[0].unsignedIntegerValue==WXGMenuActionGroupChat &&
       actions[1].unsignedIntegerValue==WXGMenuActionAddFriend && actions[2].unsignedIntegerValue==WXGMenuActionScan &&
       actions[3].unsignedIntegerValue==WXGMenuActionPay) {
        NSUInteger firstExtra=actions[4].unsignedIntegerValue==WXGMenuActionLive?5:4;
        if(firstExtra<actions.count)[dividers addIndex:firstExtra];
    }

    size_t pixelWidth=(size_t)floor(panelWidth*scale);
    CGFloat width=pixelWidth/scale;
    CGFloat rowInset=MIN(WXGMenuRowInset,width*.2);
    CGFloat rowHeight=WXGMenuRowHeight*MAX(1.,fontScale);
    CGFloat y=WXGMenuContentInset;
    NSMutableArray<NSValue *> *frames=[NSMutableArray arrayWithCapacity:titles.count];
    for(NSUInteger i=0;i<titles.count;i++) {
        if(i && [dividers containsIndex:i])y+=WXGMenuDividerHeight;
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(rowInset,y,width-2.*rowInset,rowHeight)]];
        y+=rowHeight;
    }
    size_t pixelHeight=(size_t)ceil((y+WXGMenuContentInset)*scale);
    CGColorSpaceRef colorSpace=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if(!colorSpace)return nil;
    CGContextRef context=CGBitmapContextCreate(NULL,pixelWidth,pixelHeight,8,0,colorSpace,
                                               kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if(!context)return nil;
    CGContextTranslateCTM(context,0,pixelHeight);
    CGContextScaleCTM(context,scale,-scale);
    UIGraphicsPushContext(context);
    UIImage *chevron=[UIImage systemImageNamed:@"chevron.right" withConfiguration:
                      [UIImageSymbolConfiguration configurationWithPointSize:9. weight:UIImageSymbolWeightSemibold]];
    for(NSUInteger i=0;i<titles.count;i++) {
        CGRect row=frames[i].CGRectValue;
        CGFloat center=CGRectGetMidY(row);
        if(i && [dividers containsIndex:i])WXGMenuDrawDivider(context,width,CGRectGetMinY(row)-WXGMenuDividerHeight*.5,scale,dark);
        id candidate=i<nativeIcons.count?nativeIcons[i]:nil;
        UIImage *nativeIcon=[candidate isKindOfClass:UIImage.class]?candidate:nil;
        CGFloat iconSize=0.;
        UIImage *icon=WXGMenuIcon((WXGMenuAction)actions[i].unsignedIntegerValue,nativeIcon,&iconSize);
        BOOL submenu=[submenuRows containsIndex:i];
        BOOL iconFits=icon && width>=WXGMenuTitleInset+WXGMenuTrailingInset;
        CGFloat left=iconFits?WXGMenuTitleInset:MIN(28.,width*.2);
        CGFloat right=MIN(WXGMenuTrailingInset,width*.2)+(submenu?WXGMenuChevronSpace:0.);
        if(iconFits)WXGMenuDrawImage(icon,CGPointMake(WXGMenuIconCenter,center),iconSize,foreground);
        if(submenu)WXGMenuDrawImage(chevron,CGPointMake(width-right+WXGMenuChevronSpace-.5,center),9.,foreground);
        CGRect textRect=CGRectMake(left,center-font.lineHeight*.5,MAX(0.,width-left-right),ceil(font.lineHeight)+1.);
        [titles[i] drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingTruncatesLastVisibleLine
                    attributes:attributes context:nil];
    }
    UIGraphicsPopContext();
    CGImageRef bitmap=CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if(!bitmap)return nil;
    UIImage *image=[UIImage imageWithCGImage:bitmap scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(bitmap);

    WXGMenuMorphContent *content=[self new];
    content.size=image.size;
    // The first and last rows have the same height and inset. Derive the
    // outer corner from the original selection capsule without moving any row.
    CGRect row=frames.firstObject.CGRectValue;
    CGFloat capsuleRadius=MIN(row.size.width,row.size.height)*.5;
    CGFloat outerRadius=capsuleRadius+MIN(CGRectGetMinX(row),CGRectGetMinY(row));
    content.panelCornerRadius=MIN(outerRadius,MIN(image.size.width,image.size.height)*.5);
    content.titles=titles;
    content.rowFrames=frames;
    content.image=image;
    content.highlightColor=dark?[UIColor colorWithRed:235./255. green:235./255. blue:245./255. alpha:.155]:
                                [UIColor colorWithRed:60./255. green:60./255. blue:67./255. alpha:.09];
    return content;
}
@end
