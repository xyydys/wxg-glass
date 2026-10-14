#!/usr/bin/env python3
"""FIX58: every setting of the FIX57 settings pages is still in the new pages.

usage: python3 tools/check_settings_coverage.py <FIX57 dir> [<FIX58 dir>] [--json out.json]

Reads the FIX57 table pages (Sources/WXGSettings.m, Sources/WXGOpticalSettings.m)
and the FIX58 module specs (Sources/WXGOpticalSettings.m, home cards in
Sources/WXGSettings.m) and checks:
  * each FIX57 switch / slider / colour / action exists in FIX58 (a shared glass
    setting that FIX58 splits keeps its key in the 其余玻璃 range and gets a
    dock* key in the 底栏 range);
  * slider ranges are the FIX57 ranges (dock* keys: those of their shared key);
  * every WXGConfig key the new pages write is a declared property and is in
    WXGConfig's saved key list, with a clamp in normalize for the dock* keys;
  * WXGPreferences keys (pref.*) and settings-page keys (ui.*) are properties;
  * every home card opens a module that has a spec, every module has a card.
Exit status 1 on any problem.
"""
import json, re, sys
from pathlib import Path

def read(p):
    return Path(p).read_text(encoding='utf-8')

def objc_str(s):
    return s  # titles are plain literals here

def parse_old(root):
    root = Path(root)
    optical = read(root / 'Sources/WXGOpticalSettings.m')
    settings = read(root / 'Sources/WXGSettings.m')
    items = []
    for m in re.finditer(r'WXGToggle\(@"([^"]*)",@"([^"]+)"\)', optical):
        items.append({'kind': 'switch', 'title': m.group(1), 'key': m.group(2), 'target': 'config'})
    for m in re.finditer(r'WXGSlider\(@"([^"]*)",@"([^"]+)",([-\d.]+),([-\d.]+)\)', optical):
        items.append({'kind': 'slider', 'title': m.group(1), 'key': m.group(2), 'target': 'config',
                      'min': float(m.group(3)), 'max': float(m.group(4))})
    for m in re.finditer(r'@\{@"type":@"color",@"title":@"([^"]*)",@"key":@"([^"]+)"\}', optical):
        items.append({'kind': 'color', 'title': m.group(1), 'key': m.group(2), 'target': 'config'})
    if '恢复 TEST9 材质与本版默认设置' in optical and '[WXGConfig.shared reset]' in optical:
        items.append({'kind': 'action', 'title': '恢复 TEST9 材质与本版默认设置', 'key': 'reset', 'target': 'action'})
    # Preferences page: switches with a key, the size-scale slider, navigation rows.
    for m in re.finditer(r'@\{@"title":@"([^"]*)",@"key":@"([^"]+)"(,@"slider":@YES)?\}', settings):
        if m.group(3):
            lo, hi = re.search(r'slider\.minimumValue=([-\d.]+);slider\.maximumValue=([-\d.]+)', settings).groups()
            items.append({'kind': 'slider', 'title': m.group(1), 'key': m.group(2), 'target': 'pref', 'min': float(lo), 'max': float(hi)})
        else:
            items.append({'kind': 'switch', 'title': m.group(1), 'key': m.group(2), 'target': 'pref'})
    if 'WXGDiagnosticController new' in settings:
        items.append({'kind': 'action', 'title': '材质、位置与性能诊断', 'key': 'diagnostics', 'target': 'action'})
    if 'exportDiagnosticsFrom:self' in settings:
        items.append({'kind': 'action', 'title': '导出各页诊断 JSON', 'key': 'export', 'target': 'action'})
    if 'WXGOpticalSettings()' in settings:
        items.append({'kind': 'page', 'title': 'TEST9 玻璃与独立透镜', 'key': 'optical', 'target': 'page'})
    return items

