#import "WXGIntegration.h"
#import "WXGBuildProfile.h"
#import <CommonCrypto/CommonDigest.h>

// FIX59: the plugin works only for licensed WeChat accounts. The current
// account's wxid is read from WeChat once its logged-in interface is up; until
// then, and for any other account, the plugin stays off and WeChat is
// untouched. Settings show the state and the wxid.
// FIX103: the licence is the unlock server's (WXGUnlock.m): the account's
// licence code goes to the server, which answers a listed account with the
// glass shader in a ticket signed for it. The build holds no list any more.

static WXGLicenseState WXGState=WXGLicenseUnknown;
static NSString *WXGAccount,*WXGAccountSource,*WXGAccountCode;
static CFTimeInterval WXGLastAccountRead;
static BOOL WXGMainInterface;
// FIX102: reading the account (CContactMgr getSelfContact & co.) took 50-95 ms
// of main thread on the tester's phone, every 3 s, wherever that fell (twice
// inside a tab switch: the dock froze). A known account is read again every
// 60 s, and only when the host says nothing is moving; how long it took is
// in the diagnostics.
static BOOL (*WXGLicenseQuiet)(void);
static double WXGAccountReadMS,WXGAccountReadMaxMS;
static NSUInteger WXGAccountReads,WXGAccountReadsPut;
void WXGLicenseSetQuietCheck(BOOL (*check)(void)) {WXGLicenseQuiet=check;}

