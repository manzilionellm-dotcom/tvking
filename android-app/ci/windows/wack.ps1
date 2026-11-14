param([string]$Msix = 'dist/msix-test/ZUNO-Test.msix', [string]$Report = "$env:RUNNER_TEMP/zuno-wack/wack-report.xml")
# Windows App Certification Kit, s'il est présent sur le runner.
$ErrorActionPreference = 'Stop'
$appcert = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
if (!$appcert) { 'WACK absent du runner windows-2022.' | Tee-Object (Join-Path (Split-Path $Report) 'wack-absent.txt'); exit 0 }
Write-Host "WACK : $($appcert.FullName)"
& $appcert.FullName reset | Out-Host
& $appcert.FullName test -appxpackagepath (Resolve-Path $Msix).Path -reportoutputpath $Report | Out-Host
if (!(Test-Path $Report)) { throw "WACK n'a pas produit de rapport (code $LASTEXITCODE)" }
[xml]$x = Get-Content $Report
Write-Host "WACK OVERALL_RESULT = $($x.REPORT.OVERALL_RESULT)"
foreach ($t in $x.SelectNodes('//TEST')) {
  Write-Host ("  {0} : {1}" -f $t.NAME, $t.RESULT.InnerText)
  if ($t.RESULT.InnerText -ne 'PASS') { $t.MESSAGES.MESSAGE | ForEach-Object { if ($_) { Write-Host "     > $($_.TEXT)" } } }
}
