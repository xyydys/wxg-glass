#import "WXGBannerLibraryController.h"
#import "WXGBannerLibrary.h"
#import "WXGSettingsKit.h"
#import <PhotosUI/PhotosUI.h>

static NSString *const WXGBannerImportProgress = @"WXGBannerImportProgress";

// Retain a batch across navigation. File providers remove their temporary
// representation when the callback returns, so the store copies it there.
@interface WXGBannerImport : NSObject
@property(nonatomic,readonly) BOOL running;
@property(nonatomic,readonly) NSString *status;
+ (instancetype)shared;
- (void)start:(NSArray<PHPickerResult *> *)results;
- (void)cancel;
@end

@implementation WXGBannerImport {
    NSArray<PHPickerResult *> *_results;
    NSProgress *_download;
    NSObject *_currentRequest;
    BOOL _saving;
    NSUInteger _batchNumber;
    NSUInteger _next, _saved, _failed;
    BOOL _cancelled;
    NSString *_lastError;
}
+ (instancetype)shared {
    static WXGBannerImport *batch;
    static dispatch_once_t once;
    dispatch_once(&once,^{batch=[self new];});
    return batch;
}
- (void)publish:(NSString *)status {
    _status=status;
    [NSNotificationCenter.defaultCenter postNotificationName:WXGBannerImportProgress object:self];
}
- (void)start:(NSArray<PHPickerResult *> *)results {
    if(_running || !results.count)return;
    _running=YES;
    ++_batchNumber;
    _cancelled=NO;
    _next=0;_saved=0;_failed=0;_lastError=nil;
    _results=results.copy;
    [self importNext];
}
- (void)cancel {
    if(!_running || _cancelled)return;
    _cancelled=YES;
    BOOL saving;
    @synchronized(self) {
        saving=_saving;
        if(!saving)_currentRequest=nil;
    }
    [_download cancel];
    if(saving)[self publish:@"正在保存当前项目…"];
    else [self finish];
}
- (void)finish {
    _running=NO;
    _results=nil;
    _download=nil;
    NSString *status=[NSString stringWithFormat:@"已导入 %lu 项",(unsigned long)_saved];
    if(_failed)status=[status stringByAppendingFormat:@"，%lu 项未导入。%@",(unsigned long)_failed,_lastError?:@""];
    else if(_cancelled)status=[status stringByAppendingString:@"，已停止导入。"];
    [self publish:status];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,status);
}
- (void)completeItem:(BOOL)saved error:(NSError *)error {
    _download=nil;
    if(saved)++_saved;
    else if(!_cancelled) {
        ++_failed;
        _lastError=error.localizedDescription?:@"相册未提供可读取的图片或视频。";
    }
    // Also keeps a sequence of unsupported representations off the call stack.
    NSUInteger batch=_batchNumber;
    dispatch_async(dispatch_get_main_queue(),^{if(self->_running && self->_batchNumber==batch)[self importNext];});
}
- (void)importNext {
    if(_cancelled || _next>=_results.count){[self finish];return;}
    NSItemProvider *provider=_results[_next++].itemProvider;
    BOOL livePhoto=[provider hasItemConformingToTypeIdentifier:@"com.apple.live-photo"] &&
        [provider hasItemConformingToTypeIdentifier:@"public.image"];
    BOOL video=!livePhoto && [provider hasItemConformingToTypeIdentifier:@"public.movie"];
    NSString *type=video?@"public.movie":@"public.image";
    [self publish:[NSString stringWithFormat:@"正在导入 %lu / %lu",(unsigned long)_next,(unsigned long)_results.count]];
    if(![provider hasItemConformingToTypeIdentifier:type]){[self completeItem:NO error:nil];return;}
    NSString *name=provider.suggestedName;
    NSObject *request=[NSObject new];
    @synchronized(self){_currentRequest=request;}
    _download=[provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url,NSError *error) {
        @synchronized(self) {
            if(self->_currentRequest!=request)return;
            self->_saving=YES;
        }
        NSError *importError=error;
        WXGBannerItem *item=nil;
        if(url && !error) {
            @autoreleasepool {
                item=[WXGBannerLibrary.shared importFileURL:url displayName:name isVideo:video error:&importError];
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{
            @synchronized(self){self->_currentRequest=nil;self->_saving=NO;}
            [self completeItem:item!=nil error:importError];
        });
    }];
}
@end

