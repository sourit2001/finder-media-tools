#!/bin/zsh

set -eu

installed_app="${HOME}/Applications/RightClick Converter.app"
legacy_installed_app="${HOME}/Applications/Finder Audio Tools.app"
extension_path="${installed_app}/Contents/PlugIns/FinderAudioExtension.appex"
extension_identifier="com.finderaudiotools.extension"

/usr/bin/pluginkit -e ignore -i "${extension_identifier}" 2>/dev/null || true
if [[ -d "${extension_path}" ]]; then
    /usr/bin/pluginkit -r "${extension_path}" 2>/dev/null || true
fi
/usr/bin/killall FinderAudioExtension 2>/dev/null || true
/usr/bin/killall FinderAudioTools 2>/dev/null || true

/bin/rm -rf \
    "${installed_app}" \
    "${legacy_installed_app}" \
    "${HOME}/Library/Services/转换为 MP3.workflow" \
    "${HOME}/Library/Services/转换为 M4A.workflow" \
    "${HOME}/Library/Services/转换为 WAV.workflow" \
    "${HOME}/Library/Services/提取音频….workflow" \
    "${HOME}/Library/Application Support/Finder Audio Tools"

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

print -r -- "已卸载当前用户的 Finder Audio Tools。"
