$ErrorActionPreference = 'Stop'
Get-AppxPackage -Name 'ConvertRight.Windows' | Remove-AppxPackage
Write-Host 'ConvertRight uninstalled. Purchase identity and trial usage were retained for reinstall.'
if (Test-Path (Join-Path $PSScriptRoot 'ConvertRight.cer')) {
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $PSScriptRoot 'ConvertRight.cer'))
    if ($certificate.Subject -eq 'CN=ConvertRight Development') {
        $entry = "Cert:/LocalMachine/TrustedPeople/$($certificate.Thumbprint)"
        if (Test-Path $entry) { Write-Host "Test certificate remains in LocalMachine/TrustedPeople: $($certificate.Thumbprint). Remove this certificate in certlm.msc after testing (administrator required)." }
    }
}
