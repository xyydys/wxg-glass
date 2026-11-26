#import <UIKit/UIKit.h>
@class WXGStateBag;

// The measured original and translated text in message-root coordinates.
// A normal text message has no translated envelope or material to replace.
CGRect WXGBubbleTranslatedEnvelope(UIView *host, UIView *body, UIView *skin,
                                  UIView **materialPlate);
void WXGBubbleClearTranslationPlate(UIView *plate, WXGStateBag *states);
