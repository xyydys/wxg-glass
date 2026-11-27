#include "../Sources/WXGBubbleCardFit.h"
#include "../Sources/WXGBubbleVoiceChange.h"
#include <assert.h>

int main(void) {
    WXGCardImageFit skin = WXGBubbleCardImageFit(1, 1, 280*79, 1, 1);
    WXGCardImageFit preview = WXGBubbleCardImageFit(.98, .74, 265*190, 0, 0);
    WXGCardImageFit insetPhoto = WXGBubbleCardImageFit(.89, .91, 230*110, 0, 0);
    WXGCardImageFit withTail = WXGBubbleCardImageFit(.84, .91, 230*110, 1, 0);
    assert(WXGBubbleCardAcceptFit(skin, 1));
    assert(!WXGBubbleCardAcceptFit(preview, 1));
    assert(!WXGBubbleCardAcceptFit(insetPhoto, 1));
    assert(WXGBubbleCardAcceptFit(withTail, 1));
    assert(skin.score > withTail.score);
    assert(WXGBubbleCardStandbyFit(WXGBubbleCardImageFit(.98, .98, 880, 1, 0), 0, 1000));
    assert(!WXGBubbleCardStandbyFit(WXGBubbleCardImageFit(.98, .98, 879, 1, 0), 0, 1000));
    assert(!WXGBubbleCardStandbyFit(WXGBubbleCardImageFit(.4, .65, 990, 0, 1), 0, 1000));
    assert(!WXGBubbleCardAcceptFit(WXGBubbleCardImageFit(0, 0, 100, 0, 1), 0));
    // The audio skin stays compact as the outer voice body grows to
    // accommodate a transcription; both its normal and standby image can
    // briefly report no cap insets. A preview lower in the body is unrelated.
    WXGCardImageFit compact = WXGBubbleCardImageFit(.35,.24,80*40,0,0);
    assert(!WXGBubbleCardAcceptFit(compact,0));
    assert(WXGBubbleCompactVoiceSkin(compact,0,40));
    assert(!WXGBubbleCompactVoiceSkin(compact,45,40));
    assert(!WXGBubbleCompactVoiceSkin(compact,0,120));
    assert(!WXGBubbleCompactVoiceSkin(WXGBubbleCardImageFit(0,0,0,0,0),0,40));
    // In-place lifecycle: compact loading plate before the renderer is
    // measured, one line, then a fully laid-out multi-line transcription.
    assert(WXGBubbleVoicePlate(32,60,40,0,0,1));
    assert(!WXGBubbleVoicePlate(32,60,40,0,0,0));
    assert(WXGBubbleVoicePlate(32,94,32,70,18,0));
    assert(WXGBubbleVoicePlate(36,235,288,213,260,0));
    assert(!WXGBubbleVoicePlate(0,60,40,34,18,1));
    assert(!WXGBubbleVoicePlate(32,25,200,210,185,0));
    assert(!WXGBubbleVoicePlate(32,180,70,0,0,1));
    // Replay the same physical voice cell, past its original binding retries.
    // Neither of these native role swaps changes the child count.
    WXGBubbleVoiceState row = {.parent=1,.content=2,.skin=0,.children=3,.visible=true};
    WXGBubbleVoiceState next = row;
    next.childSignature=91;
    assert(WXGBubbleVoiceHierarchyChanged(row,next));
    next=row;
    assert(!WXGBubbleVoiceChanged(row,next));
    next.skin=4;
    assert(WXGBubbleVoiceHierarchyChanged(row,next));
    row=next;next.content=5;
    assert(WXGBubbleVoiceHierarchyChanged(row,next));
    // An already attached renderer's plate becomes visible and then measures
    // its final size, without any attachment or host layout callback.
    WXGBubbleVoiceState plate = {.parent=5,.width=60,.height=40,.children=1,.visible=false};
    next=plate;next.visible=true;
    assert(!WXGBubbleVoiceHierarchyChanged(plate,next) && WXGBubbleVoiceChanged(plate,next));
    plate=next;next.width=240;next.height=150;
    assert(!WXGBubbleVoiceHierarchyChanged(plate,next) && WXGBubbleVoiceChanged(plate,next));
    assert(!WXGBubbleVoiceChanged(next,next));
    // A native image placeholder acquires a stretchable skin asynchronously.
    plate=next;next.stretchable=true;
    assert(WXGBubbleVoiceChanged(plate,next));
    return 0;
}
