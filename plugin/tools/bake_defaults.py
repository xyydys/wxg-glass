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
parameters. The main switches, the account, the frame-rate log switches, wallpapers and
the avatar are never part of it.

FIX114 G: the defaults being replaced are kept as
WXG_PREVIOUS_DEFAULT_OPTICS_JSON. On the first launch of the new build a
phone's setting still equal to that previous default (never changed) moves to
the new default; a setting the person changed stays (WXGConfig,
WXGPreferences, WXGSettingsStore: adoptBuildDefaults). The previous set is
the one committed (git HEAD): baking again before committing (the same file
or another) keeps it, so it stays the set phones actually have. With
--keep-previous the previous set is never changed; without git, the set
being replaced becomes the previous one."""
import json, math, pathlib, re, subprocess, sys

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
    pattern = r'#define WXG_DEFAULT_OPTICS_JSON(?:[^\n]*\\\n)*[^\n]*'
    current = re.findall(pattern, s)
    if len(current) != 1:
        sys.exit("WXG_DEFAULT_OPTICS_JSON not found exactly once in WXGBuildProfile.h")
    previous_pattern = r'#define WXG_PREVIOUS_DEFAULT_OPTICS_JSON(?:[^\n]*\\\n)*[^\n]*'
    committed = None
    try:
        prefix = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--show-prefix"], capture_output=True, text=True, check=True).stdout.strip()
        head = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:{prefix}Sources/WXGBuildProfile.h"], capture_output=True, text=True, check=True).stdout
        committed = re.findall(pattern, head)
        committed = committed[0] if len(committed) == 1 else None
    except (OSError, subprocess.CalledProcessError):
        committed = None
    # Rotate only from the committed set (a second bake before committing
    # would otherwise make "previous" a set no phone ever had).
    rotate = current[0] != define and "--keep-previous" not in sys.argv and (committed is None or committed == current[0])
    if current[0] != define and not rotate:
        print("previous defaults kept as they are (the set being replaced was never committed, or --keep-previous)")
    if rotate:
        # FIX114 G: the defaults being replaced, for adopting the new ones
        # where a phone still has the old (see the docstring).
        previous = current[0].replace("#define WXG_DEFAULT_OPTICS_JSON", "#define WXG_PREVIOUS_DEFAULT_OPTICS_JSON", 1)
        if re.search(previous_pattern, s):
            s = re.sub(previous_pattern, lambda m: previous, s, count=1)
        else:
            s = s.replace(current[0], current[0] + "\n// FIX114 G: the defaults before this set (tools/bake_defaults.py keeps them):\n"
                          "// a phone's setting still at one of these moves to the new default once.\n" + previous, 1)
        print("previous defaults kept as WXG_PREVIOUS_DEFAULT_OPTICS_JSON")
    new = s.replace(current[0], define, 1)
    profile.write_text(new, encoding="utf-8")
    print(f"written: {profile.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
