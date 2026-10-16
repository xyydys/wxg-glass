#import "WXGIntegration.h"
#import "WXGBuildProfile.h"
#import "WXGUnlockPolicy.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#import <os/lock.h>

// FIX103: the glass shader is not in the plugin. The unlock server
// (WXG_UNLOCK_ENDPOINTS, the wxg-glass Worker) gives it to the accounts on its
// list, as a ticket signed for this account and this device; the plugin checks
// the signature with the public key below (WXG_UNLOCK_PUBLIC_KEY) and the
// shader against the signed digest, keeps the ticket encrypted on disk and
// works offline until it expires (7 days, renewed in the background).
//
// The account is sent as the licence code SHA-256("WXGLiquidGlass.license.v1:"
// + wxid) (WXGLicense.m), the device as SHA-256("WXGLiquidGlass.device.v1:" +
// identifierForVendor); neither the wxid nor the vendor id leaves the phone.
//
// Everything here runs on the main thread except the network answer and the
// disk, which run on WXGUnlockQueue and hand their result back to main.

NSString * const WXGLicenseChangedNotification=@"WXGLicenseChangedNotification";
// The shader this plugin's uniforms are laid out for (WXGGlassView.m: 19 float4,
// 304 bytes). The server's VER must be this; another version is not used.
#define WXG_SHADER_VERSION @"1"

@interface WXGUnlockTicket : NSObject
@property(nonatomic,copy) NSString *account,*device,*ver,*digest,*origin;
@property(nonatomic) long long expiresAt;
@property(nonatomic) double fetchedAt;
@property(nonatomic) double recheckAfter;   // FIX104: the server's, as sent (0: none; WXGUnlockRecheckInterval applies the rules)
@property(nonatomic,copy) NSData *shader,*sig,*shaderSealed;
@end
@implementation WXGUnlockTicket
@end

typedef NS_ENUM(NSInteger,WXGUnlockAnswer) {WXGUnlockAnswerTicket,WXGUnlockAnswerDenied,WXGUnlockAnswerStale,WXGUnlockAnswerOutdated,WXGUnlockAnswerFailed};
@interface WXGUnlockResult : NSObject
@property(nonatomic) WXGUnlockAnswer answer;
@property(nonatomic,strong) WXGUnlockTicket *ticket;
@property(nonatomic,copy) NSString *account,*error,*serverVer;
@property(nonatomic) NSInteger status;
@property(nonatomic) double clockOffset,ms,deniedWait;   // FIX104: deniedWait, seconds before a refused account asks again
@property(nonatomic) BOOL haveOffset,badSignature;
@end
@implementation WXGUnlockResult
@end

// Main thread only. The last answer's account (WXGAttemptAccount) owns the
// back-off, the failure count and the error: another account is not held up
// by them, nor shown them.
static BOOL WXGStarted,WXGCacheLoaded,WXGInFlight;
static NSString *WXGDeviceHash,*WXGInFlightAccount,*WXGAttemptAccount,*WXGLastError,*WXGOutdatedVer;
static NSMutableDictionary<NSString *,WXGUnlockTicket *> *WXGTickets;
static NSMutableSet<NSString *> *WXGDeniedAccounts;
// FIX104: the shader and those waiting for it, under WXGShaderLock (offered
// from the cache read on WXGUnlockQueue, or from main for a server answer).
static os_unfair_lock WXGShaderLock=OS_UNFAIR_LOCK_INIT;
static NSString *WXGShaderText,*WXGShaderOrigin;
static NSMutableArray *WXGShaderWaiters;
static unsigned WXGFailures;
static CFTimeInterval WXGNextAttempt,WXGOutdatedAt,WXGEvalAt;
static double WXGClockOffset,WXGLastRequestMS;
static NSInteger WXGLastStatus,WXGEndpointIndex;
static NSUInteger WXGRequests,WXGTicketsIssued,WXGDenials,WXGBadSignatures,WXGCacheHits;
static NSString *WXGEvalAccount;
static WXGUnlockState WXGEvalState;

static dispatch_queue_t WXGUnlockQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("wxg.unlock",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});
    return queue;
}
static double WXGDeviceNow(void) {return NSDate.date.timeIntervalSince1970;}
static NSArray<NSString *> *WXGEndpoints(void) {
    // Built at runtime from encrypted C strings (see WXGBuildProfile.h): no
    // plaintext endpoint @"..." literal is baked into the dylib.
    static const char *const eps[]={WXG_UNLOCK_ENDPOINTS_C};
    NSMutableArray<NSString *> *a=[NSMutableArray arrayWithCapacity:sizeof(eps)/sizeof(*eps)];
    for(size_t i=0;i<sizeof(eps)/sizeof(*eps);i++)[a addObject:[NSString stringWithUTF8String:eps[i]]];
    return a;
}

#pragma mark - Hashes, keys

