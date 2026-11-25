#!/usr/bin/env bash
set -euo pipefail
bench="$(cd "$(dirname "$0")" && pwd)"
trial="$RUNNER_TEMP/performance-android"
mkdir -p "$trial/media" build/performance
ffmpeg -loglevel error -f lavfi -i 'color=c=0xd02020:size=640x360:rate=25' \
  -f lavfi -i sine=frequency=440 -t 25 -c:v libx264 -pix_fmt yuv420p -c:a aac \
  -movflags +faststart "$trial/media/mire.mp4"
python3 -m http.server 18910 --bind 127.0.0.1 --directory "$trial/media" > "$trial/http.log" 2>&1 &
server_pid=$!
export ANDROID_SERIAL=emulator-5554
trap 'adb emu kill >/dev/null 2>&1 || true; kill "$server_pid" 2>/dev/null || true' EXIT
export ANDROID_AVD_HOME="$trial/avd"
mkdir -p "$ANDROID_AVD_HOME"
image='system-images;android-30;google_apis;x86_64'
sdkmanager emulator "$image" >/dev/null
avdmanager create avd --force --name seven_perf --package "$image" --device pixel_2 <<< no
"$ANDROID_HOME/emulator/emulator" -avd seven_perf -port 5554 -no-window -no-audio -no-boot-anim \
  -no-snapshot -no-metrics -gpu swiftshader -accel on -cores 2 -memory 2048 -partition-size 1536 \
  > "$trial/emulator.log" 2>&1 &
emulator_pid=$!
for ((i=0;i<120;i++)); do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then tail -50 "$trial/emulator.log"; exit 1; fi
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
  sleep 3
done
[[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
adb shell wm size 720x1280
adb shell wm density 320
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell input keyevent 82
# Les mesures utilisent le loopback USB virtuel. Aucun flux commercial ou panel distant.
adb shell svc wifi disable
adb shell svc data disable
adb reverse tcp:18910 tcp:18910
if ! /usr/bin/python3 "$bench/collect.py" build/performance "$RUNNER_TEMP/phone-before.apk" "$RUNNER_TEMP/phone-after.apk"; then
  adb logcat -d -v threadtime -s ActivityTaskManager:I ActivityManager:I AndroidRuntime:E flutter:I \
    FlutterEngine:I SevenPerf:I libc:F DEBUG:F > build/performance/android.log || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity|mLastPausedActivity' \
    > build/performance/activity.txt || true
  adb shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|mShowingLockscreen' \
    > build/performance/window.txt || true
  adb exec-out screencap -p > build/performance/echec.png || true
  cp "$trial/http.log" build/performance/flux-local.log
  tail -80 build/performance/android.log
  cat build/performance/{activity,window}.txt
  exit 1
fi
