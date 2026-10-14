#ifndef WXG_INPUT_REPAIR_POLICY_H
#define WXG_INPUT_REPAIR_POLICY_H
#include <stddef.h>
#include <stdint.h>

/* A stack guard does not stop successive UIKit layout callbacks in the same
   frame. Keep immediate repairs bounded; the host drains pending work before
   the next display callback's capture, using the current native geometry. */
enum { WXGInputRepairBudget=4 };
typedef struct {
    unsigned used;
    int pending,running;
} WXGInputRepairGate;

static inline void WXGInputRepairRequest(WXGInputRepairGate *gate) {
    gate->pending=1;
}
static inline int WXGInputRepairTryBegin(WXGInputRepairGate *gate,int eligible) {
    if(!gate->pending || !eligible || gate->running || gate->used>=WXGInputRepairBudget)return 0;
    gate->pending=0;++gate->used;gate->running=1;return 1;
}
static inline void WXGInputRepairEnd(WXGInputRepairGate *gate) {
    gate->running=0;
}
static inline void WXGInputRepairNextFrame(WXGInputRepairGate *gate) {
    gate->used=0;
}

/* The caller filters desired views to those attached to this parent. Compare
   the whole final suffix before moving any sibling, so mic and emoji cannot
   alternately bring each other forward on every native layout callback. */
static inline int WXGInputSuffixMatches(const uintptr_t *actual,size_t n,
                                        const uintptr_t *ordered,size_t count) {
    if(count>n)return 0;
    for(size_t i=0;i<count;++i)if(actual[n-count+i]!=ordered[i])return 0;
    return 1;
}
#endif
