/* FIX103: unlock ticket rules (Sources/WXGUnlockPolicy.h). The signed
   message is checked against what wxg-glass worker.js signs: its
   [account, device, VER, expiresAt, digest].join("|") for these values. */
#include "../Sources/WXGUnlockPolicy.h"
#include <stdio.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    const char *account="a7a5fc72e26a50adeefabc498db7ec2d85ea5bf6e6cc8b47885514ce4cb01379";
    const char *device="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const char *digest="93b805220159c9f89963a3e3e74b9216abf8c1da8f617d8bcf59a6a33a1a88b6";
    /* From worker.js run locally (node, the same handler): */
    const char *signedByWorker="a7a5fc72e26a50adeefabc498db7ec2d85ea5bf6e6cc8b47885514ce4cb01379|"
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|1|1792597444|"
        "93b805220159c9f89963a3e3e74b9216abf8c1da8f617d8bcf59a6a33a1a88b6";
    char msg[400];
    int n=WXGUnlockSignedMessage(msg,sizeof msg,account,device,"1",1792597444LL,digest);
    CHECK(n==(int)strlen(signedByWorker) && strcmp(msg,signedByWorker)==0,"message as worker.js joins it: %s",msg);

    /* Malformed fields never make a message. */
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,"A7A5fc72e26a50adeefabc498db7ec2d85ea5bf6e6cc8b47885514ce4cb01379",device,"1",1,digest)==-1,"uppercase account");
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,account,"short","1",1,digest)==-1,"short device");
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,account,device,"",1,digest)==-1,"empty ver");
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,account,device,"1|2",1,digest)==-1,"ver with a separator");
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,account,device,"1",0,digest)==-1,"no expiry");
    CHECK(WXGUnlockSignedMessage(msg,sizeof msg,account,device,"1",1,"zz")==-1,"bad digest");
    CHECK(WXGUnlockSignedMessage(msg,100,account,device,"1",1792597444LL,digest)==-1,"too small a buffer");
    CHECK(WXGUnlockSignedMessage(NULL,0,account,device,"1",1,digest)==-1,"no buffer");
    CHECK(WXGUnlockHex64(account) && !WXGUnlockHex64(NULL) && !WXGUnlockHex64("") && !WXGUnlockHex64("g000000000000000000000000000000000000000000000000000000000000000"),"hex64");

    /* Usable until it expires; a clock set back more than a day before the fetch is not trusted. */
    const double fetched=1800000000.,expires=fetched+7*86400.;
    CHECK(WXGUnlockTicketUsable(fetched+60,expires,fetched),"fresh ticket");
    CHECK(WXGUnlockTicketUsable(expires-1,expires,fetched),"last second");
    CHECK(!WXGUnlockTicketUsable(expires,expires,fetched) && !WXGUnlockTicketUsable(expires+5,expires,fetched),"expired");
    CHECK(WXGUnlockTicketUsable(fetched-3600,expires,fetched),"a clock an hour behind is fine");
    CHECK(!WXGUnlockTicketUsable(fetched-2*86400.,expires,fetched),"a clock set back two days");
    CHECK(WXGUnlockTicketUsable(fetched,expires,0),"no fetch time: expiry alone");
    CHECK(!WXGUnlockTicketUsable(0,expires,fetched) && !WXGUnlockTicketUsable(fetched,0,fetched),"invalid times");

    /* FIX104: the server's recheck interval, clamped; a default without one. */
    CHECK(WXGUnlockRecheckInterval(0)==WXG_UNLOCK_RECHECK_DEFAULT && WXGUnlockRecheckInterval(-5)==WXG_UNLOCK_RECHECK_DEFAULT,"none: default");
    CHECK(WXGUnlockRecheckInterval(0./0.)==WXG_UNLOCK_RECHECK_DEFAULT,"NaN: default");
    CHECK(WXGUnlockRecheckInterval(300)==300 && WXGUnlockRecheckInterval(3600)==3600,"as sent");
    CHECK(WXGUnlockRecheckInterval(1)==60 && WXGUnlockRecheckInterval(59.9)==60,"at most once a minute");
    CHECK(WXGUnlockRecheckInterval(30*86400.)==7*86400. && WXGUnlockRecheckInterval(1./0.)==7*86400.,"at most the ticket's lifetime");
    CHECK(WXGUnlockDeniedWait(0)==WXG_UNLOCK_DENIED_RECHECK && WXGUnlockDeniedWait(120)==120,"refused: default or as sent");
    CHECK(WXGUnlockDeniedWait(5)==60 && WXGUnlockDeniedWait(9e9)==86400.,"refused: 1 min .. 1 day");

    /* Renewal: once the interval has passed, or with under 3 days left; always when unusable. */
    CHECK(!WXGUnlockRefreshDue(fetched+3600,expires,fetched,12*3600.),"12 h interval, one hour in: not due");
    CHECK(WXGUnlockRefreshDue(fetched+12*3600.,expires,fetched,12*3600.),"12 h interval, 12 h in: due");
    CHECK(!WXGUnlockRefreshDue(fetched+299,expires,fetched,300),"5 min interval, 299 s in: not due");
    CHECK(WXGUnlockRefreshDue(fetched+300,expires,fetched,300),"5 min interval, 300 s in: due");
    CHECK(WXGUnlockRefreshDue(fetched-301,expires,fetched,300),"clock set back past the interval: due");
    CHECK(!WXGUnlockRefreshDue(fetched-60,expires,fetched,300),"clock a minute behind: not due");
    CHECK(WXGUnlockRefreshDue(expires-2*86400.,expires,fetched+6*86400.,WXG_UNLOCK_RECHECK_MAX),"2 days left: due even if just fetched");
    CHECK(WXGUnlockRefreshDue(expires+1,expires,fetched,300),"expired: due");
    CHECK(WXGUnlockRefreshDue(fetched+60,expires,0,300),"no fetch time: due");

    /* Back-off after failures in a row. */
    CHECK(WXGUnlockBackoff(0,0)==0 && WXGUnlockBackoff(1,0)==5 && WXGUnlockBackoff(2,0)==15 && WXGUnlockBackoff(3,0)==60,"first steps");
    CHECK(WXGUnlockBackoff(4,0)==300 && WXGUnlockBackoff(5,0)==900 && WXGUnlockBackoff(40,0)==900,"capped at 15 min");
    CHECK(WXGUnlockBackoff(1,1)==300 && WXGUnlockBackoff(5,1)==900,"with a usable ticket: at least 5 min");

    /* Clock correction from the server's Date. */
    CHECK(WXGUnlockClockOffset(1000,1001,0)==0,"1 s: no correction");
    CHECK(WXGUnlockClockOffset(1000,1600,0)==600 && WXGUnlockClockOffset(1600,1000,0)==-600,"10 min either way");
    CHECK(WXGUnlockClockOffset(1000,0,42)==42,"no Date: keep the previous offset");

    printf("UnlockPolicyTests: %s\n",failures?"FAILED":"ok");
    return failures?1:0;
}
