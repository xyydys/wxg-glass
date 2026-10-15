#!/bin/sh
# Build a rootless .deb for the WeChatLiquidGlass Theos project on Linux:
# clang 18 + ld64.lld against theos/sdks iPhoneOS16.5.sdk, ldid -S, dpkg-deb.
# Usage: tools/build_deb_linux.sh <project dir> <output.deb>
# Toolchain (FIX103; once per container, ~150 MB):
#   mkdir -p /home/claude/toolchain && cd /home/claude/toolchain
#   GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout https://github.com/theos/sdks sdks
#   cd sdks && git sparse-checkout init --no-cone && git sparse-checkout set '/iPhoneOS16.5.sdk/usr/include/' \
#     '/iPhoneOS16.5.sdk/usr/lib/' '/iPhoneOS16.5.sdk/System/Library/Frameworks/' '/iPhoneOS16.5.sdk/SDKSettings.*' && git checkout
#   curl -sSL -o /home/claude/toolchain/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64 && chmod +x /home/claude/toolchain/ldid
# Needs clang 18 and ld64.lld (/usr/lib/llvm-18/bin) and dpkg-deb.
set -eu
PROJ=$(cd "$1" && pwd); OUT=$2
SDK=${SDK:-/home/claude/toolchain/sdks/iPhoneOS16.5.sdk}
LDID=${LDID:-/home/claude/toolchain/ldid}
# FIX105: the compiler is overridable so an obfuscating clang (obfuscator-llvm /
# Arkari / Hikari) can be dropped in without touching the project. Default is
# the plain clang 18. CC_DIR, if set, is prepended to PATH (where that clang
# lives); otherwise the usual llvm-18 location. OBF_FLAGS are the -mllvm passes
# and OBF_FILES the space-separated source paths they apply to (only those, so
# the render hot path is never slowed); both empty means a normal build.
CC=${CC:-clang}
export PATH=${CC_DIR:-/usr/lib/llvm-18/bin}:$PATH
OBF_FLAGS=${OBF_FLAGS:-}
OBF_FILES=${OBF_FILES:-}
# 额外链接选项（普通构建留空、不变）。间接跳转/调用混淆会生成撑爆 iOS chained
# fixups 的地址常量，链接时需 -Wl,-no_fixup_chains（由 CI 的 build-obf 设置）。
LD_EXTRA=${LD_EXTRA:-}
# 额外编译宏（普通构建留空、不变）。CI 的自测包用它传 -DWXG_FORCE_AUTHORIZED=1。
EXTRA_CFLAGS=${EXTRA_CFLAGS:-}
NAME=$(sed -n 's/^TWEAK_NAME *= *//p' "$PROJ/Makefile")
FILES=$(sed -n "s/^${NAME}_FILES *= *//p" "$PROJ/Makefile")
CFLAGS=$(sed -n "s/^${NAME}_CFLAGS *= *//p" "$PROJ/Makefile")
FRAMEWORKS=$(sed -n "s/^${NAME}_FRAMEWORKS *= *//p" "$PROJ/Makefile")
LIBRARIES=$(sed -n "s/^${NAME}_LIBRARIES *= *//p" "$PROJ/Makefile")
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
COMMON="-target arm64-apple-ios14.0 -isysroot $SDK -DTARGET_IPHONE=1 -DTHEOS_PACKAGE_INSTALL_PREFIX=\"/var/jb\""
OBJS=
for f in $FILES; do
    o="$WORK/$(basename "$f").o"
    # Only the files in OBF_FILES get the obfuscation passes; everything else,
    # including the render hot path, compiles exactly as before.
    obf=
    for g in $OBF_FILES; do [ "$g" = "$f" ] && obf=$OBF_FLAGS; done
    # Theos adds -Werror; keep it so on-device builds behave the same.
    # FIX107: -fvisibility=hidden 让内部符号(WXGLicenseCurrentState 等)变成隐藏,
    # 配合链接期 -Wl,-x 从符号表里抹掉名字——破解者就没法"按名字跳到判定函数改返回 1"了。
    # ObjC 类 / 分类 / %ctor 走运行时的 __objc_* 段注册,与符号可见性无关,不受影响。
    "$CC" $COMMON -fvisibility=hidden $CFLAGS $EXTRA_CFLAGS $obf -Werror -I"$PROJ/Sources" -c "$PROJ/$f" -o "$o"
    OBJS="$OBJS $o"
done
FW=; for x in $FRAMEWORKS; do FW="$FW -framework $x"; done
LB=; for x in $LIBRARIES; do LB="$LB -l$x"; done
"$CC" $COMMON -fuse-ld=lld -mlinker-version=711 -dynamiclib \
    -install_name "@rpath/$NAME.dylib" -Wl,-dead_strip -Wl,-x $LD_EXTRA -lobjc $FW $LB $OBJS -o "$WORK/$NAME.dylib"
# FIX107: 再尽力跑一遍 llvm-strip（能找到就剥，找不到也不致构建失败；-Wl,-x 已在链接期做了主要的事）。
STRIP=$(command -v llvm-strip 2>/dev/null || echo "${CC_DIR:-/usr/lib/llvm-18/bin}/llvm-strip")
[ -x "$STRIP" ] && "$STRIP" -x "$WORK/$NAME.dylib" 2>/dev/null || echo "note: 跳过额外 strip（链接期 -Wl,-x 已剥离局部符号）"
"$LDID" -S "$WORK/$NAME.dylib"
PKG="$WORK/pkg"; DST="$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DST" "$PKG/DEBIAN"
cp "$WORK/$NAME.dylib" "$DST/"; cp "$PROJ/$NAME.plist" "$DST/"
sed 's/^Architecture:.*/Architecture: iphoneos-arm64/' "$PROJ/control" > "$PKG/DEBIAN/control"
grep -q '^Installed-Size:' "$PKG/DEBIAN/control" || echo "Installed-Size: $(du -sk "$PKG/var" | cut -f1)" >> "$PKG/DEBIAN/control"
chmod 0755 "$PKG/DEBIAN"; chmod 0644 "$PKG/DEBIAN/control"
dpkg-deb --root-owner-group -Zgzip -b "$PKG" "$OUT" >/dev/null
cp "$WORK/$NAME.dylib" "${OUT%.deb}.dylib"
echo "built $OUT"
