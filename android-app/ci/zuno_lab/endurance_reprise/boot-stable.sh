#!/usr/bin/env bash
# Même lanceur Android TV que le diagnostic 6×80. Vérification des services avant et après la configuration.
set -euo pipefail
out=${1:?dossier observations}
ram=${2:?RAM en Mio}
image='system-images;android-36;android-tv;x86_64'
profile=tv_1080p
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" >/dev/null
sudo setfacl -m "u:$(id -un):rw" /dev/kvm
export ANDROID_SERIAL=emulator-5554
adb start-server
printf '%s\n' "$profile" > "$out/avd-profile.txt"
printf '%s\n' "$image" > "$out/image.txt"
report() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$out/amorçage.log"; }
stopavd() {
 set +e
 timeout 7 adb emu kill >/dev/null 2>&1
 if [[ -n "${avd_pid:-}" ]]; then
  for _ in {1..8};do if ! kill -0 "$avd_pid" 2>/dev/null;then break;fi;sleep 1;done
  kill "$avd_pid" 2>/dev/null
  wait "$avd_pid" 2>/dev/null
  report "emulator_exit=$?"
 fi
 set -e
}
capture_failure() {
 local log=$1
 grep -Ei 'panic|out of memory|fatal|offline|error|cannot|crash|memory|kvm|Guest connected' "$log" | sed -E 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/[EXPURGE]/gi;s@https?://[^ ]+@[URL]@g' | tail -30 >> "$out/amorçage.log" || true
}
ready() {
 local count=0 until=$((SECONDS+$1))
 while ((SECONDS < until)); do
  if ! kill -0 "$avd_pid" 2>/dev/null;then report 'emulator-process-ended';return 1;fi
  local state boot kernel services package
  state=$(timeout 5 adb get-state 2>/dev/null | tr -d '\r' || true)
  boot=$(timeout 6 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  kernel=$(timeout 6 adb shell cat /proc/meminfo 2>/dev/null | sed -n -E 's/^MemTotal: *([0-9]+) kB.*/\1/p' || true)
  services=$(timeout 7 adb shell 'service check activity;service check input;service check window;service check package' 2>/dev/null | grep -c ': found' || true)
  package=$(timeout 7 adb shell pm path android 2>/dev/null | tr -d '\r' || true)
  if [[ "$state" == device && "$boot" == 1 && "$kernel" =~ ^[0-9]+$ && "$services" == 4 && "$package" == package:* ]]; then
   count=$((count+1));report "service_sample_ok=$count MemTotal_KiB=$kernel"
   if ((count>=2));then return 0;fi
  else
   count=0;report "waiting transport=${state:-absent} boot=${boot:-absent} services=${services:-0}"
   if [[ "$state" == offline || -z "$state" ]];then timeout 5 adb reconnect offline >/dev/null 2>&1 || true;fi
  fi
  sleep 7
 done
 return 1
}
prepared=false
for attempt in 1 2;do
 name="lab-endurance-$attempt"
 echo no | avdmanager create avd -f -n "$name" -k "$image" --device "$profile" >/dev/null
 logfile="$RUNNER_TEMP/emu-final-$attempt.log"
 "$ANDROID_HOME/emulator/emulator" -avd "$name" -port 5554 -dns-server 127.0.0.1 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory "$ram" -cores 2 >"$logfile" 2>&1 &
 avd_pid=$!
 report "attempt=$attempt ram_requested_MiB=$ram process=$avd_pid"
 if ready 400;then
  for cmd in 'svc power stayon true' 'input keyevent KEYCODE_WAKEUP' 'wm dismiss-keyguard' 'input keyevent 82' 'settings put global device_provisioned 1' 'settings put secure user_setup_complete 1' 'settings put secure tv_user_setup_complete 1';do
   timeout 8 adb shell "$cmd" >/dev/null 2>&1 || report "configuration_unavailable=$cmd"
  done
  sleep 7
  if ready 100;then
   prepared=true;report "second_confirmation_after_configuration=$attempt";break
  fi
 fi
 capture_failure "$logfile";stopavd
 timeout 8 adb kill-server >/dev/null 2>&1 || true
 adb start-server
done
if [[ "$prepared" != true ]];then echo 'Échec de transport avant installation sur deux AVD neufs';exit 1;fi
trap 'stopavd' EXIT
adb shell wm size > "$out/resolution.txt"
adb shell wm density > "$out/density.txt"
adb shell cat /proc/meminfo | sed -n '/^MemTotal:/p' > "$out/boot-meminfo.txt"