static NSString *WXGHex(const unsigned char *bytes,size_t length) {
    NSMutableString *hex=[NSMutableString stringWithCapacity:length*2];
    for(size_t i=0;i<length;i++)[hex appendFormat:@"%02x",bytes[i]];
    return hex;
}
static NSString *WXGSHA256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    return WXGHex(digest,sizeof digest);
}
static NSData *WXGFromHex(const char *hex) {
    size_t n=hex?strlen(hex):0;if(n%2)return nil;
    NSMutableData *data=[NSMutableData dataWithLength:n/2];unsigned char *out=data.mutableBytes;
    for(size_t i=0;i<n/2;i++) {
        unsigned value=0;
        if(sscanf(hex+2*i,"%2x",&value)!=1)return nil;
        out[i]=(unsigned char)value;
    }
    return data;
}
static NSData *WXGCrypt(CCOperation operation,NSData *key,const void *iv,NSData *input);   // 定义在下方「加密缓存」一节
// HKDF-SHA256 (RFC 5869)，取 32 字节（L = 散列长度，一次 expand 即可）。
static NSData *WXGHKDF32(NSData *ikm,NSData *salt,NSData *info) {
    unsigned char prk[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,salt.length?salt.bytes:(const void *)"",salt.length,ikm.bytes,ikm.length,prk);   // extract
    NSMutableData *block=[NSMutableData dataWithData:info];
    unsigned char counter=0x01;[block appendBytes:&counter length:1];   // expand: info ‖ 0x01
    unsigned char okm[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,prk,sizeof prk,block.bytes,block.length,okm);
    return [NSData dataWithBytes:okm length:sizeof okm];
}
// FIX106: 着色器不再明文下发。服务器用 AES-256-CBC 把它封好（iv ‖ 密文），密钥由 HKDF
// 从票据的签名(ikm)、着色器摘要(salt)、账号+设备(info)派生。只有对这个账号 + 这台设备
// 的真签名才能解开：patch 掉验签、或自建服务器伪造票据，都只会解出坏着色器而不是打开
// 大门；账号/设备并不在票据里，所以把别人的票据搬到另一台设备也解不开。解出来后仍由
// WXGTicketProblem 的 SHA256(着色器)==digest 核对（密钥不对 → 摘要不符 → 丢弃）。
static NSData *WXGUnsealShader(NSData *sealed,NSData *sig,NSString *digest,NSString *account,NSString *device) {
    if(sealed.length<=kCCBlockSizeAES128 || !sig.length || !account || !device)return nil;
    NSData *salt=WXGFromHex(digest.UTF8String);
    if(salt.length!=CC_SHA256_DIGEST_LENGTH)return nil;
    NSData *info=[[NSString stringWithFormat:@"WXGLiquidGlass.shader.v1|%@|%@",account,device] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key=WXGHKDF32(sig,salt,info);
    NSData *ciphertext=[sealed subdataWithRange:NSMakeRange(kCCBlockSizeAES128,sealed.length-kCCBlockSizeAES128)];
    NSData *plain=WXGCrypt(kCCDecrypt,key,sealed.bytes,ciphertext);   // iv = sealed 的前 16 字节
    return plain.length?plain:nil;
}
// identifierForVendor stays the same for WeChat on this phone (it changes only
// if every Tencent app is deleted); nil just after a reboot, before unlock.
static NSString *WXGComputeDeviceHash(void) {
    NSUUID *vendor=UIDevice.currentDevice.identifierForVendor;
    if(!vendor)return nil;
    return WXGSHA256Hex([[@"WXGLiquidGlass.device.v1:" stringByAppendingString:vendor.UUIDString] dataUsingEncoding:NSUTF8StringEncoding]);
}
// The cache key belongs to this account on this phone: a copied file cannot
// even be decrypted elsewhere (and its signature names the device anyway).
static NSData *WXGCacheKey(NSString *account,NSString *device) {
    static const unsigned char seed[32]={0x19,0x2c,0xb2,0x77,0x74,0x92,0xdf,0x3b,0xa6,0x36,0xfe,0x61,0x04,0xc5,0x97,0x54,
                                         0x63,0xd7,0x34,0xae,0x5e,0x78,0xec,0xf1,0x3e,0x6b,0xc9,0x29,0xca,0x85,0xd3,0xb7};
    NSData *message=[[NSString stringWithFormat:@"cache.v1|%@|%@",account,device] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *key=[NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,seed,sizeof seed,message.bytes,message.length,key.mutableBytes);
    return key;
}

#pragma mark - Checking a ticket (any thread)

static BOOL WXGSignatureValid(NSData *message,NSData *signature) {
    NSData *raw=WXGFromHex(WXG_UNLOCK_PUBLIC_KEY);
    if(raw.length!=65 || !signature.length)return NO;
    NSDictionary *attributes=@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                               (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
                               (__bridge id)kSecAttrKeySizeInBits:@256};
    CFErrorRef error=NULL;
    SecKeyRef key=SecKeyCreateWithData((__bridge CFDataRef)raw,(__bridge CFDictionaryRef)attributes,&error);
    if(!key){if(error)CFRelease(error);return NO;}
    Boolean valid=SecKeyVerifySignature(key,kSecKeyAlgorithmECDSASignatureMessageX962SHA256,(__bridge CFDataRef)message,(__bridge CFDataRef)signature,&error);
    if(error)CFRelease(error);
    CFRelease(key);
    return valid;
}
// nil when the ticket is genuine and for this account and device; otherwise why not.
static NSString *WXGTicketProblem(WXGUnlockTicket *ticket,NSString *account,NSString *device) {
    if(!ticket || ![ticket.account isEqualToString:account] || ![ticket.device isEqualToString:device])return @"票据不属于这个账号或这台设备";
    if(!ticket.shader.length || ![WXGSHA256Hex(ticket.shader) isEqualToString:ticket.digest])return @"着色器和摘要不符";
    char message[400];
    int length=WXGUnlockSignedMessage(message,sizeof message,ticket.account.UTF8String,ticket.device.UTF8String,
                                      ticket.ver.UTF8String,ticket.expiresAt,ticket.digest.UTF8String);
    if(length<0)return @"票据字段格式不对";
    if(!WXGSignatureValid([NSData dataWithBytes:message length:(NSUInteger)length],ticket.sig))return @"签名校验失败";
    return nil;
}
static NSString *WXGStringValue(id value) {
    if([value isKindOfClass:NSString.class])return value;
    if([value isKindOfClass:NSNumber.class])return [value stringValue];
    return nil;
}
// FIX104: a number of seconds the server sent (a number or a numeric string); 0 if none.
static double WXGSecondsValue(id value) {
    if([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) {
        double seconds=[value doubleValue];
        return seconds>0 && isfinite(seconds)?seconds:0;
    }
    return 0;
}
// The server's answer as a ticket (not yet checked); nil if a field is missing.
static WXGUnlockTicket *WXGTicketFromAnswer(NSDictionary *body,NSString *account,NSString *device) {
    if(![body isKindOfClass:NSDictionary.class])return nil;
    NSString *ver=WXGStringValue(body[@"ver"]),*digest=WXGStringValue(body[@"digest"]);
    NSString *shader=WXGStringValue(body[@"shader"]),*sig=WXGStringValue(body[@"sig"]);
    id expires=body[@"expiresAt"];
    if(!ver.length || !digest.length || !shader.length || !sig.length || ![expires isKindOfClass:NSNumber.class])return nil;
    double expiresAt=[expires doubleValue];
    if(!(expiresAt>0) || expiresAt!=floor(expiresAt) || expiresAt>4e12)return nil;
    WXGUnlockTicket *ticket=[WXGUnlockTicket new];
    ticket.account=account;ticket.device=device;ticket.ver=ver;ticket.digest=digest.lowercaseString;
    ticket.expiresAt=(long long)expiresAt;
    ticket.sig=[[NSData alloc] initWithBase64EncodedString:sig options:NSDataBase64DecodingIgnoreUnknownCharacters];
    ticket.shaderSealed=[[NSData alloc] initWithBase64EncodedString:shader options:NSDataBase64DecodingIgnoreUnknownCharacters];
    ticket.shader=WXGUnsealShader(ticket.shaderSealed,ticket.sig,ticket.digest,account,device);   // FIX106: 验签派生密钥解封着色器
    ticket.recheckAfter=WXGSecondsValue(body[@"recheckAfter"]);
    return ticket.shader && ticket.sig?ticket:nil;
}

#pragma mark - The encrypted cache (WXGUnlockQueue)

// FIX111：缓存仍在 Application Support（不被 iOS 清理），但目录/文件名不再写 "Unlock"/
// "WeChatLiquidGlass"，改成从固定串派生的不透明十六进制名——障眼法，让翻容器的人不会一眼
// 认出是授权缓存（混淆包里路径字符串本就加密，磁盘上的名字也不再是牌子了）。内容/加密/绑定不变：
// 仍是 "WXGU1" + 随机 IV + AES-256-CBC(票据 JSON)，钥匙 WXGCacheKey(account,device)。
// 诚实边界：只是 OPSEC 整洁，hook 文件 API 的逆向照样能抓到。
static NSString *WXGOpaqueName(NSString *seed,NSUInteger hexLen) {
    NSData *d=[seed dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes,(CC_LONG)d.length,h);
    NSMutableString *s=[NSMutableString stringWithCapacity:hexLen];
    for(NSUInteger i=0;i*2<hexLen && i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",h[i]];
    return s;
}
static NSURL *WXGCacheDirectory(void) {
    NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:WXGOpaqueName(@"wxg.store.v1",20) isDirectory:YES];   // 稳定、不透明、不碰微信自己的目录
}
static NSURL *WXGCacheFile(NSString *account) {
    NSString *name=WXGOpaqueName([@"wxg.item.v1|" stringByAppendingString:account?:@""],24);
    return [WXGCacheDirectory() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"dat"]];
}
// 一次性清理旧的显眼目录（Application Support 下 WeChatLiquidGlass 只有 Unlock，可整删）。
static void WXGCleanupLegacyCache(void) {
    NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if(base)[NSFileManager.defaultManager removeItemAtURL:[base URLByAppendingPathComponent:@"WeChatLiquidGlass" isDirectory:YES] error:nil];
}
static NSData *WXGCrypt(CCOperation operation,NSData *key,const void *iv,NSData *input) {
    NSMutableData *output=[NSMutableData dataWithLength:input.length+kCCBlockSizeAES128];size_t moved=0;
    CCCryptorStatus status=CCCrypt(operation,kCCAlgorithmAES,kCCOptionPKCS7Padding,key.bytes,kCCKeySizeAES256,iv,
                                   input.bytes,input.length,output.mutableBytes,output.length,&moved);
    if(status!=kCCSuccess)return nil;
    output.length=moved;return output;
}
static const char WXGCacheMagic[5]={'W','X','G','U','1'};
static void WXGWriteCache(WXGUnlockTicket *ticket) {
    NSDictionary *plain=@{@"account":ticket.account,@"device":ticket.device,@"ver":ticket.ver,@"expiresAt":@(ticket.expiresAt),
                          @"digest":ticket.digest,@"fetchedAt":@(ticket.fetchedAt),@"recheckAfter":@(ticket.recheckAfter),
                          @"sig":[ticket.sig base64EncodedStringWithOptions:0],@"shader":[ticket.shaderSealed base64EncodedStringWithOptions:0]};   // FIX106: 缓存里也只存封好的密文
    NSData *json=[NSJSONSerialization dataWithJSONObject:plain options:0 error:nil];
    unsigned char iv[kCCBlockSizeAES128];
    if(!json || SecRandomCopyBytes(kSecRandomDefault,sizeof iv,iv)!=errSecSuccess)return;
    NSData *sealed=WXGCrypt(kCCEncrypt,WXGCacheKey(ticket.account,ticket.device),iv,json);
    if(!sealed)return;
    NSMutableData *file=[NSMutableData dataWithBytes:WXGCacheMagic length:sizeof WXGCacheMagic];
    [file appendBytes:iv length:sizeof iv];[file appendData:sealed];
    NSURL *directory=WXGCacheDirectory();
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];   // bound to this phone anyway
    NSError *error=nil;
    if(![file writeToURL:WXGCacheFile(ticket.account) options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error])
        WXGLog(@"授权缓存写入失败：%@",error.localizedDescription);
}
static void WXGDeleteCache(NSString *account) {
    [NSFileManager.defaultManager removeItemAtURL:WXGCacheFile(account) error:nil];
}
// *discard: the file is not a ticket of this phone or no longer valid. A file
// that cannot be read now (protected data before the first unlock, an I/O
// error) or decrypted with this phone's key is left alone.
static WXGUnlockTicket *WXGReadCache(NSURL *url,NSString *device,BOOL *discard) {
    *discard=NO;
    NSString *account=url.URLByDeletingPathExtension.lastPathComponent;
    if(!WXGUnlockHex64(account.UTF8String)){*discard=YES;return nil;}
    NSData *file=[NSData dataWithContentsOfURL:url];
    if(!file)return nil;
    size_t header=sizeof WXGCacheMagic+kCCBlockSizeAES128;
    if(file.length<=header || memcmp(file.bytes,WXGCacheMagic,sizeof WXGCacheMagic)){*discard=YES;return nil;}
    NSData *sealed=[file subdataWithRange:NSMakeRange(header,file.length-header)];
    NSData *json=WXGCrypt(kCCDecrypt,WXGCacheKey(account,device),(const unsigned char *)file.bytes+sizeof WXGCacheMagic,sealed);
    NSDictionary *plain=json?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:nil;
    if(![plain isKindOfClass:NSDictionary.class])return nil;
    *discard=YES;
    if(![plain[@"account"] isEqual:account] || ![plain[@"device"] isEqual:device])return nil;
    WXGUnlockTicket *ticket=WXGTicketFromAnswer(plain,account,device);
    ticket.fetchedAt=[plain[@"fetchedAt"] isKindOfClass:NSNumber.class]?[plain[@"fetchedAt"] doubleValue]:0;
    ticket.origin=@"cache";
    if(!ticket || WXGTicketProblem(ticket,account,device) || ![ticket.ver isEqualToString:WXG_SHADER_VERSION] ||
       !WXGUnlockTicketUsable(WXGDeviceNow(),(double)ticket.expiresAt,ticket.fetchedAt))return nil;
    *discard=NO;
    return ticket;
}
// Every cached ticket of this phone that is genuine and not expired; invalid
// or expired ones are deleted.
static NSArray<WXGUnlockTicket *> *WXGLoadCache(NSString *device) {
    NSMutableArray *tickets=[NSMutableArray array];
    NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:WXGCacheDirectory() includingPropertiesForKeys:nil options:0 error:nil];
    for(NSURL *url in files) {
        if(![url.pathExtension isEqualToString:@"dat"])continue;
        BOOL discard=NO;
        WXGUnlockTicket *ticket=WXGReadCache(url,device,&discard);
        if(ticket)[tickets addObject:ticket];
        else if(discard)[NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
    return tickets;
}

#pragma mark - The shader for the Metal pipeline

static void WXGOfferShader(WXGUnlockTicket *ticket) {
    if(!ticket.shader.length)return;
    os_unfair_lock_lock(&WXGShaderLock);BOOL offered=WXGShaderText!=nil;os_unfair_lock_unlock(&WXGShaderLock);
    if(offered)return;   // FIX104: a renewal (every few minutes) does not decode it again
    NSString *source=[[NSString alloc] initWithData:ticket.shader encoding:NSUTF8StringEncoding];
    if(!source.length)return;
    NSArray *waiters=nil;
    os_unfair_lock_lock(&WXGShaderLock);
    if(!WXGShaderText) {
        WXGShaderText=source;WXGShaderOrigin=ticket.origin;
        waiters=WXGShaderWaiters.copy?:@[];[WXGShaderWaiters removeAllObjects];
    }
    os_unfair_lock_unlock(&WXGShaderLock);
    if(!waiters)return;   // offered before
    WXGLog(@"玻璃着色器已就绪（%@，%lu 字节，加载后 %.0f ms）",ticket.origin,(unsigned long)ticket.shader.length,WXGSecondsSinceLoad()*1000);
    for(void (^block)(NSString *) in waiters)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{block(source);});
}
// FIX104: any thread, no hop through main (the pipeline registers from the
// constructor; the cached shader can arrive before WeChat's first frame).
void WXGUnlockWhenShaderReady(void (^block)(NSString *source)) {
    if(!block)return;
    NSString *source=nil;
    os_unfair_lock_lock(&WXGShaderLock);
    source=WXGShaderText;
    if(!source) {
        if(!WXGShaderWaiters)WXGShaderWaiters=[NSMutableArray array];
        [WXGShaderWaiters addObject:[block copy]];
    }
    os_unfair_lock_unlock(&WXGShaderLock);
    if(source)dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{block(source);});
}
static BOOL WXGShaderReady(NSString **origin) {
    os_unfair_lock_lock(&WXGShaderLock);
    BOOL ready=WXGShaderText!=nil;if(origin)*origin=WXGShaderOrigin;
    os_unfair_lock_unlock(&WXGShaderLock);
    return ready;
}

