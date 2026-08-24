#!/bin/zsh

set -eu

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
support_directory="${HOME}/Library/Application Support/Media Tools Prototype"
services_directory="${HOME}/Library/Services"
workflow_name="提取音频.workflow"

/bin/mkdir -p "${support_directory}" "${services_directory}"
/bin/cp "${project_directory}/scripts/extract_audio.sh" "${support_directory}/extract_audio.sh"
/bin/chmod 755 "${support_directory}/extract_audio.sh"

/bin/rm -rf "${services_directory}/${workflow_name}"
/usr/bin/ditto \
    "${project_directory}/workflow/${workflow_name}" \
    "${services_directory}/${workflow_name}"

# Refresh the Services database. Finder may still need a few seconds before the
# new Quick Action appears.
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

print -r -- "已安装：Finder → 右键 MP4/MOV → 快速操作 → 提取音频"
