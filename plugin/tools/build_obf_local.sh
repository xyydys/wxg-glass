#!/bin/sh
# 本地复刻 CI 的 build-obf 作业：在 Arkari 容器里编出和 CI 一样的「混淆发布包」。
# 用途：私有库 GitHub 托管分钟数用尽时，在自己机器上免费出包，仓库全程不公开。
#
# 怎么跑（在 WSL2 / Linux 的仓库根目录，已装 Docker）：
#   docker run --rm -v "$PWD":/work -w /work/plugin \
#     ghcr.io/xyydys/arkari-ios-toolchain:latest bash tools/build_obf_local.sh
#
# 产物：plugin/dist/com.runyu.wechatliquidglass_<版本>_iphoneos-arm64_obf.deb
#       （Windows 里从 \\wsl$\Ubuntu\...\wxg-glass\plugin\dist\ 取）
#
# 和 CI build-obf 完全一致的点：混淆 flag（cse/cff/indbr，按 FIX106 不含 icall）、
# 只混授权/联网 4 个文件、-DWXG_RELEASE=1（关日志/诊断）、出包后三项自检 + 绑定表体检。
set -eu

cd "$(dirname "$0")/.."   # -> plugin/
PROJ="$PWD"

echo "==== [1/4] 装 ld64.lld 运行期依赖 + 基础工具 ===="
apt-get update
apt-get install -y --no-install-recommends libxml2 libzstd1 zlib1g git curl ca-certificates dpkg-dev

echo "==== [2/4] 取 iOS 16.5 SDK（稀疏，已存在则跳过）===="
if [ ! -d "$PROJ/toolchain/sdks/iPhoneOS16.5.sdk/System/Library/Frameworks" ]; then
  mkdir -p "$PROJ/toolchain" && cd "$PROJ/toolchain"
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout https://github.com/theos/sdks sdks
  cd sdks
  git sparse-checkout init --no-cone
  git sparse-checkout set \
    '/iPhoneOS16.5.sdk/usr/include/' \
    '/iPhoneOS16.5.sdk/usr/lib/' \
    '/iPhoneOS16.5.sdk/System/Library/Frameworks/' \
    '/iPhoneOS16.5.sdk/SDKSettings.*'
  git checkout
  cd "$PROJ"
fi
test -d "$PROJ/toolchain/sdks/iPhoneOS16.5.sdk/System/Library/Frameworks"

echo "==== [3/4] 取 ldid（已存在则跳过）===="
LDID=/tmp/ldid
if [ ! -x "$LDID" ]; then
  curl -sSL -o "$LDID" \
    https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64
  chmod +x "$LDID"
fi
"$LDID" | head -1 || true

echo "==== [4/4] 编混淆包 ===="
VER=$(sed -n 's/^Version: *//p' control)
mkdir -p dist
OUT="dist/com.runyu.wechatliquidglass_${VER}_iphoneos-arm64_obf.deb"

export SDK="$PROJ/toolchain/sdks/iPhoneOS16.5.sdk"
export LDID
export CC_DIR=/opt/arkari/bin
export CC=clang
# 和 CI 默认一致：字符串加密 cse + 控制流平坦化 cff + 间接跳转 indbr；
# 按 FIX106 绝不加 -irobf-icall / -irobf-indgv（打进 IPA 会启动即闪退）。
export OBF_FLAGS='-mllvm -irobf -mllvm -irobf-cse -mllvm -irobf-cff -mllvm -irobf-indbr'
export OBF_FILES='Sources/WXGUnlock.m Sources/WXGLicense.m Sources/WXGGlassView.m Sources/WXGBackdrop.m'
export LD_EXTRA='-Wl,-no_fixup_chains'
export EXTRA_CFLAGS='-DWXG_RELEASE=1'

sh tools/build_deb_linux.sh "$PROJ" "$OUT"
ls -la dist

D="${OUT%.deb}.dylib"
echo "==== 自检 ===="
# 着色器文本绝不能出现在 dylib 里
if strings "$D" | grep -q "__METAL_VERSION__\|METAL_VERSION"; then
  echo "::ERROR:: dylib 里出现了着色器文本，构建判废"; exit 1
fi
# 服务器地址 / 公钥应被 -irobf-cse 加密掉
if strings "$D" | grep -q "workers.dev\|xyylwc"; then
  echo "::WARN:: dylib 里仍搜得到服务器地址明文 —— 确认 cse 覆盖了端点"
else echo "OK：服务器地址已隐藏"; fi
if strings "$D" | grep -q "73a7b661b9de"; then
  echo "::WARN:: dylib 里仍搜得到公钥明文 —— cse 可能未对 C 字符串生效"
else echo "OK：公钥已隐藏"; fi
# FIX106：绑定表不能有 64 位附加偏移（否则打进 IPA 启动即闪退）
set +e; sh tools/check_dyld_binds.sh "$D"; rc=$?; set -e
if [ "$rc" = 2 ]; then
  apt-get install -y --no-install-recommends llvm >/dev/null 2>&1 || true
  set +e; sh tools/check_dyld_binds.sh "$D"; rc=$?; set -e
fi
if [ "$rc" = 1 ]; then
  echo "::ERROR:: 绑定表 dyld 启动缓存存不下（打进 IPA 会启动即闪退）"; exit 1
elif [ "$rc" != 0 ]; then
  echo "::WARN:: 没能检查绑定表（容器里没 llvm-objdump），发包前本地再跑一遍 check_dyld_binds.sh"
fi

# 让宿主机（WSL2）无需 sudo 就能取/删产物
chmod -R a+rwX dist 2>/dev/null || true
echo "==== 完成：$OUT ===="
