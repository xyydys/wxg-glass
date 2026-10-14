#!/usr/bin/env python3
"""FIX57 lineage / scope check.
FIX57 = FIX47's lens + everything else from FIX54 (avatar and pinned row as
FIX44, the wallet top fix) + one change: at the dock's ends the band that bends
the bar seen through the lens (and the page behind it) relaxes toward the top /
bottom width.
  lens files   WXGGlass.metal, WXGGlassView.m, WXGLensOptics.h, WXGMeshRefraction.h,
               WXGOptics.h: FIX47's, plus the FIX57 edits listed below (undoing them
               must give FIX47's file exactly)
  shader       WXGShaderSource.h is WXGGlass.metal embedded (embed_shader.py)
  everything else: FIX54's (version strings aside)
  tests        FIX47's lens tests (ContourMesh, MeshRefraction, Optics, RollbackOptics,
               LensEndRim), FIX54's others, plus the new LensEndRelaxTests.c
Usage: verify_fix57_scope.py <FIX54 dir> <FIX47 dir> [--json out]"""
import json, os, re, sys
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fix54, fix47 = sys.argv[1], sys.argv[2]
VERSION = [r"0\.4\.\d+", r"test4fix\d+", r"TEST4 FIX\d+", r"TEST4_FIX\d+", r"contour_zipper_FIX\d+", r'"revision":@"FIX\d+"']
def norm(text):
    for pattern in VERSION: text = re.sub(pattern, "<v>", text)
    return text
def read(*parts): return open(os.path.join(*parts), encoding="utf-8").read()
optics = read(here, "Sources", "WXGLensOptics.h")
UNDO = {
"WXGLensOptics.h": [(optics[optics.index("\n/* ---- FIX57"):-len("#endif\n")], "")],
"WXGMeshRefraction.h": [
    ("""    float barLeft,barTop,barRight,barBottom;
    /* FIX57 (zero = off): how far the lens's left / right end has relaxed
       toward the top / bottom width at the bar's ends (WXGLensEndReach). */
    float endLeft,endRight;
""", """    float barLeft,barTop,barRight,barBottom;
"""),
    ("""    if(o.topRatio>0.f)width=WXGLensEndRelax(width,f.nx,o.edgeWidth,o.topRatio,o.endLeft,o.endRight);
""", "")],
"WXGGlass.metal": [
    ("""        // FIX57: as a lens end reaches the bar's end, the bar seen through it
        // uses the band relaxed toward the top/bottom width (no more sticking
        // to the rim at the first / last tab); icons keep lensWidth.
        float2 barMid=u.bar.xy+u.bar.zw*.5;
        float barHalf=u.bar.z*u.motion.x*.5;
        float endLeft=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,-1);
        float endRight=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,1);
        float barBand=WXGLensEndRelax(lensWidth,lens.nx,optical.edgeWidth,u.sync.y,endLeft,endRight);
        float2 bend=wxgBasePoint(p-n*(WXGOpticalOffset(lens.distance,barBand,optical.refraction)*press),u);
""", """        float2 bend=wxgBasePoint(refracted,u);
""")],
"WXGGlassView.m": [
    (""" && fabsf(a.barBottom-b.barBottom)<.25f &&
        fabsf(a.endLeft-b.endLeft)<.005f && fabsf(a.endRight-b.endRight)<.005f;""", """ && fabsf(a.barBottom-b.barBottom)<.25f;"""),
    ("float key[23]=", "float key[21]="),
    ("""roundf(optics.barBottom*10),
        roundf(optics.endLeft*1000),roundf(optics.endRight*1000),0};""", """roundf(optics.barBottom*10),0};"""),
    ("""    float _edgeMaskKey[5];
    // FIX57: last end relaxation of the lens band (0 FIX47 band .. 1 top width).
    float _endReachLeft,_endReachRight;
""", """    float _edgeMaskKey[5];
"""),
    ("""    WXGMeshOptics lensOptics=bodyOptics;CGFloat lensBlur=0;BOOL lensMesh=NO;
    _endReachLeft=_endReachRight=0.f;
""", """    WXGMeshOptics lensOptics=bodyOptics;CGFloat lensBlur=0;BOOL lensMesh=NO;
"""),
    ("""        // FIX57: at the bar's ends the band relaxes toward the top/bottom width,
        // exactly as the shader does for the bar seen through the lens. In 1/8
        // steps; zero (nothing rebuilt) while the band cannot show it.
        if(c.lensTopEdgeRatio<1 && press>0.f && (optical.refraction>0.f || optical.dispersion>0.f)) {
            CGRect bar=[self drawnBarRect];
            float barX0=(float)CGRectGetMinX(bar),barX1=(float)CGRectGetMaxX(bar);
            float lensX0=(float)CGRectGetMinX(_lensRect),lensX1=(float)CGRectGetMaxX(_lensRect);
            lensOptics.endLeft=roundf(WXGLensEndReach(barX0,barX1,lensX0,lensX1,-1)*8.f)/8.f;
            lensOptics.endRight=roundf(WXGLensEndReach(barX0,barX1,lensX0,lensX1,1)*8.f)/8.f;
        }
        _endReachLeft=lensOptics.endLeft;_endReachRight=lensOptics.endRight;
""", ""),
    ("""@"endReach":@[@(_endReachLeft),@(_endReachRight)],""", "")],
}
LENS = set(UNDO) | {"WXGOptics.h"}
VERSION_ONLY = {"WXGHost.m", "WXGSettings.m"}
problems, sources = [], {}
names = sorted(set(os.listdir(os.path.join(here, "Sources"))) | set(os.listdir(os.path.join(fix54, "Sources"))))
for name in names:
    mine = os.path.join(here, "Sources", name)
    if not os.path.exists(mine) or not os.path.exists(os.path.join(fix54, "Sources", name)):
        problems.append(f"Sources/{name}: added or removed"); continue
    new = read(mine)
    if name == "WXGShaderSource.h": continue
    if name in LENS:
        undone = new
        for after, before in UNDO.get(name, []):
            if undone.count(after) != 1: problems.append(f"Sources/{name}: FIX57 edit not found once: {after[:60]!r}"); continue
            undone = undone.replace(after, before)
        ok = norm(undone) == norm(read(fix47, "Sources", name))
        sources[name] = ("FIX47 + FIX57 edits" if name in UNDO else "FIX47") if ok else "changed"
        if not ok: problems.append(f"Sources/{name}: differs from FIX47 beyond the FIX57 edits")
        continue
    old = read(fix54, "Sources", name)
    if new == old: sources[name] = "FIX54"
    elif name in VERSION_ONLY and norm(new) == norm(old): sources[name] = "FIX54 (version strings)"
    else: sources[name] = "changed"; problems.append(f"Sources/{name}: differs from FIX54")
