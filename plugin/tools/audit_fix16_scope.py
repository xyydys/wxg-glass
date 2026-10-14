#!/usr/bin/env python3
"""FIX16 scope audit: compare this tree with an unpacked FIX15 tree.

Usage: python3 tools/audit_fix16_scope.py --baseline <FIX15 dir> [--json out.json]
Checks that optics, shader, motion, geometry and layout sources are byte-identical,
lists every changed source, and verifies the FIX16 markers exist.
"""
import argparse, hashlib, json, os, sys

FROZEN = [
    "Sources/WXGGlass.metal", "Sources/WXGShaderSource.h", "Sources/WXGOptics.h", "Sources/WXGLensOptics.h",
    "Sources/WXGMotion.h", "Sources/WXGElasticMotion.h", "Sources/WXGDistanceField.h", "Sources/WXGBackdropCopy.h",
    "Sources/WXGBackdropROI.h", "Sources/WXGBackdropTraversal.h", "Sources/WXGSourceMapping.h", "Sources/WXGGeometry.h",
    "Sources/WXGSurface.m", "Sources/WXGDemoBar.m", "Sources/WXGInput.m", "Sources/WXGNativeInput.m",
    "Sources/WXGNative.m", "Sources/WXGDecorations.m", "Sources/WXGDockInteraction.m", "Sources/WXGNativeIcons.m",
]
ALLOWED = {
    "Sources/WXGBackdrop.m", "Sources/WXGGlassView.m", "Sources/WXGHost.m", "Sources/WXGRenderPolicy.h",
    "Sources/WXGConfig.m", "Sources/WXGCommon.h", "Sources/WXGIntegration.h", "Sources/WXGOpticalSettings.m",
    "Sources/WXGSettings.m",
}
MARKERS = {
    "Sources/WXGHost.m": ["CFRunLoopObserverCreateWithHandler", "2001500", "flushPendingFrame:YES", "WXGBeginDeferredGlassTicks"],
    "Sources/WXGGlassView.m": ["WXGGlassDeferDepth", "- (void)runTick:", "WXGFlushDeferredGlassTicks"],
    "Sources/WXGBackdrop.m": ["WXGBackdropDueWithBudget", "CABackingStore", "animatingSublayer", "WXGSpecialLayerClass"],
    "Sources/WXGRenderPolicy.h": ["WXGBackdropDueWithBudget", "WXGBackdropCostAverage"],
    "Sources/WXGConfig.m": ["captureBudget"],
}

def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--json")
    a = ap.parse_args()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems, changed, added = [], [], []
    for name in sorted(os.listdir(os.path.join(here, "Sources"))):
        rel = "Sources/" + name
        old = os.path.join(a.baseline, rel)
        if not os.path.exists(old):
            added.append(rel); continue
        if digest(os.path.join(here, rel)) != digest(old):
            changed.append(rel)
    for rel in FROZEN:
        if rel in changed: problems.append("frozen source changed: " + rel)
    for rel in changed + added:
        if rel not in ALLOWED: problems.append("unexpected source change: " + rel)
    for rel, needles in MARKERS.items():
        text = open(os.path.join(here, rel), encoding="utf-8").read()
        for n in needles:
            if n not in text: problems.append(f"missing marker {n!r} in {rel}")
    report = {"baseline": os.path.abspath(a.baseline), "changedSources": changed, "addedSources": added,
              "frozenIdentical": [r for r in FROZEN if r not in changed], "problems": problems}
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f: json.dump(report, f, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))
    return 1 if problems else 0

if __name__ == "__main__":
    sys.exit(main())
