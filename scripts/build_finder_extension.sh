#!/bin/zsh

set -eu

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
source_directory="${project_directory}/finder-extension"
ffmpeg_path="${project_directory}/vendor/ffmpeg/arm64/ffmpeg"
app_path="${project_directory}/build/Finder Audio Tools.app"
app_contents="${app_path}/Contents"
extension_path="${app_contents}/PlugIns/FinderAudioExtension.appex"
extension_contents="${extension_path}/Contents"
main_compile_defines=()

if [[ -n "${LICENSE_SERVER_URL:-}" ]]; then
    main_compile_defines+=("-DRCC_LICENSE_SERVER_URL=@\"${LICENSE_SERVER_URL}\"")
fi

if [[ ! -x "${ffmpeg_path}" || ! -x "${project_directory}/vendor/ffmpeg/arm64/ffprobe" ]]; then
    print -u2 -- "缺少内置 FFmpeg，请先执行：./scripts/build_ffmpeg_arm64.sh"
    exit 69
fi

/bin/rm -rf "${app_path}"
/bin/mkdir -p \
    "${app_contents}/MacOS" \
    "${app_contents}/Resources" \
    "${extension_contents}/MacOS"

/usr/bin/clang \
    -Os \
    -fobjc-arc \
    -mmacosx-version-min=13.0 \
    -framework AppKit \
    "${main_compile_defines[@]}" \
    "${source_directory}/FinderAudioTools.m" \
    "${source_directory}/CompressionUI.m" \
    -o "${app_contents}/MacOS/FinderAudioTools"

/usr/bin/clang \
    -Os \
    -fobjc-arc \
    -fblocks \
    -fapplication-extension \
    -mmacosx-version-min=13.0 \
    -framework AppKit \
    -framework FinderSync \
    "${source_directory}/FinderSync.m" \
    -o "${extension_contents}/MacOS/FinderAudioExtension"

/usr/bin/clang -Os -fobjc-arc -fblocks -mmacosx-version-min=13.0 -framework Foundation \
    "${source_directory}/CompressionWorker.m" -o "${app_contents}/Resources/CompressionWorker"
/bin/cp "${project_directory}/vendor/ffmpeg/arm64/ffprobe" "${app_contents}/Resources/ffprobe"

/bin/cp "${source_directory}/App-Info.plist" "${app_contents}/Info.plist"
/bin/cp "${project_directory}/assets/ConvertRight.icns" "${app_contents}/Resources/ConvertRight.icns"
/bin/cp "${source_directory}/Extension-Info.plist" "${extension_contents}/Info.plist"
/bin/cp "${project_directory}/scripts/convert_media.sh" "${app_contents}/Resources/convert_media.sh"
/bin/cp "${ffmpeg_path}" "${app_contents}/Resources/ffmpeg"
/bin/cp "${project_directory}/THIRD_PARTY_NOTICES.md" "${app_contents}/Resources/THIRD_PARTY_NOTICES.md"

if [[ -d "${project_directory}/vendor/ffmpeg/arm64/licenses" ]]; then
    /usr/bin/ditto \
        "${project_directory}/vendor/ffmpeg/arm64/licenses" \
        "${app_contents}/Resources/licenses"
fi

/bin/chmod 755 \
    "${app_contents}/MacOS/FinderAudioTools" \
    "${extension_contents}/MacOS/FinderAudioExtension" \
    "${app_contents}/Resources/convert_media.sh" \
    "${app_contents}/Resources/ffmpeg" \
    "${app_contents}/Resources/ffprobe" \
    "${app_contents}/Resources/CompressionWorker"

/usr/bin/plutil -lint "${app_contents}/Info.plist" "${extension_contents}/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none \
    --entitlements "${source_directory}/Extension.entitlements" \
    "${extension_path}"
/usr/bin/codesign --force --sign - --timestamp=none "${app_path}"

print -r -- "Finder 扩展已生成：${app_path}"
