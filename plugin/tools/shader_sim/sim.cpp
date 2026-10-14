// FIX95: run the embedded Metal shader (WXGShaderSource.h) on the CPU, so the
// dock lens can be looked at with the tester's settings without a device.
// build.py turns the shader into shader.inc (Metal constructors -> stub
// overloads, as check_msl.py does) and compiles this file against stub/.
// Usage: sim <params.txt> <out.ppm>
//   params.txt: "key value" lines (see the defaults below).
#include <metal_stdlib>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>
float wxgSimFwidth = 0.f, wxgSimRecorded = 0.f; int wxgSimRecording = 0;
#include "shader.inc"

static std::map<std::string, double> P;
static double V(const char *k, double d) { auto i = P.find(k); return i == P.end() ? d : i->second; }

struct Img { int w, h; std::vector<float> px; Img(int W, int H) : w(W), h(H), px((size_t)W * H * 4, 0.f) {} };
static void disc(Img &im, float cx, float cy, float r, float ring, float4 c, float s) {
    for (int y = 0; y < im.h; y++) for (int x = 0; x < im.w; x++) {
        float px = (x + .5f) / s, py = (y + .5f) / s, d = std::sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
        float a = ring > 0 ? clamp(1 - std::fabs(d - r) / ring + .5f, 0.f, 1.f) : clamp(r - d + .5f, 0.f, 1.f);
        if (a <= 0) continue;
        float *p = &im.px[4 * ((size_t)y * im.w + x)];
        for (int k = 0; k < 4; k++) p[k] = c[k] * a + p[k] * (1 - a * c[3]);
    }
}
static void rect(Img &im, float x0, float y0, float x1, float y1, float4 c, float s) {
    for (int y = (int)(y0 * s); y < (int)(y1 * s) && y < im.h; y++) for (int x = (int)(x0 * s); x < (int)(x1 * s) && x < im.w; x++) {
        if (x < 0 || y < 0) continue;
        float *p = &im.px[4 * ((size_t)y * im.w + x)];
        for (int k = 0; k < 4; k++) p[k] = c[k] + p[k] * (1 - c[3]);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: sim params out.ppm\n"); return 2; }
    FILE *f = fopen(argv[1], "r"); char key[128]; double val;
    while (f && fscanf(f, "%127s %lf", key, &val) == 2) P[key] = val;
    if (f) fclose(f);
    const float S = 3;
    float viewW = V("viewW", 414), viewH = V("viewH", 120);
    float barW = V("barW", 321), barH = V("barH", 61.07f), barX = (viewW - barW) * .5f, barY = V("barY", 30);
    float press = V("press", 1), anchor = V("anchor", 1.5);   // anchor in tabs (0..3)
    float gap = WXGSelectionGap(V("selectionInset", 4.0), barH);
    float anchorX = WXGSelectionCenter(barW, gap, 0) + (WXGSelectionCenter(barW, gap, 3) - WXGSelectionCenter(barW, gap, 0)) * anchor / 3;
    WXGDockGeometry g = WXGDockLayout(barW, barH, gap, anchorX, press, V("lensGrowth", 1.1815), 0, V("barGrowth", 1.0357), V("endWrap", 9.11));
    WXGUniforms u; memset(&u, 0, sizeof u);
    u.viewport = mk_float4(viewW, viewH, S, 0);
    u.bar = mk_float4(barX, barY, barW, barH);
    u.lens = mk_float4(barX + g.lensX, barY + g.lensY, g.lensWidth, g.lensHeight);
    u.material = mk_float4(press, V("dockRefraction", 10.07), V("dockDispersion", 2.2165), V("dockBlur", 1.088));
    u.lensOptics = mk_float4(V("lensRefraction", 6.827), V("lensDispersion", 4.583), V("lensEdgeWidth", 19.18), V("lensBlurCoverage", 0) * .01);
    u.appearance = mk_float4(V("dark", 1), 0, 0, 1);
    float glowOn = V("glow", 1);
    u.optics = mk_float4(V("lensZoom", 1.063), glowOn ? V("glow1Width", 1.50) : V("rimWidth", 1.0), V("bodyPinch", .131), V("dockEdgeWidth", 9.528));
    u.glow = glowOn ? mk_float4(1 + V("glow1Angle", 90.24) * M_PI / 180, V("glow1End", .237), V("glow1Sharp", 5.057), V("glow1Falloff", 3.475)) : mk_float4(0.f);
    u.glow2 = glowOn ? mk_float4(1 + V("glow2Angle", 0) * M_PI / 180, V("glow2End", .15), V("glow2Sharp", 5.76), V("glow2Falloff", 3.874)) : mk_float4(0.f);
    u.glowColor2 = glowOn ? mk_float4(1, 1, 1, V("glow2Alpha", .688)) : mk_float4(0.f);
    u.extra = mk_float4(glowOn ? V("glow2Width", 2.04) : 0, V("lensDispersionWidth", 31.2), V("lensDispersionTopRatio", .4965), V("margin", .5));
    float selA = V("selectionAlpha", .5) * (V("selectionOpacity", .611) + (V("pressedOpacity", .4) - V("selectionOpacity", .611)) * press);
    u.selectionColor = mk_float4(.36f, .36f, .36f, selA);
    u.borderColor = glowOn ? mk_float4(0, 0, 0, V("glow1Alpha", .74)) : mk_float4(1, 1, 1, .23f);
    u.motion = mk_float4(g.scale, 0, V("dockBlurCoverage", 71.65) * .01, barX + g.anchorX);
    u.rim = mk_float4(0, 1, V("lensBorderWidth", .689), 0);
    float tint = V("tint", .133);   // FIX97: light mode-ish with page 1, tint ~.9
    u.tintColor = mk_float4(tint, tint, tint, V("tintAlpha", .748));
    u.sync = mk_float4(2, V("ratio", .3327), V("sharp", 3.254), 1);
    u.style = mk_float4(V("edgeFadeRange", 3.54), 0, 0, 0);
    // FIX97: lensBarDispersion, lensBarDispersionNearRim (0 0 = FIX96), the page the shader assumes behind.
    u.extra2 = mk_float4(V("barDisp", .6), V("barDispRim", .35), V("pageGuess", V("page", 0)), 0);
    // Icons: a ring (unselected) / a filled disc (selected) and a title bar per tab.
    int W = (int)(viewW * S), H = (int)(viewH * S);
    Img normal(W, H), selected(W, H);
    float cy = barY + barH * .5f;
    for (int i = 0; i < 4; i++) {
        float cx = barX + WXGSelectionCenter(barW, gap, i);
        disc(normal, cx, cy - 7, 11, 1.4f, mk_float4(.75f, .75f, .75f, 1), S);
        rect(normal, cx - 12, cy + 10, cx + 12, cy + 15, mk_float4(.75f, .75f, .75f, 1), S);
        disc(selected, cx, cy - 7, 12, 0, mk_float4(.03f * 1, .76f, .38f, 1), S);
        rect(selected, cx - 12, cy + 10, cx + 12, cy + 15, mk_float4(.03f, .76f, .38f, 1), S);
    }
    texture2d<float> none, ni, si; ni.data = normal.px.data(); ni.w = W; ni.h = H; si.data = selected.px.data(); si.w = W; si.h = H;
    // The composite: black page; the bar's render-server veil and the body
    // pass (icons) outside the lens; inside the lens's clip the lens pass over
    // the (black) refracted page.
    float veilA = clamp(.748f * 1.22f, 0.f, 1.f);
    std::vector<unsigned char> out((size_t)W * H * 3);
    WXGShapeSample tmp;
    // fwidth (the one in the lens pass): a first pass records its argument per
    // pixel, the second gets |d/dx| + |d/dy| from the neighbours (as the GPU).
    std::vector<float> rec((size_t)W * H, 0.f), fw((size_t)W * H, 0.f);
    if (V("fwidthSim", 1) > .5) {
        wxgSimRecording = 1;
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            WXGOut in; in.position = mk_float4(0.f); in.uv = mk_float2((x + .5f) / W, (y + .5f) / H);
            float2 p = in.uv * u.viewport.xy;
            if (wxgShape(p, u.lens, 0).distance * S > 1.5f) continue;
            wxgSimRecorded = 0; (void)wxgFragment(in, u, none, ni, si, none, none, none); rec[(size_t)y * W + x] = wxgSimRecorded;
        }
        wxgSimRecording = 0;
        for (int y = 0; y + 1 < H; y++) for (int x = 0; x + 1 < W; x++) {
            size_t i = (size_t)y * W + x;
            fw[i] = std::fabs(rec[i + 1] - rec[i]) + std::fabs(rec[i + W] - rec[i]);
        }
    }
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
        WXGOut in; in.position = mk_float4(0.f); in.uv = mk_float2((x + .5f) / W, (y + .5f) / H);
        float2 p = in.uv * u.viewport.xy;
        float3 c = mk_float3((float)V("page", 0));   // FIX97: the page's brightness (0 black)
        float scale = g.scale;
        tmp = wxgShape(wxgBasePoint(p, u), u.bar, 0);
        float barCov = clamp(.5f - tmp.distance * scale * S, 0.f, 1.f);
        c = c * (1 - barCov * veilA) + mk_float3(tint) * barCov * veilA;
        WXGUniforms b = u; b.appearance.w = 0;
        float4 body = wxgFragment(in, b, none, ni, si, none, none, none);
        c = body.xyz + c * (1 - body.w);
        WXGShapeSample l = wxgShape(p, u.lens, 0);
        float lensCov = clamp(.5f - l.distance * S, 0.f, 1.f);
        if (lensCov > 0) {
            wxgSimFwidth = fw[(size_t)y * W + x];
            float4 lens = wxgFragment(in, u, none, ni, si, none, none, none);
            float3 inside = lens.xyz + mk_float3((float)V("page", 0)) * (1 - lens.w);   // over the page (FIX97; black before)
            c = c * (1 - lensCov) + inside * lensCov;
            // the lens rim (CA layer): a thin light line
            float rimA = clamp(1 - std::fabs(l.distance + .35f) * S / 1.2f, 0.f, 1.f) * .45f;
            c = c * (1 - rimA) + mk_float3(.85f) * rimA;
        }
        unsigned char *o = &out[3 * ((size_t)y * W + x)];
        for (int k = 0; k < 3; k++) o[k] = (unsigned char)clamp(std::pow(clamp(c[k], 0.f, 1.f), 1.f) * 255.f + .5f, 0.f, 255.f);
    }
    FILE *o = fopen(argv[2], "wb"); fprintf(o, "P6 %d %d 255\n", W, H); fwrite(out.data(), 1, out.size(), o); fclose(o);
    printf("lens %.2f x %.2f at %.2f,%.2f  bar scale %.4f\n", g.lensWidth, g.lensHeight, barX + g.lensX, barY + g.lensY, g.scale);
    return 0;
}
