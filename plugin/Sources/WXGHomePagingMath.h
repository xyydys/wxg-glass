#ifndef WXG_HOME_PAGING_MATH_H
#define WXG_HOME_PAGING_MATH_H
#include <stdbool.h>
#include <math.h>

static inline int WXGHomeNeighbor(int current,int count,int step) {
    if(count<1 || !step)return -1;
    if(current<0)return step>0?0:count-1;
    return (current+(step>0?1:-1)+count)%count;
}
static inline bool WXGHomePageHorizontal(double x,double y) {
    return fabs(x)>fabs(y)*1.15;
}
static inline bool WXGHomePageCommits(double shift,double velocity,double width,bool interactive) {
    if(width<=0)return false;
    if(!interactive)return fabs(shift)>=48. || fabs(velocity)>=160.;
    double distance=fmax(48.,width*.35);
    if(fabs(velocity)>=160.)return shift*velocity>0;
    return fabs(shift)>=distance;
}
static inline double WXGHomePageSettle(double remaining) {
    return fmax(.20,.34*(.45+.55*fmin(1.,fabs(remaining))));
}
#endif
