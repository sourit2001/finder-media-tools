# ConvertRight for Windows 11

Windows 11 x64 implementation, version 0.1.0. Not a verified public release yet.

The native C++ Explorer extension implements `IExplorerCommand`, filtering audio/video
selections and exposing MP3/M4A/WAV subcommands in the modern context menu. It starts
a separate self-contained .NET worker using a UTF-16 request file, avoiding command
line size limits and shell interpolation of media paths. The worker invokes bundled
FFmpeg with a structured argument list. No media is uploaded.

Outputs go beside the source. FFmpeg writes a unique temporary file; successful
outputs are renamed without replacing an existing file. Failures remove temporary
files. Files without audio fail individually. The worker serializes conversion
batches so free-trial counts cannot race between Explorer requests.

## Build on Windows

Install Visual Studio 2022 or newer with Desktop development with C++, Windows 11
SDK, CMake, and the .NET 10 SDK. The actual installer includes the .NET runtime;
end users do not need these development tools.

Supply a Windows x64 FFmpeg distribution in a local folder:

```
vendor/ffmpeg/ffmpeg.exe
vendor/ffmpeg/licenses/<complete license files>
vendor/ffmpeg/SOURCE.txt
```

`SOURCE.txt` must identify the exact version, build download URL, SHA-256,
build configuration, corresponding source download and licenses. The build script
does not download an unpinned third-party binary. FFmpeg must include `libmp3lame`,
AAC and PCM encoding. Check the chosen build's complete distribution requirements
before publishing; the macOS FFmpeg binary cannot be used on Windows.

From PowerShell in `windows`:

```powershell
.\scripts\Prepare-FFmpeg.ps1
dotnet run --project tests/Conversion.Tests.csproj -- "C:\path\to\ffmpeg.exe"
.\scripts\Build.ps1 -FFmpegDirectory "C:\path\to\ffmpeg-folder"
```

`Prepare-FFmpeg.ps1` prepares a pinned Gyan FFmpeg 9.0.2 essentials build, checks
the archive SHA-256 from its release metadata, and retains upstream documents and
build configuration. You can also supply your own suitably documented FFmpeg build.

The build produces `out/ConvertRight-Windows-0.1.0-Test.zip`, containing a signed
MSIX, exported public test certificate, install/uninstall scripts and test guide.
The private key stays in the builder's certificate store and is never exported.
The shell build treats compiler warnings as errors; MakeAppx validates the manifest.

## Test and production signing

Test builds are signed by `CN=ConvertRight Development`. Installation trusts that
publisher in **Local Machine / Trusted People**, requiring a Windows administrator
prompt. No root CA is installed. The app package is then installed for the original
user. This test flow is not the public distribution experience.

For production, use a trusted signing certificate via `-CertificateThumbprint` or
integrate a managed signing service. Production installation should use Windows App
Installer directly; do not ship the development certificate trust scripts.
Changing Publisher changes package identity, so plan the beta-to-production transition.

## Purchases

Each Windows user installation has a permanent `windows-<UUID>` ID in
`%LOCALAPPDATA%\ConvertRight\license-v1.json`, independent of macOS IDs. The server
derives the payment callback scheme from the stored installation ID; Windows uses
`convertright://unlock`, macOS retains `finderaudiotools://unlock`.

Five successful file conversions are free. Ordinary updates/reinstalls retain
usage and purchase identity. The paid license is checked after seven days, with
a fourteen-day maximum offline window after a successful check, matching the Mac
implementation. Like the current Mac client, the trial uses local state; it is not
tamper-resistant and it is scoped to a user installation rather than hardware.

Payments are disabled by default in test packages. Only use `-EnablePayments` after
deploying and verifying the modified checkout, return, activation and status routes
from the sibling `landing-page` project. No database migration or new Creem product
is required: independent installation IDs produce separate purchases for each OS.

## Acceptance

Read [TESTING.md](TESTING.md). Compile success is not proof that Explorer loads the
extension; final acceptance requires installation and real right-click conversions
on a Windows 11 x64 computer, plus a verified checkout/refund flow before publishing.
