#!/bin/zsh

# Finder Audio Tools 0.2 Beta
# Convert the first audio stream of each selected media file to a requested
# output format. Outputs are written next to the source and never overwrite an
# existing file.

set -u

script_directory="${0:A:h}"

find_ffmpeg() {
    if [[ -n "${FINDER_AUDIO_TOOLS_FFMPEG:-}" && -x "${FINDER_AUDIO_TOOLS_FFMPEG}" ]]; then
        print -r -- "${FINDER_AUDIO_TOOLS_FFMPEG}"
        return 0
    fi

    local candidate
    for candidate in \
        "${script_directory}/ffmpeg" \
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
    local extension="$3"
    local index=0
    local candidate

    while true; do
        if (( index == 0 )); then
            candidate="${directory}/${stem}.${extension}"
        else
            candidate="${directory}/${stem}_${index}.${extension}"
        fi

        if (set -o noclobber; : > "${candidate}") 2>/dev/null; then
            print -r -- "${candidate}"
            return 0
        fi

        # If the path does not already exist, creation failed for another
        # reason (most commonly folder permissions). Do not retry forever with
        # incrementing suffixes.
        if [[ ! -e "${candidate}" ]]; then
            return 1
        fi

        (( index += 1 ))
    done
}

is_supported_input() {
    case "$1" in
        mp4|mov|m4v|mkv|webm|avi|mp3|m4a|aac|wav|flac|ogg|oga|opus|aif|aiff)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if (( $# < 2 )); then
    print -u2 -- "用法：convert_media.sh <mp3|m4a|wav> <文件> [文件 ...]"
    exit 64
fi

output_format="${1:l}"
shift

case "${output_format}" in
    mp3)
        codec_arguments=(-codec:a libmp3lame -q:a 2)
        ;;
    m4a)
        codec_arguments=(-codec:a aac -b:a 192k)
        ;;
    wav)
        codec_arguments=(-codec:a pcm_s16le)
        ;;
    *)
        print -u2 -- "不支持的输出格式：${output_format}"
        exit 64
        ;;
esac

ffmpeg_path="$(find_ffmpeg)" || {
    print -u2 -- "找不到内置 FFmpeg，请重新安装 Finder Audio Tools。"
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

    input_extension="${input_path:e:l}"
    if ! is_supported_input "${input_extension}"; then
        print -u2 -- "跳过：不支持的媒体格式：${input_path}"
        (( failure_count += 1 ))
        continue
    fi

    directory="${input_path:h}"
    stem="${input_path:t:r}"
    output_path="$(reserve_output_path "${directory}" "${stem}" "${output_format}")" || {
        print -u2 -- "无法创建输出文件：${input_path}"
        (( failure_count += 1 ))
        continue
    }

    if "${ffmpeg_path}" \
        -hide_banner \
        -loglevel error \
        -nostdin \
        -y \
        -i "${input_path}" \
        -map 0:a:0 \
        -vn \
        "${codec_arguments[@]}" \
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
