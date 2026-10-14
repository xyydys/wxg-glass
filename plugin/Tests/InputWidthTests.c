#include "../Sources/WXGInputWidthPolicy.h"
#include "../Sources/WXGInputPolicy.h"
#include <assert.h>
#include <stdio.h>
static void near(double a,double b){assert(fabs(a-b)<1e-8);}
int main(void) {
    // Replay alternating native layout and adapter layout at the wrapping
    // boundary. Native height/keyboard y must change without changing text width.
    WXGRect saved={54,710,304,40},target={68,710,230,40};
    for(int cycle=0;cycle<100;cycle++) {
        WXGRect incoming={54,cycle%2?470:710,304,cycle%3?40:64};
        saved=WXGInputRememberHorizontal(saved,incoming,target);
        WXGRect accepted=WXGInputAcceptHorizontal(incoming,target);
        near(accepted.x,68);near(accepted.w,230);near(accepted.y,incoming.y);near(accepted.h,incoming.h);
        // UIKit may send the corrected frame back unchanged, or update only h.
        saved=WXGInputRememberHorizontal(saved,accepted,target);
        near(saved.x,54);near(saved.w,304);near(saved.y,incoming.y);near(saved.h,incoming.h);
        WXGRect restored=WXGInputNativeFrame(saved,accepted,accepted,1);
        near(restored.x,54);near(restored.w,304);near(restored.h,incoming.h);
    }
    // A native width-only update must not turn the corrected x into the restore x.
    saved=WXGInputRememberHorizontal(saved,(WXGRect){68,490,324,84},target);
    near(saved.x,54);near(saved.w,324);near(saved.y,490);near(saved.h,84);
    // Rebinding the same editor to three segments accepts its new width once.
    target=(WXGRect){58,490,238,84};
    WXGRect accepted=WXGInputAcceptHorizontal(saved,target);
    near(accepted.x,58);near(accepted.w,238);near(accepted.h,84);
    // The native bounds + center layout path must produce exactly the same
    // x/width as setFrame, including noninteger sizes from the uploaded traces.
    double widths[]={259.3303,294.6667,238};
    for(int i=0;i<3;i++) {
        target.w=widths[i];
        double center=WXGInputAcceptedCenterX(target,widths[i]);
        near(center-widths[i]*.5,target.x);
    }
    // Existing accepted voice-mode/dictation policy remains shared with FIX3/4.
    assert(WXGInputRightAction(0,0,0,1,1,1)==WXGInputActionVoiceMode);
    assert(WXGInputRightAction(1,0,0,1,1,1)==WXGInputActionDictation);
    puts("PASS: stable input width through 100 native/adapter layout cycles; native height, keyboard y, restore frame and action policy retained.");
}
