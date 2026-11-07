param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$DistDir = 'dist',
    [string]$SourceDir = 'build/windows/x64/runner/Release'
)

# Exécuté sur Windows APRÈS le vrai packaging. Aucun mock de SignTool ni de
# l'installeur : les fichiers livrés sont extraits, installés puis désinstallés.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$dist = (Resolve-Path $DistDir).Path
$source = (Resolve-Path $SourceDir).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ('zuno-package-test-' + [guid]::NewGuid())
$portable = Join-Path $temp 'portable'
$install = Join-Path $temp 'installed'
$setup = Join-Path $dist 'Zuno-Setup.exe'
$signtool = $null
$proof = Get-Content "$dist/build-manifest.json" -Raw | ConvertFrom-Json
$manifest = Get-Content "$dist/version.json" -Raw | ConvertFrom-Json

function Assert-FileHash([string]$Path, [string]$Expected) {
    if (!(Test-Path $Path) -or (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
        throw 'Fichier absent ou empreinte différente dans le paquet Windows.'
    }
}

function Assert-TrustedSignature([string]$Path) {
    & $script:signtool verify /pa /all /tw $Path
    if ($LASTEXITCODE -ne 0) { throw 'Signature Authenticode non valide.' }
    $signature = Get-AuthenticodeSignature $Path
    if ($signature.Status -ne 'Valid' -or !$signature.TimeStamperCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $script:proof.signerThumbprint) {
        throw 'Certificat ou horodatage inattendu dans le paquet Windows.'
    }
}

try {
    if ($proof.commit -ne $Commit -or $manifest.commit -ne $Commit -or
        $manifest.authenticode -ne $proof.signed -or
        $manifest.versionName -ne $proof.version -or $manifest.versionCode -le 0) {
        throw 'Manifestes Windows incohérents avec le commit compilé.'
    }
    Assert-FileHash $setup $manifest.sha256
    if ((Get-Item $setup).Length -ne $manifest.size) { throw "Taille de l'installeur incohérente." }
    foreach ($entry in $proof.files) {
        if ($entry.name -notin @('Zuno-Setup.exe', 'zuno-windows.zip')) { throw 'Nom de fichier inattendu.' }
        Assert-FileHash (Join-Path $dist $entry.name) $entry.sha256
    }
    foreach ($line in Get-Content "$dist/SHA256SUMS.txt") {
        if ($line -notmatch '^([0-9a-f]{64})  (Zuno-Setup\.exe|zuno-windows\.zip)$') {
            throw 'Liste SHA-256 invalide.'
        }
        Assert-FileHash (Join-Path $dist $Matches[2]) $Matches[1]
    }

    New-Item -ItemType Directory -Force -Path $portable | Out-Null
    Expand-Archive "$dist/zuno-windows.zip" $portable
    foreach ($file in 'tv_king.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'sqlite3.dll',
        'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        if (!(Test-Path (Join-Path $portable $file))) { throw "Paquet portable incomplet : $file" }
    }
    if (!(Get-ChildItem $portable -Filter '*mpv*.dll')) { throw 'libmpv absent du portable.' }
    # Comparaison de TOUT le bundle compilé, pas seulement des noms attendus.
    foreach ($file in Get-ChildItem $source -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        Assert-FileHash (Join-Path $portable $relative) (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    if ($proof.signed) {
        $signtool = (Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/signtool.exe" |
            Sort-Object FullName -Descending | Select-Object -First 1).FullName
        Assert-TrustedSignature $setup
        Assert-TrustedSignature "$portable/tv_king.exe"
        # Une signature valide du lanceur ne protège pas une DLL non signée.
        # Chaque PE livré doit être approuvé par la chaîne de confiance Windows.
        $peFiles = @(Get-ChildItem $portable -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' })
        if (!$peFiles) { throw 'Aucun module PE dans le paquet Windows.' }
        foreach ($file in $peFiles) {
            & $signtool verify /pa /all /tw $file.FullName
            if ($LASTEXITCODE -ne 0) { throw "Module Windows non signé ou non fiable : $($file.Name)" }
            $signature = Get-AuthenticodeSignature -FilePath $file.FullName
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.TimeStamperCertificate) {
                throw "Signature Windows invalide ou non horodatée : $($file.Name)"
            }
        }
        # Contrôle négatif réel : un octet de code altéré doit invalider la signature.
        $altered = Join-Path $temp 'altered.exe'
        Copy-Item "$portable/tv_king.exe" $altered
        $stream = [IO.File]::Open($altered, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
        try {
            $stream.Position = 4096
            $byte = $stream.ReadByte()
            if ($byte -lt 0) { throw "Binaire trop court pour le contrôle d'intégrité." }
            $stream.Position = 4096
            $stream.WriteByte([byte]($byte -bxor 1))
        } finally { $stream.Dispose() }
        & $signtool verify /pa $altered *> $null
        if ($LASTEXITCODE -eq 0) { throw 'Un exécutable altéré a été accepté.' }
    }

    # Installer puis lancer les vrais fichiers en mode smoke hors réseau :
    # aucune inscription ni session sur le panel de production.
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER',
        '/LAUNCHAFTERUPDATE=0', '/TASKS=""', "/DIR=`"$install`"")
    $process = Start-Process $setup -ArgumentList $arguments -PassThru
    if (!$process.WaitForExit(120000)) {
        $process.Kill($true)
        throw "L'installation Windows a dépassé deux minutes."
    }
    if ($process.ExitCode -ne 0) { throw "L'installation Windows a échoué." }
    foreach ($file in Get-ChildItem $portable -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($portable, $file.FullName)
        Assert-FileHash (Join-Path $install $relative) (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    # Lancer les VRAIS fichiers installés, et non le répertoire de build.
    & "$PSScriptRoot/smoke.ps1" -ExePath (Join-Path $install 'tv_king.exe')
    $uninstaller = Join-Path $install 'unins000.exe'
    if (!(Test-Path $uninstaller)) { throw 'Désinstalleur absent.' }
    if ($proof.signed) { Assert-TrustedSignature $uninstaller }
    $process = Start-Process $uninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru
    if (!$process.WaitForExit(120000)) {
        $process.Kill($true)
        throw 'La désinstallation Windows a dépassé deux minutes.'
    }
    if ($process.ExitCode -ne 0 -or (Test-Path "$install/tv_king.exe")) {
        throw 'La désinstallation Windows est incomplète.'
    }
    Write-Host 'Paquets Windows vérifiés : empreintes, bundle complet, installation et désinstallation.'
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
