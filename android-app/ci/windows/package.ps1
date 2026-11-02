param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')][string]$Version,
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$Build,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$SourceDir = 'build/windows/x64/runner/Release',
    [switch]$RequireSignature
)

# Une revue peut compiler sans certificat. Une livraison client ne peut jamais
# devenir « signée » parce qu'une somme SHA-256 existe : Authenticode est exigé.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$rel = (Resolve-Path $SourceDir).Path
$dist = (New-Item -ItemType Directory -Force -Path dist).FullName
$certificateFile = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.pfx')
$imported = @()
$existing = @()
$certificate = $null
$signtool = $null
$signed = $false
$timestamp = 'http://timestamp.digicert.com'

function Assert-Signature([string]$Path) {
    & $script:signtool verify /pa /all /tw $Path
    if ($LASTEXITCODE -ne 0) { throw 'Signature Authenticode ou horodatage non valide.' }
    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Thumbprint -ne $script:certificate.Thumbprint -or
        $null -eq $signature.TimeStamperCertificate) {
        throw 'Le fichier ne porte pas la signature horodatée du certificat attendu.'
    }
}

try {
    foreach ($file in 'tv_king.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat') {
        if (!(Test-Path (Join-Path $rel $file))) { throw "Binaire incomplet : $file" }
    }
    if (!(Get-ChildItem $rel -Filter '*mpv*.dll')) { throw 'Lecteur libmpv absent.' }

    # Flutter exige aussi le runtime Visual C++. Le copier depuis les éléments
    # redistribuables de VS évite un EXE qui ne s'ouvre que sur un PC développeur.
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Runtime Visual C++ redistribuable introuvable.' }
    $crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (!$crt) { throw 'Dossier CRT x64 absent.' }
    Copy-Item "$($crt.FullName)/*.dll" $rel -Force
    foreach ($file in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        if (!(Test-Path (Join-Path $rel $file))) { throw "Runtime incomplet : $file" }
    }

    $encoded = $env:WINDOWS_SIGNING_CERTIFICATE_BASE64
    $thumbprint = ([string]$env:WINDOWS_SIGNING_CERTIFICATE_THUMBPRINT -replace '\s', '').ToUpperInvariant()
    if (!$encoded) {
        if ($RequireSignature) { throw 'Certificat Windows absent : publication signée impossible.' }
        Write-Warning 'Paquet de revue NON SIGNÉ. Aucune publication client autorisée.'
    } else {
        if ($thumbprint -notmatch '^[0-9A-F]{40}$') { throw 'Empreinte du certificat Windows absente ou invalide.' }
        $signtool = (Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/signtool.exe" |
            Sort-Object FullName -Descending | Select-Object -First 1).FullName
        if (!$signtool) { throw 'SignTool du SDK Windows absent.' }
        $existing = @(Get-ChildItem Cert:\CurrentUser\My | ForEach-Object Thumbprint)
        try {
            [IO.File]::WriteAllBytes($certificateFile, [Convert]::FromBase64String($encoded))
            $password = if ($env:WINDOWS_SIGNING_CERTIFICATE_PASSWORD) {
                ConvertTo-SecureString -String $env:WINDOWS_SIGNING_CERTIFICATE_PASSWORD -AsPlainText -Force
            } else { [Security.SecureString]::new() }
            $imported = @(Import-PfxCertificate -FilePath $certificateFile -CertStoreLocation Cert:\CurrentUser\My -Password $password -Exportable:$false)
        } catch {
            # Ne jamais recopier une valeur de secret dans les logs CI.
            throw 'Import du certificat Windows impossible.'
        }
        $certificate = $imported | Where-Object { $_.Thumbprint -eq $thumbprint -and $_.HasPrivateKey } | Select-Object -First 1
        if (!$certificate -or $certificate.NotAfter -le (Get-Date) -or $certificate.NotBefore -gt (Get-Date) -or
            !($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId.Value -eq '1.3.6.1.5.5.7.3.3' })) {
            throw 'Certificat de signature de code valide avec clé privée requis.'
        }
        & $signtool sign /sha1 $thumbprint /s My /fd SHA256 /tr $timestamp /td SHA256 "$rel/tv_king.exe"
        if ($LASTEXITCODE -ne 0) { throw 'Signature de Zuno impossible.' }
        Assert-Signature "$rel/tv_king.exe"
        $signed = $true
    }

    # L'exécutable signé et TOUTES ses dépendances sont conservés dans le ZIP.
    Compress-Archive -Path "$rel/*" -DestinationPath "$dist/zuno-windows.zip" -Force
    $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (!(Test-Path $iscc)) {
        choco install innosetup -y --no-progress | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Installation du compilateur Inno Setup impossible.' }
    }
    if (!(Test-Path $iscc)) { throw 'Inno Setup introuvable.' }
    $compilerArgs = @("/DAppVersion=$Version", "/DSourceDir=$rel", "/O$dist")
    if ($signed) {
        # $f et $q sont interprétés par Inno Setup, jamais par PowerShell.
        # Aucun mot de passe dans la ligne de commande du compilateur.
        $command = '$q' + $signtool + '$q sign /sha1 ' + $thumbprint +
            ' /s My /fd SHA256 /tr ' + $timestamp + ' /td SHA256 $f'
        $compilerArgs += @('/DUseAuthenticode=1', "/Szuno=$command")
    }
    & $iscc @compilerArgs "$PSScriptRoot/zuno.iss"
    if ($LASTEXITCODE -ne 0) { throw 'Compilation de l’installeur impossible.' }
    $setup = Join-Path $dist 'Zuno-Setup.exe'
    if ($signed) { Assert-Signature $setup }

    $sha = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $setup).Length
    $zipHash = (Get-FileHash "$dist/zuno-windows.zip" -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        versionCode = $Build
        versionName = $Version
        url = 'https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/Zuno-Setup.exe'
        sha256 = $sha
        size = $size
        mandatory = $false
        commit = $Commit
        authenticode = $signed
    }
    $manifest | ConvertTo-Json | Set-Content "$dist/version.json" -Encoding utf8NoBOM
    [ordered]@{
        commit = $Commit
        version = $Version
        signed = $signed
        signaturePolicy = 'Authenticode /pa; SHA-256; RFC 3161 timestamp'
        signerThumbprint = $(if ($signed) { $thumbprint } else { $null })
        files = @(
            @{ name = 'Zuno-Setup.exe'; sha256 = $sha; size = $size },
            @{ name = 'zuno-windows.zip'; sha256 = $zipHash; size = (Get-Item "$dist/zuno-windows.zip").Length }
        )
    } | ConvertTo-Json -Depth 4 | Set-Content "$dist/build-manifest.json" -Encoding utf8NoBOM
    @("$sha  Zuno-Setup.exe", "$zipHash  zuno-windows.zip") |
        Set-Content "$dist/SHA256SUMS.txt" -Encoding ascii
    if ($env:GITHUB_ENV) {
        @("SETUP_SHA=$sha", "SETUP_SIZE=$size", "WINDOWS_SIGNED=$($signed.ToString().ToLowerInvariant())") |
            Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    }
} finally {
    Remove-Item $certificateFile -Force -ErrorAction SilentlyContinue
    foreach ($cert in $imported) {
        if ($cert.Thumbprint -notin $existing) {
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item Env:WINDOWS_SIGNING_CERTIFICATE_BASE64 -ErrorAction SilentlyContinue
    Remove-Item Env:WINDOWS_SIGNING_CERTIFICATE_PASSWORD -ErrorAction SilentlyContinue
}
