#!/bin/zsh

set -eu

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
built_app="${project_directory}/build/Finder Audio Tools.app"
installed_app="${HOME}/Applications/RightClick Converter.app"
legacy_installed_app="${HOME}/Applications/Finder Audio Tools.app"
extension_path="${installed_app}/Contents/PlugIns/FinderAudioExtension.appex"
extension_identifier="com.finderaudiotools.extension"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -x "${built_app}/Contents/MacOS/FinderAudioTools" ]]; then
    "${script_directory}/build_finder_extension.sh"
fi

/bin/mkdir -p "${HOME}/Applications"

if [[ -d "${extension_path}" ]]; then
    /usr/bin/pluginkit -r "${extension_path}" 2>/dev/null || true
fi

# Stop only this extension's uniquely named process before replacing its bundle.
/usr/bin/killall FinderAudioExtension 2>/dev/null || true
/usr/bin/killall FinderAudioTools 2>/dev/null || true

"${lsregister}" -u "${built_app}" 2>/dev/null || true
"${lsregister}" -u "${installed_app}" 2>/dev/null || true
"${lsregister}" -u "${legacy_installed_app}" 2>/dev/null || true
/bin/rm -rf "${installed_app}" "${legacy_installed_app}"
/usr/bin/ditto "${built_app}" "${installed_app}"

"${lsregister}" -f "${installed_app}"
/usr/bin/pluginkit -a "${extension_path}"
/usr/bin/pluginkit -e use -i "${extension_identifier}"

# Remove all current-user copies of the older Quick Action/picker prototypes.
/bin/rm -rf \
    "${HOME}/Library/Services/转换为 MP3.workflow" \
    "${HOME}/Library/Services/转换为 M4A.workflow" \
    "${HOME}/Library/Services/转换为 WAV.workflow" \
    "${HOME}/Library/Services/提取音频….workflow" \
    "${HOME}/Library/Application Support/Finder Audio Tools"

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

print -r -- "已安装：Finder → 右键媒体文件 → 提取/转换音频为… → MP3/M4A/WAV"
print -r -- "如果系统级旧菜单仍存在，请删除：/Library/Services/提取音频….workflow"
