#!/bin/zsh

# Media Tools Phase 1 prototype: extract the first audio stream from MP4/MOV
# inputs as MP3 files next to the originals. Existing files are never replaced.

set -u

find_ffmpeg() {
    if [[ -n "${MEDIA_TOOLS_FFMPEG:-}" && -x "${MEDIA_TOOLS_FFMPEG}" ]]; then
        print -r -- "${MEDIA_TOOLS_FFMPEG}"
        return 0
    fi

    local candidate
    for candidate in \
        "/opt/homebrew/bin/ffmpeg" \
        "/usr/local/bin/ffmpeg" \
        "/usr/bin/ffmpeg"; do
        if [[ -x "${candidate}" ]]; then
            print -r -- "${candidate}"
            return 0
        fi
    done

    candidate="$(command -v ffmpeg 2>/dev/null || true)"
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
        print -r -- "${candidate}"
        return 0
    fi

    return 1
}

reserve_output_path() {
    local directory="$1"
    local stem="$2"
    local index=0
    local candidate

    while true; do
        if (( index == 0 )); then
            candidate="${directory}/${stem}.mp3"
        else
            candidate="${directory}/${stem}_${index}.mp3"
        fi

        # noclobber makes the zero-byte reservation atomic, including when two
        # Finder actions for the same source start at nearly the same time.
        if (set -o noclobber; : > "${candidate}") 2>/dev/null; then
            print -r -- "${candidate}"
            return 0
        fi

        (( index += 1 ))
    done
}

if (( $# == 0 )); then
    print -u2 -- "没有收到任何文件。"
    exit 64
fi

ffmpeg_path="$(find_ffmpeg)" || {
    print -u2 -- "找不到 FFmpeg。Prototype 需要本机已有 FFmpeg。"
    exit 69
}

failure_count=0
success_count=0

for input_path in "$@"; do
    if [[ ! -f "${input_path}" ]]; then
        print -u2 -- "跳过：不是普通文件：${input_path}"
        (( failure_count += 1 ))
        continue
    fi

    extension="${input_path:e:l}"
    if [[ "${extension}" != "mp4" && "${extension}" != "mov" ]]; then
        print -u2 -- "跳过：Prototype 仅支持 MP4/MOV：${input_path}"
        (( failure_count += 1 ))
        continue
    fi

    directory="${input_path:h}"
    stem="${input_path:t:r}"
    output_path="$(reserve_output_path "${directory}" "${stem}")" || {
        print -u2 -- "无法创建输出文件：${input_path}"
        (( failure_count += 1 ))
        continue
    }

    # Write directly into the atomically reserved destination. Automator's
    # security-scoped permission allows creating/writing the destination but,
    # in protected folders such as Downloads, can reject a later rename of a
    # child-process-created temporary file with EPERM.
    if "${ffmpeg_path}" \
        -hide_banner \
        -loglevel error \
        -nostdin \
        -y \
        -i "${input_path}" \
        -map 0:a:0 \
        -vn \
        -codec:a libmp3lame \
        -q:a 2 \
        "${output_path}"; then
        print -r -- "已生成：${output_path}"
        (( success_count += 1 ))
    else
        /bin/rm -f "${output_path}"
        print -u2 -- "转换失败（文件可能没有音轨）：${input_path}"
        (( failure_count += 1 ))
    fi
done

print -r -- "完成：成功 ${success_count} 个，失败 ${failure_count} 个。"

(( failure_count == 0 ))
