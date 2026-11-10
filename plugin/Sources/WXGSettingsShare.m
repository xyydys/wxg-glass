#import "WXGSettingsKit.h"

/* FIX84: 参数共享 (基本设置 → 帧率与参数).
   One JSON for everything the settings pages set, except the main switches
   and the account: every glass parameter (WXGConfig, the same keys as the
   diagnostics' materialParameters), the switches of 基本设置 / 底栏 / 渐隐
   (WXGPreferences) and the settings pages' card radius and accent colour.
   Wallpapers and the avatar are pictures and stay on the phone.
     {"schema":"wxg-settings-v1","version":…,"build":…,"exportedAt":…,
      "config":{…},"integration":{…},"ui":{…}}
   Copy (compact text, for a chat message) or a .json file to share; import
   from the clipboard or a file. Import also takes a diagnostics export (its
   settingsShare block, or from older builds only materialParameters) or a
   bare object of WXGConfig keys. Values are checked by type and go through
   the same clamping as the sliders.
   The same JSON in WXGBuildProfile.h (tools/bake_defaults.py) is a build's
   defaults: a fresh install starts from it and 恢复默认 returns to it. */

static NSArray<NSString *> *WXGShareSkippedIntegration(void) {return @[@"enabled",@"homeSearch",@"perfMonitor",@"perfHUD"];}

NSDictionary *WXGSharePayload(void) {
    WXGConfig *c=WXGConfig.shared;WXGPreferences *p=WXGPreferences.shared;WXGSettingsStore *ui=WXGSettingsStore.shared;
    NSMutableDictionary *config=[c.parameterValues mutableCopy];[config removeObjectForKey:@"enabled"];
    // FIX114 C: nothing JSON cannot hold (a value that is not a finite number
    // would make the whole export fail).
    for(NSString *key in config.allKeys) {
        id value=config[key];
        if(value==NSNull.null || ([value isKindOfClass:NSNumber.class] && !isfinite([value doubleValue])) ||
           !([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]))[config removeObjectForKey:key];
    }
    NSMutableDictionary *integration=[[p dictionaryWithValuesForKeys:p.keys] mutableCopy];
    [integration removeObjectsForKeys:WXGShareSkippedIntegration()];
    NSMutableDictionary *look=[NSMutableDictionary dictionaryWithObject:@(ui.cardRadius) forKey:@"cardRadius"];
    if(ui.accentHex)look[@"accentHex"]=ui.accentHex;
    static NSDateFormatter *formatter;static dispatch_once_t once;
    dispatch_once(&once,^{formatter=[NSDateFormatter new];formatter.dateFormat=@"yyyy-MM-dd HH:mm:ss";formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];});
    return @{@"schema":@"wxg-settings-v1",@"version":WXGIntegrationHost.shared.versionString,@"build":WXGBuildLabel(),
             @"exportedAt":[formatter stringFromDate:NSDate.date],@"config":config,@"integration":integration,@"ui":look};
}

#pragma mark - Reading

