#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WXG_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$WXG_TEST_TMP"' EXIT HUP INT TERM
for source in Tests/*.c; do
    name=$(basename "$source" .c)
    "${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror "$source" -lm -o "$WXG_TEST_TMP/$name"
    "$WXG_TEST_TMP/$name"
done