#pragma mark - Asking the server

// host: whether the glass may have to come or go. FIX104: with checks every
// few minutes, an answer that leaves the account as it was (a renewal, a
// failure while the ticket still works) no longer refreshes the whole host;
// the settings page still hears of it (new expiry, last error).
static void WXGChanged(BOOL host) {
    WXGEvalAt=0;
    [NSNotificationCenter.defaultCenter postNotificationName:WXGLicenseChangedNotification object:nil];
    if(host)[WXGIntegrationHost.shared schedule];
}
static NSURLSession *WXGUnlockSession(void) {
    static NSURLSession *session;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest=15;configuration.timeoutIntervalForResource=20;
        configuration.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;configuration.URLCache=nil;
        NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;queue.underlyingQueue=WXGUnlockQueue();
        session=[NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:queue];
    });
    return session;
}
static double WXGServerDate(NSHTTPURLResponse *response) {
    NSString *date=[response isKindOfClass:NSHTTPURLResponse.class]?[response valueForHTTPHeaderField:@"Date"]:nil;
    if(![date isKindOfClass:NSString.class])return 0;
    static NSDateFormatter *formatter;static dispatch_once_t once;
    dispatch_once(&once,^{
        formatter=[NSDateFormatter new];formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];formatter.dateFormat=@"EEE',' dd MMM yyyy HH':'mm':'ss z";
    });
    return [formatter dateFromString:date].timeIntervalSince1970;   // only ever used on WXGUnlockQueue
}
// WXGUnlockQueue: what the server said, checked; a new ticket is also cached.
// FIX104: recheckAfter of a 403 (how long a refused account waits).
static double WXGDeniedRecheckOf(id body) {
    return [body isKindOfClass:NSDictionary.class]?WXGSecondsValue(body[@"recheckAfter"]):0;
}
static WXGUnlockResult *WXGReadAnswer(NSString *account,NSString *device,double previousOffset,NSData *data,NSURLResponse *response,NSError *error) {
    WXGUnlockResult *result=[WXGUnlockResult new];result.account=account;result.clockOffset=previousOffset;
    NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(NSHTTPURLResponse *)response:nil;
    result.status=http.statusCode;
    double serverDate=WXGServerDate(http);
    if(serverDate>0){result.clockOffset=WXGUnlockClockOffset(WXGDeviceNow(),serverDate,previousOffset);result.haveOffset=YES;}
    if(error || !http) {
        result.answer=WXGUnlockAnswerFailed;
        result.error=[NSString stringWithFormat:@"连不上授权服务器（%@）",error.localizedDescription?:@"没有回应"];
        return result;
    }
    id body=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSString *serverError=[body isKindOfClass:NSDictionary.class]?WXGStringValue(body[@"error"]):nil;
    // Only the Worker's own refusal revokes; a 403 from a proxy or a block page is a failure.
    if(http.statusCode==403 && [serverError isEqualToString:@"not authorized"]){result.answer=WXGUnlockAnswerDenied;result.deniedWait=WXGUnlockDeniedWait(WXGDeniedRecheckOf(body));return result;}
    if(http.statusCode==400 && [serverError isEqualToString:@"stale"]){result.answer=WXGUnlockAnswerStale;result.error=@"手机时间和服务器相差超过 5 分钟";return result;}
    if(http.statusCode!=200) {
        result.answer=WXGUnlockAnswerFailed;
        result.error=[NSString stringWithFormat:@"服务器返回 %ld%@%@",(long)http.statusCode,serverError?@"：":@"",serverError?:@""];
        return result;
    }
    WXGUnlockTicket *ticket=WXGTicketFromAnswer(body,account,device);
    NSString *problem=ticket?WXGTicketProblem(ticket,account,device):@"服务器的回答缺少字段";
    if(problem) {
        result.answer=WXGUnlockAnswerFailed;result.error=problem;result.badSignature=ticket!=nil;
        return result;
    }
    if(![ticket.ver isEqualToString:WXG_SHADER_VERSION]){result.answer=WXGUnlockAnswerOutdated;result.serverVer=ticket.ver;return result;}
    ticket.fetchedAt=WXGDeviceNow()+result.clockOffset;ticket.origin=@"server";
    WXGWriteCache(ticket);
    result.answer=WXGUnlockAnswerTicket;result.ticket=ticket;
    return result;
}
static void WXGRequest(NSString *account,BOOL retryIfStale);
static BOOL WXGTicketUsableFor(NSString *account) {
    WXGUnlockTicket *ticket=account?WXGTickets[account]:nil;
    return ticket && WXGUnlockTicketUsable(WXGDeviceNow()+WXGClockOffset,(double)ticket.expiresAt,ticket.fetchedAt);
}
static void WXGApplyAnswer(WXGUnlockResult *result,BOOL retryIfStale) {
    // FIX104: what the host was last told for this account (before the
    // answer's Date moves the clock), so a clock correction alone that makes
    // the ticket usable or not still reaches it.
    BOOL shownReady=[WXGEvalAccount isEqualToString:result.account] && WXGEvalState==WXGUnlockReady;
    WXGInFlight=NO;WXGInFlightAccount=nil;
    WXGLastStatus=result.status;WXGLastRequestMS=result.ms;
    if(result.haveOffset)WXGClockOffset=result.clockOffset;
    NSString *account=result.account;CFTimeInterval mono=CACurrentMediaTime();
    BOOL usableBefore=WXGTicketUsableFor(account);   // FIX104: also, a renewal logs once an hour, not every few minutes
    if(![WXGAttemptAccount isEqualToString:account]){WXGAttemptAccount=account;WXGFailures=0;WXGLastError=nil;}
    switch(result.answer) {
        case WXGUnlockAnswerTicket:
            WXGTickets[account]=result.ticket;[WXGDeniedAccounts removeObject:account];
            // Not again for a minute, whatever the ticket says (a short-lived
            // ticket would otherwise be renewed on every evaluation).
            WXGFailures=0;WXGNextAttempt=mono+60;WXGLastError=nil;WXGOutdatedVer=nil;++WXGTicketsIssued;
            {static CFTimeInterval loggedAt;
             if(!usableBefore || mono-loggedAt>3600){loggedAt=mono;WXGLog(@"授权：服务器已签发，有效期至 %@，%.0f s 后复查",[NSDate dateWithTimeIntervalSince1970:(double)result.ticket.expiresAt],WXGUnlockRecheckInterval(result.ticket.recheckAfter));}}
            WXGOfferShader(result.ticket);
            break;
        case WXGUnlockAnswerDenied: {
            [WXGDeniedAccounts addObject:account];[WXGTickets removeObjectForKey:account];++WXGDenials;
            WXGFailures=0;WXGNextAttempt=mono+result.deniedWait;WXGLastError=@"账号不在服务器的授权名单里";   // FIX104: the 403's recheckAfter (WXGUnlockDeniedWait)
            dispatch_async(WXGUnlockQueue(),^{WXGDeleteCache(account);});
            WXGLog(@"授权：服务器拒绝（403），已删除本地票据");
            break;
        }
        case WXGUnlockAnswerOutdated:
            WXGOutdatedVer=result.serverVer;WXGOutdatedAt=mono;
            WXGFailures=0;WXGNextAttempt=mono+WXG_UNLOCK_OUTDATED_RECHECK;
            WXGLastError=[NSString stringWithFormat:@"服务器的着色器是第 %@ 版，这个插件需要第 %@ 版",result.serverVer,WXG_SHADER_VERSION];
            WXGLog(@"授权：%@",WXGLastError);
            break;
        case WXGUnlockAnswerStale:
            if(retryIfStale && result.haveOffset){WXGLog(@"授权：手机时间偏差 %.0f s，按服务器时间重试",WXGClockOffset);WXGRequest(account,NO);return;}
            __attribute__((fallthrough));   // a failure like any other
        case WXGUnlockAnswerFailed: {
            BOOL usable=WXGTicketUsableFor(account);
            ++WXGFailures;WXGNextAttempt=mono+WXGUnlockBackoff(WXGFailures,usable);WXGLastError=result.error;
            if(result.badSignature)++WXGBadSignatures;
            if(WXGEndpoints().count>1)WXGEndpointIndex=(WXGEndpointIndex+1)%(NSInteger)WXGEndpoints().count;
            WXGLog(@"授权：%@（第 %u 次，%.0f s 后再试）",result.error,WXGFailures,WXGUnlockBackoff(WXGFailures,usable));
            break;
        }
    }
    // A refusal always reaches the host (the glass goes now, FIX104's point).
    BOOL usableNow=WXGTicketUsableFor(account);
    WXGChanged(result.answer==WXGUnlockAnswerDenied || usableNow!=shownReady || usableNow!=usableBefore);
}
static void WXGRequest(NSString *account,BOOL retryIfStale) {
    NSArray<NSString *> *endpoints=WXGEndpoints();
    NSURL *url=endpoints.count?[NSURL URLWithString:endpoints[(NSUInteger)WXGEndpointIndex%endpoints.count]]:nil;
    NSString *device=WXGDeviceHash;double offset=WXGClockOffset;
    if(!url || !device)return;
    WXGInFlight=YES;WXGInFlightAccount=account;++WXGRequests;
    // FIX104: built and sent from WXGUnlockQueue: an authorized account now
    // asks every few minutes, and at launch inside the first refresh (the
    // session's first use is not free).
    dispatch_async(WXGUnlockQueue(),^{
        long long ts=llround(WXGDeviceNow()+offset);
        NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"account":account,@"device":device,@"ts":@(ts),@"ver":WXG_SHADER_VERSION} options:0 error:nil];
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
        request.HTTPMethod=@"POST";request.HTTPBody=body;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        CFTimeInterval started=CACurrentMediaTime();
        NSURLSessionDataTask *task=[WXGUnlockSession() dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            WXGUnlockResult *result=WXGReadAnswer(account,device,offset,data,response,error);
            result.ms=(CACurrentMediaTime()-started)*1000;
            dispatch_async(dispatch_get_main_queue(),^{WXGApplyAnswer(result,retryIfStale);});
        }];
        [task resume];
    });
}

