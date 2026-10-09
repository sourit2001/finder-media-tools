# ConvertRight for Windows 11

1. Extract the entire ZIP to a folder you want to keep, such as Documents\ConvertRight.
2. Open ConvertRight.exe. No installer, .NET installation, administrator permission, or certificate installation is required.
3. Drag audio or video files into the window, choose MP4 to compress video (or MP3, M4A or WAV to extract audio), then click Convert.
4. For MP4, set a target size in MB (2 GB = 2,000 MB), choose maximum 1080p, 720p or original resolution, and optionally remove audio. Click Cancel to stop video compression.
5. Converted files appear alongside the originals. Existing files are never overwritten. Double-click a completed result to reveal it in File Explorer.

The app includes five free successful conversions. Windows and Mac purchases are separate. Use Unlock this PC to buy a one-time $1 Windows license. Complete payment in your browser and allow it to open ConvertRight. If activation is delayed, click Restore purchase; do not pay again. Each purchase applies only to the installation that started checkout.

## Optional right-click menu

Click **Enable right-click menu** in the window. In File Explorer, select your files, right-click, then choose **Show more options → ConvertRight** and an output format. This registers the menu only for your Windows account; it does not need administrator permission.

Keep the application folder in place while using the menu. After moving it, open the app and enable the menu again. To stop using the menu, click **Remove right-click menu** before deleting the folder. Your conversion history and license are stored in `%LOCALAPPDATA%\ConvertRight`.

The executable is currently unsigned. Windows may show a reputation warning for downloaded software. It does not require installing a certificate or changing system security settings.

FFmpeg is bundled so conversion works offline. Its license texts and source information are included in the licenses folder and FFMPEG-SOURCE.txt.

Video compression uses H.264 and AAC. Smaller targets can reduce detail. A 1080p limit preserves aspect ratio and never enlarges smaller input. Audio conversion is available from the optional Explorer menu; video compression is available in the application window.

This Windows version accepts SDR video. HDR video is rejected with an explanation so it is not exported with incorrect colors.
