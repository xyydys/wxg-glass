#ifndef WXG_TELEGRAM_INK_H
#define WXG_TELEGRAM_INK_H
#include <stdint.h>

typedef struct { uint8_t r,g,b,a; } WXGTelegramPixel;

static inline WXGTelegramPixel WXGTelegramCoveredInk(WXGTelegramPixel color,uint8_t coverage) {
    unsigned alpha=(color.a*coverage+127u)/255u;
    return (WXGTelegramPixel){(color.r*alpha+127u)/255u,(color.g*alpha+127u)/255u,
                              (color.b*alpha+127u)/255u,alpha};
}
#endif
