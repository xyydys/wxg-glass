#include "../Sources/WXGBubbleFamily.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    WXGBubbleMessageIdentity source={41,901,1700000000,49,0,"room-a","self","member-a"};
    for(unsigned piece=0;piece<11;++piece) {
        // A rebuilt VM may carry a new wrap and retain only one of the IDs.
        WXGBubbleMessageIdentity clone=source;
        if(piece%3==1)clone.local=0;
        if(piece%3==2)clone.server=0;
        assert(WXGBubbleSameMessage(source,clone) && WXGBubbleSameMessage(clone,source));
        clone.from="room-b";assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.to=NULL;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.from="";assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.sender="member-b";assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.type=1;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.innerType=57;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.time++;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.local++;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.server++;assert(!WXGBubbleSameMessage(source,clone));
        clone=source;clone.local=clone.server=0;assert(!WXGBubbleSameMessage(source,clone));
    }
    // The local ID has no meaning outside its pair of conversation endpoints.
    for(unsigned i=1;i<=256;++i)for(unsigned j=1;j<=256;++j) {
        WXGBubbleMessageIdentity a=source,b=source;
        a.server=b.server=0;
        a.local=i;b.local=j;
        assert(WXGBubbleSameMessage(a,b)==(i==j));
        b.to="another-account";assert(!WXGBubbleSameMessage(a,b));
    }
    puts("PASS: eleven rebuilt fragments, scoped local/server IDs, conflicting and absent metadata.");
}