static NSDictionary *WXGShareFind(id object,NSString *key,NSUInteger depth) {
    if(depth>6)return nil;
    if([object isKindOfClass:NSDictionary.class]) {
        id value=((NSDictionary *)object)[key];
        if([value isKindOfClass:NSDictionary.class])return value;
        for(id child in ((NSDictionary *)object).allValues) {
            NSDictionary *found=WXGShareFind(child,key,depth+1);
            if(found)return found;
        }
    }else if([object isKindOfClass:NSArray.class]) {
        for(id child in (NSArray *)object) {
            NSDictionary *found=WXGShareFind(child,key,depth+1);
            if(found)return found;
        }
    }
    return nil;
}
static BOOL WXGShareNumber(id value) {return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);}
/* The known, well-typed values of `source` for `keys` (colours: valid hex). */
static NSDictionary *WXGShareFilter(NSDictionary *source,NSArray<NSString *> *keys,NSArray<NSString *> *skipped) {
    if(![source isKindOfClass:NSDictionary.class])return @{};
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    for(NSString *key in keys) {
        if([skipped containsObject:key])continue;
        id value=source[key];
        if([key hasSuffix:@"Hex"]){if([value isKindOfClass:NSString.class] && WXGNormalizeHex(value))out[key]=WXGNormalizeHex(value);}
        else if(WXGShareNumber(value))out[key]=value;
    }
    return out;
}
/* The settings in a pasted or picked text, or nil with the reason. */
static NSDictionary *WXGShareParse(NSString *text,NSString **reason) {
    NSString *trimmed=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Text copied out of a chat may carry words around the JSON.
    NSRange open=[trimmed rangeOfString:@"{"],close=[trimmed rangeOfString:@"}" options:NSBackwardsSearch];
    if(open.location==NSNotFound || close.location==NSNotFound || close.location<open.location){*reason=@"没有找到参数（不是 JSON）。";return nil;}
    trimmed=[trimmed substringWithRange:NSMakeRange(open.location,close.location-open.location+1)];
    NSData *data=[trimmed dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error=nil;id root=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]:nil;
    if(![root isKindOfClass:NSDictionary.class]){*reason=@"JSON 读不出来，可能复制不完整。";return nil;}
    NSDictionary *share=[root[@"config"] isKindOfClass:NSDictionary.class]?root:WXGShareFind(root,@"settingsShare",0);
    NSDictionary *config=share[@"config"],*integration=share[@"integration"],*look=share[@"ui"];
    NSString *source=share?[NSString stringWithFormat:@"%@ · %@",share[@"version"]?:@"?",share[@"exportedAt"]?:@"?"]:nil;
    if(![config isKindOfClass:NSDictionary.class]) {
        // An older diagnostics export: glass parameters only, the current
        // scene's first (the history holds older ones).
        config=WXGShareFind(root[@"currentOrLastScene"],@"materialParameters",0)?:WXGShareFind(root,@"materialParameters",0);
        if(config)source=@"诊断文件（只有玻璃参数）";
        else {
            config=root;source=@"参数对象";
        }
    }
    NSArray *configKeys=WXGConfig.shared.keys;
    NSDictionary *c=WXGShareFilter([config isKindOfClass:NSDictionary.class]?WXGRenamedSettings(config):config,configKeys,@[@"enabled"]);   // FIX130: an older file's names
    NSDictionary *i=WXGShareFilter(integration,WXGPreferences.shared.keys,WXGShareSkippedIntegration());
    NSMutableDictionary *u=[NSMutableDictionary dictionary];
    if([look isKindOfClass:NSDictionary.class]) {
        if(WXGShareNumber(look[@"cardRadius"]))u[@"cardRadius"]=look[@"cardRadius"];
        // No accent in the export: the sender follows the system colour.
        u[@"accentHex"]=[look[@"accentHex"] isKindOfClass:NSString.class] && WXGNormalizeHex(look[@"accentHex"])?WXGNormalizeHex(look[@"accentHex"]):NSNull.null;
    }
    if(c.count<8 && !i.count){*reason=@"里面没有本插件的参数。";return nil;}
    return @{@"config":c,@"integration":i,@"ui":u,@"source":source?:@"?"};
}
static NSString *WXGShareApply(NSDictionary *parsed) {
    WXGConfig *c=WXGConfig.shared;WXGPreferences *p=WXGPreferences.shared;WXGSettingsStore *ui=WXGSettingsStore.shared;
    NSDictionary *config=parsed[@"config"],*integration=parsed[@"integration"],*look=parsed[@"ui"];
    [config enumerateKeysAndObjectsUsingBlock:^(NSString *key,id value,__unused BOOL *stop){[c setValue:value forKey:key];}];
    if(config.count)[c reinheritExtrasMissingFrom:config];   // FIX85: older exports: the new keys follow the imported ones
    if(config.count)[c save];
    [integration enumerateKeysAndObjectsUsingBlock:^(NSString *key,id value,__unused BOOL *stop){[p setValue:value forKey:key];}];
    if(integration.count)[p save];
    if(look[@"cardRadius"])ui.cardRadius=[look[@"cardRadius"] doubleValue];
    if(look[@"accentHex"])ui.accentHex=look[@"accentHex"]==NSNull.null?nil:look[@"accentHex"];
    if(look.count)[ui save];
    WXGLog(@"参数导入：玻璃 %lu 项，开关 %lu 项，界面 %lu 项（%@）",(unsigned long)config.count,(unsigned long)integration.count,(unsigned long)look.count,parsed[@"source"]);
    return [NSString stringWithFormat:@"玻璃参数 %lu 项、开关 %lu 项、界面 %lu 项",(unsigned long)config.count,(unsigned long)integration.count,(unsigned long)look.count];
}

#pragma mark - UI

/* Runs once nothing is presented over `from` any more (a file picker or an
   alert still going away would make a new presentation fail), at most 3 s. */
