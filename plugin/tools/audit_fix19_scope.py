#!/usr/bin/env python3
"""FIX19 scope audit against an unpacked FIX18 tree.

Usage: python3 tools/audit_fix19_scope.py --baseline <FIX18 dir> [--json out.json]
FIX19 changes only WHEN and FROM WHICH TREE the background is read and how the
drawable is presented. Shader, optics, prediction model, geometry, layout,
input and dock sources must be byte-identical to FIX18.
"""
import argparse, hashlib, json, os, sys
FROZEN = ["WXGGlass.metal", "WXGShaderSource.h", "WXGOptics.h", "WXGLensOptics.h", "WXGMotion.h", "WXGElasticMotion.h",
          "WXGMotionPrediction.h", "WXGDistanceField.h", "WXGBackdropCopy.h", "WXGBackdropROI.h", "WXGBackdropTraversal.h",
          "WXGSourceMapping.h", "WXGGeometry.h", "WXGRenderPolicy.h", "WXGSurface.m", "WXGDemoBar.m", "WXGInput.m",
          "WXGNativeInput.m", "WXGNative.m", "WXGDecorations.m", "WXGDockInteraction.m", "WXGNativeIcons.m"]
ALLOWED = {"WXGBackdrop.m", "WXGGlassView.m", "WXGHost.m", "WXGConfig.m", "WXGCommon.h", "WXGIntegration.h",
           "WXGOpticalSettings.m", "WXGSettings.m"}
MARKERS = {"WXGBackdrop.m": ["WXGModelScanTree", "[source.layer renderInContext:ctx]", "holdFreshAnimation",
                              "WXGModelTransform", "sample.modelTree=modelPathUsed", "WXGUseModelMapping"],
           "WXGHost.m": ["1999500", "layoutIfNeeded]", "beforeCoreAnimationCommit"],
           "WXGGlassView.m": ["presentsWithTransaction", "waitUntilScheduled", "WXGPresentBatching"],
           "WXGConfig.m": ["samplerSource", "syncPresent"]}
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
