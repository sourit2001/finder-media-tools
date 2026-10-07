#!/bin/zsh

set -eu

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
converter="${project_directory}/scripts/convert_media.sh"
bundled_ffmpeg="${project_directory}/vendor/ffmpeg/arm64/ffmpeg"
fixture_ffmpeg="$(command -v ffmpeg 2>/dev/null || true)"

if [[ ! -x "${bundled_ffmpeg}" ]]; then
    print -u2 -- "缺少内置 FFmpeg，请先执行 scripts/build_ffmpeg_arm64.sh"
    exit 69
fi

if [[ -z "${fixture_ffmpeg}" || ! -x "${fixture_ffmpeg}" ]]; then
    print -u2 -- "生成测试素材需要开发机安装 FFmpeg。"
    exit 69
fi

test_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/finder-audio-tools-test.XXXXXX")"

cleanup() {
    /bin/rm -rf "${test_directory}"
}
trap cleanup EXIT

"${fixture_ffmpeg}" \
    -hide_banner -loglevel error \
    -f lavfi -i color=c=blue:s=320x180:d=2 \
    -f lavfi -i sine=frequency=440:duration=2 \
    -shortest -c:v mpeg4 -c:a aac \
    "${test_directory}/测试 视频.mov"

"${fixture_ffmpeg}" \
    -hide_banner -loglevel error \
    -f lavfi -i sine=frequency=660:duration=2 \
    "${test_directory}/测试音频.flac"

for format in mp3 m4a wav; do
    FINDER_AUDIO_TOOLS_FFMPEG="${bundled_ffmpeg}" \
        "${converter}" "${format}" \
        "${test_directory}/测试 视频.mov" \
        "${test_directory}/测试音频.flac"

    for stem in "测试 视频" "测试音频"; do
        output_path="${test_directory}/${stem}.${format}"
        if [[ ! -s "${output_path}" ]]; then
            print -u2 -- "输出文件缺失或为空：${output_path}"
            exit 65
        fi
    done
done

FINDER_AUDIO_TOOLS_FFMPEG="${bundled_ffmpeg}" \
    "${converter}" mp3 "${test_directory}/测试 视频.mov"

if [[ ! -s "${test_directory}/测试 视频_1.mp3" ]]; then
    print -u2 -- "同名文件自动编号测试失败。"
    exit 65
fi

"${fixture_ffmpeg}" \
    -hide_banner -loglevel error \
    -f lavfi -i color=c=red:s=320x180:d=1 \
    -c:v mpeg4 "${test_directory}/无音轨.mov"

if FINDER_AUDIO_TOOLS_FFMPEG="${bundled_ffmpeg}" \
    "${converter}" mp3 "${test_directory}/无音轨.mov"; then
    print -u2 -- "无音轨视频应该转换失败。"
    exit 65
fi

if [[ -e "${test_directory}/无音轨.mp3" ]]; then
    print -u2 -- "失败转换遗留了空输出文件。"
    exit 65
fi

print -r -- "转换测试通过：三种输出、批量、同名编号与失败清理"
