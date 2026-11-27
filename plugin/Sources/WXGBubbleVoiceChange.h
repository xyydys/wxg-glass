#pragma once
#include <stdbool.h>
#include <stdint.h>

// Only changes that affect ownership, material discovery or the occupied rect
// require repainting. Ignore intermediate opacity values during native fades.
typedef struct {
    uintptr_t parent, content, skin, childSignature;
    double x, y, width, height;
    unsigned long children;
    bool visible, stretchable;
} WXGBubbleVoiceState;

static inline bool WXGBubbleVoiceHierarchyChanged(WXGBubbleVoiceState old, WXGBubbleVoiceState now) {
    return old.parent != now.parent || old.content != now.content || old.skin != now.skin ||
        old.children != now.children || old.childSignature != now.childSignature;
}

static inline bool WXGBubbleVoiceChanged(WXGBubbleVoiceState old, WXGBubbleVoiceState now) {
    return WXGBubbleVoiceHierarchyChanged(old, now) ||
        old.x != now.x || old.y != now.y || old.width != now.width || old.height != now.height ||
        old.visible != now.visible || old.stretchable != now.stretchable;
}
