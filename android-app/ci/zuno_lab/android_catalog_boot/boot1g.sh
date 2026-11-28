#!/usr/bin/env bash
# AVD de laboratoire neuf. Les services Android sont interrogés séparément.
set -euo pipefail
img='system-images;android-36;android-tv;x86_64'
out="${1:?dossier}"
mkdir -p "$out"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$img" >/dev/null
echo no | avdmanager create avd -f -n catalog1g -k "$img" --device tv_1080p >/dev/null
sudo setfacl -m "u:$(id -un):rw" /dev/kvm
export ANDROID_SERIAL=emulator-5554
adb start-server
"$ANDROID_HOME/emulator/emulator" -avd catalog1g -port 5554 -http-proxy http://127.0.0.1:9 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory 1024 -cores 2 > "$RUNNER_TEMP/catalog-emulator.log" 2>&1 &
avd_pid=$!
finish_avd() {
  local rc=$?
  set +e
  printf 'shell_exit=%s\n' "$rc" >> "$out/system-events.log"
  local pkg=com.sevenmotion.tv.seven_tv.lab.catalog
  timeout 8 adb shell pidof "$pkg" > "$out/last-pid.txt"
  timeout 8 adb shell dumpsys activity exit-info "$pkg" | grep -oE 'reason=[0-9]+ \([^)]*\)|subreason=[0-9]+ \([^)]*\)|status=[0-9]+' > "$out/last-exit-info.txt"
  timeout 8 adb logcat -b crash -d | grep -oE '(java|android|androidx|kotlin)\.[A-Za-z0-9_.$]+(Exception|Error)' | sort -u > "$out/last-exceptions.txt"
  adb emu kill >/dev/null 2>&1
  return "$rc"
}
trap finish_avd EXIT
printf '%s\n' "$img" > "$out/image.txt"
printf '%s\n' 'tv_1080p, 1024 MiB demandés, 2 vCPU' > "$out/avd-profile.txt"
deadline=$((SECONDS+480))
ready=false
while ((SECONDS<deadline)); do
  if ! kill -0 "$avd_pid" 2>/dev/null; then
    echo 'Émulateur quitté' >> "$out/system-events.log"; break
  fi
  complete=$(timeout 8 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  services=$(timeout 8 adb shell 'service check activity; service check package; service check window; service check input' 2>/dev/null | tr -d '\r' || true)
  printf 't=%s boot=%s services=%s\n' "$SECONDS" "$complete" "$(printf '%s' "$services" | tr '\n' ',')" >> "$out/system-events.log"
  if [[ "$complete" == 1 ]] && [[ "$(printf '%s\n' "$services" | grep -c ': found' || true)" == 4 ]]; then ready=true; break; fi
  sleep 3
done
if [[ "$ready" != true ]]; then
  echo 'Services Android indisponibles'
  grep -Ei 'fatal|panic|not enough|cannot|minimum RAM|out of memory|increas.*ram|kvm' "$RUNNER_TEMP/catalog-emulator.log" | sed -E 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/[REDACTED]/gi' | tail -30 > "$out/emulator-errors.txt" || true
  return 1
fi
# Le réglage d'écran peut échouer sur Android TV sans service téléphonie.
# Le harness exige ensuite l’activité ZUNO et les compteurs de la vraie vue.
optional(){
  local name=$1; shift
  local rc=0
  timeout 12 adb shell "$@" >/dev/null 2>&1 || rc=$?
  printf '%s code=%s\n' "$name" "$rc" >> "$out/system-events.log"
}
optional stayon svc power stayon true
optional wake input keyevent KEYCODE_WAKEUP
optional unlock wm dismiss-keyguard
optional setup-menu input keyevent 82
optional provision settings put global device_provisioned 1
optional setup settings put secure user_setup_complete 1
optional tv-setup settings put secure tv_user_setup_complete 1
adb shell wm size > "$out/resolution.txt" || true
adb shell wm density > "$out/density.txt" || true
adb shell cat /proc/meminfo > "$out/boot-meminfo.txt" || true