src = read(here, "Sources", "WXGGlass.metal")
src = src.replace('#include "WXGLensOptics.h"', read(here, "Sources", "WXGLensOptics.h")).replace('#include "WXGOptics.h"', read(here, "Sources", "WXGOptics.h"))
embedded = ('// Generated from WXGGlass.metal; rebuild with tools/embed_shader.py.\n'
            'static const char WXGMetalSource[] =\n' + '\n'.join(json.dumps(line + '\n') for line in src.splitlines()) + ';\n')
sources["WXGShaderSource.h"] = "embedded WXGGlass.metal" if embedded == read(here, "Sources", "WXGShaderSource.h") else "stale"
if sources["WXGShaderSource.h"] == "stale": problems.append("WXGShaderSource.h is not the embedded WXGGlass.metal")
# Icons keep FIX47's band; the avatar / pinned code of FIX45-47 is gone; the wallet fix is in.
shader = read(here, "Sources", "WXGGlass.metal")
for line in ["float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,optical.edgeWidth,u.sync.y,u.sync.z,wxgShape(base,u.bar,u.rim.w).distance*u.motion.x);",
             "float2 refracted=p-n*offset;",
             "float2 iconRay=iconCenter+((barCentre+(refracted-barCentre)/u.motion.x)-iconCenter)/zoom;",
             "return wxgIconsOver(selectedIcons,iconRay,chroma/(u.motion.x*zoom),acc,u);"]:
    if shader.count(line) != 1: problems.append(f"shader: icon line missing or changed: {line}")
allsrc = "".join(read(here, "Sources", n) for n in names if os.path.exists(os.path.join(here, "Sources", n)))
for gone in ["avatarBare", "avatarSize", "avatarRimHex", "applyPinnedShift", "pinnedProbe", "avatarProbe", "chatAvatarImageForTitle", "additionalSafeAreaInsets"]:
    if gone in allsrc: problems.append(f"avatar / pinned code still present: {gone}")
for kept in ["WXGColorsDiffer", "allowOverflow:", "kindaProbe"]:
    if kept not in allsrc: problems.append(f"wallet fix missing: {kept}")
tests = {}
LENS_TESTS = {"ContourMeshTests.c", "MeshRefractionTests.c", "OpticsTests.c", "RollbackOpticsTests.c", "LensEndRimTests.c"}
for name in sorted(set(os.listdir(os.path.join(here, "Tests"))) | set(os.listdir(os.path.join(fix54, "Tests")))):
    mine = os.path.join(here, "Tests", name)
    if os.path.isdir(mine): continue
    if name == "LensEndRelaxTests.c": tests[name] = "new"; continue
    base = fix47 if name in LENS_TESTS else fix54
    ref = os.path.join(base, "Tests", name)
    if not os.path.exists(mine) or not os.path.exists(ref): tests[name] = "missing"; problems.append(f"Tests/{name}: added or removed"); continue
    same = read(mine) == read(ref)
    tests[name] = ("FIX47" if base == fix47 else "FIX54") if same else "changed"
    if not same: problems.append(f"Tests/{name}: differs from {'FIX47' if base == fix47 else 'FIX54'}")
strip = lambda t: "\n".join(l for l in norm(t).splitlines() if not l.startswith("Description:"))
if strip(read(fix54, "control")) != strip(read(here, "control")): problems.append("control: changed beyond name / version / description")
result = {"sources": sources, "tests": tests, "problems": problems}
if len(sys.argv) > 4 and sys.argv[3] == "--json":
    json.dump(result, open(sys.argv[4], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(result, ensure_ascii=False, indent=1))
sys.exit(1 if problems else 0)
