#!/bin/sh
# wxg-glass Linux deb 构建环境一键恢复脚本（容器重建后跑一次）。
# 与 CI build.yml 的 build 作业、plugin/tools/build_deb_linux.sh 完全同链。
set -eu
TC=${TC:-/home/claude/toolchain}   # build_deb_linux.sh 默认也找这里（或设 SDK= / LDID=）
mkdir -p "$TC"

# 1) clang-18 + lld-18（Ubuntu 24.04 一般自带；缺了再装）
command -v /usr/lib/llvm-18/bin/clang >/dev/null 2>&1 || {
  sudo apt-get update && sudo apt-get install -y clang-18 lld-18 dpkg-dev
}

# 2) ldid（ProcursusTeam 预编译）
[ -x "$TC/ldid" ] || {
  curl -sSL -o "$TC/ldid" \
    https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64
  chmod +x "$TC/ldid"
}

# 3) iOS 16.5 SDK（theos/sdks 稀疏拉取，约 147M）
[ -d "$TC/sdks/iPhoneOS16.5.sdk/System/Library/Frameworks" ] || {
  cd "$TC"
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout https://github.com/theos/sdks sdks
  cd sdks
  git sparse-checkout init --no-cone
  git sparse-checkout set \
    '/iPhoneOS16.5.sdk/usr/include/' \
    '/iPhoneOS16.5.sdk/usr/lib/' \
    '/iPhoneOS16.5.sdk/System/Library/Frameworks/' \
    '/iPhoneOS16.5.sdk/SDKSettings.*'
  git checkout
}
echo "toolchain ready at $TC"

# ---- 编普通包（不混淆）----
#   cd <repo>/plugin
#   sh tools/build_deb_linux.sh "$PWD" dist/out.deb
# SDK/LDID 默认就指向 $TC，无需额外 env。产物：dist/out.deb + dist/out.dylib
