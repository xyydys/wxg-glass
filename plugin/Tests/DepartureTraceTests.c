#include "../Sources/WXGPresentationMath.h"
#include "fixtures/NativeTitleTrace.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    const double reference=title_trace[0][0],glass=220;
    unsigned wrong_with_live_model=0;
    for(unsigned i=0;i<sizeof(title_trace)/sizeof(title_trace[0]);i++) {
        double model=title_trace[i][0],shown=title_trace[i][1];
        WXGAffine fixed=WXGPresentationDelta((WXGPoint){reference,78.3333},(WXGPoint){reference+1,78.3333},(WXGPoint){reference,79.3333},
            (WXGPoint){shown,78.3333},(WXGPoint){shown+1,78.3333},(WXGPoint){shown,79.3333},(WXGPoint){glass,78.3333});
        assert(fabs((glass+fixed.tx)-(shown+glass-reference))<1e-7);
        // Prior binding used the already moved final model as the outgoing base.
        double previous=shown-model;
        if(fabs(previous-fixed.tx)>100)++wrong_with_live_model;
    }
    assert(wrong_with_live_model>10);
    assert(fabs(title_trace[sizeof(title_trace)/sizeof(title_trace[0])-1][1]-reference)<1e-7);
    printf("PASS: %zu captured native title samples, departure reference and cancelled return; %u samples detect the old >100pt offset.\n",
        sizeof(title_trace)/sizeof(title_trace[0]),wrong_with_live_model);
}