def split_args(s):
    """Top-level comma split of an argument list (no nested parens in our specs)."""
    out, depth, cur, inq = [], 0, '', False
    for ch in s:
        if ch == '"' and not cur.endswith('\\'):
            inq = not inq
        if not inq and ch in '([{':
            depth += 1
        if not inq and ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0 and not inq:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out

def lit(a):
    a = a.strip()
    if a == 'nil':
        return None
    m = re.fullmatch(r'@"(.*)"', a)
    return m.group(1) if m else a

def parse_new(root):
    root = Path(root)
    optical = read(root / 'Sources/WXGOpticalSettings.m')
    home = read(root / 'Sources/WXGSettings.m')
    spec_start = optical.index('static NSDictionary *WXGModuleSpec(')
    spec_end = optical.index('#pragma mark - Values')
    spec = optical[spec_start:spec_end]
    modules = {}
    # Split per module: if([module isEqual:@"x"])return @{@"title":@"...",...
    parts = re.split(r'if\(\[module isEqual:@"([a-z]+)"\]\)return ', spec)
    for i in range(1, len(parts), 2):
        name, body = parts[i], parts[i + 1]
        title = re.match(r'@\{@"title":@"([^"]*)"', body).group(1)
        scoped = '@"scoped":@YES' in body
        rows = []
        # Each group: WXGGroup(@"title",scope,@[rows],footer)
        for g in re.finditer(r'WXGGroup\((@"[^"]*"|nil),(@"[a-z]+"|nil),@\[', body):
            gtitle, gscope = lit(g.group(1)), lit(g.group(2))
            # rows run to the matching ']'
            j, depth = g.end(), 1
            while depth:
                ch = body[j]
                if ch == '[': depth += 1
                elif ch == ']': depth -= 1
                j += 1
            rowtext = body[g.end():j - 1]
            for r in re.finditer(r'(WXGSlider|WXGSwitch|WXGColorRow|WXGAction|WXGWallpaperRow)\(', rowtext):
                k, depth = r.end(), 1
                while depth:
                    ch = rowtext[k]
                    if ch == '(': depth += 1
                    elif ch == ')': depth -= 1
                    k += 1
                args = split_args(rowtext[r.end():k - 1])
                kind = {'WXGSlider': 'slider', 'WXGSwitch': 'switch', 'WXGColorRow': 'color',
                        'WXGAction': 'action', 'WXGWallpaperRow': 'wallpaper'}[r.group(1)]
                row = {'kind': kind, 'title': lit(args[0]), 'group': gtitle, 'scope': gscope, 'module': name}
                if kind == 'slider':
                    row.update(key=lit(args[1]), dock=lit(args[2]), min=float(args[3]), max=float(args[4]))
                elif kind in ('switch', 'color'):
                    row.update(key=lit(args[1]), dock=lit(args[2]))
                elif kind == 'action':
                    row.update(key=lit(args[1]), dock=None)
                else:
                    row.update(key=None, dock=None, dark=args[1] == 'YES')
                rows.append(row)
        modules[name] = {'title': title, 'scoped': scoped, 'rows': rows}
    cards = re.findall(r'@\[@"([a-z]+)",@"([^"]+)",@"([^"]*)",@\[', home[home.index('+ (NSArray<NSDictionary *> *)sections'):])
    header_switch = 'WXGPreferences.shared.enabled=sender.on' in home
    return modules, cards, header_switch

def config_info(root):
    root = Path(root)
    common = read(root / 'Sources/WXGCommon.h')
    config = read(root / 'Sources/WXGConfig.m')
    iface = common[common.index('@interface WXGConfig'):]
    iface = iface[:iface.index('@end')]
    props = {}
    for m in re.finditer(r'@property\(([^)]*)\)\s*([A-Za-z]+)\s*(\*?)\s*([^;]+);', iface):
        typ = m.group(2) + m.group(3)
        for name in m.group(4).split(','):
            props[name.strip().lstrip('*')] = typ
    keys_src = re.search(r'- \(NSArray \*\)keys \{ return @\[(.*?)\]; \}', config, re.S).group(1)
    saved = set(re.findall(r'@"([A-Za-z]+)"', keys_src))
    normalize = config[config.index('- (void)normalize'):config.index('static NSUInteger WXGConfigRevisionCounter')]
    return props, saved, normalize