@interface WXGBannerMediaCell : UITableViewCell
@property(nonatomic,copy) NSString *representedIdentifier;
@property(nonatomic,strong) NSOperation *thumbnailOperation;
@end
@implementation WXGBannerMediaCell
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.thumbnailOperation cancel];self.thumbnailOperation=nil;self.representedIdentifier=nil;
}
@end

@interface WXGBannerLibraryController : WXGSettingsPage <UITableViewDataSource,UITableViewDelegate,PHPickerViewControllerDelegate>
@end

@implementation WXGBannerLibraryController {
    WXGSettingsCard *_actions,*_media;
    UIButton *_add,*_manage;
    UILabel *_status;
    UITableView *_table;
    NSArray<WXGBannerItem *> *_items;
    NSString *_selected,*_loadError;
    NSCache<NSString *,UIImage *> *_thumbnails;
    NSOperationQueue *_thumbnailQueue;
    dispatch_queue_t _selectionQueue;
    BOOL _loaded;
}
- (instancetype)init {
    if((self=[super initWithNibName:nil bundle:nil])) {
        self.pageTitle=@"横幅媒体库";
        _thumbnails=[NSCache new];
        _thumbnails.totalCostLimit=8*1024*1024;
        _selectionQueue=dispatch_queue_create("wxg.banner.selection",DISPATCH_QUEUE_SERIAL);
        _thumbnailQueue=[NSOperationQueue new];
        _thumbnailQueue.maxConcurrentOperationCount=2;
        _thumbnailQueue.qualityOfService=NSQualityOfServiceUtility;
    }
    return self;
}
- (void)dealloc {[_thumbnailQueue cancelAllOperations];}
- (void)buildContent {
    self.scrollView.scrollEnabled=NO;
    _actions=[self addCard:NO];
    _add=[UIButton buttonWithType:UIButtonTypeSystem];
    _add.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _add.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    [_add addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    _manage=[UIButton buttonWithType:UIButtonTypeSystem];
    [_manage addTarget:self action:@selector(toggleManage) forControlEvents:UIControlEventTouchUpInside];
    [_actions.contentView addSubview:_add];[_actions.contentView addSubview:_manage];
    _status=[self sectionLabel:@""];
    _status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];_status.numberOfLines=0;
    _media=[self addCard:NO];
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor=UIColor.clearColor;
    _table.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    _table.dataSource=self;_table.delegate=self;
    _table.tableFooterView=[UIView new];_table.estimatedRowHeight=64;_table.rowHeight=UITableViewAutomaticDimension;
    [_table registerClass:WXGBannerMediaCell.class forCellReuseIdentifier:@"asset"];
    [_media.contentView addSubview:_table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadLibrary) name:WXGBannerLibraryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatus) name:WXGBannerImportProgress object:nil];
    [self updateStatus];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak typeof(self) weakSelf=self;
    [WXGBannerLibrary.shared loadWithCompletion:^(NSError *error){
        WXGBannerLibraryController *page=weakSelf;
        if(!page)return;
        page->_loadError=error.localizedDescription;
        page->_loaded=error==nil;
        [page reloadLibrary];
    }];
}
- (void)reloadLibrary {
    _items=WXGBannerLibrary.shared.items;
    _selected=WXGBannerLibrary.shared.selectedItem.identifier;
    if(!_items.count && _table.editing)[_table setEditing:NO animated:NO];
    [_table reloadData];[self updateStatus];
}
- (void)updateStatus {
    WXGBannerImport *batch=WXGBannerImport.shared;
    [_add setTitle:(batch.running?@"停止导入":@"从相册添加") forState:UIControlStateNormal];
    [_manage setTitle:(_table.editing?@"完成":@"管理") forState:UIControlStateNormal];
    NSString *detail=batch.status;
    if(_loadError.length)detail=_loadError;
    else if(!detail.length)detail=_items.count?@"点选要用作横幅的图片或视频。":@"可一次添加多张图片和视频。";
    _status.text=detail;
    _add.enabled=_loaded || batch.running;
    _manage.enabled=_loaded && _items.count>0 && !batch.running;
    [self.view setNeedsLayout];
}
- (void)applyLook {
    [super applyLook];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    _table.tintColor=store.controlTint?:UIColor.systemBlueColor;
    _table.separatorColor=[store.secondaryColor colorWithAlphaComponent:.18];
    _add.tintColor=_manage.tintColor=store.controlTint?:UIColor.systemBlueColor;
    _status.textColor=store.secondaryColor;
    [_table reloadData];
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat w=MIN(640,MAX(1,width-2*self.sideMargin));
    CGFloat x=(width-w)*.5;
    CGFloat barHeight=MAX(48,_add.titleLabel.font.lineHeight+20);
    _actions.frame=CGRectMake(x,0,w,barHeight);
    _add.frame=CGRectMake(16,0,MAX(0,w-108),barHeight);
    _manage.frame=CGRectMake(w-80,0,68,barHeight);
    CGFloat statusWidth=MAX(1,w-20);
    CGFloat statusHeight=ceil([_status sizeThatFits:CGSizeMake(statusWidth,CGFLOAT_MAX)].height);
    _status.frame=CGRectMake(x+10,barHeight+10,statusWidth,statusHeight);
    CGFloat y=CGRectGetMaxY(_status.frame)+10;
    CGFloat available=self.view.bounds.size.height-self.contentTop-self.view.safeAreaInsets.bottom-y-12;
    CGFloat h=MAX(1,available);
    _media.frame=CGRectMake(x,y,w,h);
    _table.frame=(CGRect){CGPointZero,{w,h}};
    _table.layer.cornerRadius=_media.cornerRadius;_table.layer.cornerCurve=kCACornerCurveContinuous;
    return y+h;
}
- (void)addTapped {
    if(WXGBannerImport.shared.running){[WXGBannerImport.shared cancel];return;}
    if(!_loaded || self.presentedViewController)return;
    [_table setEditing:NO animated:YES];[self updateStatus];
    PHPickerConfiguration *config=[PHPickerConfiguration new];
    config.filter=[PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter,PHPickerFilter.videosFilter]];
    config.selectionLimit=0;
    config.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:config];
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if(results.count)[WXGBannerImport.shared start:results];
}
- (void)toggleManage {
    [_table setEditing:!_table.editing animated:YES];
    [self updateStatus];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;(void)section;
    return 1+(NSInteger)_items.count;
}
- (void)setThumbnail:(UIImage *)image cell:(WXGBannerMediaCell *)cell {
    UIListContentConfiguration *content=[(UIListContentConfiguration *)cell.contentConfiguration copy];
    content.image=image;
    cell.contentConfiguration=content;
}
- (void)loadThumbnail:(WXGBannerItem *)item cell:(WXGBannerMediaCell *)cell {
    if(!item.thumbnailURL)return;
    UIImage *image=[_thumbnails objectForKey:item.identifier];
    if(image){[self setThumbnail:image cell:cell];return;}
    NSURL *url=item.thumbnailURL;
    NSString *identifier=item.identifier;
    __weak WXGBannerMediaCell *weakCell=cell;
    __weak WXGBannerLibraryController *weakSelf=self;
    NSCache *cache=_thumbnails;
    NSBlockOperation *operation=[NSBlockOperation blockOperationWithBlock:^{
        @autoreleasepool {
            UIImage *thumb=[UIImage imageWithContentsOfFile:url.path];
            if(!thumb)return;
            CGImageRef cg=thumb.CGImage;
            NSUInteger bytes=cg?CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg):0;
            [cache setObject:thumb forKey:identifier cost:bytes];
            dispatch_async(dispatch_get_main_queue(),^{
                WXGBannerMediaCell *shown=weakCell;
                if([shown.representedIdentifier isEqual:identifier])[weakSelf setThumbnail:thumb cell:shown];
            });
        }
    }];
    cell.thumbnailOperation=operation;
    [_thumbnailQueue addOperation:operation];
}
- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;(void)indexPath;
    if([cell isKindOfClass:WXGBannerMediaCell.class])[((WXGBannerMediaCell *)cell).thumbnailOperation cancel];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    WXGBannerMediaCell *cell=[tableView dequeueReusableCellWithIdentifier:@"asset" forIndexPath:indexPath];
    WXGBannerItem *item=indexPath.row?_items[(NSUInteger)indexPath.row-1]:nil;
    [cell.thumbnailOperation cancel];
    cell.representedIdentifier=item.identifier;
    BOOL selected=item?[_selected isEqual:item.identifier]:!_selected;
    cell.backgroundColor=UIColor.clearColor;
    cell.accessoryType=selected?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    cell.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    UIListContentConfiguration *content=cell.defaultContentConfiguration;
    content.text=item?item.displayName:@"微信头像";
    content.textProperties.color=WXGSettingsStore.shared.accentColor;
    content.secondaryText=item?(item.isVideo?@"视频":@"图片"):nil;
    content.secondaryTextProperties.color=WXGSettingsStore.shared.secondaryColor;
    content.image=[UIImage systemImageNamed:item?(item.isVideo?@"film":@"photo"):@"person.crop.circle"];
    content.imageProperties.maximumSize=CGSizeMake(52,52);
    content.imageProperties.reservedLayoutSize=CGSizeMake(52,52);
    content.imageProperties.cornerRadius=8;
    content.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(7,14,7,12);
    cell.contentConfiguration=content;
    if(item)[self loadThumbnail:item cell:cell];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(!_loaded || indexPath.row>(NSInteger)_items.count)return;
    NSString *identifier=indexPath.row?_items[(NSUInteger)indexPath.row-1].identifier:nil;
    dispatch_async(_selectionQueue,^{
        NSError *error=nil;
        if(![WXGBannerLibrary.shared selectIdentifier:identifier error:&error])dispatch_async(dispatch_get_main_queue(),^{
            if(self.viewIfLoaded.window)[self showMessage:@"未能切换横幅" detail:error.localizedDescription];
        });
    });
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.row>0 && _loaded && !WXGBannerImport.shared.running;
}
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;(void)indexPath;return @"移除";
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if(style!=UITableViewCellEditingStyleDelete || indexPath.row<1 || indexPath.row>(NSInteger)_items.count)return;
    WXGBannerItem *item=_items[(NSUInteger)indexPath.row-1];
    NSString *detail=[_selected isEqual:item.identifier]?@"移除后，横幅将使用微信头像。":@"此操作只移除媒体库中的副本。";
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"移除“%@”？",item.displayName]
        message:detail preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        dispatch_async(self->_selectionQueue,^{
            NSError *error=nil;
            if(![WXGBannerLibrary.shared removeIdentifier:item.identifier error:&error])dispatch_async(dispatch_get_main_queue(),^{
                if(self.viewIfLoaded.window)[self showMessage:@"未能移除" detail:error.localizedDescription];
            });
            [self->_thumbnails removeObjectForKey:item.identifier];
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
@end

UIViewController *WXGBannerLibraryPage(void) {
    return [WXGBannerLibraryController new];
}
