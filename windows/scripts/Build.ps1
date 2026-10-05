param(
    [Parameter(Mandatory=$true)][string]$FFmpegDirectory,
    [string]$CertificateThumbprint,
    [switch]$EnablePayments
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'out'
$stage = Join-Path $out 'stage'
$bundle = Join-Path $out 'ConvertRight-Windows-0.1.0-Test'
if (-not (Test-Path (Join-Path $FFmpegDirectory 'ffmpeg.exe'))) { throw 'FFmpegDirectory must contain ffmpeg.exe.' }
if (-not (Test-Path (Join-Path $FFmpegDirectory 'licenses'))) { throw 'Include the complete FFmpeg license texts in a licenses folder.' }
if (-not (Test-Path (Join-Path $FFmpegDirectory 'SOURCE.txt'))) { throw 'Include SOURCE.txt with exact FFmpeg version, build source URL, checksum and corresponding source URL.' }
New-Item -ItemType Directory -Force $out | Out-Null
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
if (Test-Path $bundle) { Remove-Item -Recurse -Force $bundle }
New-Item -ItemType Directory -Force $stage,$bundle | Out-Null
function CheckExit([string]$step) { if ($LASTEXITCODE -ne 0) { throw "$step failed with exit code $LASTEXITCODE." } }
dotnet publish (Join-Path $root 'Worker/ConvertRight.csproj') -c Release -r win-x64 -o $stage
CheckExit 'Worker build'
cmake -S (Join-Path $root 'Shell') -B (Join-Path $out 'shell') -A x64
CheckExit 'Shell configure'
cmake --build (Join-Path $out 'shell') --config Release
CheckExit 'Shell build'
Copy-Item (Join-Path $out 'shell/Release/ConvertRightShell.dll') $stage
Copy-Item (Join-Path $FFmpegDirectory 'ffmpeg.exe') $stage
Copy-Item (Join-Path $FFmpegDirectory 'licenses') (Join-Path $stage 'licenses') -Recurse
Copy-Item (Join-Path $FFmpegDirectory 'SOURCE.txt') (Join-Path $stage 'FFMPEG-SOURCE.txt')
Copy-Item (Join-Path $root 'package/AppxManifest.xml') $stage
if ($EnablePayments) { 'Windows backend deployment verified' | Set-Content (Join-Path $stage 'payments-enabled.txt') }

# Generate simple blue/white app tiles; Windows draws its native menu and dialogs.
Add-Type -AssemblyName System.Drawing
$assets = Join-Path $stage 'Assets'
New-Item -ItemType Directory -Force $assets | Out-Null
foreach ($tile in @(@('StoreLogo.png',50), @('Square44x44Logo.png',44), @('Square150x150Logo.png',150))) {
    $size = [int]$tile[1]
    $bitmap = New-Object System.Drawing.Bitmap($size,$size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::FromArgb(23,108,205))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White,([float]($size/12)))
    $graphics.DrawLines($pen,[System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($size*.28,$size*.52),
        [System.Drawing.PointF]::new($size*.45,$size*.69),
        [System.Drawing.PointF]::new($size*.74,$size*.31)))
    $bitmap.Save((Join-Path $assets $tile[0]),[System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$sdk = Get-ChildItem $sdkRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'x64/makeappx.exe') } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { throw 'Install the Windows 11 SDK.' }
$makeappx = Join-Path $sdk.FullName 'x64/makeappx.exe'
$signtool = Join-Path $sdk.FullName 'x64/signtool.exe'
$certificate = $null
if ($CertificateThumbprint) {
    $certificate = Get-Item "Cert:/CurrentUser/My/$CertificateThumbprint"
    [xml]$manifest = Get-Content (Join-Path $stage 'AppxManifest.xml')
    $manifest.Package.Identity.Publisher = $certificate.Subject
    $manifest.Save((Join-Path $stage 'AppxManifest.xml'))
} else {
    # Reuse the development identity so ordinary rebuilds remain upgradable.
    $certificate = Get-ChildItem Cert:/CurrentUser/My | Where-Object { $_.Subject -eq 'CN=ConvertRight Development' -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(7) } | Select-Object -First 1
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate -Type Custom -Subject 'CN=ConvertRight Development' -FriendlyName 'ConvertRight local test signing' -CertStoreLocation 'Cert:/CurrentUser/My' -KeyUsage DigitalSignature -HashAlgorithm SHA256 -KeyExportPolicy NonExportable -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}')
    }
}
$msix = Join-Path $bundle 'ConvertRight.msix'
& $makeappx pack /d $stage /p $msix /o
CheckExit 'MSIX packaging'
& $signtool sign /fd SHA256 /sha1 $certificate.Thumbprint $msix
CheckExit 'MSIX signing'
Export-Certificate -Cert $certificate -FilePath (Join-Path $bundle 'ConvertRight.cer') | Out-Null
Copy-Item (Join-Path $root 'scripts/Install-Test.ps1') $bundle
Copy-Item (Join-Path $root 'scripts/Install-Test.cmd') $bundle
Copy-Item (Join-Path $root 'scripts/Trust-TestCertificate.ps1') $bundle
Copy-Item (Join-Path $root 'scripts/Uninstall.ps1') $bundle
Copy-Item (Join-Path $root 'TESTING.md') $bundle
Get-FileHash $msix -Algorithm SHA256 | Format-List | Out-File (Join-Path $bundle 'SHA256.txt')
$zip = "$bundle.zip"
Compress-Archive -Path "$bundle/*" -DestinationPath $zip -Force
Write-Host "Created $zip"
