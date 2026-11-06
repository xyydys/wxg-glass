#ifndef WXG_SHARE_CHAIN_H
#define WXG_SHARE_CHAIN_H
/* FIX114 L / N: 共用 — whose settings of a page (折射 0, 模糊 1, 材质 2,
   边框 3) a glass range uses. Ranges: 0 其余玻璃, 1 底栏, 2 气泡, 3 分组,
   4 设置页, 5 底栏透镜, 6 分组透镜, 7 视频号 (FIX115 S, 边框 only). A range of a page holds 0 (its own) or
   the range it uses + 1. FIX114 N (user: from a range's page its settings
   are shared OUT to the ranges chosen there, 共用到): the settings page sets
   those ranges' values; any range of the page may be the source.
   Resolution follows the chain (分组 uses 底栏, 底栏 uses 其余玻璃); a value
   naming no range of that page, or a loop (never made by the settings page),
   is the range's own. */
#define WXG_SHARE_RANGES 8
#define WXG_SHARE_PAGES 4
typedef long (*WXGShareValueFn)(void *context,int range,int page);
/* present[r][p]: range r is on page p (it has a value there). */
static inline int WXGShareResolve(int range,int page,const unsigned char present[WXG_SHARE_RANGES][WXG_SHARE_PAGES],
                                  WXGShareValueFn value,void *context) {
    if(page<0 || page>=WXG_SHARE_PAGES || range<0 || range>=WXG_SHARE_RANGES)return range;
    int start=range;
    for(int step=0;step<=WXG_SHARE_RANGES;step++) {
        if(!present[range][page])return range;
        long v=value(context,range,page);
        if(v<1 || v>WXG_SHARE_RANGES)return range;
        int next=(int)v-1;
        if(next==range || !present[next][page])return range;
        range=next;
    }
    return start;   /* a loop */
}
#endif
