from pathlib import Path
src=Path('android-app/ci/zuno_lab/endurance_signee/run.sh')
s=src.read_text()
a=s.index('python3 - "$ram" "$localtools/android_catalog_boot/boot1g.sh"')
b=s.index('(cd apk && cp',a)
s=s[:a]+'source "$localtools/endurance_reprise/boot-stable.sh" "$obs" "$ram"\n'+s[b:]
# Stocker une constatation claire si le processus système se perd après installation.
s=s.replace("  adb emu kill >/dev/null 2>&1 || true", '''  adb get-state > "$obs/transport-apres.txt" 2>/dev/null || true
  stopavd''')
Path('android-app/ci/zuno_lab/endurance_reprise/run-temp.sh').write_text(s)
