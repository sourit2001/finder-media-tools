#!/bin/zsh

set -eu
export LC_ALL=C
export LANG=C

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
vendor_directory="${project_directory}/vendor/ffmpeg/arm64"
ffmpeg_version="7.1"
ffmpeg_archive="ffmpeg-${ffmpeg_version}.tar.xz"
ffmpeg_url="https://ffmpeg.org/releases/${ffmpeg_archive}"
ffmpeg_sha256="40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6"
x264_commit="b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
x264_sha256="cd71a7515b0e9a012e1ac9b1f8415bebcaf6fc97d4db32286642ac4c0fbe24f9"
zimg_version="3.0.5"
zimg_sha256="a9a0226bf85e0d83c41a8ebe4e3e690e1348682f6a2a7838f1b8cbff1b799bcf"
lame_version="3.100"
lame_archive="lame-${lame_version}.tar.gz"
lame_url="https://downloads.sourceforge.net/project/lame/lame/${lame_version}/${lame_archive}"
lame_sha256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 -- "当前 Beta 只构建 Apple Silicon arm64 版本。"
    exit 69
fi

build_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/finder-audio-tools-ffmpeg.XXXXXX")"
export MACOSX_DEPLOYMENT_TARGET="13.0"

cleanup() {
    /bin/rm -rf "${build_directory}"
}
trap cleanup EXIT

archive_path="${build_directory}/${ffmpeg_archive}"
lame_archive_path="${build_directory}/${lame_archive}"

if [[ -f "/private/tmp/${ffmpeg_archive}" ]]; then
    /bin/cp "/private/tmp/${ffmpeg_archive}" "${archive_path}"
else
    /usr/bin/curl -L --fail --show-error "${ffmpeg_url}" -o "${archive_path}"
fi

if [[ -f "/private/tmp/${lame_archive}" ]]; then
    /bin/cp "/private/tmp/${lame_archive}" "${lame_archive_path}"
else
    /usr/bin/curl -L --fail --show-error "${lame_url}" -o "${lame_archive_path}"
fi

actual_sha256="$(LC_ALL=C /usr/bin/shasum -a 256 "${archive_path}" | /usr/bin/awk '{print $1}')"
if [[ "${actual_sha256}" != "${ffmpeg_sha256}" ]]; then
    print -u2 -- "FFmpeg 源码校验失败。"
    print -u2 -- "预期：${ffmpeg_sha256}"
    print -u2 -- "实际：${actual_sha256}"
    exit 65
fi

actual_lame_sha256="$(LC_ALL=C /usr/bin/shasum -a 256 "${lame_archive_path}" | /usr/bin/awk '{print $1}')"
if [[ "${actual_lame_sha256}" != "${lame_sha256}" ]]; then
    print -u2 -- "LAME 源码校验失败。"
    print -u2 -- "预期：${lame_sha256}"
    print -u2 -- "实际：${actual_lame_sha256}"
    exit 65
fi

/usr/bin/tar -xf "${archive_path}" -C "${build_directory}"
/usr/bin/tar -xf "${lame_archive_path}" -C "${build_directory}"
source_directory="${build_directory}/ffmpeg-${ffmpeg_version}"
lame_source_directory="${build_directory}/lame-${lame_version}"
lame_install_directory="${build_directory}/lame-install"

cd "${lame_source_directory}"

./configure \
    --prefix="${lame_install_directory}" \
    --disable-shared \
    --enable-static \
    --disable-frontend

/usr/bin/make -s -j"$(/usr/sbin/sysctl -n hw.logicalcpu)"
/usr/bin/make -s install

x264_archive="${build_directory}/x264.tar.gz"
if [[ -f "/private/tmp/x264-b35605a.tar.gz" ]]; then
    /bin/cp "/private/tmp/x264-b35605a.tar.gz" "${x264_archive}"
else
    /usr/bin/curl -L --fail --show-error "https://code.videolan.org/videolan/x264/-/archive/${x264_commit}/x264-${x264_commit}.tar.gz" -o "${x264_archive}"
fi
[[ "$(/usr/bin/shasum -a 256 "${x264_archive}" | /usr/bin/awk '{print $1}')" == "${x264_sha256}" ]] || { print -u2 -- "x264 source checksum mismatch"; exit 65; }
/usr/bin/tar -xf "${x264_archive}" -C "${build_directory}"
x264_source="${build_directory}/x264-${x264_commit}"
x264_install="${build_directory}/x264-install"
cd "${x264_source}"
./configure --prefix="${x264_install}" --enable-static --disable-cli --disable-asm --extra-cflags="-mmacosx-version-min=13.0"
/usr/bin/make -s -j"$(/usr/sbin/sysctl -n hw.logicalcpu)"
/usr/bin/make -s install

