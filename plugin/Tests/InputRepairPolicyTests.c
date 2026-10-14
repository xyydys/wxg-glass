#include "../Sources/WXGInputRepairPolicy.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

enum { NativeA=1,NativeB=2,NativeC=3,Pill=4,Mic=10,Emoji=20,ReplacementEmoji=30 };
static size_t indexOf(const uintptr_t *views,size_t count,uintptr_t view) {
    for(size_t i=0;i<count;++i)if(views[i]==view)return i;
    return count;
}
static void bringFront(uintptr_t *views,size_t count,uintptr_t view) {
    size_t index=indexOf(views,count,view);assert(index<count);
    memmove(views+index,views+index+1,(count-index-1)*sizeof(*views));
    views[count-1]=view;
}
/* Model only hierarchy operations: the predicate is production code and the
   expected resulting orders below are independent fixed fixtures. */
static unsigned repairSuffix(uintptr_t *views,size_t count,const uintptr_t *desired,size_t desiredCount) {
    if(WXGInputSuffixMatches(views,count,desired,desiredCount))return 0;
    for(size_t i=0;i<desiredCount;++i)bringFront(views,count,desired[i]);
    return (unsigned)desiredCount;
}
static void expectOrder(const uintptr_t *views,const uintptr_t *expected,size_t count) {
    assert(memcmp(views,expected,count*sizeof(*views))==0);
}
static void testSuffix(void) {
    const uintptr_t desired[]={Mic,Emoji};
    const uintptr_t final[]={NativeA,Pill,NativeB,NativeC,Mic,Emoji};
    uintptr_t old[6];memcpy(old,final,sizeof old);
    unsigned oldWrites=0;
    for(unsigned pass=0;pass<1000;++pass) {
        if(old[5]!=Mic){bringFront(old,6,Mic);++oldWrites;}
        bringFront(old,6,Emoji);++oldWrites;
        expectOrder(old,final,6);
    }
    assert(oldWrites==2000); /* FIX11's final order still dirties every pass. */

    uintptr_t mixed[]={Emoji,NativeA,Pill,Mic,NativeB,NativeC};
    assert(!WXGInputSuffixMatches(mixed,6,desired,2));
    assert(repairSuffix(mixed,6,desired,2)==2);expectOrder(mixed,final,6);
    for(unsigned pass=0;pass<100000;++pass)assert(repairSuffix(mixed,6,desired,2)==0);

    /* Missing emoji: the caller supplies a filtered one-view suffix. */
    uintptr_t absent[]={NativeA,Mic,Pill,NativeB,NativeC};
    const uintptr_t micOnly[]={Mic},withoutEmoji[]={NativeA,Pill,NativeB,NativeC,Mic};
    assert(repairSuffix(absent,5,micOnly,1)==1);expectOrder(absent,withoutEmoji,5);
    assert(repairSuffix(absent,5,micOnly,1)==0);

    /* A reattached replacement is ordered without perturbing native siblings. */
    uintptr_t replaced[]={ReplacementEmoji,NativeA,Pill,Mic,NativeB,NativeC};
    const uintptr_t replacement[]={Mic,ReplacementEmoji};
    const uintptr_t withReplacement[]={NativeA,Pill,NativeB,NativeC,Mic,ReplacementEmoji};
    assert(!WXGInputSuffixMatches(replaced,6,replacement,2));
    assert(repairSuffix(replaced,6,replacement,2)==2);expectOrder(replaced,withReplacement,6);
    assert(repairSuffix(replaced,6,replacement,2)==0);
    assert(!WXGInputSuffixMatches(replaced,6,desired,2));
    assert(!WXGInputSuffixMatches(absent,1,desired,2));
    assert(WXGInputSuffixMatches(NULL,0,NULL,0));
    assert(WXGInputSuffixMatches(replaced,6,NULL,0));
}
static void testGate(void) {
    WXGInputRepairGate gate={0};
    assert(!WXGInputRepairTryBegin(&gate,1));
    WXGInputRepairRequest(&gate);
    for(unsigned i=0;i<1000;++i)assert(!WXGInputRepairTryBegin(&gate,0));
    assert(gate.pending && !gate.running && gate.used==0);

    unsigned repairs=0,latestGeometry=0,appliedGeometry=0;
    for(unsigned request=1;request<=100000;++request) {
        latestGeometry=request;WXGInputRepairRequest(&gate);
        int began=WXGInputRepairTryBegin(&gate,request%7!=0);
        if(began) {
            ++repairs;appliedGeometry=latestGeometry;
            unsigned used=gate.used;
            assert(gate.running && !gate.pending);
            /* A setter can synchronously reach the hook again. It leaves one
               pending repair, without recursively consuming another permit. */
            for(unsigned nested=0;nested<8;++nested) {
                WXGInputRepairRequest(&gate);
                assert(!WXGInputRepairTryBegin(&gate,1));
                assert(gate.used==used && gate.pending && gate.running);
            }
            WXGInputRepairEnd(&gate);assert(!gate.running);
        }
        assert(gate.used<=4);
    }
    assert(repairs==4 && gate.used==4 && gate.pending);
    assert(appliedGeometry==4 && latestGeometry==100000);

    WXGInputRepairNextFrame(&gate);
    assert(gate.used==0 && gate.pending && !gate.running);
    assert(WXGInputRepairTryBegin(&gate,1));
    appliedGeometry=latestGeometry;WXGInputRepairEnd(&gate);
    assert(appliedGeometry==100000 && gate.used==1 && !gate.pending);
    assert(!WXGInputRepairTryBegin(&gate,1));

    /* Ineligibility across frame boundaries must retain work for reattachment. */
    WXGInputRepairRequest(&gate);WXGInputRepairNextFrame(&gate);
    assert(!WXGInputRepairTryBegin(&gate,0));
    WXGInputRepairNextFrame(&gate);
    assert(gate.pending && !gate.used && WXGInputRepairTryBegin(&gate,1));
    WXGInputRepairEnd(&gate);
}
static void testFrameEpochs(void) {
    const unsigned rates[]={60,120};
    for(size_t rate=0;rate<sizeof rates/sizeof rates[0];++rate) {
        WXGInputRepairGate gate={0};unsigned repairs=0;double previous=-1;
        /* Advancing wall time inside one callback storm is not a frame reset.
           Only the explicit display callback below can replenish the budget. */
        for(unsigned sample=0;sample<rates[rate]*3;++sample) {
            double timestamp=100.0+(double)sample/rates[rate];assert(timestamp>previous);previous=timestamp;
            WXGInputRepairRequest(&gate);
            if(WXGInputRepairTryBegin(&gate,1)){++repairs;WXGInputRepairEnd(&gate);}
        }
        assert(repairs==4 && gate.used==4 && gate.pending);

        for(unsigned frame=0;frame<rates[rate]*2;++frame) {
            WXGInputRepairNextFrame(&gate);unsigned inFrame=0;
            for(unsigned request=0;request<1000;++request) {
                WXGInputRepairRequest(&gate);
                if(WXGInputRepairTryBegin(&gate,1)){++inFrame;WXGInputRepairEnd(&gate);}
            }
            assert(inFrame==4 && gate.used==4 && gate.pending);
        }
    }
}
int main(void) {
    testSuffix();testGate();testFrameEpochs();
    puts("PASS: stable input suffix eliminates repeating sibling writes; absent/replaced emoji preserves native order; 100000 requests and reentry stay within four repairs per display epoch, retaining latest pending work at 60/120 Hz.");
    return 0;
}
