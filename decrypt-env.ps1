<#
Decrypt your team's .env.enc (AES-256, sent by the organizers) into a .env you can use.

Usage:
  pwsh ./decrypt-env.ps1                          # auto-finds the single *.env.enc next to this script
  pwsh ./decrypt-env.ps1 -In rg-team-05.env.enc   # or point at a specific file
  pwsh ./decrypt-env.ps1 -In rg-team-05.env.enc -Out .env

You are prompted for the password (ask your coach; it is shared separately from the file).
No Azure sign-in, no extra tools - just PowerShell 7.
#>
param(
    [string]$In,
    [string]$Out = '.env'
)

if (-not $In) {
    $encs = @(Get-ChildItem -Path $PSScriptRoot -Filter *.env.enc -File)
    if ($encs.Count -eq 1) { $In = $encs[0].FullName }
    elseif ($encs.Count -eq 0) { Write-Host 'No .env.enc found here. Save your team file next to this script, or pass -In <file>.' -ForegroundColor Red; exit 1 }
    else { Write-Host 'Multiple .env.enc files found; choose one with -In <file>:' -ForegroundColor Red; $encs.Name | ForEach-Object { Write-Host "  $_" }; exit 1 }
}
if (-not (Test-Path $In)) { Write-Host "Not found: $In" -ForegroundColor Red; exit 1 }

$sec = Read-Host 'Password (from your coach)' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

# Format written by the organizers' protect-envs.ps1: base64( salt[16] + iv[16] + AES-256-CBC ciphertext ).
$b = [Convert]::FromBase64String((Get-Content -Raw $In))
$salt = [byte[]]$b[0..15]; $iv = [byte[]]$b[16..31]; $ct = [byte[]]$b[32..($b.Length - 1)]
$kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new([Text.Encoding]::UTF8.GetBytes($pw), $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
$aes = [Security.Cryptography.Aes]::Create(); $aes.Key = $kdf.GetBytes(32); $aes.IV = $iv
try { $plain = $aes.CreateDecryptor().TransformFinalBlock($ct, 0, $ct.Length) }
catch { Write-Host 'Wrong password or corrupt file.' -ForegroundColor Red; exit 1 }
[IO.File]::WriteAllBytes($Out, $plain)
Write-Host "Decrypted -> $Out. You can now run verify-lab.ps1, the app, or the notebook." -ForegroundColor Green
