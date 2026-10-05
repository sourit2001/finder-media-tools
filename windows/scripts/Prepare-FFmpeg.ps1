$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$vendor = Join-Path $root 'vendor/ffmpeg'
$archive = Join-Path $root 'vendor/ffmpeg-9.0.2-essentials_build.zip'
$url = 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip'
$expected = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
New-Item -ItemType Directory -Force (Split-Path $archive) | Out-Null
if (-not (Test-Path $archive)) {
    & curl.exe --fail --location --retry 3 --max-time 300 --output $archive $url
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg archive download failed.' }
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'FFmpeg archive checksum mismatch.' }
$expanded = Join-Path $root 'vendor/expanded'
if (Test-Path $expanded) { Remove-Item -Recurse -Force $expanded }
Expand-Archive $archive $expanded
$binary = Get-ChildItem $expanded -Filter 'ffmpeg.exe' -Recurse | Select-Object -First 1
if (-not $binary) { throw 'FFmpeg binary was not found in the archive.' }
New-Item -ItemType Directory -Force $vendor,(Join-Path $vendor 'licenses') | Out-Null
Copy-Item $binary.FullName (Join-Path $vendor 'ffmpeg.exe') -Force
$distribution = Split-Path (Split-Path $binary.FullName)
# Preserve all upstream notices and documentation instead of just the executable.
Get-ChildItem $distribution | Where-Object { $_.Name -ne 'bin' } | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $vendor 'licenses') -Recurse -Force
}
$configuration = & (Join-Path $vendor 'ffmpeg.exe') -hide_banner -buildconf 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Bundled FFmpeg could not run.' }
@"
FFmpeg 9.0.2 essentials Windows x64 build by Gyan Doshi
Archive: $url
SHA256: $expected
Upstream FFmpeg source commit: https://github.com/FFmpeg/FFmpeg/commit/946fcce07b
FFmpeg source archive: https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n9.0.2.zip
Build distributor and dependency information: https://www.gyan.dev/ffmpeg/builds/
Build repository: https://github.com/GyanD/codexffmpeg/tree/9.0.2
Upstream legal information: https://ffmpeg.org/legal.html
License and documentation files from the upstream archive are included unchanged.
This executable runs as a separate process. Review corresponding source availability
for FFmpeg and enabled external libraries before a public distribution.

$configuration
"@ | Set-Content (Join-Path $vendor 'SOURCE.txt')
Write-Host "Prepared pinned FFmpeg in $vendor"
