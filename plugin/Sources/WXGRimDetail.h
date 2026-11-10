#ifndef WXG_RIM_DETAIL_H
#define WXG_RIM_DETAIL_H
/* What the two borders' layers share (WXGGlassView.m): a stack of nested
   Core Animation borders on the glass' own continuous corners (each band the
   outline inset by `inset`, `width` wide, at `alpha`), and a QuartzCore
   colour matrix (rows R, G, B, A of r, g, b, a, offset). */
#define WXG_RIM_MAX_STEPS 10
typedef struct { int count; double inset[2*WXG_RIM_MAX_STEPS+1],width[2*WXG_RIM_MAX_STEPS+1],alpha[2*WXG_RIM_MAX_STEPS+1]; } WXGRimBands;
typedef struct { float m[20]; } WXGRimMatrix;
#endif
