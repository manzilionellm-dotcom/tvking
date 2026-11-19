#!/usr/bin/env bash
# Hôte jetable : charge ensemble les deux plugins Android réellement inclus
# dans 7 MOTION pour détecter les incompatibilités binaires de Media3.
set -euo pipefail
fixture="$(cd "$(dirname "$0")" && pwd)"
phone="$(pwd)"
trial="$(mktemp -d)"
export GRADLE_USER_HOME="$trial/gradle"
cd "$trial"
flutter create --no-pub --platforms=android --org com.sevenmotion.test video_probe >/dev/null
cd video_probe
cp "$fixture/android_playback_probe.dart.fixture" lib/main.dart
python3 - "$phone" <<'PY'
from pathlib import Path
import sys
p=Path("pubspec.yaml")
s=p.read_text().replace("dependencies:\n  flutter:", f"dependencies:\n  media_kit: ^1.2.6\n  native_video_player:\n    path: {sys.argv[1]}/packages/native_video_player\n  novatube_video:\n    path: {sys.argv[1]}/packages/novatube_video\n  flutter:",1)
p.write_text(s)
p=Path("android/app/src/debug/AndroidManifest.xml")
p.write_text(p.read_text().replace("</manifest>",'<application android:usesCleartextTraffic="true" /></manifest>'))
PY
flutter pub get
flutter build apk --debug --target-platform android-x64
cp build/app/outputs/flutter-apk/app-debug.apk "$trial/probe.apk"
flutter clean >/dev/null
# Un émulateur refuse de démarrer si Gradle occupe son espace de stockage.
rm -rf "$trial/gradle"
mkdir -p "$trial/media"
for width in 320 640; do
  color=0xd02020
  if [[ "$width" == 640 ]]; then color=0x20d020; fi
  ffmpeg -loglevel error -f lavfi -i "color=c=$color:size=${width}x$((width*9/16)):rate=25" \
    -f lavfi -i sine=frequency=440 -t 8 -c:v libx264 -pix_fmt yuv420p -c:a aac \
    -movflags +faststart "$trial/media/$width.mp4"
done
python3 -m http.server 18910 --bind 127.0.0.1 --directory "$trial/media" >"$trial/http.log" 2>&1 &
server_pid=$!
image="system-images;android-30;google_apis;x86_64"
sdkmanager 'emulator' "$image" >/dev/null
# Le SDK peut déplacer le dossier utilisateur des AVD. L'émulateur et sa
# configuration partagent ici un chemin explicite sur le runner jetable.
export ANDROID_AVD_HOME="$trial/avd"
avd="$ANDROID_AVD_HOME/seven_video.avd"
mkdir -p "$avd"
printf 'avd.ini.encoding=UTF-8\npath=%s\ntarget=android-30\n' "$avd" > "$ANDROID_AVD_HOME/seven_video.ini"
cat > "$avd/config.ini" <<'AVD'
AvdId=seven_video
avd.ini.displayname=7 MOTION phone
image.sysdir.1=system-images/android-30/google_apis/x86_64/
abi.type=x86_64
hw.cpu.arch=x86_64
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader
hw.ramSize=2048
disk.dataPartition.size=1024M
tag.id=google_apis
tag.display=Google APIs
AVD
test -f "$ANDROID_HOME/system-images/android-30/google_apis/x86_64/system.img"
"$ANDROID_HOME/emulator/emulator" -list-avds | grep -Fx seven_video
df -h "$avd"
"$ANDROID_HOME/emulator/emulator" -avd seven_video -port 5554 -no-window -no-audio \
  -no-boot-anim -no-snapshot -no-metrics -gpu swiftshader -accel on -cores 2 -camera-back none -camera-front none -memory 2048 -partition-size 1024 >"$trial/emulator.log" 2>&1 &
emulator_pid=$!
trap 'adb -s emulator-5554 emu kill >/dev/null 2>&1 || true; kill "$server_pid" 2>/dev/null || true' EXIT
for ((i=0;i<120;i++)); do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then cat "$trial/emulator.log"; exit 1; fi
  [[ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != 1 ]] || break
  sleep 3
done
if [[ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != 1 ]]; then
  cat "$trial/emulator.log"; exit 1
fi
adb -s emulator-5554 shell input keyevent 82
adb -s emulator-5554 reverse tcp:18910 tcp:18910
adb -s emulator-5554 install "$trial/probe.apk"
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell am start -n com.sevenmotion.test.video_probe/.MainActivity
mkdir -p "$phone/build/video-captures"
captured=0
for ((i=0;i<90;i++)); do
  adb -s emulator-5554 logcat -d > "$trial/playback.log"
  step=$((captured+1))
  if grep -q "SEVEN_VIDEO_FRAME $step " "$trial/playback.log"; then
    capture="$phone/build/video-captures/step-$step.png"
    adb -s emulator-5554 exec-out screencap -p > "$capture"
    /usr/bin/python3 - "$capture" "$step" <<'PIXEL'
from PIL import Image, ImageStat
import sys
with Image.open(sys.argv[1]) as shot:
    x, y = shot.width // 2, shot.height // 2
    rgb = ImageStat.Stat(shot.convert('RGB').crop((x-30,y-30,x+30,y+30))).mean
channel = 1 if sys.argv[2] == '2' else 0
print(f"Capture {sys.argv[2]} : RVB moyen à l'écran = {rgb}", flush=True)
assert rgb[channel] > 120 and all(rgb[channel] > value*2 for i,value in enumerate(rgb) if i != channel), "Mire attendue absente à l'écran"
PIXEL
    touch "$trial/media/capture-$step"
    captured=$step
  fi
  if grep -q 'SEVEN_VIDEO_PROBE_OK' "$trial/playback.log"; then
    [[ "$captured" == 3 ]]
    echo 'Trois ouvertures, premières images 320/640/320, pause, reprise et arrêt confirmés.'
    exit 0
  fi
  if grep -Eq 'SEVEN_VIDEO_PROBE_FAILED|FATAL EXCEPTION' "$trial/playback.log"; then break; fi
  sleep 2
done
grep -Ei 'flutter|ExoPlayer|AndroidRuntime|FATAL' "$trial/playback.log" | tail -100
exit 1
