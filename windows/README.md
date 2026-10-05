# ConvertRight for Windows 11

The default distribution is a portable Windows 11 x64 application. Extract the ZIP and open ConvertRight.exe. The self-contained application includes its .NET runtime and FFmpeg; users do not install certificates or request administrator permission.

The window accepts audio/video files through drag-and-drop or a file picker, offers MP3/M4A/WAV, shows batch progress and individual results, and reveals completed outputs in File Explorer. Originals remain unchanged and existing outputs are never overwritten.

The optional right-click menu uses the native IExplorerCommand DLL registered under HKCU only. In Windows 11 it is available through Show more options. Enable/remove registration from the application window; keep the portable folder in place or enable registration again after moving it. No registry changes occur merely by opening the app.

## Build

Use Windows with Visual Studio C++ tools, CMake and .NET 10 SDK:

```powershell
.\scripts\Prepare-FFmpeg.ps1
dotnet run --project tests/Conversion.Tests.csproj -- "$PWD\vendor\ffmpeg\ffmpeg.exe"
.\scripts\Build-Portable.ps1 -FFmpegDirectory "$PWD\vendor\ffmpeg"
.\scripts\Smoke-Portable.ps1
```

Output: `out/ConvertRight-Windows-0.1.0-x64.zip`. Includes the executable, shell DLL, FFmpeg, complete upstream license texts, source details and guide. Build.ps1 remains an alternative developer MSIX packaging tool; it is not used by the default download workflow.

## Licensing and verification

Five successful conversions are free. License state is retained under `%LOCALAPPDATA%\ConvertRight`; Windows and Mac identities are separate. Windows paid checkout remains disabled until the corresponding server routes are deployed and verified. This is not yet a verified commercial release.

The CI executes real FFmpeg conversion tests, compiles the native DLL, publishes the portable app, opens its window and checks its controls. Real Windows 11 hardware acceptance is still required for Explorer integration and the complete purchase/refund flow. See InstallationGuide.md.