static void WXGShareWhenFree(UIViewController *from,NSUInteger tries,void (^run)(void)) {
    if(!from)return;
    if(from.presentedViewController && tries<30) {
        __weak UIViewController *weakFrom=from;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            UIViewController *strong=weakFrom;
            if(strong)WXGShareWhenFree(strong,tries+1,run);
        });
        return;
    }
    run();
}
static void WXGShareTell(UIViewController *from,NSString *title,NSString *detail) {
    __weak UIViewController *weakFrom=from;
    WXGShareWhenFree(from,0,^{
        UIViewController *strong=weakFrom;if(!strong)return;
        if([strong isKindOfClass:WXGSettingsPage.class]){[(WXGSettingsPage *)strong showMessage:title detail:detail];return;}
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *presenter=strong;
        while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)presenter=presenter.presentedViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}
static void WXGShareConfirm(UIViewController *from,NSString *text,void (^done)(void)) {
    NSString *reason=nil;NSDictionary *parsed=WXGShareParse(text?:@"",&reason);
    if(!parsed){WXGShareTell(from,@"不能导入",reason);return;}
    NSDictionary *config=parsed[@"config"],*integration=parsed[@"integration"],*look=parsed[@"ui"];
    NSString *message=[NSString stringWithFormat:@"来源：%@\n\n玻璃参数 %lu 项、开关 %lu 项、界面 %lu 项会替换现在的设置。总开关、授权、壁纸和头像不变。",
        parsed[@"source"],(unsigned long)config.count,(unsigned long)integration.count,(unsigned long)look.count];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"导入这套参数？" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weakFrom=from;
    [alert addAction:[UIAlertAction actionWithTitle:@"导入" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        NSString *summary=WXGShareApply(parsed);
        if(done)done();
        UIViewController *strong=weakFrom;
        if(strong)WXGShareTell(strong,@"已导入",summary);
    }]];
    WXGShareWhenFree(from,0,^{
        UIViewController *presenter=weakFrom;
        while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)presenter=presenter.presentedViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}
static NSString *WXGShareJSONOf(NSDictionary *payload,BOOL pretty) {
    // (review) a value JSON cannot hold throws: nil (the caller says so) instead.
    if(!payload || ![NSJSONSerialization isValidJSONObject:payload])return nil;
    NSJSONWritingOptions options=NSJSONWritingSortedKeys|(pretty?NSJSONWritingPrettyPrinted:0);
    NSData *data=nil;@try {data=[NSJSONSerialization dataWithJSONObject:payload options:options error:nil];} @catch(__unused NSException *error) {data=nil;}
    return data?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
}
static NSString *WXGShareJSON(BOOL pretty) {return WXGShareJSONOf(WXGSharePayload(),pretty);}
void WXGShareCopy(UIViewController *from) {
    NSDictionary *payload=WXGSharePayload();
    NSString *json=WXGShareJSONOf(payload,NO);
    if(!json){WXGShareTell(from,@"复制失败",@"参数无法转成 JSON。");return;}
    UIPasteboard.generalPasteboard.string=json;
    WXGShareTell(from,@"已复制当前参数",[NSString stringWithFormat:@"玻璃参数 %lu 项、开关 %lu 项、界面 %lu 项，%lu 个字符。发给别人后，对方复制整段文字，在这里点“从剪贴板导入参数”。",
        (unsigned long)[payload[@"config"] count],(unsigned long)[payload[@"integration"] count],(unsigned long)[payload[@"ui"] count],(unsigned long)json.length]);
}
void WXGShareExportFrom(UIViewController *from) {
    NSString *json=WXGShareJSON(YES);
    static NSDateFormatter *stamp;static dispatch_once_t once;
    dispatch_once(&once,^{stamp=[NSDateFormatter new];stamp.dateFormat=@"yyyyMMdd_HHmm";stamp.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];});
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"WeChatLiquidGlass_settings_%@.json",[stamp stringFromDate:NSDate.date]]];
    if(!json || ![json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]){WXGShareTell(from,@"导出失败",@"文件写不进去。");return;}
    UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView=from.view;share.popoverPresentationController.sourceRect=CGRectMake(from.view.bounds.size.width*.5,60,1,1);
    [from presentViewController:share animated:YES completion:nil];
}
void WXGShareImportClipboard(UIViewController *from,void (^done)(void)) {
    NSString *text=UIPasteboard.generalPasteboard.string;
    if(!text.length){WXGShareTell(from,@"剪贴板是空的",@"先复制整段参数文字（以 { 开头、} 结尾）。");return;}
    WXGShareConfirm(from,text,done);
}

/* The file picker's delegate lives as long as the picker. */
@interface WXGShareFilePicker : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,weak) UIViewController *from;
@property(nonatomic,copy) void (^done)(void);
@end
@implementation WXGShareFilePicker
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;UIViewController *from=self.from;
    if(!url || !from)return;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    NSData *data=!size || size.unsignedLongLongValue<=16*1024*1024?[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil]:nil;
    if(data.length>16*1024*1024)data=nil;
    if(scoped)[url stopAccessingSecurityScopedResource];
    NSString *text=data?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
    void (^done)(void)=self.done;
    // Shown once the picker has gone away (WXGShareWhenFree).
    if(!text.length)WXGShareTell(from,@"不能导入",@"文件读不出来（只支持 16 MB 以内的 JSON 文本）。");
    else WXGShareConfirm(from,text,done);
}
@end
static char WXGShareFilePickerKey;
void WXGShareImportFile(UIViewController *from,void (^done)(void)) {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initWithDocumentTypes:@[@"public.json",@"public.plain-text",@"public.text",@"public.data"]
                                                                                                 inMode:UIDocumentPickerModeImport];
    WXGShareFilePicker *delegate=[WXGShareFilePicker new];delegate.from=from;delegate.done=done;
    objc_setAssociatedObject(picker,&WXGShareFilePickerKey,delegate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    picker.delegate=delegate;picker.allowsMultipleSelection=NO;
    [from presentViewController:picker animated:YES completion:nil];
}
