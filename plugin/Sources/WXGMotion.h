#ifndef WXG_MOTION_H
#define WXG_MOTION_H
#include <math.h>

static inline double WXGClamp(double x, double lo, double hi) {
    return fmin(hi, fmax(lo, x));
}
// Semi-implicit integration with bounded substeps survives delayed display links.
static inline void WXGSpring(double *x, double *v, double target,
                             double stiffness, double damping, double dt) {
    dt = WXGClamp(dt, 0, 0.064);
    int count = (int)ceil(dt / (1.0 / 240.0));
    if (count < 1) return;
    double h = dt / count;
    for (int i = 0; i < count; ++i) {
        *v += ((target - *x) * stiffness - *v * damping) * h;
        *x += *v * h;
    }
    if (fabs(target - *x) < 0.0001 && fabs(*v) < 0.0001) { *x = target; *v = 0; }
}
static inline int WXGSlot(double x, double start, double width, int count) {
    if (!(width > 0) || count <= 0) return 0;
    return (int)WXGClamp(floor((x - start) / (width / count)), 0, count - 1);
}
#endif