def pref_props(root):
    text = read(Path(root) / 'Sources/WXGIntegration.h')
    iface = text[text.index('@interface WXGPreferences'):]
    iface = iface[:iface.index('@end')]
    props = {}
    for m in re.finditer(r'@property\(([^)]*)\)\s*([A-Za-z]+)\s*([^;]+);', iface):
        for name in m.group(3).split(','):
            props[name.strip()] = m.group(2)
    return props

def store_props(root):
    text = read(Path(root) / 'Sources/WXGSettingsKit.h')
    iface = text[text.index('@interface WXGSettingsStore'):]
    iface = iface[:iface.index('@end')]
    props = {}
    for m in re.finditer(r'@property\(([^)]*)\)\s*([A-Za-z]+)\s*(\*?)\s*([A-Za-z]+);', iface):
        props[m.group(4)] = m.group(2) + m.group(3)
    return props

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = None
    if '--json' in sys.argv:
        out = sys.argv[sys.argv.index('--json') + 1]
        args = [a for a in args if a != out]
    if not args:
        print(__doc__); return 2
    old_root = args[0]
    new_root = args[1] if len(args) > 1 else str(Path(__file__).resolve().parent.parent)
    old = parse_old(old_root)
    modules, cards, header_switch = parse_new(new_root)
    props, saved, normalize = config_info(new_root)
    prefs = pref_props(new_root)
    store = store_props(new_root)
    problems = []
    new_rows = [r for m in modules.values() for r in m['rows']]

    def find(key, kind):
        hits = []
        for r in new_rows:
            if r['kind'] != kind:
                continue
            if r.get('key') == key or r.get('dock') == key:
                hits.append(r)
        return hits

    report = []
    for item in old:
        entry = {'old': item}
        if item['target'] == 'pref':
            if item['key'] == 'enabled':
                ok = header_switch
                entry['new'] = '设置首页 · 头部卡片右侧开关' if ok else None
            else:
                hits = find('pref.' + item['key'], item['kind'])
                ok = bool(hits)
                entry['new'] = [f"{modules[h['module']]['title']} · {h['group']} · {h['title']}" for h in hits]
                for h in hits:
                    if item['kind'] == 'slider' and (abs(h['min'] - item['min']) > 1e-9 or abs(h['max'] - item['max']) > 1e-9):
                        problems.append(f"range of pref.{item['key']}: FIX57 {item['min']}..{item['max']}, FIX58 {h['min']}..{h['max']}")
        elif item['target'] == 'action':
            hits = [r for r in new_rows if r['kind'] == 'action' and r['key'] == item['key']]
            ok = bool(hits)
            entry['new'] = [f"{modules[h['module']]['title']} · {h['group']} · {h['title']}" for h in hits]
        elif item['target'] == 'page':
            ok = {'refraction', 'blur', 'material', 'border', 'dock'} <= {c[0] for c in cards}
            entry['new'] = '设置首页的玻璃模块卡片' if ok else None
        else:
            hits = find(item['key'], item['kind'])
            ok = bool(hits)
            entry['new'] = []
            for h in hits:
                where = f"{modules[h['module']]['title']} · {h['group']} · {h['title']}"
                if modules[h['module']]['scoped'] and h.get('dock') and h['key'] == item['key']:
                    where += '（其余玻璃）'
                if modules[h['module']]['scoped'] and h.get('dock') == item['key']:
                    where += '（底栏）'
                entry['new'].append(where)
                if item['kind'] == 'slider' and (abs(h['min'] - item['min']) > 1e-9 or abs(h['max'] - item['max']) > 1e-9):
                    problems.append(f"range of {item['key']}: FIX57 {item['min']}..{item['max']}, FIX58 {h['min']}..{h['max']}")
        entry['covered'] = ok
        if not ok:
            problems.append(f"FIX57 {item['kind']} '{item['title']}' ({item['key']}) is missing in FIX58")
        report.append(entry)

    # Keys written by the new pages.
    split = []
    for r in new_rows:
        for field in ('key', 'dock'):
            key = r.get(field)
            if not key or r['kind'] in ('action', 'wallpaper'):
                continue
            if key.startswith('pref.'):
                name = key[5:]
                want = 'BOOL' if r['kind'] == 'switch' else 'CGFloat'
                if prefs.get(name) != want:
                    problems.append(f"{key}: WXGPreferences has no {want} property '{name}'")
                continue
            if key.startswith('ui.'):
                name = key[3:]
                want = {'slider': 'CGFloat', 'color': 'NSString*'}.get(r['kind'])
                if store.get(name) != want:
                    problems.append(f"{key}: WXGSettingsStore has no {want} property '{name}'")
                continue
            want = {'slider': 'CGFloat', 'switch': 'BOOL', 'color': 'NSString*'}[r['kind']]
            if props.get(key) != want:
                problems.append(f"{key}: WXGConfig property type {props.get(key)}, expected {want}")
            if key not in saved:
                problems.append(f"{key}: not in WXGConfig keys (would not be saved)")
        if r.get('dock') and r['dock'] != r['key']:
            split.append({'module': modules[r['module']]['title'], 'title': r['title'], 'other': r['key'], 'dock': r['dock']})
        # A dock-only group's keys are dock settings already (lens etc.).
    # FIX58 dock* keys must be clamped in normalize like their shared keys.
    fix58_dock = ['dockRefraction', 'dockDispersion', 'dockEdgeWidth', 'dockBlur', 'dockBlurCoverage', 'dockRimHex', 'dockDarkRimHex',
                  'dockRimOpacity', 'dockDarkRimOpacity', 'dockBorderWidth', 'dockDarkBorderWidth', 'dockRimBrightness',
                  'dockDarkRimBrightness', 'dockRimFade', 'dockDarkRimFade']
    for key in fix58_dock:
        if key not in saved:
            problems.append(f"{key}: not saved")
        if '_' + key not in normalize:
            problems.append(f"{key}: not clamped in normalize")
        if not any(r.get('dock') == key or r.get('key') == key for r in new_rows):
            problems.append(f"{key}: no control in the new pages")
    # Home cards and module specs.
    card_ids = [c[0] for c in cards]
    for c in card_ids:
        if c not in modules:
            problems.append(f"home card '{c}' has no module spec")
    for m in modules:
        if m not in card_ids:
            problems.append(f"module '{m}' has no home card")
    scoped = sorted(modules[m]['title'] for m in modules if modules[m]['scoped'])

    print(f"FIX57 settings: {len(old)}; covered: {sum(e['covered'] for e in report)}")
    for e in report:
        o = e['old']
        new = e['new'] if isinstance(e['new'], str) else '；'.join(e['new'] or ['—'])
        print(f"  {'ok ' if e['covered'] else 'MISSING'} {o['kind']:7s} {o['key']:28s} → {new}")
    print(f"FIX58 controls: {len(new_rows)} rows in {len(modules)} modules; home cards: {', '.join(c[1] for c in cards)}")
    print(f"two ranges (底栏 / 其余玻璃): {', '.join(scoped)}; split rows: {len(split)}")
    print(f"problems: {len(problems)}")
    for p in problems:
        print('  ' + p)
    if out:
        Path(out).write_text(json.dumps({'fix57': report, 'fix58_modules': modules, 'home_cards': cards,
                                         'split_rows': split, 'problems': problems}, ensure_ascii=False, indent=1), encoding='utf-8')
    return 1 if problems else 0

if __name__ == '__main__':
    sys.exit(main())
