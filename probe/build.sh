#!/bin/sh
# Builds GlassProbe.dylib (arm64, ad-hoc signed) on Linux: clang 18 + ld64.lld
# against theos/sdks iPhoneOS16.5.sdk, as the plugin is built. No hooking
# library: plain Objective-C, system frameworks only.
# Usage: probe/build.sh <output dir>     (env: SDK, LDID)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); OUT=${1:-$HERE/dist}
SDK=${SDK:?set SDK to iPhoneOS16.5.sdk}; LDID=${LDID:-}
export PATH=${CC_DIR:-/usr/lib/llvm-18/bin}:$PATH
mkdir -p "$OUT"
COMMON="-target arm64-apple-ios15.0 -isysroot $SDK"
clang $COMMON -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -Werror -c "$HERE/GlassProbe.m" -o "$OUT/GlassProbe.o"
clang $COMMON -fuse-ld=lld -mlinker-version=711 -dynamiclib -install_name "@rpath/GlassProbe.dylib" -Wl,-dead_strip \
    -lobjc -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation "$OUT/GlassProbe.o" -o "$OUT/GlassProbe.dylib"
rm -f "$OUT/GlassProbe.o"
if [ -n "$LDID" ]; then "$LDID" -S "$OUT/GlassProbe.dylib"; else echo "note: not signed (no LDID); the injecting tool signs it anyway"; fi
ls -l "$OUT/GlassProbe.dylib"
