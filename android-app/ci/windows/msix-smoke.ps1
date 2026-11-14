param(
  [string]$Msix = 'dist/msix-test/ZUNO-Test.msix',
  [string]$ShotsDir = "$env:RUNNER_TEMP/zuno-store-shots",
  [int]$Seconds = 20
)
# Installe la copie MSIX signée test (Add-AppxPackage), lance l'app PAR le
# paquet (alias zuno.exe = identité du paquet) avec le réseau RÉEL, et vérifie :
# processus vivant, vraie interface, journal et base dans le conteneur MSIX,
# runtime VC++ chargé depuis le paquet. Puis captures 1920×1080 pour le Store.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class ZunoDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string d, int m, ref DEVMODE dm);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int f);
  public static int Set(int w, int h) {
    DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    EnumDisplaySettings(null, -1, ref dm); dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000;
    return ChangeDisplaySettings(ref dm, 0);
  }
}
'@
# État des lancements Inno précédents retiré : le conteneur MSIX doit tout créer.
Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($old in @("$env:APPDATA\Zuno", "$env:LOCALAPPDATA\Zuno")) { if (Test-Path $old) { Remove-Item $old -Recurse -Force } }
Get-ChildItem ([Environment]::GetFolderPath('MyDocuments')) -Filter 'tv_king.db*' -Force -ErrorAction SilentlyContinue | Remove-Item -Force
$msixPath = (Resolve-Path $Msix).Path
Add-AppxPackage -Path $msixPath
$pkg = Get-AppxPackage | Where-Object { $_.PackageFullName -like '*ZUNO*' } | Select-Object -First 1
if (!$pkg) { throw 'Paquet ZUNO non installé' }
Write-Host "Installé : $($pkg.PackageFullName) dans $($pkg.InstallLocation)"
$alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\zuno.exe'
if (!(Test-Path $alias)) { throw "Alias d'exécution absent : $alias" }
$pkgData = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)"

$dir = 'C:\zuno-msix-smoke'
New-Item -ItemType Directory -Force $dir | Out-Null
icacls $dir /grant 'Everyone:(OI)(CI)F' | Out-Null

function Start-Zuno([string]$marker) {
  Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Process $alias -ArgumentList @('--zuno-smoke-online', "`"$marker`"") | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    $p = Get-Process tv_king -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return $p }
  }
  throw 'tv_king.exe ne démarre pas depuis le paquet MSIX'
}

$marker = Join-Path $dir 'ready.txt'
Remove-Item $marker -ErrorAction SilentlyContinue
$p = Start-Zuno $marker
try {
  for ($i = 0; $i -lt ($Seconds * 2); $i++) {
    Start-Sleep -Milliseconds 500
    $p.Refresh()
    if ($p.HasExited) { throw "ZUNO (MSIX) a quitté (code $($p.ExitCode))" }
    if ((Test-Path $marker) -and (Get-Content $marker -Raw) -eq 'error') { throw 'Erreur de démarrage (MSIX)' }
  }
  if (!(Test-Path $marker) -or (Get-Content $marker -Raw) -ne 'ready') { throw 'Vraie interface non confirmée (MSIX)' }
  if ($p.Path -notlike "$($pkg.InstallLocation)*") { throw "Processus hors paquet : $($p.Path)" }
  $mods = @((Get-Process -Id $p.Id).Modules)
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'sqlite3.dll') {
    $m = @($mods | Where-Object { $_.ModuleName -ieq $dll })
    if ($m.Count -ne 1 -or $m[0].FileName -notlike "$($pkg.InstallLocation)*") { throw "$dll non chargé depuis le paquet" }
    Write-Host "Chargé depuis le paquet : $dll"
  }
  $log = @(Get-ChildItem $pkgData, (Join-Path $env:LOCALAPPDATA 'Zuno\logs') -Recurse -Filter startup.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if (!$log) { throw 'startup.log introuvable (conteneur MSIX)' }
  Write-Host "startup.log : $($log[0].FullName)"
  $text = Get-Content $log[0].FullName -Raw
  if ($text -notmatch 'realUi\.frame') { throw 'startup.log sans première image réelle' }
  $db = @(Get-ChildItem $pkgData, (Join-Path $env:APPDATA 'Zuno') -Recurse -Filter tv_king.db -ErrorAction SilentlyContinue)
  $db | ForEach-Object { Write-Host "Base SQLite : $($_.FullName) ($($_.Length) o)" }
  if (!$db) { throw 'Base tv_king.db absente du dossier de l''app' }
  Get-Content $log[0].FullName -Tail 60 | Write-Host
  Write-Host "Smoke MSIX OK : installé par Add-AppxPackage, lancé par le paquet, vivant $Seconds s, vraie interface, réseau RÉEL."
} finally {
  Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
}

# Captures Store : 1920×1080, quelques écrans atteints au clavier (D-pad).
New-Item -ItemType Directory -Force $ShotsDir | Out-Null
$r = [ZunoDisplay]::Set(1920, 1080)
Start-Sleep -Seconds 2
$b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "Écran pour captures : $($b.Width)x$($b.Height) (ChangeDisplaySettings=$r)"
$sequences = [ordered]@{
  '01-accueil'   = @()
  '02-droite'    = @('{RIGHT}')
  '03-droite-ok' = @('{RIGHT}', '{ENTER}')
  '04-bas-ok'    = @('{DOWN}', '{ENTER}')
  '05-droite2-ok' = @('{RIGHT}', '{RIGHT}', '{ENTER}')
  '06-droite3-ok' = @('{RIGHT}', '{RIGHT}', '{RIGHT}', '{ENTER}')
  '07-bas2-ok'   = @('{RIGHT}', '{DOWN}', '{ENTER}')
  '08-bas3-ok'   = @('{RIGHT}', '{DOWN}', '{RIGHT}', '{ENTER}')
  '09-tab-ok'    = @('{TAB}', '{TAB}', '{ENTER}')
}
foreach ($name in $sequences.Keys) {
  $p = Start-Zuno (Join-Path $dir "$name.txt")
  Start-Sleep -Seconds 9
  foreach ($k in $sequences[$name]) { [Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds 900 }
  Start-Sleep -Seconds 3
  $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $bmp.Save((Join-Path $ShotsDir "$name.png")); $bmp.Dispose()
  Get-Process tv_king -ErrorAction SilentlyContinue | Stop-Process -Force
}
Remove-AppxPackage -Package $pkg.PackageFullName
Write-Host "Captures : $ShotsDir (désinstallé ensuite)"
