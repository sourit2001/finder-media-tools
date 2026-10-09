param([Parameter(Mandatory=$true)][string]$FFmpegDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'out'
$bundle = Join-Path $out 'ConvertRight-Windows-0.1.0-x64'
if (Test-Path $bundle) { Remove-Item -Recurse -Force $bundle }
New-Item -ItemType Directory -Force $bundle | Out-Null
function CheckExit([string]$step) { if ($LASTEXITCODE -ne 0) { throw "$step failed with exit code $LASTEXITCODE." } }
dotnet publish (Join-Path $root 'Worker/ConvertRight.csproj') -c Release -r win-x64 -o $bundle
CheckExit 'Application build'
cmake -S (Join-Path $root 'Shell') -B (Join-Path $out 'shell') -A x64
CheckExit 'Shell configure'
cmake --build (Join-Path $out 'shell') --config Release
CheckExit 'Shell build'
Copy-Item (Join-Path $out 'shell/Release/ConvertRightShell.dll') $bundle
Copy-Item (Join-Path $FFmpegDirectory 'ffmpeg.exe') $bundle
Copy-Item (Join-Path $FFmpegDirectory 'licenses') (Join-Path $bundle 'licenses') -Recurse
Copy-Item (Join-Path $FFmpegDirectory 'SOURCE.txt') (Join-Path $bundle 'FFMPEG-SOURCE.txt')
Copy-Item (Join-Path $root 'InstallationGuide.md') $bundle
$hashes = Get-ChildItem $bundle -File | Get-FileHash -Algorithm SHA256
$hashes | Format-List | Out-File (Join-Path $bundle 'SHA256.txt')
$zip = "$bundle.zip"
Compress-Archive -Path $bundle -DestinationPath $zip -Force
Write-Host "Created $zip"