# Build zimg's portable C++ core from pinned upstream sources. No Homebrew
# libraries are linked; the portable core also keeps the macOS 13 deployment floor.
zimg_archive="${build_directory}/zimg.tar.gz"
if [[ -f "/private/tmp/zimg-${zimg_version}.tar.gz" ]]; then
    /bin/cp "/private/tmp/zimg-${zimg_version}.tar.gz" "${zimg_archive}"
else
    /usr/bin/curl -L --fail --show-error "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-${zimg_version}.tar.gz" -o "${zimg_archive}"
fi
[[ "$(/usr/bin/shasum -a 256 "${zimg_archive}" | /usr/bin/awk '{print $1}')" == "${zimg_sha256}" ]] || exit 65
/usr/bin/tar -xf "${zimg_archive}" -C "${build_directory}"
zimg_source="${build_directory}/zimg-release-${zimg_version}"
zimg_install="${build_directory}/zimg-install"
/bin/mkdir -p "${zimg_install}/lib/pkgconfig" "${zimg_install}/include" "${build_directory}/zimg-objects"
for source in "${zimg_source}"/src/zimg/**/*.cpp; do
    [[ "${source}" == */arm/* || "${source}" == */x86/* ]] && continue
    object="${build_directory}/zimg-objects/${${source#${zimg_source}/}:gs/\//_}.o"
    /usr/bin/clang++ -O2 -std=c++11 -mmacosx-version-min=13.0 -I"${zimg_source}/src/zimg" -c "${source}" -o "${object}"
done
/usr/bin/ar rcs "${zimg_install}/lib/libzimg.a" "${build_directory}/zimg-objects/"*.o
/bin/cp "${zimg_source}/src/zimg/api/zimg.h" "${zimg_install}/include/"
/bin/cat > "${zimg_install}/lib/pkgconfig/zimg.pc" <<EOF
prefix=${zimg_install}
Name: zimg
Description: zimg portable core
Version: ${zimg_version}
Libs: -L${zimg_install}/lib -lzimg -lc++
Cflags: -I${zimg_install}/include
EOF
export PKG_CONFIG_PATH="${zimg_install}/lib/pkgconfig:${x264_install}/lib/pkgconfig"

cd "${source_directory}"

./configure \
    --prefix="/opt/finder-audio-tools-ffmpeg" \
    --extra-version="finder-audio-tools-beta" \
    --arch=arm64 \
    --target-os=darwin \
    --cc=clang \
    --disable-shared \
    --enable-static \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --disable-network \
    --disable-avdevice \
    --disable-postproc \
    --disable-autodetect \
    --enable-gpl \
    --enable-libmp3lame \
    --enable-videotoolbox \
    --enable-libzimg \
    --enable-libx264 \
    --extra-cflags="-I${lame_install_directory}/include" \
    --extra-ldflags="-L${lame_install_directory}/lib"

/usr/bin/make -s -j"$(/usr/sbin/sysctl -n hw.logicalcpu)" ffmpeg ffprobe

/bin/mkdir -p "${vendor_directory}/licenses"
/bin/cp "${source_directory}/ffmpeg" "${vendor_directory}/ffmpeg"
/bin/cp "${source_directory}/ffprobe" "${vendor_directory}/ffprobe"
/bin/chmod 755 "${vendor_directory}/ffmpeg" "${vendor_directory}/ffprobe"
/bin/cp "${x264_source}/COPYING" "${vendor_directory}/licenses/x264-GPL-2.0.txt"
/bin/cp "${zimg_source}/COPYING" "${vendor_directory}/licenses/zimg-MIT.txt"
/bin/cp "${source_directory}/COPYING.GPLv2" "${vendor_directory}/licenses/FFmpeg-GPL-2.0.txt"

/bin/cp "${lame_source_directory}/COPYING" "${vendor_directory}/licenses/LAME-LGPL.txt"

if /usr/bin/otool -L "${vendor_directory}/ffmpeg" | /usr/bin/grep -q '/opt/homebrew\|/usr/local'; then
    print -u2 -- "构建结果仍依赖 Homebrew 动态库，不能用于分发。"
    exit 65
fi

print -r -- "已构建：${vendor_directory}/ffmpeg"
"${vendor_directory}/ffmpeg" -version | /usr/bin/head -5
