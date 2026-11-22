#!/usr/bin/env python3
"""FIX55: syntax / type check of the EMBEDDED Metal source without a Metal
compiler. The source (WXGShaderSource.h + WXGBackdropCopy.h, exactly what the
device compiles at run time) is compiled as C++14 against tools/msl_stub/
metal_stdlib, a small stand-in for Metal's vector types and functions.
Catches misspelt names, wrong argument counts and float/vector mismatches; it
cannot catch Metal-only restrictions. Usage: python3 tools/check_msl.py"""
import json, os, re, subprocess, sys, tempfile
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def literal(path, name):
    text = open(path, encoding='utf-8').read()
    start = text.index(name)
    body = text[text.index('=', start) + 1: text.index(';\n', start)]
    return ''.join(json.loads(p) for p in re.findall(r'"(?:[^"\\]|\\.)*"', body))
fallback = '--original' in sys.argv
src = literal(os.path.join(root, 'Sources/WXGOriginalShaderSource.h' if fallback else 'Sources/WXGShaderSource.h'), 'WXGOriginalMetalSource' if fallback else 'WXGMetalSource') + \
      literal(os.path.join(root, 'Sources/WXGBackdropCopy.h'), 'WXGBackdropCopySource')
src = re.sub(r'\b(float[234])\(', r'mk_\1(', src)   # Metal constructors -> stub overloads
# Metal 2.1 <metal_stdlib> does not define C's NULL macro; fail fast if it leaks into MSL.
src = src.replace('#include <metal_stdlib>\n', '#include <metal_stdlib>\n#undef NULL\n', 1)
with tempfile.NamedTemporaryFile('w', suffix='.cpp', delete=False) as f:
    f.write(src); name = f.name
cmd = [os.environ.get('CXX', 'clang++'), '-std=c++14', '-fsyntax-only', '-I', os.path.join(root, 'tools', 'msl_stub'),
       '-Wall', '-Wextra', '-Werror', '-Wno-unknown-attributes', '-Wno-unused-parameter', '-Wno-unused-function',
       '-Wno-unused-const-variable', name]
r = subprocess.run(cmd, capture_output=True, text=True)
print(r.stdout + r.stderr if r.returncode else 'MSL stand-in check: OK (%d lines)' % src.count('\n'))
os.unlink(name); sys.exit(r.returncode)
