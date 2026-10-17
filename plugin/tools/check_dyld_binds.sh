#!/bin/sh
# FIX106: refuse a dylib whose binds carry addends dyld cannot store in a
# launch closure.
#
# Why: injected into an IPA (LC_LOAD_DYLIB: sideloading, TrollFools …) the
# dylib is part of the app's launch, and dyld4 (iOS 16+) serialises every
# bind target into its prebuilt launch closure; the target's offset
# (symbol + addend) must fit 8 high bits + a signed 39-bit field. Arkari's
# -irobf-icall (and -irobf-indgv) store each imported function as
# "symbol + random 64-bit key": the obfuscated FIX106 J build had 331 such
# binds (CGContextRelease + 0xd559b8e69681b44d …), and WeChat aborted on
# launch on an iPhone 15 Pro / iOS 17.0 ("Assertion failed: ... large offset
# not support, function BindTargetRef, PrebuiltLoader.cpp"). Jailbreak tweak
# loaders and LiveContainer dlopen the dylib later (no launch closure), so
# the same build ran fine there.
#
# Usage: tools/check_dyld_binds.sh <dylib>
#   exit 0  no bind addend beyond ±2^32 (a plain build has none at all)
#   exit 1  such binds found (listed)
#   exit 2  no llvm-objdump, or no bind table could be read
# OBJDUMP=/path/to/llvm-objdump overrides the lookup.
set -eu
D=${1:?usage: check_dyld_binds.sh <dylib>}
OBJ=${OBJDUMP:-}
if [ -z "$OBJ" ]; then
    for c in llvm-objdump /opt/arkari/bin/llvm-objdump /usr/lib/llvm-18/bin/llvm-objdump \
             $(ls -d /usr/lib/llvm-*/bin/llvm-objdump 2>/dev/null) \
             $(ls /usr/bin/llvm-objdump-* 2>/dev/null); do
        if command -v "$c" >/dev/null 2>&1; then OBJ=$c; break; fi
    done
fi
if [ -z "$OBJ" ] || ! command -v "$OBJ" >/dev/null 2>&1; then echo "check_dyld_binds: 没有 llvm-objdump，无法检查" >&2; exit 2; fi
[ -f "$D" ] || { echo "check_dyld_binds: 找不到 $D" >&2; exit 2; }

# Bind tables (non-lazy, weak, lazy): columns segment section address type
# addend dylib symbol (weak: no dylib column, the symbol is last either way).
# An addend is fine when it is 0, a positive value below 2^32, or a negative
# one above -2^32 (sign-extended hex ffffffff…).
for kind in --bind --weak-bind --lazy-bind; do
    "$OBJ" --macho $kind "$D" 2>/dev/null || true
done | awk '
    $3 ~ /^0x[0-9A-Fa-f]+$/ && NF>=6 {
        a=tolower($5); ok=1
        if (a!="0") {
            if (a ~ /^0x/) {
                h=substr(a,3); sub(/^0+/,"",h)
                if (length(h)>8 && !(length(h)==16 && substr(h,1,8)=="ffffffff")) ok=0
            } else {
                d=a; neg=sub(/^-/,"",d)
                if (length(d)>9) ok=0
            }
        }
        if (!ok) { n++; if (n<=8) printf "  %s %s %s + %s\n", $2, $3, $NF, $5 }
        total++
    }
    END {
        if (total==0) { print "check_dyld_binds: 读不到绑定表（不是 Mach-O dylib？）"; exit 2 }
        if (n>0) {
            printf "check_dyld_binds: %d / %d 个绑定带超大附加偏移（多半是 -irobf-icall / -irobf-indgv）。\n", n, total
            print  "打进 IPA 后 iOS 16+ 的 dyld 生成启动缓存时会断言退出（large offset not support），微信一启动就闪退。"
            exit 1
        }
        printf "check_dyld_binds: %d 个绑定，附加偏移都在 dyld 启动缓存能存的范围内\n", total
    }'
