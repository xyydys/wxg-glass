#!/usr/bin/env python3
"""FIX84: make a set of settings this build's defaults.

usage: python3 tools/bake_defaults.py <settings.json | diagnostics.json> [--dry-run]

Reads a settings export (插件设置 → 帧率与参数 → 导出参数文件 / 复制当前参数) or a
diagnostics export (its settingsShare block; from builds before FIX84 only
materialParameters, the glass parameters), keeps the known, well-typed keys
(WXGConfig keys from Sources/WXGConfig.m, switches from Sources/WXGNative.m),
and writes them as WXG_DEFAULT_OPTICS_JSON into Sources/WXGBuildProfile.h:

    {"config":{...},"integration":{...},"ui":{...}}

A fresh install then starts from these values (glass parameters, switches,
settings-page look), and 恢复本版默认参数 / 恢复本页默认 return to the glass
parameters. Settings people already have on their phones are not touched.
The main switches, the account, the frame-rate log switches, wallpapers and
the avatar are never part of it."""
import json, math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SKIP_CONFIG = {"enabled"}
SKIP_INTEGRATION = {"enabled", "homeSearch", "perfMonitor", "perfHUD"}


def objc_keys(path, pattern):
    text = (ROOT / path).read_text(encoding="utf-8")
    m = re.search(pattern, text, re.S)
    if not m:
        sys.exit(f"cannot find the key list in {path}")
    return re.findall(r'@"([A-Za-z0-9_]+)"', m.group(1))


def find(obj, key, depth=0):
    if depth > 6:
        return None
    if isinstance(obj, dict):
        if isinstance(obj.get(key), dict):
            return obj[key]
        for v in obj.values():
            r = find(v, key, depth + 1)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find(v, key, depth + 1)
            if r is not None:
                return r
    return None


HEX = re.compile(r"^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")


def normalize_hex(v):
    if not isinstance(v, str):
        return None
    s = v.strip()
    if not HEX.match(s):
        return None
    s = s.lstrip("#").upper()
    return "#" + (s + "FF" if len(s) == 6 else s)


def number(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)) and math.isfinite(v):
        return round(v, 6) if isinstance(v, float) else v
    return None


def filtered(source, keys, skip):
    out = {}
    if not isinstance(source, dict):
        return out
    for k in keys:
        if k in skip or k not in source:
            continue
        v = normalize_hex(source[k]) if k.endswith("Hex") else number(source[k])
        if v is not None:
            out[k] = v
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    root = json.loads(pathlib.Path(args[0]).read_text(encoding="utf-8"))
    config_keys = objc_keys("Sources/WXGConfig.m", r"- \(NSArray \*\)baseKeys \{ return @\[(.*?)\]; \}")
    # FIX85: the keys kept in WXGConfig.m's table (WXGExtraSpecs).
    table = (ROOT / "Sources/WXGConfig.m").read_text(encoding="utf-8")
    config_keys += re.findall(r'^\s*\{"([A-Za-z0-9_]+)",\'[nbh]\'', table, re.M)
    pref_keys = objc_keys("Sources/WXGNative.m", r"@implementation WXGPreferences.*?- \(NSArray \*\)keys \{return @\[(.*?)\];\}")
    share = root if isinstance(root.get("config"), dict) else find(root, "settingsShare")
    if share:
        config, integration, ui = share.get("config"), share.get("integration"), share.get("ui")
        source = f"settings {share.get('version', '?')} {share.get('exportedAt', '?')}"
    else:
        scene = root.get("currentOrLastScene")
        config = find(scene, "materialParameters") or find(root, "materialParameters") or root
        integration, ui, source = None, None, "materialParameters only"
    payload = {"config": filtered(config, config_keys, SKIP_CONFIG),
               "integration": filtered(integration, pref_keys, SKIP_INTEGRATION),
               "ui": {}}
    if isinstance(ui, dict):
        if number(ui.get("cardRadius")) is not None:
            payload["ui"]["cardRadius"] = number(ui["cardRadius"])
        if normalize_hex(ui.get("accentHex")):
            payload["ui"]["accentHex"] = normalize_hex(ui["accentHex"])
    if len(payload["config"]) < 8:
        sys.exit("no glass parameters found")
    missing = [k for k in config_keys if k not in payload["config"] and k not in SKIP_CONFIG]
    text = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    chunks = [text[i:i + 96] for i in range(0, len(text), 96)]
    literal = " \\\n    ".join('"' + c.replace("\\", "\\\\").replace('"', '\\"') + '"' for c in chunks)
    define = "#define WXG_DEFAULT_OPTICS_JSON \\\n    " + literal
    print(f"source: {source}")
    print(f"config {len(payload['config'])}/{len(config_keys) - len(SKIP_CONFIG)} keys, "
          f"integration {len(payload['integration'])}, ui {len(payload['ui'])}")
    if missing:
        print("not in the file (built-in defaults stay): " + ", ".join(missing))
    if "--dry-run" in sys.argv:
        print(define)
        return
    profile = ROOT / "Sources/WXGBuildProfile.h"
    s = profile.read_text(encoding="utf-8")
    new, n = re.subn(r'#define WXG_DEFAULT_OPTICS_JSON(?:[^\n]*\\\n)*[^\n]*', lambda m: define, s)
    if n != 1:
        sys.exit("WXG_DEFAULT_OPTICS_JSON not found exactly once in WXGBuildProfile.h")
    profile.write_text(new, encoding="utf-8")
    print(f"written: {profile.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
