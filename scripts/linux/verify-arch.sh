#!/usr/bin/env bash
# 校验 Arch 原生包的架构、文件、依赖与词库完整性。
set -euo pipefail
pkg=${1:?用法: verify-arch.sh <pkg.tar.zst>}
[[ -f "$pkg" ]] || { echo "包不存在: $pkg" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bsdtar -xf "$pkg" -C "$tmp"
meta=$(cat "$tmp/.PKGINFO")
grep -qx 'pkgname = fcitx5-windinput' <<<"$meta"
grep -qx 'arch = x86_64' <<<"$meta"
for dep in fcitx5 fontconfig libxcb wayland glibc gcc-libs hicolor-icon-theme libxkbcommon procps-ng; do
    grep -qx "depend = $dep" <<<"$meta" || { echo "缺依赖: $dep" >&2; exit 1; }
done
for path in usr/lib/fcitx5/libwindinput.so usr/lib/windinput/wind_input  usr/lib/windinput/wind_setting usr/share/fcitx5/addon/windinput.conf  usr/share/fcitx5/inputmethod/windinput.conf  usr/share/applications/windinput-setting.desktop  usr/share/mime/packages/windinput.xml; do
    [[ -f "$tmp/$path" ]] || { echo "缺文件: $path" >&2; exit 1; }
done
check_min() {
    local path=$1 min=$2 size
    [[ -f "$tmp/usr/lib/windinput/data/$path" ]] || { echo "缺词库: $path" >&2; exit 1; }
    size=$(stat -c%s "$tmp/usr/lib/windinput/data/$path")
    (( size >= min )) || { echo "词库过小: $path ($size < $min)" >&2; exit 1; }
}
check_min schemas/pinyin/cn_dicts/base.dict.yaml 1000000
check_min schemas/wubi86/wubi86_jidian.dict.yaml 1000000
check_min opencc/STPhrases.octrie 100000
check_min pinyin_map.txt 10000
check_min schemas/stroke/stroke.dict.yaml 500000
if grep -vE '^[[:space:]]*(#|$)' "$tmp/usr/lib/windinput/data/compat.toml" | grep -q .; then
    echo 'Linux compat.toml 含有效规则' >&2
    exit 1
fi
for path in usr/lib/fcitx5/libwindinput.so usr/lib/windinput/wind_input usr/lib/windinput/wind_setting; do
    file="$tmp/$path"
    machine=$(readelf -h "$file" | sed -n 's/.*Machine:[[:space:]]*//p')
    [[ "$machine" == 'Advanced Micro Devices X86-64' ]] || { echo "$path 架构错误: $machine" >&2; exit 1; }
    if ldd "$file" | grep -q 'not found'; then
        echo "$path 有缺失动态库" >&2
        exit 1
    fi
done
readelf -d "$tmp/usr/lib/fcitx5/libwindinput.so" | grep -q 'libwayland-client.so.0'
readelf -d "$tmp/usr/lib/fcitx5/libwindinput.so" | grep -q 'libFcitx5Core.so.7'
bad=$(find "$tmp/usr" -perm /022 ! -type l -print)
[[ -z "$bad" ]] || { echo "包内组或其他用户可写: $bad" >&2; exit 1; }
echo "Arch package verification PASS: $pkg"
