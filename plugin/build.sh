#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -z "${THEOS:-}" ]; then
    if [ -f /var/jb/var/theos/makefiles/common.mk ]; then THEOS=/var/jb/var/theos
    elif [ -f /var/theos/makefiles/common.mk ]; then THEOS=/var/theos
    elif [ -f /opt/theos/makefiles/common.mk ]; then THEOS=/opt/theos
    else
        echo '没有找到 Theos。请设置 THEOS 为你已安装的 Theos 目录。' >&2
        exit 1
    fi
fi
export THEOS
case "${1:-}" in
    rootless) export THEOS_PACKAGE_SCHEME=rootless ;;
    rootful) unset THEOS_PACKAGE_SCHEME ;;
    '') : ;;
    *) echo '用法：./build.sh [rootless|rootful]' >&2; exit 2 ;;
esac
make clean
make package FINALPACKAGE=1 -j1
echo '编译完成：安装 packages 内的 deb，然后完全退出并重新打开微信。'
