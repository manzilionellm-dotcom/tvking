param([string]$Setup = 'dist/Zuno-Setup.exe')
# Smoke EN LIGNE comme chez un client : installeur par défaut (Program Files),
# réseau réel, et mise à jour PAR-DESSUS les versions déjà publiées et lancées
# (septembre 106 puis 113.0.2). La vraie interface doit apparaître à chaque fois.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = 'manzilionellm-dotcom/tvking'
$work = Join-Path $env:RUNNER_TEMP 'zuno-online'
New-Item -ItemType Directory -Force $work | Out-Null
$exe = Join-Path ${env:ProgramFiles} 'Zuno\tv_king.exe'
$Setup = (Resolve-Path $Setup).Path

function Install-Zuno([string]$installer) {
  $p = Start-Process $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LAUNCHAFTERUPDATE=0' -PassThru
  if (!$p.WaitForExit(180000)) { $p.Kill($true); throw 'installation > 3 min' }
  if ($p.ExitCode -ne 0) { throw "installation code $($p.ExitCode)" }
  if (!(Test-Path $exe)) { throw "tv_king.exe absent : $exe" }
}
function Clear-State {
  Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
  foreach ($p in @("$env:APPDATA\Zuno", "$env:APPDATA\com.sevenmotion", "$env:LOCALAPPDATA\com.sevenmotion")) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
  }
}
function Start-Old([string]$path, [int]$seconds) {
  $p = Start-Process $path -WorkingDirectory (Split-Path $path) -PassThru
  Start-Sleep -Seconds $seconds
  if (!$p.HasExited) { $p.Kill($true); $p.WaitForExit() }
}


function Set-CorruptPreferences {
  # Fichier tronqué par une coupure / fermeture forcée pendant l'écriture.
  $dir = Join-Path $env:APPDATA 'Zuno\Zuno'
  New-Item -ItemType Directory -Force $dir | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $dir 'shared_preferences.json'), [byte[]]::new(1532))
}
function Set-DocumentsReadOnly([bool]$on) {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  $who = "$env:USERDOMAIN\$env:USERNAME"
  if ($on) {
    Get-ChildItem $docs -Filter 'tv_king.db*' -Force -ErrorAction SilentlyContinue | Remove-Item -Force
    icacls $docs /deny "${who}:(OI)(CI)(W,D,DC)" | Out-Null
  } else { icacls $docs /remove:d $who | Out-Null }
}

# 1) PC neuf, installeur par défaut, réseau réel.
Clear-State
Install-Zuno $Setup
& "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'neuf-en-ligne'
# 2) Relance immédiate (état créé par le premier lancement).
& "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'relance-en-ligne'

# 3) Cas réel : 113.0.2 installée et lancée, puis mise à jour 113.0.3.
Clear-State
$old = Join-Path $work 'Zuno-Setup-113.0.2.exe'
Invoke-WebRequest "https://github.com/$repo/releases/download/zuno-windows-113.0.2/Zuno-Setup.exe" -OutFile $old
Install-Zuno $old
Start-Old $exe 30
Install-Zuno $Setup
& "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'maj-depuis-113.0.2'

# 4) Données de la version de septembre (106) déjà lancée.
Clear-State
$zip = Join-Path $work 'zuno-windows-106.zip'
Invoke-WebRequest "https://github.com/$repo/releases/download/zuno-windows/zuno-windows.zip" -OutFile $zip
Expand-Archive $zip (Join-Path $work 'v106') -Force
Start-Old (Get-ChildItem (Join-Path $work 'v106') -Recurse -Filter tv_king.exe | Select-Object -First 1).FullName 25
& "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'donnees-106'

# 5) Préférences illisibles : mises de côté, interface atteinte.
Clear-State
Set-CorruptPreferences
& "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'preferences-illisibles'
if (!(Get-ChildItem (Join-Path $env:APPDATA 'Zuno\Zuno') -Filter 'shared_preferences.json.illisible-*')) { throw 'Préférences illisibles non mises de côté.' }
# 6) Documents non inscriptible : base impossible, interface quand même.
Clear-State
try { Set-DocumentsReadOnly $true; & "$PSScriptRoot/smoke.ps1" -ExePath $exe -Online -Label 'documents-lecture-seule' }
finally { Set-DocumentsReadOnly $false }

$un = Join-Path ${env:ProgramFiles} 'Zuno\unins000.exe'
if (Test-Path $un) { Start-Process $un -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait }
Write-Host 'Smoke en ligne OK : 6 scénarios, vraie interface à chaque lancement.'
