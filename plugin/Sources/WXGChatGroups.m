#import "WXGSettingsKit.h"

/* FIX113 R (user: "cannot set a group, cannot add a new one"): the settings
   pages for the chat list's groups (WXGChatGroupList in WXGChatSegments.m).
   管理分组: the groups in the bar's order (1-6), each renamed, given another
   rule, moved, deleted; a new one added; the defaults back. A custom group's
   chats are chosen on the next page from WeChat's home list (names are read
   here only, never written to the diagnostics). */

static NSString *WXGGroupRuleText(NSDictionary *group) {
    switch([group[@"rule"] integerValue]) {
        case 0:return @"微信原来的完整列表";
        case 1:return @"有未读或 @ 的聊天";
        case 2:return @"个人聊天（不含公众号、服务通知这类）";
        case 3:return @"群聊（含折叠的群聊）";
        default:return [NSString stringWithFormat:@"自定义 · %lu 个聊天",(unsigned long)[group[@"members"] count]];
    }
}
static NSArray<NSString *> *WXGGroupRuleNames(void) {return @[@"全部（完整列表）",@"未读",@"单聊",@"群聊",@"自定义（自己选聊天）"];}

// One row: a title over a line of detail, a chevron; pressed it tints.
@interface WXGGroupRow : UIControl
@property(nonatomic,strong,readonly) UILabel *title,*detail,*chevron;
@property(nonatomic,strong,readonly) UIView *highlight;
@end
@implementation WXGGroupRow
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        _highlight=[UIView new];_highlight.userInteractionEnabled=NO;_highlight.alpha=0;[self addSubview:_highlight];
        _title=[UILabel new];_title.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        _detail=[UILabel new];_detail.font=[UIFont systemFontOfSize:12.5];
        _chevron=[UILabel new];_chevron.text=@"›";_chevron.font=[UIFont systemFontOfSize:22 weight:UIFontWeightRegular];_chevron.textAlignment=NSTextAlignmentRight;
        for(UILabel *label in @[_title,_detail,_chevron]){label.userInteractionEnabled=NO;[self addSubview:label];}
        _title.adjustsFontSizeToFitWidth=_detail.adjustsFontSizeToFitWidth=YES;_title.minimumScaleFactor=_detail.minimumScaleFactor=.75;
        [self addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(released) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
        self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    }
    return self;
}
- (void)pressed {_highlight.alpha=1;}
- (void)released {[UIView animateWithDuration:.25 animations:^{self->_highlight.alpha=0;}];}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;_highlight.frame=self.bounds;
    BOOL two=_detail.text.length>0;
    _title.frame=CGRectMake(16,two?9:(h-22)*.5,MAX(0,w-52),22);_detail.frame=CGRectMake(16,32,MAX(0,w-52),17);
    _chevron.frame=CGRectMake(w-40,0,26,h);
}
@end

#pragma mark - Members

