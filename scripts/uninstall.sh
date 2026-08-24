#!/bin/zsh

set -eu

workflow_path="${HOME}/Library/Services/提取音频.workflow"
support_directory="${HOME}/Library/Application Support/Media Tools Prototype"

/bin/rm -rf "${workflow_path}" "${support_directory}"
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

print -r -- "已卸载 Media Tools Prototype。"
