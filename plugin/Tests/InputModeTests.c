#include "../Sources/WXGInputPolicy.h"
#include <assert.h>
#include <stdio.h>

static void near(double a,double b) { assert(fabs(a-b)<.001); }

static void action_regressions(void) {
    /* Captured iOS 15 idle state: dictation still exists. It must not take
       the sole mode-switch slot, regardless of whether a draft is retained. */
    assert(WXGInputRightAction(0,0,0,1,1,1)==WXGInputActionVoiceMode);
    assert(WXGInputRightAction(0,0,1,1,1,1)==WXGInputActionVoiceMode);
    /* Same behavior when another system creates dictation lazily. */
    assert(WXGInputRightAction(0,0,0,1,0,1)==WXGInputActionVoiceMode);
    assert(WXGInputRightAction(1,0,0,1,1,1)==WXGInputActionDictation);
    assert(WXGInputRightAction(1,0,1,1,1,1)==WXGInputActionSend);
    /* A retained draft must not turn the exit-from-voice button into Send. */
    assert(WXGInputRightAction(0,1,1,1,1,1)==WXGInputActionKeyboard);
    assert(WXGInputRightAction(0,1,0,1,1,1)==WXGInputActionKeyboard);
    assert(WXGInputRightAction(1,1,1,1,1,1)==WXGInputActionKeyboard);
    /* No fabricated action when a native target is missing/disabled. */
    assert(WXGInputRightAction(1,0,0,1,0,1)==WXGInputActionVoiceMode);
    assert(WXGInputRightAction(0,0,0,0,1,1)==WXGInputActionUnavailable);
    assert(WXGInputRightAction(0,1,0,0,1,1)==WXGInputActionUnavailable);
    assert(WXGInputRightAction(1,0,1,0,1,0)==WXGInputActionUnavailable);
    assert(WXGInputRightAction(1,0,1,1,1,0)==WXGInputActionVoiceMode);
    assert(WXGInputRightAction(1,0,0,0,1,0)==WXGInputActionDictation);
    assert(WXGInputRightAction(1,0,1,0,0,1)==WXGInputActionSend);
    assert(WXGInputRightAction(1,0,0,0,0,0)==WXGInputActionUnavailable);
}

static void captured_width_regression(void) {
    /* Snapshot 10: editor after the native parent's next layout extends
       77.91 pt under the emoji column, undoing the previous child-frame fix. */
    double editorRight=96.059+283.4203,emojiLeft=301.5697;
    assert(editorRight-emojiLeft>77);
    WXGInputGeometry glass=WXGInputLayout(414,0,0,504.5,57,47,1.1964);
    /* The probe rounds sizeScale to four decimal places. */
    assert(fabs(glass.pill.x-90.059)<.01);
    WXGRect host=WXGInputContentHost((WXGRect){48,476,278,57},glass.pill,emojiLeft,12);
    /* Replaying the captured native rule x=6,width=host-9, plus the 10 pt
       negative right contentInset, must still leave a gap before the icon. */
    double nativeEditorRight=host.x+6+(host.w-9);
    assert(nativeEditorRight+10<emojiLeft);
    near(host.y,476);near(host.h,57);
    near(host.x,glass.pill.x);
    assert(host.w<278 && host.w>160);
}

static unsigned geometry_invariants(void) {
    const double widths[]={320,375,390,414,440,568,667,844,1024};
    const double scales[]={.85,1,1.1964,1.20};
    const double heights[]={40,57,77,138,200};
    unsigned count=0;
    for(unsigned i=0;i<sizeof(widths)/sizeof(*widths);i++)
    for(unsigned j=0;j<sizeof(scales)/sizeof(*scales);j++)
    for(unsigned h=0;h<sizeof(heights)/sizeof(*heights);h++)
    for(unsigned safe=0;safe<2;safe++)
    for(unsigned emoji=0;emoji<2;emoji++) {
        double left=safe?20:0,right=safe?34:0;
        WXGInputGeometry g=WXGInputLayout(widths[i],left,right,500,heights[h],heights[h]-10,scales[j]);
        WXGMetrics m=WXGMeasure(widths[i]-left-right,scales[j]);
        double action=g.mic.x-(emoji?fmin(28,m.inputButton*.72)+5*m.scale:0);
        WXGRect native={48,500-heights[h]/2,278,heights[h]};
        WXGRect host=WXGInputContentHost(native,g.pill,action,fmax(6*m.scale,12));
        assert(host.w>=40 && host.x>=left);
        assert(host.x+host.w+10<action);
        assert(host.x+host.w<=g.pill.x+g.pill.w);
        near(host.y,native.y);near(host.h,native.h);
        count++;
    }
    return count;
}

static void reversible_native_geometry(void) {
    WXGRect saved={48,8,278,40},applied={90.059,8,199.5107,40};
    WXGRect next=applied;next.h=57;
    saved=WXGInputNativeFrame(saved,next,applied,1);
    near(saved.x,48);near(saved.w,278);near(saved.h,57);near(saved.y,8);
    applied=next;next.y=5;next.h=138;
    saved=WXGInputNativeFrame(saved,next,applied,1);
    near(saved.x,48);near(saved.w,278);near(saved.h,138);near(saved.y,5);
    /* Native rotation assigns a new width: that is the restore baseline. */
    applied=next;next=(WXGRect){64,8,440,77};
    saved=WXGInputNativeFrame(saved,next,applied,1);
    near(saved.x,64);near(saved.w,440);near(saved.y,8);near(saved.h,77);
    /* A newly encountered record host must learn its own frame. */
    saved=WXGInputNativeFrame(saved,(WXGRect){48,8,278,40},applied,0);
    near(saved.x,48);near(saved.w,278);near(saved.h,40);
}

int main(void) {
    action_regressions();captured_width_regression();reversible_native_geometry();
    printf("PASS: input mode 16 cases, captured overlap regression, %u width/height cases, native geometry restoration\n",geometry_invariants());
    return 0;
}
