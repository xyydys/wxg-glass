// Standalone UIKit fixture. Link with WXGBubbleContent.m in a test process.
#import "../Sources/WXGBubbleContent.h"
#import <assert.h>

BOOL WXGIsPluginView(__unused UIView *view) { return NO; }
@interface VoiceMessageCellView : UIView {
@public UIView *m_contentView;
@public UIImageView *m_bgImageView;
}
@end
@implementation VoiceMessageCellView
@end
@interface YYAsyncImageView : UIImageView @end
@implementation YYAsyncImageView @end

int main(void) {
    @autoreleasepool {
        VoiceMessageCellView *root=[[VoiceMessageCellView alloc] initWithFrame:CGRectMake(0,0,390,180)];
        UIView *oldBody=[[UIView alloc] initWithFrame:CGRectMake(60,0,130,42)];
        [root addSubview:oldBody];
        UIImageView *oldSkin=[[YYAsyncImageView alloc] initWithFrame:oldBody.bounds];
        [oldBody addSubview:oldSkin];
        root->m_contentView=oldBody;
        root->m_bgImageView=oldSkin;
        assert(WXGBubbleCardBody(root)==oldBody);

        // The cell, old body and full-size old skin all remain attached.
        // The expanding body already exists inside a wrapper, but its native
        // skin arrives after layout with zero bounds and without capInsets.
        UIView *wrapper=[[UIView alloc] initWithFrame:root.bounds];
        [root addSubview:wrapper];
        UIView *expanded=[[UIView alloc] initWithFrame:CGRectMake(60,0,240,150)];
        [wrapper addSubview:expanded];
        root->m_contentView=expanded;
        UIImageView *late=[[YYAsyncImageView alloc] initWithFrame:CGRectZero];
        [expanded addSubview:late];
        root->m_bgImageView=late;
        assert(WXGBubbleCardBody(root)==expanded);
        assert(WXGBubbleCardBackgrounds(root,expanded).firstObject==late);

        // Reparenting a still-retained widget to another cell invalidates that
        // reference before this row's next layout.
        [late removeFromSuperview];
        assert(WXGBubbleVoiceSkin(root)==nil);
        assert(WXGBubbleCardBody(root)==oldBody);
    }
    return 0;
}
