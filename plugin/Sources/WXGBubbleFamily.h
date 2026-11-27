#ifndef WXG_BUBBLE_FAMILY_H
#define WXG_BUBBLE_FAMILY_H

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// Message IDs can be reused by a different conversation. When both wraps
// supply a field they must agree, even if another ID happens to match.
typedef struct {
    uint64_t local,server,time;
    uint32_t type,innerType;
    const char *from,*to,*sender;
} WXGBubbleMessageIdentity;

static inline bool WXGBubbleSameMessage(WXGBubbleMessageIdentity a,WXGBubbleMessageIdentity b) {
    if(!a.type || a.type!=b.type || a.innerType!=b.innerType)return false;
    if(!a.from || !*a.from || !b.from || strcmp(a.from,b.from) ||
       !a.to || !*a.to || !b.to || strcmp(a.to,b.to))return false;
    if(a.sender && *a.sender && b.sender && *b.sender && strcmp(a.sender,b.sender))return false;
    if((a.local && b.local && a.local!=b.local) || (a.server && b.server && a.server!=b.server) ||
       (a.time && b.time && a.time!=b.time))return false;
    return (a.local && a.local==b.local) || (a.server && a.server==b.server);
}

#ifdef __OBJC__
#import "WXGIntegration.h"

// Misses on optional fields are common when plug-ins replace a view model.
// Check the getter/ivar before KVC to avoid throwing on the scrolling path.
static inline id WXGBubbleModelField(id object,NSString *key) {
    if(!object)return nil;
    // A host getter can replace a family without replacing its backing ivar.
    // KVC reads the live getter with its own object/scalar ABI.
    if([object respondsToSelector:NSSelectorFromString(key)]) {
        @try {return [object valueForKey:key];}
        @catch(__unused NSException *error) {return nil;}
    }
    Class cls=object_getClass(object);
    if(!class_getInstanceVariable(cls,key.UTF8String) &&
       !class_getInstanceVariable(cls,[[@"_" stringByAppendingString:key] UTF8String]))return nil;
    return WXGRead(object,key);
}
static inline id WXGBubbleParentModel(id model) {
    for(NSString *key in @[@"parentModel",@"m_parentModel",@"m_parentViewModel",@"_parentViewModel"]) {
        id value=WXGBubbleModelField(model,key);
        if(value && value!=model)return value;
    }
    return nil;
}
static inline NSArray *WXGBubbleParts(id parent) {
    id parts=WXGBubbleModelField(parent,@"subViewModels");
    if(![parts isKindOfClass:NSArray.class] || ![parts count])parts=WXGBubbleModelField(parent,@"m_subViewModels");
    return [parts isKindOfClass:NSArray.class]?parts:nil;
}
static inline id WXGBubbleDirectWrap(id model) {
    for(NSString *key in @[@"messageWrap",@"m_messageWrap",@"m_oMessageWrap",@"_messageWrap"]) {
        id wrap=WXGBubbleModelField(model,key);
        if([WXGBubbleModelField(wrap,@"m_uiMessageType") isKindOfClass:NSNumber.class])return wrap;
    }
    return nil;
}
static inline id WXGBubbleModelWrap(id model) {
    for(NSUInteger hop=0;model && hop<3;++hop,model=WXGBubbleParentModel(model)) {
        id wrap=WXGBubbleDirectWrap(model);
        if(wrap)return wrap;
    }
    return nil;
}
static inline BOOL WXGBubbleIsFragment(id model) {
    return [model isKindOfClass:NSClassFromString(@"TextMessageSubViewModel")];
}
static inline BOOL WXGBubbleHasNativeLongHint(id model) {
    if(WXGBubbleIsFragment(model))return YES;
    for(NSString *key in @[@"isLongSplitMessage",@"mm_isLongSplitMessage"]) {
        id value=WXGBubbleModelField(model,key);
        if([value isKindOfClass:NSNumber.class] && [value boolValue])return YES;
    }
    return NO;
}
static inline NSArray *WXGBubbleConversation(id wrap) {
    NSMutableArray *fields=[NSMutableArray arrayWithCapacity:3];
    for(NSString *key in @[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"]) {
        id value=WXGBubbleModelField(wrap,key);
        [fields addObject:[value isKindOfClass:NSString.class]?value:@""];
    }
    return fields;
}
static inline uint64_t WXGBubbleIdentityNumber(id wrap,NSString *key) {
    id value=WXGBubbleModelField(wrap,key);
    return [value isKindOfClass:NSNumber.class]?[value unsignedLongLongValue]:0;
}
static inline WXGBubbleMessageIdentity WXGBubbleIdentityForWrap(id wrap,NSArray<NSString *> *names) {
    return (WXGBubbleMessageIdentity){
        .local=WXGBubbleIdentityNumber(wrap,@"m_uiMesLocalID"),.server=WXGBubbleIdentityNumber(wrap,@"m_n64MesSvrID"),
        .time=WXGBubbleIdentityNumber(wrap,@"m_uiCreateTime"),.type=(uint32_t)WXGBubbleIdentityNumber(wrap,@"m_uiMessageType"),
        .innerType=(uint32_t)WXGBubbleIdentityNumber(wrap,@"m_uiAppMsgInnerType"),
        .from=names[0].UTF8String,.to=names[1].UTF8String,.sender=names[2].UTF8String
    };
}
static inline BOOL WXGBubbleSameFamilyKey(id a,id b) {
    if(!a || !b)return NO;
    if(a==b)return YES;
    if(![WXGBubbleModelField(a,@"m_uiMessageType") isKindOfClass:NSNumber.class] ||
       ![WXGBubbleModelField(b,@"m_uiMessageType") isKindOfClass:NSNumber.class])return NO;
    // Keep the six original NSStrings alive while comparing their UTF-8 buffers.
    __attribute__((objc_precise_lifetime)) NSArray *left=WXGBubbleConversation(a),*right=WXGBubbleConversation(b);
    return WXGBubbleSameMessage(WXGBubbleIdentityForWrap(a,left),WXGBubbleIdentityForWrap(b,right));
}

// Only a physical fragment may establish membership. Several normal two-line
// parent models also expose subViewModels and must stay a single local bubble.
static inline id WXGBubbleFamily(id model,NSUInteger *index,NSUInteger *count) {
    *index=NSNotFound;*count=0;
    if(!WXGBubbleIsFragment(model))return nil;
    id parent=WXGBubbleParentModel(model);
    if(![parent isKindOfClass:NSClassFromString(@"TextMessageViewModel")] &&
       ![parent isKindOfClass:NSClassFromString(@"GroupNoticeMessageViewModel")])return nil;
    id raw=WXGBubbleParts(parent);
    if(![raw isKindOfClass:NSArray.class] || [raw count]<2)return nil;
    NSArray *parts=[raw copy];
    id wrap=WXGBubbleModelWrap(parent);
    NSUInteger at=NSNotFound;
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for(id part in parts) {
        if(!WXGBubbleIsFragment(part) || [seen containsObject:part])return nil;
        id owner=WXGBubbleParentModel(part);
        if(owner && owner!=parent)return nil;
        id childWrap=WXGBubbleDirectWrap(part);
        if(childWrap && wrap && !WXGBubbleSameFamilyKey(wrap,childWrap))return nil;
        if(!wrap && childWrap)wrap=childWrap;
        if(part==model)at=seen.count;
        [seen addObject:part];
    }
    if(at==NSNotFound)return nil;
    *index=at;*count=parts.count;
    return wrap?:parent;
}

// Without an indexed family, only identical direct wraps on physically
// adjacent native long rows can be used. A populated but rejected family
// must never be reinterpreted as an unindexed one.
static inline id WXGBubbleNativeLongWrap(id model) {
    if(!WXGBubbleHasNativeLongHint(model))return nil;
    id parent=WXGBubbleParentModel(model);
    for(id candidate in parent?@[model,parent]:@[model]) {
        id parts=WXGBubbleParts(candidate);
        if(parts && (![parts isKindOfClass:NSArray.class] || [parts count]))return nil;
    }
    return WXGBubbleDirectWrap(model);
}
#endif
#endif
