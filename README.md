# ConvertRight / RightClick Converter for Mac

当前版本：`0.7.1`（本地测试版）。Apple Silicon，macOS 13 或更高版本。

在 Finder 右键视频或音频即可转换，处理完全在本机进行。视频压缩会显示原生玻璃效果的小进度窗口；不覆盖原文件。

## 视频压缩

右键视频 → **Compress Video**：

- **Quick Compress**：自动缩小文件；如果没有变小，则保留原文件并提示。
- **Under 10 MB / Under 20 MB / Under 50 MB / Under 100 MB**：每个视频分别压到所选上限以下。
- **Custom Size…**：自定义十进制 MB 上限、自动/原分辨率/最高 1080p/最高 720p，以及移除音轨。记住上次选项。

默认输出 MP4（H.264 + AAC），保持画面比例、正确旋转竖屏，支持 HDR 转 SDR。自动模式按码率缩小分辨率，最高 1080p、最高 30fps；不会放大画面。Apple VideoToolbox 优先，低码率或硬件失败时使用 x264；目标大小的软件编码采用双遍处理。成品检查实际大小和时长，超标最多重试三次，失败不留下不合格输出。

支持 MP4、MOV、M4V、MKV、WebM、AVI。多选按顺序处理，单个文件失败不影响其他文件。已满足大小与格式要求的文件跳过；过小的目标会提示增加上限。

进度窗口可取消，取消当前及待处理文件，保留已完成文件。关闭进行中的窗口也会先取消；完成后点击 **Show in Finder** 定位结果，点击 **Done** 关闭窗口。

输出与源文件同目录，命名为 `原名_under-20MB.mp4` 或 `原名_compressed.mp4`；同名自动加编号。视频压缩沿用现有五次试用和购买授权，仅成功生成的视频计入使用次数。

日志：`~/Library/Logs/ConvertRight Compression.log`。

## 音频转换

### 功能

- Finder 根据所选文件显示“提取音频为…”或“转换音频为…”入口
- 子菜单直接提供 MP3、M4A 和 WAV
- 支持 Finder 单选和多选
- 视频提取第一条音轨，音频文件执行格式转换
- 输出到源文件所在目录
- 已存在同名文件时生成 `_1`、`_2` 等新文件
- 不修改或覆盖源文件
- 转换完全在本机完成，不上传文件
- 点击格式后静默转换，无弹窗、无 Dock 图标、无菜单栏图标

### 支持的输入格式

视频：MP4、MOV、M4V、MKV、WebM、AVI

音频：MP3、M4A、AAC、WAV、FLAC、OGG、OGA、Opus、AIFF

Beta 首先支持 Apple Silicon Mac 和 macOS 13 或更高版本。

### 安装与音频操作

1. 下载并打开 DMG。
2. 双击“安装 Finder Audio Tools.pkg”。
3. Finder 选择视频或音频文件。
4. 视频右键选择“提取音频为…”，音频右键选择“转换音频为…”，再选择 MP3/M4A/WAV。
5. 新文件静默生成在源文件旁边。

当前 Beta 没有 Apple Developer ID 签名。首次安装时，macOS 可能阻止打开。
尝试打开一次后，前往“系统设置 → 隐私与安全性 → 仍要打开”。

## 开发安装

开发安装写入当前用户的 `~/Applications`，不需要管理员密码：

```sh
./scripts/build_finder_extension.sh
./scripts/install.sh
```

卸载开发版本：

```sh
./scripts/uninstall.sh
```

运行日志：

```text
~/Library/Logs/Finder Audio Tools.log
```

## 构建内置 FFmpeg

构建脚本从 FFmpeg 与 LAME 官方源码构建 Apple Silicon 静态二进制，最低系统版本为
macOS 13。运行时不依赖 Homebrew。

```sh
./scripts/build_ffmpeg_arm64.sh
```

源码版本和 SHA-256 固定在构建脚本中。生成的二进制位于：

```text
vendor/ffmpeg/arm64/ffmpeg
```

## 构建未签名 Beta DMG

```sh
./scripts/build_beta_dmg.sh
```

输出位于：

```text
dist/RightClick-Converter-0.7.1.dmg
dist/RightClick-Converter-0.7.1.dmg.sha256
```

DMG 包含系统级 PKG、安装说明和卸载脚本。系统级安装需要输入 Mac 管理员密码。

## 测试

视频压缩集成测试（真实编码、完整解码、大小/方向/HDR/取消校验）：

```sh
python3 tests/test_compression.py
```

VideoToolbox 需要真实 macOS 服务访问；受限沙箱中可能无法创建硬件编码会话。测试生成素材需开发机安装 FFmpeg，分发应用无此依赖。


转换引擎测试：

```sh
./tests/test_convert_media.sh
```

Finder 集成需要额外验证：扩展已在 `pluginkit` 中启用、真实右键菜单可见，且点击格式后
确实在源文件旁生成可播放的输出文件。仅构建成功不代表 Finder 已加载扩展。

## 第三方组件

内置 FFmpeg 7.1、LAME 3.100、x264 和 zimg 3.0.5。许可证与源码地址见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。分发包中同时包含完整许可证文本。
