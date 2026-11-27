#ifndef WXG_INPUT_POLICY_H
#define WXG_INPUT_POLICY_H
#include "WXGGeometry.h"
typedef enum {
    WXGInputActionUnavailable, WXGInputActionVoiceMode, WXGInputActionKeyboard,
    WXGInputActionDictation, WXGInputActionSend
} WXGInputAction;
/* iOS 15/WeChat 8.0.73 retains the dictation control when not editing.
   Existence of iconClicked is not a signal that the keyboard is raised. */
static inline WXGInputAction WXGInputRightAction(int editing,int holdingVoice,int hasText,
                                                int canVoice,int canDictate,int canSend) {
    if(holdingVoice)return canVoice?WXGInputActionKeyboard:WXGInputActionUnavailable;
    if(!editing)return canVoice?WXGInputActionVoiceMode:WXGInputActionUnavailable;
    if(hasText && canSend)return WXGInputActionSend;
    if(canDictate)return WXGInputActionDictation;
    return canVoice?WXGInputActionVoiceMode:WXGInputActionUnavailable;
}
/* The open expression panel owns the return-to-keyboard button even after
   the system keyboard resigns. A hardware keyboard alone has no screen area. */
static inline int WXGInputShowsEmoji(int available,int keyboardOnly,int editing,int keyboardVisible,int expressionPanelOpen) {
    return available && (!keyboardOnly || (editing && keyboardVisible) || expressionPanelOpen);
}
/* WeChat may resize the native icon when deleting the last dictated word.
   Accept that size while keeping the displayed action in its reserved slot. */
static inline WXGRect WXGInputFrameAtSlot(WXGRect proposed,double cx,double cy) {
    proposed.x=cx-proposed.w*.5;
    proposed.y=cy-proposed.h*.5;
    return proposed;
}
/* GrowTextView owns its editor's frame, content inset, TextKit container and
   height. Reserve action space by sizing that host, not its UITextView child. */
static inline WXGRect WXGInputContentHost(WXGRect native,WXGRect pill,double firstActionX,double gap) {
    WXGRect out=native;
    out.x=pill.x;
    out.w=fmax(40,fmin(pill.w,firstActionX-gap-pill.x));
    return out;
}
/* Remember only components actually changed by native layout. A new native
   height must not turn our own modified x/width into the restore baseline. */
static inline WXGRect WXGInputNativeFrame(WXGRect saved,WXGRect current,WXGRect applied,int hasApplied) {
    if(!hasApplied)return current;
    return (WXGRect){fabs(current.x-applied.x)>.01?current.x:saved.x,
        fabs(current.y-applied.y)>.01?current.y:saved.y,
        fabs(current.w-applied.w)>.01?current.w:saved.w,
        fabs(current.h-applied.h)>.01?current.h:saved.h};
}
#endif
