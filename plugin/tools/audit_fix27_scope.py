#!/usr/bin/env python3
"""FIX27 scope audit against an unpacked FIX26 tree.

Usage: python3 tools/audit_fix27_scope.py --baseline <FIX26 dir> [--json out.json]
Checks: the mesh builder, ROI/prediction/geometry and input/dock-interaction
sources are byte-identical; no identifier or string containing "lumi" remains
in Sources/Tests/tools; FIX27 markers exist.
"""
import argparse, hashlib, json, os, re, sys
FROZEN = ["WXGMeshRefraction.h", "WXGLensOptics.h", "WXGMotion.h", "WXGElasticMotion.h.skip", "WXGMotionPrediction.h",
          "WXGDistanceField.h", "WXGBackdropCopy.h", "WXGBackdropROI.h", "WXGBackdropTraversal.h", "WXGSourceMapping.h",
          "WXGGeometry.h", "WXGRenderPolicy.h", "WXGSurface.m", "WXGInput.m", "WXGNativeInput.m", "WXGNative.m",
          "WXGDockInteraction.m", "WXGNativeIcons.m", "WXGIntegration.h"]
MARKERS = {"WXGHost.m": ["concealTransitionSnapshots", "MainFrameTableView", "capturePullDownCensus", "readback=WXGEffectiveRenderMode()<2"],
           "WXGGlassView.m": ["WXGRimStrengthTLBR", "WXGBrightened", "_dockSurface?(dark?c.dockDarkMaterialHex", "marginWidth", "==224"],
           "WXGGlass.metal": ["float4 style;", "wxgVeilWidth"],
           "WXGOptics.h": ["WXGRimStrengthTLBR"],
           "WXGConfig.m": ["_renderMode=2;_syncMeshRefraction=YES;", "messageMenuCornerRadius", "dockMaterialOpacity"],
           "WXGDecorations.m": ["messageMenuCornerRadius"]}
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--baseline", required=True); ap.add_argument("--json"); a = ap.parse_args()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    S = lambda root, n: os.path.join(root, "Sources", n)
    problems, changed, added = [], [], []
    for n in sorted(os.listdir(os.path.join(here, "Sources"))):
        if not os.path.exists(S(a.baseline, n)): added.append(n)
        elif sha(S(here, n)) != sha(S(a.baseline, n)): changed.append(n)
    frozen = [n for n in FROZEN if not n.endswith(".skip")]
    problems += ["frozen changed: " + n for n in frozen if n in changed]
    for n, needles in MARKERS.items():
        t = open(S(here, n), encoding="utf-8").read()
        problems += [f"missing {x!r} in {n}" for x in needles if x not in t]
    lumi = []
    for folder in ("Sources", "Tests", "tools"):
        for name in os.listdir(os.path.join(here, folder)):
            path = os.path.join(here, folder, name)
            if os.path.isfile(path) and re.search(r"lumi", open(path, encoding="utf-8", errors="ignore").read(), re.I):
                lumi.append(f"{folder}/{name}")
    lumi = [x for x in lumi if not x.endswith("audit_fix27_scope.py")]
    problems += ["'lumi' still in " + x for x in lumi]
    report = {"baseline": os.path.abspath(a.baseline), "changedSources": changed, "addedSources": added,
              "frozenIdentical": [n for n in frozen if n not in changed], "lumiOccurrences": lumi, "problems": problems}
    if a.json: json.dump(report, open(a.json, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1)); return 1 if problems else 0
if __name__ == "__main__": sys.exit(main())
