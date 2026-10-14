#!/usr/bin/env python3
"""FIX18 scope audit against an unpacked FIX17 tree.

Usage: python3 tools/audit_fix18_scope.py --baseline <FIX17 dir> [--json out.json]
1. Optics/geometry/motion/layout sources are byte-identical to FIX17.
2. Removing the FIX18 sync additions from WXGGlass.metal reproduces the FIX17
   shader exactly, so readback mode (renderMode 0) runs the same optics.
3. Only expected sources changed; FIX18 markers exist.
"""
import argparse, hashlib, json, os, sys

FROZEN = ["WXGOptics.h", "WXGLensOptics.h", "WXGMotion.h", "WXGElasticMotion.h", "WXGDistanceField.h",
          "WXGBackdropCopy.h", "WXGBackdropROI.h", "WXGBackdropTraversal.h", "WXGSourceMapping.h", "WXGGeometry.h",
          "WXGRenderPolicy.h", "WXGSurface.m", "WXGDemoBar.m", "WXGInput.m", "WXGNativeInput.m", "WXGNative.m",
          "WXGDecorations.m", "WXGDockInteraction.m", "WXGNativeIcons.m"]
ALLOWED = {"WXGGlass.metal", "WXGShaderSource.h", "WXGGlassView.m", "WXGBackdrop.m", "WXGMotionPrediction.h",
           "WXGConfig.m", "WXGCommon.h", "WXGIntegration.h", "WXGOpticalSettings.m", "WXGSettings.m", "WXGHost.m"}
MARKERS = {"WXGGlassView.m": ["CABackdropLayer", "WXGSyncBackdropView", "groupName", "u.sync=", "==208"],
           "WXGGlass.metal": ["float4 sync;", "wxgSyncBase", "wxgIconsOver", "u.sync.x>1.5"],
           "WXGBackdrop.m": ["renderServerOnly", "WXGMotionPredict2"],
           "WXGMotionPrediction.h": ["WXGMotionDisplacement", "WXGMotionOlder"],
           "WXGOpticalSettings.m": ["WXGSegment(", "segment:"]}

def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()

def strip_block(src, head):
    """Remove `head {...}` (brace-matched) including the trailing newline."""
    i = src.index(head); j = src.index("{", i); depth = 0
    for k in range(j, len(src)):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                end = k + 1
                if src[end:end+1] == "\n": end += 1
                line_start = src.rfind("\n", 0, i) + 1
                return src[:line_start] + src[end:]
    raise ValueError(head)

def readback_shader(src):
    src = src.replace("    float4 sync;       // FIX18 x: 0 readback optics, 1 hybrid edge band, 2 render-server body\n", "")
    a = src.index("// FIX18 render-server modes."); b = src.index("fragment float4 wxgFragment(")
    src = src[:a] + src[b:]
    src = strip_block(src, "if(u.sync.x>.5)")
    src = strip_block(src, "if(u.sync.x>1.5)")
    return src

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
    shader_ok = readback_shader(open(S(here, "WXGGlass.metal")).read()) == open(S(a.baseline, "WXGGlass.metal")).read()
    if not shader_ok: problems.append("readback shader path differs from FIX17")
    report = {"baseline": os.path.abspath(a.baseline), "changedSources": changed, "addedSources": added,
              "frozenIdentical": [n for n in FROZEN if n not in changed], "readbackShaderIdenticalToFIX17": shader_ok,
              "problems": problems}
    if a.json: json.dump(report, open(a.json, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))
    return 1 if problems else 0

if __name__ == "__main__": sys.exit(main())
