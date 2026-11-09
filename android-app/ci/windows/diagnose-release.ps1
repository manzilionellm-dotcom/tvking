param(
  [string]$Tag = 'zuno-windows-113.0.2',
  [string]$LegacyTag = 'zuno-windows',
  [int]$Seconds = 35
)
# Diagnostic : reproduit l'installation RÉELLE d'une release publiée
# (installeur, Program Files, réseau ACTIF) et capture la trace de démarrage
# (stdout Dart : [ZunoStartup] + [CrashReporting]) et une capture d'écran.
# Ne publie rien. Le démarrage normal peut contacter le panel, comme sur un PC.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$repo = 'manzilionellm-dotcom/tvking'
$out = Join-Path $env:RUNNER_TEMP 'zuno-diag'
New-Item -ItemType Directory -Force $out | Out-Null
$docs = [Environment]::GetFolderPath('MyDocuments')

function Get-Asset([string]$tag, [string]$name) {
  $dest = Join-Path $out "$tag-$name"
  Invoke-WebRequest "https://github.com/$repo/releases/download/$tag/$name" -OutFile $dest
  Write-Host "$tag/$name : $((Get-Item $dest).Length) octets, sha256 $((Get-FileHash $dest).Hash)"
  return $dest
}

function Clear-ZunoState {
  Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
  foreach ($p in @("$env:APPDATA\com.sevenmotion", "$env:LOCALAPPDATA\com.sevenmotion", "$env:LOCALAPPDATA\Zuno\logs")) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
  }
  Get-ChildItem $docs -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.db$|\.db-|zuno|tv_king|cinema' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Show-State([datetime]$since) {
  foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA, $docs)) {
    Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -ge $since -and $_.FullName -notmatch '\\(Temp|Microsoft|NuGet|pip|npm|Packages)\\' } |
      Select-Object -First 40 | ForEach-Object { Write-Host "  écrit : $($_.FullName) ($($_.Length) o)" }
  }
}

function Invoke-Zuno([string]$exe, [string]$label, [int]$seconds, [string[]]$arguments = @()) {
  Write-Host "::group::$label"
  $since = Get-Date
  $so = Join-Path $out "$label.stdout.log"; $se = Join-Path $out "$label.stderr.log"
  $start = @{ FilePath = $exe; WorkingDirectory = (Split-Path $exe); PassThru = $true
              RedirectStandardOutput = $so; RedirectStandardError = $se }
  if ($arguments.Count) { $start.ArgumentList = $arguments }
  $p = Start-Process @start
  Start-Sleep -Seconds $seconds
  $p.Refresh()
  $alive = !$p.HasExited
  $title = if ($alive) { $p.MainWindowTitle } else { "(sorti code $($p.ExitCode))" }
  $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $bmp.Save((Join-Path $out "$label.png")); $bmp.Dispose()
  if ($alive) { $p.Kill($true); $p.WaitForExit() }
  Write-Host "vivant=$alive fenêtre='$title'"
  $lines = @(Get-Content $so -ErrorAction SilentlyContinue) + @(Get-Content $se -ErrorAction SilentlyContinue)
  $lines | Write-Host
  $failed = @($lines | Where-Object { $_ -match '\.failed|\[CrashReporting\]|Exception|Error' })
  $reached = [bool]($lines | Where-Object { $_ -match '\] \d+ms runApp$' })
  Write-Host "RÉSUMÉ $label : runApp atteint=$reached ; lignes d'erreur=$($failed.Count)"
  $failed | ForEach-Object { Write-Host "  ERREUR> $_" }
  Show-State $since
  Write-Host '::endgroup::'
  "$label | runApp=$reached | erreurs=$($failed.Count) | $($failed | Select-Object -First 3)" |
    Out-File (Join-Path $out 'summary.txt') -Append -Encoding utf8
}

$setup = Get-Asset $Tag 'Zuno-Setup.exe'
$legacyZip = Get-Asset $LegacyTag 'zuno-windows.zip'
$legacy = Join-Path $out 'legacy'
Expand-Archive $legacyZip $legacy -Force
$legacyExe = (Get-ChildItem $legacy -Recurse -Filter tv_king.exe | Select-Object -First 1).FullName

$proc = Start-Process $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LAUNCHAFTERUPDATE=0' -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "installeur $Tag code $($proc.ExitCode)" }
$exe = Join-Path ${env:ProgramFiles} 'Zuno\tv_king.exe'
if (!(Test-Path $exe)) { throw "tv_king.exe absent de $exe" }
Write-Host "Installé : $exe"

# 1) Premier lancement, PC neuf, réseau actif.
Clear-ZunoState
Invoke-Zuno $exe 'A-neuf-reseau' $Seconds
# 2) Deuxième lancement (état créé par le premier).
Invoke-Zuno $exe 'B-relance' $Seconds
# 3) Mise à jour depuis la version de septembre déjà lancée (cas réel de Lionel).
Clear-ZunoState
Invoke-Zuno $legacyExe 'C0-ancienne-106' 25
Invoke-Zuno $exe 'C-apres-106' $Seconds
# 4) Accès contrôlé aux dossiers (Defender) : Documents non inscriptible pour une app inconnue.
Clear-ZunoState
try {
  Set-MpPreference -EnableControlledFolderAccess Enabled
  Invoke-Zuno $exe 'D-acces-controle' $Seconds
} catch { Write-Host "Accès contrôlé indisponible : $($_.Exception.Message)" }
finally { Set-MpPreference -EnableControlledFolderAccess Disabled -ErrorAction SilentlyContinue }
Get-Content (Join-Path $out 'summary.txt') | Write-Host
