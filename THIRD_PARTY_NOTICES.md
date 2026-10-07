# Third-party notices

Finder Audio Tools uses FFmpeg 7.1 with the LAME MP3 encoder, x264 H.264 encoder and zimg color conversion library. Apple VideoToolbox is used for hardware H.264 encoding; x264 provides software and two-pass fallback. The bundled Beta
binary is built from source by `scripts/build_ffmpeg_arm64.sh`.

- FFmpeg source: <https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz>
- FFmpeg license information: <https://ffmpeg.org/legal.html>
- x264 source: <https://code.videolan.org/videolan/x264> (GPL-2.0-or-later; pinned archive SHA-256 in the build script).
- zimg source: <https://github.com/sekrit-twc/zimg/tree/release-3.0.5> (MIT).
- LAME project: <https://lame.sourceforge.io/>

The generated distribution includes the license files copied from the FFmpeg
and LAME source archives. Because this build enables `libmp3lame`, the bundled
FFmpeg executable is distributed under the GNU General Public License version 2
or later. Finder Audio Tools invokes FFmpeg as a separate executable.

