#!/usr/bin/env python3
"""The licence code of a WeChat account: SHA-256("WXGLiquidGlass.license.v1:" + wxid).
FIX103: the list lives on the unlock server (wxg-glass worker.js, ALLOWLIST);
this prints the line to add there. An unlisted account also sees its code in
the plugin's settings ("复制账号" copies it).
usage: python3 tools/license_hash.py <wxid> [<wxid> ...]"""
import hashlib, sys
if len(sys.argv) < 2:
    print(__doc__); sys.exit(2)
for wxid in sys.argv[1:]:
    digest = hashlib.sha256(("WXGLiquidGlass.license.v1:" + wxid.strip()).encode("utf-8")).hexdigest()
    print(f'  "{digest}",  // {wxid.strip()[:6]}…')