NSString *WXGBuildLabel(void) {return WXG_BUILD_LABEL;}
NSArray<NSString *> *WXGHiddenSettingsModules(void) {return WXG_HIDDEN_MODULES;}
// FIX84: WXG_DEFAULT_OPTICS_JSON is either an object of WXGConfig keys (as
// before) or a settings export (WXGSettingsShare.m: "config", "integration",
// "ui"), written by tools/bake_defaults.py.
static NSDictionary *WXGBuildDefaultsRoot(void) {
    static NSDictionary *defaults;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSData *data=[@WXG_DEFAULT_OPTICS_JSON dataUsingEncoding:NSUTF8StringEncoding];
        id root=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        defaults=[root isKindOfClass:NSDictionary.class]?root:@{};
    });
    return defaults;
}
NSDictionary *WXGBuildDefaultSection(NSString *section) {
    NSDictionary *root=WXGBuildDefaultsRoot();
    id value=root[section];
    if([value isKindOfClass:NSDictionary.class])return value;
    // A bare object of WXGConfig keys is the "config" section.
    if([section isEqual:@"config"] && ![root[@"integration"] isKindOfClass:NSDictionary.class] && ![root[@"ui"] isKindOfClass:NSDictionary.class])return root;
    return @{};
}
NSDictionary *WXGBuildDefaultOptics(void) {return WXGBuildDefaultSection(@"config");}
// FIX114 G: the defaults this build's replace (tools/bake_defaults.py keeps
// them), and a stamp of this build's: a phone's setting still at the previous
// default (never changed) moves to the new one, once per new set of defaults.
#ifndef WXG_PREVIOUS_DEFAULT_OPTICS_JSON
#define WXG_PREVIOUS_DEFAULT_OPTICS_JSON ""
#endif
static NSDictionary *WXGPreviousDefaultsRoot(void) {
    static NSDictionary *defaults;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSData *data=[@WXG_PREVIOUS_DEFAULT_OPTICS_JSON dataUsingEncoding:NSUTF8StringEncoding];
        id root=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        defaults=[root isKindOfClass:NSDictionary.class]?root:@{};
    });
    return defaults;
}
NSDictionary *WXGPreviousBuildDefaultSection(NSString *section) {
    NSDictionary *root=WXGPreviousDefaultsRoot();
    id value=root[section];
    if([value isKindOfClass:NSDictionary.class])return value;
    if([section isEqual:@"config"] && root.count && ![root[@"integration"] isKindOfClass:NSDictionary.class] && ![root[@"ui"] isKindOfClass:NSDictionary.class])return root;
    return @{};
}
NSString *WXGBuildDefaultsStamp(void) {
    static NSString *stamp;static dispatch_once_t once;
    dispatch_once(&once,^{
        const char *json=[@WXG_DEFAULT_OPTICS_JSON UTF8String]?:"";size_t n=strlen(json);uint64_t h=1469598103934665603ULL;   // FNV-1a (the same literal as the defaults: one copy in the binary)
        for(size_t i=0;i<n;i++){h^=(uint8_t)json[i];h*=1099511628211ULL;}
        stamp=n?[NSString stringWithFormat:@"%016llx-%zu",(unsigned long long)h,n]:@"";
    });
    return stamp;
}
// Two stored setting values the same: colours by their normalised hex,
// numbers (switches too) within rounding of the exported values.
BOOL WXGSameSettingValue(id a,id b) {
    if([a isKindOfClass:NSString.class] && [b isKindOfClass:NSString.class])return [(WXGNormalizeHex(a)?:a) isEqualToString:(WXGNormalizeHex(b)?:b)];
    if([a isKindOfClass:NSNumber.class] && [b isKindOfClass:NSNumber.class]) {
        double x=[a doubleValue],y=[b doubleValue];
        if(!isfinite(x) || !isfinite(y))return NO;
        return fabs(x-y)<=1e-5*MAX(1.0,MAX(fabs(x),fabs(y)));
    }
    return (!a || a==NSNull.null) && (!b || b==NSNull.null);
}
static NSMutableDictionary *WXGAdoptionLog;
static NSObject *WXGAdoptionLock(void) {static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
void WXGNoteDefaultsAdoption(NSString *section,NSDictionary *info) {
    @synchronized(WXGAdoptionLock()){if(!WXGAdoptionLog)WXGAdoptionLog=[NSMutableDictionary dictionary];if(section && info)WXGAdoptionLog[section]=info;}
}
NSDictionary *WXGDefaultsAdoption(void) {
    @synchronized(WXGAdoptionLock()){return @{@"stamp":WXGBuildDefaultsStamp(),@"previousKeys":@(WXGPreviousBuildDefaultSection(@"config").count),
        @"sections":WXGAdoptionLog?[WXGAdoptionLog copy]:@{}};}
}

#pragma mark - Reading the account

static NSString *WXGPlausibleAccount(id value) {
    if(![value isKindOfClass:NSString.class])return nil;
    NSString *s=value;
    if(s.length<2 || s.length>64 || [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)return nil;
    return s;
}
static id WXGCall(id target,NSString *selectorName) {
    SEL selector=NSSelectorFromString(selectorName);
    if(!target || ![target respondsToSelector:selector])return nil;
    @try {return ((id (*)(id,SEL))objc_msgSend)(target,selector);}
    @catch(__unused NSException *error) {return nil;}
}
static id WXGService(id container,NSString *className) {
    Class cls=NSClassFromString(className);SEL selector=NSSelectorFromString(@"getService:");
    if(!container || !cls || ![container respondsToSelector:selector])return nil;
    @try {return ((id (*)(id,SEL,Class))objc_msgSend)(container,selector,cls);}
    @catch(__unused NSException *error) {return nil;}
}
static NSString *WXGUserNameOf(id object) {
    if(!object)return nil;
    id value=nil;
    @try {value=[object valueForKey:@"m_nsUsrName"];}
    @catch(__unused NSException *error) {value=nil;}
    return WXGPlausibleAccount(value)?:WXGPlausibleAccount(WXGRead(object,@"m_nsUsrName"));
}
// The ways WeChat tweaks read the logged-in user's wxid, newest first; the
// first that answers wins (its name goes to the diagnostics and settings).
static NSString *WXGReadAccount(NSString **source) {
    NSArray *containers=@[
        @[@"MMContext",WXGCall(NSClassFromString(@"MMContext"),@"currentContext")?:NSNull.null],
        @[@"MMServiceCenter",WXGCall(NSClassFromString(@"MMServiceCenter"),@"defaultCenter")?:NSNull.null]];
    for(NSArray *pair in containers) {
        id container=pair[1];if(container==NSNull.null)continue;
        NSString *name=WXGUserNameOf(WXGCall(WXGService(container,@"CContactMgr"),@"getSelfContact"));
        if(name){*source=[pair[0] stringByAppendingString:@" · CContactMgr"];return name;}
    }
    Class util=NSClassFromString(@"SettingUtil");
    SEL local=NSSelectorFromString(@"getLocalUsrName:");
    if(util && [util respondsToSelector:local]) {
        id value=nil;
        @try {value=((id (*)(id,SEL,unsigned int))objc_msgSend)(util,local,0);}
        @catch(__unused NSException *error) {value=nil;}
        NSString *name=WXGPlausibleAccount(value);
        if(name){*source=@"SettingUtil · getLocalUsrName";return name;}
    }
    NSString *name=WXGPlausibleAccount(WXGCall(util,@"getCurUsrName"));
    if(name){*source=@"SettingUtil · getCurUsrName";return name;}
    for(NSArray *pair in containers) {
        id container=pair[1];if(container==NSNull.null)continue;
        id storage=WXGService(container,@"AccountStorageMgr");
        id setting=nil;
        @try {setting=[storage valueForKey:@"m_oSetting"];}
        @catch(__unused NSException *error) {setting=WXGRead(storage,@"m_oSetting");}
        name=WXGUserNameOf(setting);
        if(name){*source=[pair[0] stringByAppendingString:@" · AccountStorageMgr"];return name;}
    }
    return nil;
}

#pragma mark - Checking it

// FIX59: the licence code, SHA-256("WXGLiquidGlass.license.v1:" + wxid) in
// lowercase hex (tools/license_hash.py); FIX103: what the server's list holds.
static NSString *WXGAccountHash(NSString *account) {
    NSData *data=[[@"WXGLiquidGlass.license.v1:" stringByAppendingString:account] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[hex appendFormat:@"%02x",digest[i]];
    return [hex copy];   // immutable: asked for its UTF-8 on every WXGPluginEnabled()
}
static WXGLicenseState WXGLicenseFromUnlock(WXGUnlockState state) {
    switch(state) {
        case WXGUnlockReady:return WXGLicenseAuthorized;
        case WXGUnlockDenied:return WXGLicenseDenied;
        case WXGUnlockChecking:return WXGLicenseChecking;
        case WXGUnlockUnreachable:return WXGLicenseUnreachable;
        case WXGUnlockOutdated:return WXGLicenseOutdated;
        case WXGUnlockNone:break;
    }
    return WXGLicenseUnknown;
}
static NSString *WXGLicenseStateName(WXGLicenseState state) {
    switch(state) {
        case WXGLicenseAuthorized:return @"authorized";
        case WXGLicenseDenied:return @"denied";
        case WXGLicenseChecking:return @"checking";
        case WXGLicenseUnreachable:return @"unreachable";
        case WXGLicenseOutdated:return @"outdated";
        case WXGLicenseUnknown:break;
    }
    return @"unknown";
}
void WXGLicenseNoteMainInterface(void) {WXGMainInterface=YES;}
// Main thread. Cheap when nothing is due: a known account is read again at
// most every 60 s (0.5 s while unknown), so switching accounts is noticed; the
// server's answer for it is kept by WXGUnlock.m. force: ask the server now.
static WXGLicenseState WXGLicenseEvaluate(BOOL recheck,BOOL force) {
#ifdef WXG_FORCE_AUTHORIZED
    // 测试专用（默认不定义这个宏，正式/混淆包完全不含这段）。强制「已授权」，等效于破解版
    // 把授权判定 patch 成恒真之后的状态：overlay 装上、本地渲染照跑；但授权链不走真票，
    // Metal 着色器仍然不会加载。用来在自己源码上复现破解效果，并验证加固后本地路径还渲不渲。
    (void)recheck; (void)force;
    return WXGLicenseAuthorized;
#endif
    if(recheck)WXGMainInterface=YES;
    if(!WXGMainInterface || !NSThread.isMainThread)return WXGState;
    CFTimeInterval now=CACurrentMediaTime();
    BOOL due=recheck || now-WXGLastAccountRead>=(WXGAccount?60.:.5);
    if(due && !recheck && WXGAccount && WXGLicenseQuiet && !WXGLicenseQuiet()){++WXGAccountReadsPut;due=NO;}
    if(due) {
        WXGLastAccountRead=now;
        NSString *source=nil,*account=WXGReadAccount(&source);
        WXGAccountReadMS=(CACurrentMediaTime()-now)*1000;++WXGAccountReads;
        if(WXGAccountReadMS>WXGAccountReadMaxMS)WXGAccountReadMaxMS=WXGAccountReadMS;
        if(account && ![account isEqual:WXGAccount]){WXGAccount=account;WXGAccountSource=source;WXGAccountCode=WXGAccountHash(account);}
    }
    WXGLicenseState state=WXGAccountCode?WXGLicenseFromUnlock(WXGUnlockStateFor(WXGAccountCode,force)):WXGLicenseUnknown;
    if(state!=WXGState) {
        WXGState=state;
        WXGLog(@"授权：%@（%@）",WXGLicenseStateName(state),WXGAccountSource?:@"未读到账号");
        [WXGIntegrationHost.shared schedule];
    }
    return WXGState;
}
WXGLicenseState WXGLicenseCurrentState(BOOL recheck) {return WXGLicenseEvaluate(recheck,NO);}
WXGLicenseState WXGLicenseRecheckServer(void) {return WXGLicenseEvaluate(YES,YES);}
// FIX109: 自相矛盾陷阱。正版里"授权为真"必然伴随"有真票或真着色器"——授权状态本就由票派生。
// 破解只把授权判定焊成真，却造不出票/着色器(他那份诊断就是 shaderReady=false、ticket={})。
// 所以"自称已授权、却既无票也无着色器、还过了启动宽限"= 判定被 patch → 不再放行渲染，且锁定本次运行。
// 它照样能被再 patch 掉；意义在于每版、在混淆包里，是破解者要再找的"又一个"点(明文包里一眼删掉)。
static BOOL WXGLicenseTamperSuspected(void) {
#ifdef WXG_FORCE_AUTHORIZED
    return NO;   // 强制授权自测包本就无票，别自触发
#endif
    static BOOL tripped=NO; if(tripped)return YES;
    // 只在已被判为"授权"后才会走到这里(见 WXGPluginEnabled)；核对是否有真货。
    if(WXGUnlockShaderReady() || WXGUnlockHasUsableTicket(WXGAccountCode))return NO;   // 有真货 = 正版
    static CFTimeInterval firstSeen=0; CFTimeInterval now=CACurrentMediaTime();
    if(firstSeen==0){firstSeen=now;return NO;}   // 第一次看到，给足正版启动/取票宽限
    if(now-firstSeen<60)return NO;               // 60s 宽限：正版一旦授权就有票，绝不会卡在这，杜绝误伤
    tripped=YES; return YES;
}
BOOL WXGPluginEnabled(void) {
    if(!WXGPreferences.shared.enabled)return NO;
    if(WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized)return NO;
    if(WXGLicenseTamperSuspected())return NO;    // FIX109: 自称已授权，但拿不出真货 → 拒绝
    return YES;
}
NSString *WXGLicenseAccount(void) {return WXGAccount;}
NSString *WXGLicenseCode(void) {return WXGAccountCode;}
NSString *WXGLicenseAccountSource(void) {return WXGAccountSource;}
NSDictionary *WXGLicenseEvidence(void) {
    NSString *masked=WXGAccount.length>10?[NSString stringWithFormat:@"%@…%@",[WXGAccount substringToIndex:6],[WXGAccount substringFromIndex:WXGAccount.length-4]]:WXGAccount;
    return @{@"build":WXGBuildLabel(),@"state":WXGLicenseStateName(WXGState),@"code":WXGAccountCode.length>8?[WXGAccountCode substringToIndex:8]:@"",
             @"account":masked?:@"",@"source":WXGAccountSource?:@"",@"mainInterface":@(WXGMainInterface),
             @"accountReads":@(WXGAccountReads),@"accountReadLastMS":@(round(WXGAccountReadMS*10)/10),@"accountReadMaxMS":@(round(WXGAccountReadMaxMS*10)/10),
             @"accountReadsPutOff":@(WXGAccountReadsPut),
             @"unlock":WXGUnlockEvidence(),@"hiddenModules":WXGHiddenSettingsModules(),
             @"buildDefaults":@{@"config":@(WXGBuildDefaultSection(@"config").count),@"integration":@(WXGBuildDefaultSection(@"integration").count),
                                @"ui":@(WXGBuildDefaultSection(@"ui").count)}};
}
