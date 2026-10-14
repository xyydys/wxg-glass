#ifndef WXG_BUTTON_PRESS_H
#define WXG_BUTTON_PRESS_H
#include <math.h>

typedef struct { double scaleX,scaleY,offsetX,offsetY; } WXGButtonPressPose;

/* One glass body, one shared centre. Direction deforms the existing body;
   it never creates a second rim or changes its distance-field dimensions. */
static inline WXGButtonPressPose WXGButtonPress(double pressure,double x,double y,int reduceMotion) {
    double p=isfinite(pressure)?fmax(0,fmin(1,pressure)):0;
    x=isfinite(x)?fmax(-1,fmin(1,x)):0;
    y=isfinite(y)?fmax(-1,fmin(1,y)):0;
    if(reduceMotion)return (WXGButtonPressPose){1,1,0,0};
    return (WXGButtonPressPose){1+p*(.064+.014*fabs(x)-.010*fabs(y)),
                               1+p*(.048+.010*fabs(y)-.012*fabs(x)),
                               1.8*p*x,1.8*p*y};
}

/* A child scales around its own anchor by default. Compensate its translation
   so artwork, badge and body instead move around the SAME material centre. */
static inline double WXGButtonChildOffset(double scale,double relativeCentre,double translation) {
    return (scale-1)*relativeCentre+translation;
}
#endif
