#ifndef WXG_INPUT_SYMBOLS_H
#define WXG_INPUT_SYMBOLS_H
#import <UIKit/UIKit.h>

// The role keys also identify persisted settings. The two keyboard buttons
// belong to different controls and have independent artwork.
#define WXG_INPUT_SYMBOLS(X) \
    X(Plus, "附件加号", "plus", 23, "#000000FF") \
    X(Emoji, "表情", "faceid", 21, "#000000FF") \
    X(EmojiKeyboard, "关闭表情面板", "keyboard", 20, "#000000FF") \
    X(Voice, "切换到语音", "waveform", 21, "#000000FF") \
    X(VoiceKeyboard, "从语音切换到键盘", "keyboard", 20, "#000000FF") \
    X(Send, "发送", "arrow.up.circle.fill", 24, "#000000FF") \
    X(Dictation, "语音转文字", "mic", 20, "#000000FF") \
    X(Listening, "语音转文字进行中", "mic.fill", 20, "#FFFFFFFF")

typedef NS_ENUM(NSUInteger, WXGInputSymbolRole) {
#define WXG_ROLE(key, title, symbol, points, light) WXGInputSymbol##key,
    WXG_INPUT_SYMBOLS(WXG_ROLE)
#undef WXG_ROLE
    WXGInputSymbolCount
};

typedef struct { const char *stem, *label, *fallback; } WXGInputSymbolInfo;
static inline WXGInputSymbolInfo WXGInputRoleInfo(WXGInputSymbolRole role) {
    static const WXGInputSymbolInfo info[]={
#define WXG_INFO(key, title, symbol, points, light) {"split" #key,title,symbol},
        WXG_INPUT_SYMBOLS(WXG_INFO)
#undef WXG_INFO
    };
    return info[role];
}
FOUNDATION_EXPORT UIImage *WXGInputSymbolImage(WXGInputSymbolRole role);
FOUNDATION_EXPORT UIColor *WXGInputSymbolColor(WXGInputSymbolRole role);

#endif
