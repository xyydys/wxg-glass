#!/usr/bin/env python3
"""Embed the standalone Metal source so the dylib requires no resource bundle."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
src=(root/'Sources/WXGGlass.metal').read_text()
src=src.replace('#include \"WXGLensOptics.h\"',(root/'Sources/WXGLensOptics.h').read_text())
src=src.replace('#include \"WXGOptics.h\"',(root/'Sources/WXGOptics.h').read_text())
(root/'Sources/WXGShaderSource.h').write_text(
    '// Generated from WXGGlass.metal; rebuild with tools/embed_shader.py.\n'
    'static const char WXGMetalSource[] =\n'+
    '\n'.join(json.dumps(line+'\n') for line in src.splitlines())+';\n')