@interface WXGGroupMembersPage : WXGSettingsPage <UITableViewDataSource,UITableViewDelegate,UITextFieldDelegate>
- (instancetype)initWithGroup:(NSString *)groupID;
@end
@implementation WXGGroupMembersPage {
    NSString *_groupID;
    NSMutableOrderedSet<NSString *> *_members;
    NSArray<NSDictionary *> *_choices,*_shown;
    WXGSettingsCard *_searchCard;
    UITextField *_search;
    UIImageView *_searchIcon;
    UITableView *_table;
    UILabel *_empty,*_nameNote;
    BOOL _changed;
}
- (instancetype)initWithGroup:(NSString *)groupID {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _groupID=[groupID copy];
        NSDictionary *group=nil;for(NSDictionary *g in WXGChatGroupList())if([g[@"id"] isEqual:groupID])group=g;
        self.pageTitle=group[@"name"]?:@"选择聊天";
        _members=[NSMutableOrderedSet orderedSetWithArray:group[@"members"]?:@[]];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(saveMembers) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)buildContent {
    // The chats of the home list; ones chosen before that are not in it now
    // (deleted, folded away) stay chosen and are listed at the end.
    NSMutableArray *choices=[WXGChatSessionChoices() mutableCopy]?:[NSMutableArray array];
    NSMutableSet *known=[NSMutableSet set];for(NSDictionary *c in choices)[known addObject:c[@"id"]];
    for(NSString *member in _members)if(![known containsObject:member])[choices addObject:@{@"id":member,@"title":@"（不在当前列表里的聊天）",@"kind":@(-1)}];
    _choices=choices;_shown=choices;
    _searchCard=[self addCard:NO];
    _searchIcon=[[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"magnifyingglass"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _searchIcon.contentMode=UIViewContentModeScaleAspectFit;
    _search=[UITextField new];_search.font=[UIFont systemFontOfSize:16];_search.delegate=self;_search.clearButtonMode=UITextFieldViewModeWhileEditing;
    _search.returnKeyType=UIReturnKeySearch;_search.autocorrectionType=UITextAutocorrectionTypeNo;
    [_search addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    for(UIView *v in @[_searchIcon,_search])[_searchCard.contentView addSubview:v];
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;_table.rowHeight=56;
    _table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;_table.tableFooterView=[UIView new];
    _table.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    // FIX113 Z: how many names were read and from where (no names).
    NSString *summary=WXGChatNameSummary();
    if(summary.length) {
        _nameNote=[UILabel new];_nameNote.numberOfLines=0;_nameNote.font=[UIFont systemFontOfSize:12];_nameNote.text=summary;
        UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,10)];[header addSubview:_nameNote];_table.tableHeaderView=header;
    }
    [self.view addSubview:_table];
    _empty=[UILabel new];_empty.numberOfLines=0;_empty.textAlignment=NSTextAlignmentCenter;_empty.font=[UIFont systemFontOfSize:14];
    _empty.text=@"还没有读到微信首页的聊天列表。\n先回到微信首页，让聊天列表显示一次（打开过“通讯录”页的话，那里的好友和群也会列出来），再来这里选。";
    _empty.hidden=_choices.count>0;[self.view addSubview:_empty];
    self.scrollView.scrollEnabled=NO;
}
- (void)applyLook {
    [super applyLook];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    _searchIcon.tintColor=store.secondaryColor;_search.textColor=store.accentColor;_search.tintColor=store.controlTint?:UIColor.systemBlueColor;
    [self updatePlaceholder];
    _table.separatorColor=[UIColor.labelColor colorWithAlphaComponent:.12];_table.tintColor=store.controlTint?:UIColor.systemBlueColor;
    _empty.textColor=store.secondaryColor;_nameNote.textColor=store.secondaryColor;
    [_table reloadData];
}
- (void)updatePlaceholder {
    NSString *text=[NSString stringWithFormat:@"搜索聊天（已选 %lu 个）",(unsigned long)_members.count];
    _search.attributedPlaceholder=[[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName:WXGSettingsStore.shared.secondaryColor}];
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat inner=MIN(MAX(100,width-2*self.sideMargin),620),side=(width-inner)*.5,h=46;
    _searchCard.frame=CGRectMake(side,0,inner,h);
    _searchIcon.frame=CGRectMake(15,(h-20)*.5,20,20);_search.frame=CGRectMake(44,0,MAX(40,inner-52),h);
    return h;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b=self.view.bounds;UIEdgeInsets safe=self.view.safeAreaInsets;
    CGFloat top=self.contentTop+46+12;
    _table.frame=CGRectMake(safe.left,top,b.size.width-safe.left-safe.right,MAX(0,b.size.height-top));
    _table.contentInset=UIEdgeInsetsMake(0,0,safe.bottom+12,0);
    _empty.frame=CGRectMake(24,top+40,b.size.width-48,80);
    UIView *header=_table.tableHeaderView;
    if(_nameNote && header) {
        CGFloat w=_table.bounds.size.width,inner=MAX(40,w-32);
        CGFloat h=ceil([_nameNote sizeThatFits:CGSizeMake(inner,CGFLOAT_MAX)].height);
        _nameNote.frame=CGRectMake(16,4,inner,h);
        if(fabs(header.frame.size.height-(h+12))>.5 || fabs(header.frame.size.width-w)>.5){header.frame=CGRectMake(0,0,w,h+12);_table.tableHeaderView=header;}
    }
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {[field resignFirstResponder];return NO;}
- (void)searchChanged {
    NSString *q=[_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!q.length)_shown=_choices;
    else {
        NSMutableArray *shown=[NSMutableArray array];
        for(NSDictionary *c in _choices)if([c[@"title"] rangeOfString:q options:NSCaseInsensitiveSearch|NSWidthInsensitiveSearch].location!=NSNotFound)[shown addObject:c];
        _shown=shown;
    }
    [_table reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {(void)tableView;(void)section;return (NSInteger)_shown.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"member"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"member"];
    cell.backgroundColor=UIColor.clearColor;
    NSDictionary *c=indexPath.row<(NSInteger)_shown.count?_shown[(NSUInteger)indexPath.row]:nil;
    WXGSettingsStore *store=WXGSettingsStore.shared;
    cell.textLabel.text=c[@"title"];cell.textLabel.textColor=store.accentColor;cell.textLabel.font=[UIFont systemFontOfSize:16];
    NSInteger kind=[c[@"kind"] integerValue];
    NSString *kindText=kind==3?@"群聊":kind==2?@"单聊":kind==0?@"公众号":@"";
    if(c[@"inList"] && ![c[@"inList"] boolValue])kindText=[kindText stringByAppendingString:@" · 通讯录里的，当前不在聊天列表"];
    cell.detailTextLabel.text=kindText;cell.detailTextLabel.textColor=store.secondaryColor;
    cell.accessoryType=c && [_members containsObject:c[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    UIView *selected=[UIView new];selected.backgroundColor=[UIColor.labelColor colorWithAlphaComponent:.08];cell.selectedBackgroundView=selected;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row>=(NSInteger)_shown.count)return;
    NSString *member=_shown[(NSUInteger)indexPath.row][@"id"];
    if([_members containsObject:member])[_members removeObject:member];else [_members addObject:member];
    _changed=YES;[self updatePlaceholder];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self saveMembers];}
- (void)saveMembers {
    if(!_changed)return;_changed=NO;
    NSMutableArray *groups=[NSMutableArray array];
    for(NSDictionary *g in WXGChatGroupList()) {
        if(![g[@"id"] isEqual:_groupID]){[groups addObject:g];continue;}
        NSMutableDictionary *m=[g mutableCopy];m[@"members"]=_members.array;[groups addObject:m];
    }
    WXGChatGroupSave(groups);
}
@end

#pragma mark - Groups

@interface WXGGroupsPage : WXGSettingsPage
@end
@implementation WXGGroupsPage {
    UILabel *_label,*_footer;
    WXGSettingsCard *_listCard,*_actionsCard;
    NSMutableArray<WXGGroupRow *> *_rows,*_actions;
    NSMutableArray<UIView *> *_lines;
}
- (instancetype)init {
    if((self=[super initWithNibName:nil bundle:nil])) {
        self.pageTitle=@"管理分组";
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(groupsChanged) name:WXGChatGroupsChanged object:nil];
    }
    return self;
}
- (void)groupsChanged {if(self.isViewLoaded)[self rebuildContent];}
- (void)buildContent {
    NSArray<NSDictionary *> *groups=WXGChatGroupList();
    _rows=[NSMutableArray array];_actions=[NSMutableArray array];_lines=[NSMutableArray array];
    _label=[self sectionLabel:[NSString stringWithFormat:@"分组 %lu / 6 · 从左到右就是分组栏的顺序",(unsigned long)groups.count]];
    _listCard=[self addCard:NO];
    for(NSUInteger i=0;i<groups.count;i++) {
        WXGGroupRow *row=[WXGGroupRow new];row.tag=(NSInteger)i;
        row.title.text=groups[i][@"name"];row.detail.text=WXGGroupRuleText(groups[i]);
        row.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",row.title.text,row.detail.text];
        [row addTarget:self action:@selector(groupTapped:) forControlEvents:UIControlEventTouchUpInside];
        if(_rows.count){UIView *line=[UIView new];line.userInteractionEnabled=NO;[_listCard.contentView addSubview:line];[_lines addObject:line];}
        [_listCard.contentView addSubview:row];[_rows addObject:row];
    }
    _actionsCard=[self addCard:NO];
    NSArray *titles=@[groups.count<6?@"新建分组":@"新建分组（已满 6 个）",@"恢复默认分组"];
    for(NSUInteger i=0;i<titles.count;i++) {
        WXGGroupRow *row=[WXGGroupRow new];row.tag=(NSInteger)i;row.title.text=titles[i];row.chevron.text=@"";
        row.accessibilityLabel=titles[i];row.enabled=i!=0 || groups.count<6;
        [row addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
        if(_actions.count){UIView *line=[UIView new];line.userInteractionEnabled=NO;[_actionsCard.contentView addSubview:line];[_lines addObject:line];}
        [_actionsCard.contentView addSubview:row];[_actions addObject:row];
    }
    _footer=[UILabel new];_footer.numberOfLines=0;_footer.font=[UIFont systemFontOfSize:12.5];
    _footer.text=@"点一个分组可以改名、换类型、左右移动或删除；“自定义”的分组自己选里面有哪些聊天（单聊、群聊、公众号都可以）。分组栏上点哪个，聊天列表就只显示那一组，置顶的照样在前；“全部”类型就是微信原来的列表。每次打开微信，从第一个“全部”类型的分组开始。";
    [self.content addSubview:_footer];
}
- (void)applyLook {
    [super applyLook];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    _label.textColor=store.secondaryColor;_footer.textColor=store.secondaryColor;
    UIColor *line=[UIColor.labelColor colorWithAlphaComponent:.12],*pressed=[UIColor.labelColor colorWithAlphaComponent:.08];
    for(UIView *v in _lines)v.backgroundColor=line;
    for(WXGGroupRow *row in [_rows arrayByAddingObjectsFromArray:_actions?:@[]]) {
        row.highlight.backgroundColor=pressed;row.title.textColor=row.enabled?store.accentColor:store.secondaryColor;
        row.detail.textColor=store.secondaryColor;row.chevron.textColor=store.secondaryColor;
    }
    if(_actions.count>1)_actions[1].title.textColor=UIColor.systemRedColor;
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat inner=MIN(MAX(100,width-2*self.sideMargin),620),side=(width-inner)*.5,y=0,hairline=1/MAX(1,UIScreen.mainScreen.scale);
    _label.frame=CGRectMake(side+6,y,inner-12,18);y+=26;
    CGFloat rowY=0;NSUInteger line=0;
    for(NSUInteger i=0;i<_rows.count;i++) {
        if(i && line<_lines.count)_lines[line++].frame=CGRectMake(16,rowY-hairline*.5,inner-16,hairline);
        _rows[i].frame=CGRectMake(0,rowY,inner,58);rowY+=58;
    }
    _listCard.frame=CGRectMake(side,y,inner,MAX(rowY,1));y+=rowY+24;
    rowY=0;
    for(NSUInteger i=0;i<_actions.count;i++) {
        if(i && line<_lines.count)_lines[line++].frame=CGRectMake(16,rowY-hairline*.5,inner-16,hairline);
        _actions[i].frame=CGRectMake(0,rowY,inner,50);rowY+=50;
    }
    _actionsCard.frame=CGRectMake(side,y,inner,MAX(rowY,1));y+=rowY;
    CGSize size=[_footer sizeThatFits:CGSizeMake(inner-12,CGFLOAT_MAX)];
    _footer.frame=CGRectMake(side+6,y+7,inner-12,ceil(size.height));y+=7+ceil(size.height)+24;
    return y;
}
- (void)saveChanging:(NSString *)groupID with:(void (^)(NSMutableDictionary *group))change {
    NSMutableArray *groups=[NSMutableArray array];
    for(NSDictionary *g in WXGChatGroupList()) {
        if(![g[@"id"] isEqual:groupID]){[groups addObject:g];continue;}
        NSMutableDictionary *m=[g mutableCopy];change(m);[groups addObject:m];
    }
    WXGChatGroupSave(groups);
}
- (void)present:(UIAlertController *)alert from:(UIView *)source {
    alert.popoverPresentationController.sourceView=source?:self.view;
    alert.popoverPresentationController.sourceRect=source?source.bounds:CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)askName:(NSString *)title current:(NSString *)current done:(void (^)(NSString *name))done {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:@"最多 10 个字，分组栏上显示的就是它" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=current;field.placeholder=@"分组名";field.clearButtonMode=UITextFieldViewModeWhileEditing;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        NSString *name=[weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(name.length)done(name.length>10?[name substringWithRange:[name rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,10)]]:name);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)askRule:(NSString *)title from:(UIView *)source done:(void (^)(NSInteger rule))done {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *names=WXGGroupRuleNames();
    for(NSUInteger i=0;i<names.count;i++)[sheet addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){done((NSInteger)i);}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet from:source];
}
- (void)openMembers:(NSString *)groupID {
    [self.navigationController pushViewController:[[WXGGroupMembersPage alloc] initWithGroup:groupID] animated:YES];
}
- (void)groupTapped:(WXGGroupRow *)row {
    NSArray<NSDictionary *> *groups=WXGChatGroupList();NSInteger i=row.tag;
    if(i<0 || i>=(NSInteger)groups.count)return;
    NSDictionary *group=groups[(NSUInteger)i];NSString *gid=group[@"id"];
    __weak WXGGroupsPage *weakSelf=self;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:group[@"name"] message:WXGGroupRuleText(group) preferredStyle:UIAlertControllerStyleActionSheet];
    if([group[@"rule"] integerValue]==4)
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"选择聊天（已选 %lu 个）",(unsigned long)[group[@"members"] count]] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[weakSelf openMembers:gid];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"改名" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [weakSelf askName:@"分组改名" current:group[@"name"] done:^(NSString *name){[weakSelf saveChanging:gid with:^(NSMutableDictionary *g){g[@"name"]=name;}];}];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"换类型" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [weakSelf askRule:@"这个分组显示什么" from:row done:^(NSInteger rule){
            [weakSelf saveChanging:gid with:^(NSMutableDictionary *g){g[@"rule"]=@(rule);}];
            if(rule==4)[weakSelf openMembers:gid];
        }];
    }]];
    for(int dir=-1;dir<=1;dir+=2) {
        NSInteger to=i+dir;if(to<0 || to>=(NSInteger)groups.count)continue;
        [sheet addAction:[UIAlertAction actionWithTitle:dir<0?@"左移":@"右移" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            NSMutableArray *moved=[WXGChatGroupList() mutableCopy];if(i>=(NSInteger)moved.count || to>=(NSInteger)moved.count)return;
            [moved exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:(NSUInteger)to];WXGChatGroupSave(moved);
        }]];
    }
    if(groups.count>1)
        [sheet addAction:[UIAlertAction actionWithTitle:@"删除这个分组" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
            NSMutableArray *kept=[NSMutableArray array];for(NSDictionary *g in WXGChatGroupList())if(![g[@"id"] isEqual:gid])[kept addObject:g];
            WXGChatGroupSave(kept);
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet from:row];
}
- (void)actionTapped:(WXGGroupRow *)row {
    __weak WXGGroupsPage *weakSelf=self;
    if(row.tag==0) {
        if(WXGChatGroupList().count>=6)return;
        [self askName:@"新建分组" current:@"" done:^(NSString *name){
            [weakSelf askRule:[NSString stringWithFormat:@"“%@”显示什么",name] from:row done:^(NSInteger rule){
                NSString *gid=[@"g" stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:8]];
                NSMutableArray *groups=[WXGChatGroupList() mutableCopy];
                [groups addObject:@{@"id":gid,@"name":name,@"rule":@(rule),@"members":@[]}];
                WXGChatGroupSave(groups);
                if(rule==4)[weakSelf openMembers:gid];
            }];
        }];
        return;
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"恢复默认分组？" message:@"回到 全部 / 未读 / 单聊 / 群聊 四个，自建的分组和选好的聊天都会删掉。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){WXGChatGroupSave(WXGChatGroupDefaults());}]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

UIViewController *WXGChatGroupsPage(void) {return [WXGGroupsPage new];}
