#!/usr/bin/env bash
# 在 Arch Linux 上从当前源码和生成词库原生编译标准 pacman 包。
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
setting=${SETTING_REPO:-"$repo/../wind-setting"}
data=${DATA_DIR:-"$repo/build_dev/data"}
out=${OUT_DIR:-"$repo/dist/arch"}
work=${WORK_DIR:-"${XDG_CACHE_HOME:-$HOME/.cache}/wi-arch"}
[[ -f "$setting/Cargo.toml" ]] || { echo "缺设置程序: $setting" >&2; exit 1; }
[[ -f "$setting/../wind-ui-rust/Cargo.toml" ]] || { echo '缺设置程序的 wind-ui-rust path 依赖' >&2; exit 1; }
[[ -f "$data/schemas/pinyin/cn_dicts/base.dict.yaml" ]] || { echo "词库未生成: $data" >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo '当前仅验证 x86_64 Arch 架构' >&2; exit 1; }
command -v makepkg >/dev/null || { echo '需要 pacman/makepkg' >&2; exit 1; }
version=$(tr -d '[:space:]' <"$repo/docs/VERSION")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "暂不支持该预发布版本: $version" >&2; exit 1; }
mkdir -p "$out" "$work"
export WIND_ARCH_REPO=$repo WIND_ARCH_SETTING=$setting WIND_ARCH_DATA=$data WIND_ARCH_PKGVER=$version
export WIND_ARCH_TARGET=${SERVICE_TARGET:-"$work/target"}
export WIND_ARCH_SETTING_TARGET=${SETTING_TARGET:-"$work/setting-target"}
export WIND_ARCH_CMAKE=${ADDON_BUILD:-"$work/cmake"}
# 用户的 shell 可能设置了交叉编译工具链；原生包总用 Arch host 工具链。
unset CC CXX AR RANLIB
export CC=/usr/bin/gcc CXX=/usr/bin/g++ AR=/usr/bin/ar RANLIB=/usr/bin/ranlib
cd "$repo/scripts/linux/arch"
PKGDEST=$out BUILDDIR=$work makepkg -f --noconfirm
"$repo/scripts/linux/verify-arch.sh" "$out/fcitx5-windinput-$version-1-x86_64.pkg.tar.zst"
printf 'Arch package: %s\n' "$out/fcitx5-windinput-$version-1-x86_64.pkg.tar.zst"
