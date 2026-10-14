#ifndef WXG_UNLOCK_POLICY_H
#define WXG_UNLOCK_POLICY_H
#include <stdio.h>
#include <string.h>
/* FIX103: the unlock ticket's rules (WXGUnlock.m), pure C.
   The server (wxg-glass worker.js, POST /v1/unlock) answers an authorized
   account with {ver, expiresAt, shader, digest, sig}; sig is ECDSA P-256 /
   SHA-256 (X9.62 DER) over "account|device|ver|expiresAt|digest", account
   and device as sent (64 lowercase hex), expiresAt in whole Unix seconds,
   digest the lowercase hex SHA-256 of the shader's UTF-8 bytes. */

/* Times are Unix seconds (the device clock corrected by the server's Date). */
/* FIX104: how often an authorized account asks again is the server's: its
   answer's recheckAfter (seconds; not signed, only ever shortens how long an
   account keeps working after it leaves the list, never the signed expiry).
   No recheckAfter (FIX103's server, a FIX103 cache): the default below. A 403
   may carry one too: how long a refused account waits before asking again. */
#define WXG_UNLOCK_RECHECK_DEFAULT (600.)        /* the server named no interval */
#define WXG_UNLOCK_RECHECK_MIN     (60.)         /* never more often than once a minute */
#define WXG_UNLOCK_RECHECK_MAX     (7.*86400.)   /* the ticket's lifetime */
#define WXG_UNLOCK_REFRESH_LEFT    (3.*86400.)   /* also renewed when less than 3 days remain */
#define WXG_UNLOCK_ROLLBACK_SLACK  (86400.)      /* a clock this far before the fetch: not trusted */
#define WXG_UNLOCK_DENIED_RECHECK  (600.)        /* a refused account is asked again after 10 min */
#define WXG_UNLOCK_OUTDATED_RECHECK (3600.)      /* a shader of another version: again after 1 h */

/* 64 lowercase hex digits: the account and device as the server takes them. */
static inline int WXGUnlockHex64(const char *s) {
    if(!s || strlen(s)!=64)return 0;
    for(const char *p=s;*p;p++)if(!((*p>='0' && *p<='9') || (*p>='a' && *p<='f')))return 0;
    return 1;
}
/* The signed message, exactly as worker.js joins it. Returns its length, or
   -1 when a field is malformed or it does not fit. */
static inline int WXGUnlockSignedMessage(char *out,size_t size,const char *account,const char *device,
                                         const char *ver,long long expiresAt,const char *digest) {
    if(!out || !size || !WXGUnlockHex64(account) || !WXGUnlockHex64(device) || !WXGUnlockHex64(digest) || !ver || !*ver || strchr(ver,'|') || expiresAt<=0)return -1;
    int n=snprintf(out,size,"%s|%s|%s|%lld|%s",account,device,ver,expiresAt,digest);
    return n>0 && (size_t)n<size?n:-1;
}
/* A ticket opens the plugin until it expires, unless the clock is well
   before the time it was fetched (set back to stretch the 7 days). */
static inline int WXGUnlockTicketUsable(double now,double expiresAt,double fetchedAt) {
    if(!(now>0.) || !(expiresAt>0.))return 0;
    if(fetchedAt>0. && now<fetchedAt-WXG_UNLOCK_ROLLBACK_SLACK)return 0;
    return now<expiresAt;
}
/* FIX104: the server's recheckAfter as used: missing, zero, negative or NaN
   -> the default; otherwise within [min, max]. */
static inline double WXGUnlockRecheckInterval(double sent) {
    if(!(sent>0.))return WXG_UNLOCK_RECHECK_DEFAULT;
    return sent<WXG_UNLOCK_RECHECK_MIN?WXG_UNLOCK_RECHECK_MIN:sent>WXG_UNLOCK_RECHECK_MAX?WXG_UNLOCK_RECHECK_MAX:sent;
}
/* A refused account asks again after the 403's recheckAfter (at most a day),
   or WXG_UNLOCK_DENIED_RECHECK when it named none. */
static inline double WXGUnlockDeniedWait(double sent) {
    if(!(sent>0.))return WXG_UNLOCK_DENIED_RECHECK;
    return sent<WXG_UNLOCK_RECHECK_MIN?WXG_UNLOCK_RECHECK_MIN:sent>86400.?86400.:sent;
}
/* A usable ticket is checked again in the background once `recheck` seconds
   (WXGUnlockRecheckInterval) have passed since it was fetched, or with less
   than 3 days left (so a phone opened once a week stays open). A clock that
   far before the fetch counts as passed too (FIX104). */
static inline int WXGUnlockRefreshDue(double now,double expiresAt,double fetchedAt,double recheck) {
    if(!WXGUnlockTicketUsable(now,expiresAt,fetchedAt))return 1;
    double since=now-fetchedAt;
    return since>=recheck || -since>=recheck || expiresAt-now<WXG_UNLOCK_REFRESH_LEFT;
}
/* Seconds to wait after the n-th failure in a row (1-based): 5, 15, 60,
   300, then 900. With a usable ticket the wait is at least 5 minutes. */
static inline double WXGUnlockBackoff(unsigned failures,int haveTicket) {
    static const double steps[]={5.,15.,60.,300.,900.};
    double wait=failures==0?0.:steps[failures>5?4:failures-1];
    return haveTicket && wait<300.?300.:wait;
}
/* The device clock is corrected by the server's Date header when they
   differ by more than 2 s; the server refuses a ts more than 300 s off. */
static inline double WXGUnlockClockOffset(double deviceNow,double serverDate,double previous) {
    if(!(serverDate>0.) || !(deviceNow>0.))return previous;
    double d=serverDate-deviceNow;
    return d>2. || d<-2.?d:0.;
}
#endif
