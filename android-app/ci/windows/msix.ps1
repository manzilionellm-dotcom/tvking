param(
  [string]$SourceDir = 'build/windows/x64/runner/Release',
  [string]$OutFile = 'dist/msix/ZUNO-Store.msix',
  [string]$Version = '113.0.3.0',
  # TODO(Partner Center) : valeurs réelles après réservation du nom ZUNO.
  [string]$IdentityName = 'ZUNO.PLACEHOLDER',
  [string]$Publisher = 'CN=00000000-0000-0000-0000-000000000000',
  [string]$PublisherDisplayName = 'ZUNO (editeur a definir)',
  # Copie de TEST : signée par un certificat auto-signé de ce runner.
  [switch]$TestSign
)
# Paquet MSIX du MÊME dossier Release que l'installeur (runtime VC++ et
# sqlite3.dll inclus à côté de l'exe). Sans -TestSign : non signé, prêt pour
# l'envoi dans Partner Center (le Store signe lui-même).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw "Version MSIX invalide (dernier nombre = 0 pour le Store) : $Version" }
$rel = (Resolve-Path $SourceDir).Path
foreach ($f in 'tv_king.exe', 'flutter_windows.dll', 'data/app.so', 'sqlite3.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  if (!(Test-Path (Join-Path $rel $f))) { throw "Dossier Release incomplet : $f" }
}
$kit = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64" -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName 'makeappx.exe') } | Sort-Object Name -Descending | Select-Object -First 1
if (!$kit) { throw 'makeappx.exe introuvable (Windows SDK)' }
$makeappx = Join-Path $kit.FullName 'makeappx.exe'
$makepri = Join-Path $kit.FullName 'makepri.exe'
$signtool = Join-Path $kit.FullName 'signtool.exe'
Write-Host "Windows SDK : $($kit.FullName)"

$stage = Join-Path ([IO.Path]::GetTempPath()) ('zuno-msix-' + [guid]::NewGuid())
New-Item -ItemType Directory $stage | Out-Null
try {
  Copy-Item "$rel\*" $stage -Recurse -Force
  # Rien d'un installeur Inno dans le paquet Store.
  Get-ChildItem $stage -Filter 'unins*' -ErrorAction SilentlyContinue | Remove-Item -Force
  Copy-Item "$PSScriptRoot/msix/Assets" (Join-Path $stage 'Assets') -Recurse -Force
  $xml = Get-Content "$PSScriptRoot/msix/AppxManifest.template.xml" -Raw -Encoding UTF8
  $esc = { param($v) [Security.SecurityElement]::Escape($v) }
  $xml = $xml.Replace('__IDENTITY_NAME__', (& $esc $IdentityName)).Replace('__PUBLISHER__', (& $esc $Publisher)).
    Replace('__PUBLISHER_DISPLAY_NAME__', (& $esc $PublisherDisplayName)).Replace('__VERSION__', $Version)
  [IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $xml, (New-Object Text.UTF8Encoding $false))

  # Index des ressources (logos, langues fr-FR / en-US).
  $cfg = Join-Path ([IO.Path]::GetTempPath()) "priconfig-$([guid]::NewGuid()).xml"
  & $makepri createconfig /cf $cfg /dq fr-FR_en-US /pv 10.0.0 /o | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "makepri createconfig : $LASTEXITCODE" }
  & $makepri new /pr $stage /cf $cfg /mn (Join-Path $stage 'AppxManifest.xml') /of (Join-Path $stage 'resources.pri') /o | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "makepri new : $LASTEXITCODE" }

  New-Item -ItemType Directory -Force (Split-Path $OutFile) | Out-Null
  & $makeappx pack /d $stage /p $OutFile /o | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "makeappx pack : $LASTEXITCODE" }

  if ($TestSign) {
    $cert = New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyUsage DigitalSignature `
      -FriendlyName 'ZUNO MSIX test (CI)' -CertStoreLocation 'Cert:\CurrentUser\My' `
      -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $cer = Join-Path ([IO.Path]::GetTempPath()) 'zuno-msix-test.cer'
    Export-Certificate -Cert $cert -FilePath $cer | Out-Null
    # Confiance limitée à CE runner éphémère, pour Add-AppxPackage.
    Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /s My $OutFile | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "signtool : $LASTEXITCODE" }
    & $signtool verify /pa $OutFile | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'signature MSIX de test non vérifiée' }
    Copy-Item $cer ([IO.Path]::ChangeExtension($OutFile, '.cer')) -Force
  }
  $item = Get-Item $OutFile
  $hash = (Get-FileHash $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "MSIX : $($item.FullName) $($item.Length) octets sha256 $hash (Identity=$IdentityName ; Publisher=$Publisher ; Version=$Version ; signé test=$TestSign)"
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
