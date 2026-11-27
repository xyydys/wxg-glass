#import "WXGHomeCategories.h"
#import "WXGIntegration.h"
#import <objc/message.h>

static UIVisualEffect *WXGCategoryMaterial(void) {
    Class glass=NSClassFromString(@"UIGlassEffect");
    SEL make=NSSelectorFromString(@"effectWithStyle:");
    if([glass respondsToSelector:make]) {
        UIVisualEffect *effect=((id(*)(id,SEL,NSInteger))objc_msgSend)(glass,make,0);
        SEL interactive=NSSelectorFromString(@"setInteractive:");
        if([effect respondsToSelector:interactive])((void(*)(id,SEL,BOOL))objc_msgSend)(effect,interactive,YES);
        if(effect)return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

@implementation WXGHomeCategoryBar {
    UIVisualEffectView *_material;
    UIScrollView *_strip;
    UIView *_selection,*_divider;
    NSMutableArray<UIButton *> *_buttons;
    NSMutableArray<UILabel *> *_badges;
    NSInteger _from,_to;
    CGFloat _fraction;
}
@synthesize active=_active,selectedIndex=_selectedIndex,titles=_titles;

- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        _selectedIndex=_from=_to=_tappedIndex=-1;
        _material=[[UIVisualEffectView alloc] initWithEffect:WXGCategoryMaterial()];
        _material.clipsToBounds=YES;_material.layer.cornerCurve=kCACornerCurveContinuous;
        [self addSubview:_material];
        _strip=[UIScrollView new];_strip.showsHorizontalScrollIndicator=NO;
        _strip.scrollsToTop=NO;_strip.alwaysBounceHorizontal=NO;_strip.directionalLockEnabled=YES;
        _strip.delaysContentTouches=NO;_strip.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
        [_material.contentView addSubview:_strip];
        _selection=[UIView new];_selection.userInteractionEnabled=NO;
        _selection.layer.cornerCurve=kCACornerCurveContinuous;[_strip addSubview:_selection];
        _divider=[UIView new];_divider.backgroundColor=UIColor.separatorColor;_divider.userInteractionEnabled=NO;
        [_strip addSubview:_divider];
        _buttons=[NSMutableArray array];_badges=[NSMutableArray array];
        [self refreshLook];
    }
    return self;
}
- (void)setActive:(BOOL)active {_active=active;self.userInteractionEnabled=active;}
- (void)refreshLook {
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    _selection.backgroundColor=[UIColor colorWithWhite:dark?1:0 alpha:dark?.16:.085];
    _material.layer.borderColor=[UIColor colorWithWhite:1 alpha:dark?.17:.62].CGColor;
    _material.layer.borderWidth=1./MAX(1.,self.traitCollection.displayScale);
    [self setNeedsLayout];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];[self refreshLook];
}
- (void)setTitles:(NSArray<NSString *> *)titles {
    if([_titles isEqual:titles])return;
    _titles=titles.count>5?[titles subarrayWithRange:NSMakeRange(0,5)]:[titles copy];
    for(UIButton *b in _buttons)[b removeFromSuperview];
    [_buttons removeAllObjects];[_badges removeAllObjects];
    for(NSString *name in _titles) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
        b.tag=(NSInteger)_buttons.count;
        [b setTitle:name forState:UIControlStateNormal];b.accessibilityLabel=name;
        b.titleLabel.font=[UIFont systemFontOfSize:15];
        [b setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithRed:.03 green:.75 blue:.38 alpha:1] forState:UIControlStateSelected];
        b.titleLabel.adjustsFontSizeToFitWidth=YES;b.titleLabel.minimumScaleFactor=.65;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *badge=[UILabel new];badge.textAlignment=NSTextAlignmentCenter;badge.textColor=UIColor.whiteColor;
        badge.font=[UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightSemibold];
        badge.backgroundColor=UIColor.systemRedColor;badge.clipsToBounds=YES;badge.userInteractionEnabled=NO;
        [b addSubview:badge];[_strip addSubview:b];[_buttons addObject:b];[_badges addObject:badge];
    }
    [self setNeedsLayout];
}
- (void)tapped:(UIButton *)b {
    _tappedIndex=b.tag;[self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)setDeviceTitle:(NSString *)title {
    if(_deviceTitle==title || [_deviceTitle isEqual:title])return;
    _deviceTitle=[title copy];
    NSString *symbol=nil;
    if(title.length) {
        if([title isEqual:@"iPad"] || [title isEqual:@"平板"])symbol=@"ipad";
        else if([title isEqual:@"Win"])symbol=@"desktopcomputer";
        else if([title isEqual:@"安卓"])symbol=@"iphone";
        else symbol=@"laptopcomputer";
    }
    UIImage *image=symbol?[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14]]:nil;
    [_buttons.lastObject setImage:image forState:UIControlStateNormal];[self setNeedsLayout];
}
- (void)setUnreadCounts:(NSArray<NSNumber *> *)counts {
    if([_unreadCounts isEqual:counts])return;
    _unreadCounts=[counts copy];[self setNeedsLayout];
}
- (void)setSelectedIndex:(NSInteger)index {[self returnToIndex:index];}
- (void)returnToIndex:(NSInteger)index {
    _selectedIndex=_from=_to=index;_fraction=1;[self setNeedsLayout];
}
- (void)showFrom:(NSInteger)source to:(NSInteger)destination progress:(CGFloat)fraction {
    _from=source;_to=destination;_fraction=MIN(1,MAX(0,fraction));
    [self positionSelection];
}
- (CGRect)pillFor:(NSInteger)i {
    if(i<0 || i>=(NSInteger)_buttons.count)return CGRectZero;
    return CGRectInset(_buttons[(NSUInteger)i].frame,-4,0);
}
- (void)positionSelection {
    CGRect start=[self pillFor:_from],end=[self pillFor:_to];
    BOOL hasStart=!CGRectIsEmpty(start),hasEnd=!CGRectIsEmpty(end);
    _selection.hidden=!hasStart && !hasEnd;
    CGFloat opacity=hasStart?(hasEnd?1:1-_fraction):_fraction;
    if(!hasStart)start=end;
    if(!hasEnd)end=start;
    CGFloat x=start.origin.x+(end.origin.x-start.origin.x)*_fraction;
    CGFloat w=start.size.width+(end.size.width-start.size.width)*_fraction;
    _selection.frame=CGRectMake(x,start.origin.y,w,start.size.height);
    _selection.layer.cornerRadius=start.size.height*.5;_selection.alpha=opacity;
    NSInteger marked=_fraction>=.5?_to:_from;
    for(UIButton *b in _buttons) {
        BOOL selected=b.tag==marked;
        if(b.selected==selected)continue;
        b.titleLabel.font=[UIFont systemFontOfSize:15 weight:selected?UIFontWeightSemibold:UIFontWeightRegular];
        b.selected=selected;b.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect body=CGRectInset(self.bounds,WXGCanvasPaddingX,WXGCanvasPaddingY);
    _material.frame=body;_material.layer.cornerRadius=MAX(0,body.size.height*.5);
    CGFloat height=MAX(0,body.size.height),width=MAX(0,body.size.width);
    _strip.frame=_material.bounds;
    NSUInteger n=_buttons.count;if(!n)return;
    BOOL deviceTab=_deviceTitle.length>0;
    _divider.hidden=!deviceTab;
    CGFloat base[5]={0},sum=0;
    UIFont *font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    for(NSUInteger i=0;i<n;i++) {
        BOOL device=deviceTab && i+1==n;
        NSString *name=device?_deviceTitle:_titles[i];
        base[i]=ceil([name sizeWithAttributes:@{NSFontAttributeName:font}].width)+(device?22:17);
        sum+=base[i];
    }
    // Reserve space for badges even while empty. On wide bars distribute surplus
    // between tabs; on narrow bars the five readable buttons can scroll.
    CGFloat available=MAX(0,width-16-(deviceTab?8:0));
    CGFloat slots=n-1+(deviceTab?1:0);
    CGFloat gap=MIN(7.,MAX(2.,(available-sum-16*n)/MAX(1.,slots)));
    CGFloat padding=MIN(30.,MAX(8.,(available-sum-gap*slots)/n));
    if(slots>0)gap=MAX(gap,(available-sum-padding*n)/slots);
    CGFloat x=8;
    for(NSUInteger i=0;i<n;i++) {
        UIButton *b=_buttons[i];UILabel *badge=_badges[i];BOOL device=deviceTab && i+1==n;
        if(device) {
            x+=8;_divider.frame=CGRectMake(x+gap*.5,height*.26,1,height*.48);x+=gap;
        }
        CGFloat cell=base[i]+padding;
        b.frame=CGRectMake(x,4,cell,MAX(0,height-8));
        b.layer.cornerRadius=b.bounds.size.height*.5;b.layer.cornerCurve=kCACornerCurveContinuous;
        b.layer.borderWidth=device?1./MAX(1.,self.traitCollection.displayScale):0;
        b.layer.borderColor=UIColor.separatorColor.CGColor;
        b.backgroundColor=device?UIColor.tertiarySystemFillColor:UIColor.clearColor;
        b.tintColor=UIColor.labelColor;
        NSString *name=device?_deviceTitle:_titles[i];
        if(![b.currentTitle isEqual:name])[b setTitle:name forState:UIControlStateNormal];
        x+=cell+(i+1<n?gap:0);
        NSInteger number=!device && i<_unreadCounts.count?_unreadCounts[i].integerValue:0;
        NSString *count=number>99?@"99+":number>0?[@(number) stringValue]:nil;
        CGFloat bh=MIN(15,height*.48),bw=number<0?7:MAX(bh,ceil([count sizeWithAttributes:@{NSFontAttributeName:badge.font}].width)+4);
        if(number<0)bh=bw;
        CGFloat space=number!=0?bw+3:0;
        b.contentEdgeInsets=UIEdgeInsetsMake(0,device?0:2,0,space+2);
        b.titleEdgeInsets=UIEdgeInsetsMake(0,device?4:0,0,0);
        badge.hidden=number==0;badge.text=count;
        CGFloat textWidth=MIN(MAX(0,cell-space-4),ceil([name sizeWithAttributes:@{NSFontAttributeName:b.titleLabel.font}].width));
        badge.frame=CGRectMake(MIN(cell-bw-1,(cell+textWidth+space)*.5-bw),(b.bounds.size.height-bh)*.5,bw,bh);
        badge.layer.cornerRadius=bh*.5;
        b.accessibilityLabel=name;b.accessibilityValue=number<0?@"未读":count;
    }
    _strip.contentSize=CGSizeMake(ceil(x+8),height);
    _strip.scrollEnabled=_strip.contentSize.width>width+1;
    if(!_strip.tracking && !_strip.decelerating && _selectedIndex>=0 && _strip.scrollEnabled)
        [_strip scrollRectToVisible:CGRectInset([self pillFor:_selectedIndex],-4,0) animated:NO];
    [self positionSelection];
}
- (CGFloat)currentLensX {return _selection.hidden?-1:CGRectGetMidX(_selection.frame);}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;return _active && CGRectContainsPoint(_material.frame,point);
}
- (NSDictionary *)evidence {
    return @{@"form":@"categories",@"selected":@(_selectedIndex),@"deviceTab":@(_deviceTitle.length>0)};
}
@end
