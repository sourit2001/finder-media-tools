# Media Tools Prototype

Phase 1 技术验证：在 Finder 中选中一个或多个 MP4/MOV 文件，通过右键“快速操作 → 提取音频”，在每个源文件所在目录生成 MP3。

## 当前范围

- 支持 MP4、MOV
- 支持 Finder 单选和多选
- 支持中文、空格及其他常见文件名
- 输出到源文件目录
- 已存在同名文件时依次生成 `_1`、`_2`
- 不修改或覆盖源文件

Prototype 暂时调用本机已有 FFmpeg。正式产品会将签名后的 FFmpeg 放入 App Bundle，用户不需要 Homebrew。

## 安装

在项目目录执行：

```sh
./scripts/install.sh
```

然后在 Finder 选中 MP4/MOV，右键选择“快速操作 → 提取音频”。

日志位于：

```text
~/Library/Logs/Media Tools Prototype.log
```

## 卸载

```sh
./scripts/uninstall.sh
```

## 直接测试转换逻辑

```sh
./scripts/extract_audio.sh "/path/to/video.mp4" "/path/to/另一个 视频.mov"
```
