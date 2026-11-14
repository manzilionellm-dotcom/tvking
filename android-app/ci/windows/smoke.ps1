param(
  [string]$ExePath = 'build/windows/x64/runner/Release/tv_king.exe',
  # Réseau RÉEL (démarrage client normal) au lieu du HTTP bloqué.
  [switch]$Online,
  [string]$Label = 'smoke'
)

# Le binaire démarre vraiment. Le mode smoke bloque tout HTTP Dart avant
# le bootstrap : aucune inscription d'appareil sur le panel de production.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$exe = (Resolve-Path $ExePath).Path
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  if (!(Test-Path (Join-Path (Split-Path $exe) $dll))) { throw "Runtime app-local absent : $dll" }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('zuno-smoke-' + [guid]::NewGuid())
New-Item -ItemType Directory $temp | Out-Null
$marker = Join-Path $temp 'ready.txt'
$process = $null
$log = Join-Path $env:LOCALAPPDATA 'Zuno\logs\startup.log'
$logStart = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
try {
  $process = Start-Process $exe -WorkingDirectory (Split-Path $exe) `
    -ArgumentList @($(if ($Online) { '--zuno-smoke-online' } else { '--zuno-smoke' }), "`"$marker`"") -PassThru `
    -RedirectStandardOutput (Join-Path $temp 'stdout.log') `
    -RedirectStandardError (Join-Path $temp 'stderr.log')
  $windowSeen = $false
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw "ZUNO a quitté pendant le smoke test (code $($process.ExitCode))." }
    if ($process.MainWindowHandle -ne 0 -and $process.MainWindowTitle -match 'Zuno') { $windowSeen = $true }
    if ((Test-Path $marker) -and (Get-Content $marker -Raw) -eq 'error') { throw 'Erreur Flutter pendant le bootstrap Windows.' }
  }
  if (!$windowSeen) { throw 'Aucune fenêtre Zuno créée en 20 secondes.' }
  if (!(Test-Path $marker) -or (Get-Content $marker -Raw) -ne 'ready') {
    throw 'La vraie interface Flutter ne confirme pas sa première image en 20 secondes.'
  }
  # Le runner possède aussi VC++ : prouver que CE processus charge les DLL
  # livrées à côté de l'EXE, pas celles préinstallées dans System32.
  $modules = @((Get-Process -Id $process.Id).Modules)
  foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $loaded = @($modules | Where-Object { $_.ModuleName -ieq $dll })
    $expected = Join-Path (Split-Path $exe) $dll
    if ($loaded.Count -ne 1 -or $loaded[0].FileName -ine $expected) {
      throw "Runtime non chargé depuis le dossier app-local : $dll"
    }
    Write-Host "DLL app-local vérifiée : $dll"
  }
  if (!(Test-Path $log)) { throw "Journal absent : $log" }
  $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); $fs.Seek($logStart, 'Begin') | Out-Null
  $run = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Dispose()
  if ($run -notmatch 'realUi\.frame') { throw 'startup.log ne confirme pas la première image de la vraie interface.' }
  if ($run -match 'bootstrap\.failed|bootstrap\.slow') { throw 'startup.log signale un échec de démarrage.' }
  $skipped = @($run -split "`r?`n" | Where-Object { $_ -match '\.(failed|timeout)' })
  Write-Host "startup.log ($log) : vraie interface atteinte ; étapes sautées sans bloquer : $($skipped.Count)"
  $skipped | ForEach-Object { Write-Host "  SAUTÉ> $_" }
  $mode = if ($Online) { 'Réseau RÉEL.' } else { 'Réseau bloqué.' }
  Write-Host "Smoke OK [$Label] : processus vivant 20 s, fenêtre Zuno, vraie interface (accueil/connexion) affichée. $mode"
} finally {
  if ($null -ne $process -and !$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
  if (Test-Path $log) { Write-Host "----- $log -----"; Get-Content $log -Tail 120 | Write-Host }
  foreach ($std in @('stdout.log', 'stderr.log')) {
    $file = Join-Path $temp $std
    if (Test-Path $file) { Get-Content $file | Write-Host }
  }
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
