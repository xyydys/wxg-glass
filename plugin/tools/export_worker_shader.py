#!/usr/bin/env python3
"""FIX103: put the glass shader into the unlock server.
The plugin no longer carries Sources/WXGGlass.metal; the Worker serves it.
After changing the shader: python3 tools/embed_shader.py (for check_msl and the
simulator), then
    python3 tools/export_worker_shader.py <path to wxg-glass/worker.js>
rewrites the SHADER block of worker.js with exactly the text the plugin used to
embed (WXGMetalSource) and prints its sha256; commit and push wxg-glass.
If the uniforms changed (WXGGlassView.m, WXGUniforms), the plugins already out
cannot use the new shader: bump VER in worker.js and WXG_SHADER_VERSION in
Sources/WXGUnlock.m together (older plugins then say they need an update)."""
import hashlib, json, os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
if len(sys.argv) != 2:
    print(__doc__); sys.exit(2)
header = open(os.path.join(root, 'Sources/WXGShaderSource.h'), encoding='utf-8').read()
body = header[header.index('WXGMetalSource[] =') + len('WXGMetalSource[] ='):header.rindex(';')]
source = ''.join(json.loads(line) for line in body.strip().splitlines())
assert source.endswith('\n')
lines = source[:-1].split('\n') + ['']          # worker.js joins with "\n"
block = 'const SHADER = [\n' + ''.join('  ' + json.dumps(l, ensure_ascii=False) + ',\n' for l in lines) + '].join("\\n");'
digest = hashlib.sha256(source.encode('utf-8')).hexdigest()
path = sys.argv[1]
js = open(path, encoding='utf-8').read()
js, n = re.subn(r'const SHADER = \[\n.*?\]\.join\("\\n"\);', lambda m: block, js, count=1, flags=re.S)
if n != 1:
    sys.exit('SHADER block not found in ' + path)
js = re.sub(r'// sha256 = [0-9a-f]{64}', '// sha256 = ' + digest, js, count=1)
open(path, 'w', encoding='utf-8').write(js)
print(f'{path}: shader {len(source.encode())} bytes, sha256 {digest}')
