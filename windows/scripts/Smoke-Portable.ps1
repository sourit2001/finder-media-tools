$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $root 'out/ConvertRight-Windows-0.2.0-x64'
foreach ($file in @('ConvertRight.exe','ConvertRightShell.dll','ffmpeg.exe','ffprobe.exe','FFMPEG-SOURCE.txt','InstallationGuide.md')) {
    if (-not (Test-Path (Join-Path $bundle $file))) { throw "Missing $file" }
}
if (Get-ChildItem $bundle -Include *.cmd,*.cer,*.msix -Recurse) { throw 'Portable package contains installer components.' }
$app = Start-Process (Join-Path $bundle 'ConvertRight.exe') -PassThru
try {
    Start-Sleep -Seconds 8
    $app.Refresh()
    if ($app.HasExited -or $app.MainWindowHandle -eq 0) { throw 'Application did not show its window.' }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    foreach ($name in @("Add files$([char]0x2026)",'Convert','Enable right-click menu','Remove right-click menu')) {
        $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$name)
        if (-not $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)) { throw "Missing UI control: $name" }
    }
    Add-Type -AssemblyName System.Drawing
    $bounds = $window.Current.BoundingRectangle
    $bitmap = New-Object System.Drawing.Bitmap([int]$bounds.Width,[int]$bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen([int]$bounds.X,[int]$bounds.Y,0,0,$bitmap.Size)
    $bitmap.Save((Join-Path $root 'out/portable-window.png'))
    $graphics.Dispose(); $bitmap.Dispose()
    Write-Host 'Portable window and controls verified.'
} finally { if (-not $app.HasExited) { $app.Kill() } }
