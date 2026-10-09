$ErrorActionPreference = 'Stop'
try {
    $path = Join-Path $PSScriptRoot 'ConvertRight.cer'
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($path)
    if ($certificate.Subject -ne 'CN=ConvertRight Development') { throw 'Use the normal Windows installer for a production certificate.' }
    # This publisher is trusted only for private test packages, not as a root CA.
    Import-Certificate -FilePath $path -CertStoreLocation 'Cert:/LocalMachine/TrustedPeople' | Out-Null
} catch { Write-Error $_; exit 1 }
