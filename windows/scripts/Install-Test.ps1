$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Version.Build -lt 22000 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This test build requires Windows 11 x64 (Intel or AMD).' }
    $certificateFile = Join-Path $PSScriptRoot 'ConvertRight.cer'
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificateFile)
    Write-Host "Test package publisher: $($certificate.Subject)"
    Write-Host "Certificate fingerprint: $($certificate.Thumbprint)"
    # Only certificate trust is elevated; install the app for the original user.
    if (-not (Test-Path "Cert:/LocalMachine/TrustedPeople/$($certificate.Thumbprint)")) {
        $trustScript = Join-Path $PSScriptRoot 'Trust-TestCertificate.ps1'
        $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$trustScript`""
        if ($process.ExitCode -ne 0) { throw 'Test certificate trust was cancelled or failed.' }
    }
    Add-AppxPackage -Path (Join-Path $PSScriptRoot 'ConvertRight.msix')
    Write-Host 'Installed. Close and reopen File Explorer, then right-click an audio or video file.'
    Write-Host 'If the menu is missing, sign out and sign back in.'
} catch { Write-Host $_ -ForegroundColor Red; exit 1 }
