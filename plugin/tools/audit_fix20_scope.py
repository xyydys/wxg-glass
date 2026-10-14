#!/usr/bin/env python3
"""FIX20 scope audit against an unpacked FIX19 tree.

Usage: python3 tools/audit_fix20_scope.py --baseline <FIX19 dir> [--json out.json]
FIX20 changes only the render-server (同步) mode: mesh refraction and the clear
edge ring. The readback sampler (WXGBackdrop.m), shader, optics, prediction,
geometry, layout, input and dock sources must be byte-identical to FIX19.
"""
import argparse, hashlib, json, os, sys
FROZEN = ["WXGBackdrop.m", "WXGIntegration.h", "WXGGlass.metal", "WXGShaderSource.h", "WXGOptics.h", "WXGLensOptics.h",
          "WXGMotion.h", "WXGElasticMotion.h", "WXGMotionPrediction.h", "WXGDistanceField.h", "WXGBackdropCopy.h",
          "WXGBackdropROI.h", "WXGBackdropTraversal.h", "WXGSourceMapping.h", "WXGGeometry.h", "WXGRenderPolicy.h",
          "WXGSurface.m", "WXGDemoBar.m", "WXGInput.m", "WXGNativeInput.m", "WXGNative.m", "WXGDecorations.m",
          "WXGDockInteraction.m", "WXGNativeIcons.m"]
ALLOWED = {"WXGGlassView.m", "WXGHost.m", "WXGConfig.m", "WXGCommon.h", "WXGOpticalSettings.m", "WXGSettings.m",
           "WXGMeshRefraction.h"}
MARKERS = {"WXGGlassView.m": ["meshTransformWithVertexCount", "applyRefraction:", "WXGSharpRingAlpha", "_edgeBackdrop", "colorSaturate"],
           "WXGMeshRefraction.h": ["WXGBuildRefractionMesh", "WXGOpticalOffset", "WXGRoundedOpticalField"],
           "WXGConfig.m": ["syncMeshRefraction"]}
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
