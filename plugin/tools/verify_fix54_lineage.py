#!/usr/bin/env python3
"""FIX54 lineage check: every source equals its origin, version strings aside.
FIX54 = FIX46 without its avatar / pinned-row changes, plus the wallet fix:
  WXGGlass.metal, WXGShaderSource.h          <- FIX46 (lens: inset kept, smooth edges, no bar colour split)
  WXGHost.m, WXGNative.m, WXGIntegration.h   <- FIX50 (= FIX44 + wallet top fix)
  everything else                            <- FIX44 (= FIX46 without avatar / pinned row)
Usage: verify_fix54_lineage.py <FIX44 dir> <FIX46 dir> <FIX50 dir> [--json out]"""
import json, os, re, sys
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fix44, fix46, fix50 = sys.argv[1:4]
VERSION = [r"0\.4\.\d+", r"test4fix\d+", r"TEST4 FIX\d+", r"TEST4_FIX\d+", r"contour_zipper_FIX\d+", r'"revision":@"FIX\d+"']
def norm(path):
    text = open(path, encoding="utf-8").read()
    for pattern in VERSION: text = re.sub(pattern, "<v>", text)
    return text
origin = {"WXGGlass.metal": fix46, "WXGShaderSource.h": fix46,
          "WXGHost.m": fix50, "WXGNative.m": fix50, "WXGIntegration.h": fix50}
problems, report = [], {}
for name in sorted(os.listdir(os.path.join(here, "Sources"))):
    base = origin.get(name, fix44)
    same = os.path.exists(os.path.join(base, "Sources", name)) and norm(os.path.join(here, "Sources", name)) == norm(os.path.join(base, "Sources", name))
    report[name] = ("FIX46" if base == fix46 else "FIX50" if base == fix50 else "FIX44") + (" (identical)" if same else " (DIFFERS)")
    if not same: problems.append(name)
forbidden = ["avatarSize", "avatarBare", "avatarGlass", "avatarRim", "WXGHookPinnedFrame", "applyPinnedShift", "chatAvatarImageForTitle", "layoutAvatarStroke"]
leftovers = [f"{n}: {w}" for n in os.listdir(os.path.join(here, "Sources")) for w in forbidden
             if w in open(os.path.join(here, "Sources", n), encoding="utf-8", errors="ignore").read()]
problems += leftovers
wallet = ["static BOOL WXGColorsDiffer", "FIX50: WeChat Pay's Kinda pages", "[_navStates paint:v color:content]"]
problems += [f"wallet marker missing: {m}" for m in wallet if m not in open(os.path.join(here, "Sources", "WXGHost.m"), encoding="utf-8").read()]
result = {"origins": report, "avatarPinnedLeftovers": leftovers, "problems": problems}
if len(sys.argv) > 5 and sys.argv[4] == "--json": json.dump(result, open(sys.argv[5], "w"), ensure_ascii=False, indent=1)
print(json.dumps(result, ensure_ascii=False, indent=1))
sys.exit(1 if problems else 0)
