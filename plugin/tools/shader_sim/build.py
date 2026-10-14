#!/usr/bin/env python3
"""FIX95: build the CPU shader simulator (sim.cpp) from the EMBEDDED shader
(Sources/WXGShaderSource.h, what the device compiles), and optionally render.
Usage: python3 tools/shader_sim/build.py [out_dir] [params.txt ...]
Each params file renders to <out_dir>/<name>.png (needs Pillow)."""
import json, os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
def literal(path, name):
    text = open(path, encoding='utf-8').read()
    start = text.index(name)
    body = text[text.index('=', start) + 1: text.index(';\n', start)]
    return ''.join(json.loads(p) for p in re.findall(r'"(?:[^"\\]|\\.)*"', body))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'out')
os.makedirs(out, exist_ok=True)
src = literal(os.path.join(root, 'Sources/WXGShaderSource.h'), 'WXGMetalSource')
src = re.sub(r'\b(float[234])\(', r'mk_\1(', src)
src = src.replace('#include <metal_stdlib>', '').replace('using namespace metal;', '')
open(os.path.join(out, 'shader.inc'), 'w').write(src)
exe = os.path.join(out, 'sim')
cmd = [os.environ.get('CXX', 'clang++'), '-std=c++14', '-O2', '-I', os.path.join(here, 'stub'), '-I', out,
       '-Wno-unknown-attributes', '-w', os.path.join(here, 'sim.cpp'), '-o', exe]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode:
    print(r.stdout + r.stderr); sys.exit(1)
for params in sys.argv[2:]:
    name = os.path.splitext(os.path.basename(params))[0]
    ppm = os.path.join(out, name + '.ppm')
    r = subprocess.run([exe, params, ppm], capture_output=True, text=True)
    print(name, r.stdout.strip(), r.stderr.strip())
    try:
        from PIL import Image
        Image.open(ppm).save(os.path.join(out, name + '.png')); os.unlink(ppm)
    except ImportError:
        pass
