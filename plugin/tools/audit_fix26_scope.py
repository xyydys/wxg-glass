#!/usr/bin/env python3
"""FIX26 scope audit against an unpacked FIX25 tree.

Usage: python3 tools/audit_fix21_scope.py --baseline <FIX25 dir> [--json out.json]
"""
import argparse, hashlib, json, os, sys
FROZEN = ["WXGBackdrop.m", "WXGGlass.metal", "WXGShaderSource.h", "WXGLensOptics.h", "WXGDemoBar.m",
          "WXGNativeIcons.m", "WXGOptics.h", "WXGMotion.h", "WXGElasticMotion.h", "WXGMotionPrediction.h", "WXGDistanceField.h",
          "WXGBackdropCopy.h", "WXGBackdropROI.h", "WXGBackdropTraversal.h", "WXGSourceMapping.h", "WXGGeometry.h",
          "WXGRenderPolicy.h", "WXGSurface.m", "WXGInput.m", "WXGNativeInput.m", "WXGNative.m", "WXGDecorations.m",
          "WXGDockInteraction.m", "WXGIntegration.h"]
ALLOWED = {"WXGMeshRefraction.h", "WXGGlassView.m", "WXGHost.m", "WXGSettings.m", "WXGCommon.h", "WXGConfig.m", "WXGOpticalSettings.m"}
MARKERS = {"WXGMeshRefraction.h": ["WXGMeshZipperChains", "((float)i+.5f)", "segments%2==0"],
           "WXGGlassView.m": ["applyCaptureScale", "contour_zipper_FIX26", "requestedCaptureScale"],
           "WXGConfig.m": ["syncCaptureScale"]}
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--baseline", required=True); ap.add_argument("--json"); a = ap.parse_args()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    S = lambda root, n: os.path.join(root, "Sources", n)
    problems, changed, added = [], [], []
    for n in sorted(os.listdir(os.path.join(here, "Sources"))):
        if not os.path.exists(S(a.baseline, n)): added.append(n)
        elif sha(S(here, n)) != sha(S(a.baseline, n)): changed.append(n)
    problems += ["frozen changed: " + n for n in FROZEN if n in changed]
    problems += ["unexpected change: " + n for n in changed + added if n not in ALLOWED]
    for n, needles in MARKERS.items():
        t = open(S(here, n), encoding="utf-8").read()
        problems += [f"missing {x!r} in {n}" for x in needles if x not in t]
    report = {"baseline": os.path.abspath(a.baseline), "changedSources": changed, "addedSources": added,
              "frozenIdentical": [n for n in FROZEN if n not in changed], "problems": problems}
    if a.json: json.dump(report, open(a.json, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1)); return 1 if problems else 0
if __name__ == "__main__": sys.exit(main())