#pragma mark - State

// FIX104 (cold start: native interface first, then a jump to glass): FIX103
// handed the cached tickets to main by a hop queued behind WeChat's launch,
// so the first refresh still found none ("正在验证"), and the shader was
// offered to the Metal pipeline only after that hop. Now the read starts in
// the constructor (WXGUnlockStart), offers the shader straight from
// WXGUnlockQueue, and main takes the tickets over before it first decides
// anything (WXGAdoptCache), waiting for a read still running, once, briefly.
#define WXG_UNLOCK_LAUNCH_WAIT (.3)   // s; the read takes a few ms and starts long before
static BOOL WXGCacheLoading,WXGCacheWaited;            // main
static dispatch_group_t WXGCacheGroup;                 // main; the read leaves it when done
static NSString *WXGReadDevice;                        // written by the read before it leaves the group,
static NSArray<WXGUnlockTicket *> *WXGReadTickets;     // taken by main after waiting on it
static double WXGReadMS,WXGReadAtMS;                   // likewise
static double WXGCacheReadMS=-1,WXGCacheReadAtMS=-1,WXGCacheWaitMS=-1;   // main, for the diagnostics
static BOOL WXGAdoptCache(double wait);
static void WXGStartCacheLoad(void) {   // main
    if(WXGCacheLoaded || WXGCacheLoading)return;
    WXGCacheLoading=YES;
    dispatch_group_t group=dispatch_group_create();dispatch_group_enter(group);WXGCacheGroup=group;
    NSString *known=WXGDeviceHash;
    // Above WXGUnlockQueue's utility QoS: main may be waiting for it.
    dispatch_block_t read=dispatch_block_create_with_qos_class(DISPATCH_BLOCK_ENFORCE_QOS_CLASS,QOS_CLASS_USER_INITIATED,0,^{
        CFTimeInterval started=CACurrentMediaTime();
        NSString *device=known?:WXGComputeDeviceHash();
        NSArray<WXGUnlockTicket *> *tickets=device?WXGLoadCache(device):@[];
        // Compile the shader now, as before FIX103, even before the account
        // is read: it is genuine; using it still needs this account's ticket.
        WXGUnlockTicket *newest=nil;
        for(WXGUnlockTicket *ticket in tickets)if(!newest || ticket.fetchedAt>newest.fetchedAt)newest=ticket;
        if(newest)WXGOfferShader(newest);
        WXGReadDevice=device;WXGReadTickets=tickets;
        WXGReadMS=(CACurrentMediaTime()-started)*1000;WXGReadAtMS=WXGSecondsSinceLoad()*1000;
        dispatch_group_leave(group);
        // Nobody has asked yet: take them over at main's next turn.
        dispatch_async(dispatch_get_main_queue(),^{if(WXGAdoptCache(0))WXGChanged(YES);});
    });
    dispatch_async(WXGUnlockQueue(),read);
}
// Main: take over what the read found, waiting up to `wait` s for it. YES when
// this call took the tickets over.
static BOOL WXGAdoptCache(double wait) {
    if(WXGCacheLoaded || !WXGCacheLoading)return NO;
    CFTimeInterval started=CACurrentMediaTime();
    dispatch_time_t until=wait>0?dispatch_time(DISPATCH_TIME_NOW,(int64_t)(wait*NSEC_PER_SEC)):DISPATCH_TIME_NOW;
    long timedOut=dispatch_group_wait(WXGCacheGroup,until);
    if(wait>0)WXGCacheWaitMS=(CACurrentMediaTime()-started)*1000;
    if(timedOut)return NO;
    WXGCacheLoading=NO;WXGCacheGroup=nil;
    NSString *device=WXGReadDevice;NSArray<WXGUnlockTicket *> *tickets=WXGReadTickets;
    WXGReadDevice=nil;WXGReadTickets=nil;WXGCacheReadMS=WXGReadMS;WXGCacheReadAtMS=WXGReadAtMS;
    if(!device)return NO;   // no identifierForVendor yet (before the first unlock): WXGUnlockStateFor tries again
    if(!WXGDeviceHash)WXGDeviceHash=device;
    for(WXGUnlockTicket *ticket in tickets)if(!WXGTickets[ticket.account])WXGTickets[ticket.account]=ticket;
    WXGCacheHits=tickets.count;WXGCacheLoaded=YES;
    return YES;
}
// Main thread, at launch (FIX104: from the constructor): the cached tickets
// and the device id start loading at once, off main.
void WXGUnlockStart(void) {
    if(WXGStarted || !NSThread.isMainThread)return;
    WXGStarted=YES;
    WXGTickets=[NSMutableDictionary dictionary];WXGDeniedAccounts=[NSMutableSet set];
    WXGCleanupLegacyCache();   // FIX111: 删掉旧的显眼目录（一次性，不存在则无操作）
    WXGStartCacheLoad();
}
// Main thread; cheap (asked again at most once a second unless forced).
// force: the settings page's "重新检测": ask the server now, whatever the
// back-off or an earlier refusal says.
WXGUnlockState WXGUnlockStateFor(NSString *account,BOOL force) {
    if(!NSThread.isMainThread || !account)return WXGUnlockNone;
    CFTimeInterval mono=CACurrentMediaTime();
    if(!force && WXGEvalAt>0 && mono-WXGEvalAt<1 && [account isEqualToString:WXGEvalAccount])return WXGEvalState;
    if(!WXGUnlockHex64(account.UTF8String))return WXGUnlockNone;
    WXGUnlockStart();
    // FIX104: the tickets read since launch, before anything is decided. The
    // first question waits for a read still running (up to 0.3 s), once.
    if(WXGCacheLoading){double wait=WXGCacheWaited?0:WXG_UNLOCK_LAUNCH_WAIT;WXGCacheWaited=YES;WXGAdoptCache(wait);}
    if(!WXGDeviceHash && !WXGCacheLoading) {
        // No identifierForVendor at launch (before the first unlock after a
        // reboot): read now that there is one, waiting as at launch (once).
        WXGDeviceHash=WXGComputeDeviceHash();
        if(WXGDeviceHash){WXGStartCacheLoad();WXGAdoptCache(WXG_UNLOCK_LAUNCH_WAIT);}
    }
    WXGUnlockState state;
    WXGUnlockTicket *ticket=WXGTickets[account];
    double now=WXGDeviceNow()+WXGClockOffset;
    // This account's last answer asked to wait (back-off, refusal, version).
    BOOL waiting=[WXGAttemptAccount isEqualToString:account] && mono<WXGNextAttempt;
    BOOL waitOutdated=WXGOutdatedVer && mono-WXGOutdatedAt<WXG_UNLOCK_OUTDATED_RECHECK;
    if(!WXGDeviceHash || !WXGCacheLoaded)state=WXGUnlockChecking;
    else if(ticket && WXGUnlockTicketUsable(now,(double)ticket.expiresAt,ticket.fetchedAt)) {
        state=WXGUnlockReady;
        // FIX104: due after the server's own interval (recheckAfter), not a
        // fixed 12 h; "重新检测" (force) asks now, as for any other account.
        BOOL due=WXGUnlockRefreshDue(now,(double)ticket.expiresAt,ticket.fetchedAt,WXGUnlockRecheckInterval(ticket.recheckAfter));
        if(!WXGInFlight && (force || (!waiting && !waitOutdated && due)))WXGRequest(account,YES);
    }else {
        if(!WXGInFlight && (force || (!waiting && !waitOutdated)))WXGRequest(account,YES);
        if(WXGInFlight && [WXGInFlightAccount isEqualToString:account])state=WXGUnlockChecking;
        else if([WXGDeniedAccounts containsObject:account])state=WXGUnlockDenied;
        else if(WXGOutdatedVer)state=WXGUnlockOutdated;
        else if(WXGFailures && [WXGAttemptAccount isEqualToString:account])state=WXGUnlockUnreachable;
        else state=WXGUnlockChecking;
    }
    WXGEvalAccount=account;WXGEvalAt=mono;WXGEvalState=state;
    return state;
}
// The last answer's problem, for the account asked about last (nil otherwise).
NSString *WXGUnlockLastError(void) {return [WXGAttemptAccount isEqualToString:WXGEvalAccount]?WXGLastError:nil;}
NSString *WXGUnlockServerShaderVersion(void) {return WXGOutdatedVer;}
BOOL WXGUnlockAsking(NSString *account) {return WXGInFlight && account && [WXGInFlightAccount isEqualToString:account];}   // FIX104
// FIX109 防篡改用的"真实货"信号：破解只是把授权判定焊成真，并不会凭空造出着色器或票。
// 这两个读的是实际数据(WXGShaderText / WXGTickets)，所以"自称已授权却这俩都空"即被 patch。
BOOL WXGUnlockShaderReady(void) {return WXGShaderReady(NULL);}
BOOL WXGUnlockHasUsableTicket(NSString *account) {
    if(!account)return NO;
    WXGUnlockTicket *t=WXGTickets[account];
    return t && WXGUnlockTicketUsable(WXGDeviceNow()+WXGClockOffset,(double)t.expiresAt,t.fetchedAt);
}
NSDate *WXGUnlockExpiry(NSString *account) {
    WXGUnlockTicket *ticket=account?WXGTickets[account]:nil;
    return ticket?[NSDate dateWithTimeIntervalSince1970:(double)ticket.expiresAt]:nil;
}
NSDictionary *WXGUnlockEvidence(void) {
    static NSISO8601DateFormatter *iso;static dispatch_once_t once;
    dispatch_once(&once,^{iso=[NSISO8601DateFormatter new];iso.timeZone=NSTimeZone.localTimeZone;});
    WXGUnlockTicket *ticket=WXGEvalAccount?WXGTickets[WXGEvalAccount]:nil;
    NSArray<NSString *> *endpoints=WXGEndpoints();
    NSString *endpoint=endpoints.count?endpoints[(NSUInteger)WXGEndpointIndex%endpoints.count]:@"";
    NSDictionary *ticketEvidence=ticket?@{@"origin":ticket.origin?:@"",@"ver":ticket.ver?:@"",
        @"expiresAt":[iso stringFromDate:[NSDate dateWithTimeIntervalSince1970:(double)ticket.expiresAt]],
        @"fetchedAt":ticket.fetchedAt>0?[iso stringFromDate:[NSDate dateWithTimeIntervalSince1970:ticket.fetchedAt]]:@"",
        @"digest":ticket.digest.length>12?[ticket.digest substringToIndex:12]:ticket.digest?:@"",@"shaderBytes":@(ticket.shader.length),
        @"recheckAfterSent":@(ticket.recheckAfter),@"recheckEveryS":@(WXGUnlockRecheckInterval(ticket.recheckAfter))}:@{};   // FIX104
    NSString *shaderFrom=nil;BOOL shaderReady=WXGShaderReady(&shaderFrom);
    return @{@"server":[NSURL URLWithString:endpoint].host?:@"",@"shaderVersion":WXG_SHADER_VERSION,
             @"device":WXGDeviceHash.length>8?[WXGDeviceHash substringToIndex:8]:@"",@"cacheLoaded":@(WXGCacheLoaded),@"cachedTickets":@(WXGCacheHits),
             // FIX104: when the cached tickets were read (ms after the plugin loaded), how long it took, how long main waited.
             @"cacheReadAtMS":@(round(WXGCacheReadAtMS)),@"cacheReadMS":@(round(WXGCacheReadMS*10)/10),@"cacheWaitMS":@(round(WXGCacheWaitMS*10)/10),
             @"ticket":ticketEvidence,@"shaderReady":@(shaderReady),@"shaderFrom":shaderFrom?:@"",
             @"requests":@(WXGRequests),@"issued":@(WXGTicketsIssued),@"denied":@(WXGDenials),@"deniedAccounts":@(WXGDeniedAccounts.count),@"badSignatures":@(WXGBadSignatures),
             @"failuresInARow":@(WXGFailures),@"inFlight":@(WXGInFlight),@"lastStatus":@(WXGLastStatus),
             @"lastRequestMS":@(round(WXGLastRequestMS)),@"clockOffsetS":@(round(WXGClockOffset)),
             @"lastError":WXGLastError?:@"",@"serverShaderVersion":WXGOutdatedVer?:@""};
}
