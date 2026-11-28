#!/usr/bin/env bash
# Vrai APK, Android 14 tactile, réseau actif pour l'essai normal de la licence.
# Le média et le récepteur sont locaux ; aucune chaîne ni clé de signature.
set -euo pipefail
apk="$(readlink -f "$1")"
out="$(mkdir -p "$2" && readlink -f "$2")"
scripts="$(dirname "$(readlink -f "$0")")"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?Android SDK absent}}"
serial=emulator-5554
pkg="${NOVATUBE_REVIEW_PACKAGE:-com.sevenmotion.novatube.tv}"
version="${NOVATUBE_REVIEW_VERSION_CODE:-1794878684}"
digest="${NOVATUBE_REVIEW_APK_SHA256:-}"
[[ "$pkg" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ && "$version" =~ ^[0-9]+$ ]]
image='system-images;android-34;google_apis;x86_64'
hardware=pixel_2
api=34
memory=3072
profile="${NOVATUBE_PERF_PROFILE:-}"
vpn="${NOVATUBE_QA_VPN:-off}"
tunnel="$scripts/../novatube_vpn/tunnel.sh"
cast_transport=adb
if [[ "$profile" == phone && "${NOVATUBE_QA_CAST_LAN:-on}" == on ]]; then
  cast_transport=slirp
fi
if [[ -n "$profile" ]]; then
  [[ "$profile" == phone || "$profile" == tv ]]
  [[ "$vpn" == on || "$vpn" == off ]]
  [[ "$pkg" == com.sevenmotion.novatube.tv.lab.retour.rec || "$pkg" == com.sevenmotion.novatube.tv.lab.retour.rec.vpn ]]
  if [[ "$profile" == tv ]]; then
    api=36
    image='system-images;android-36;android-tv;x86_64'
    hardware=tv_1080p
    memory=1536
  fi
  if [[ "$vpn" == on ]]; then export NOVATUBE_QA_ORIGIN=http://192.0.2.1:18999
  else export NOVATUBE_QA_ORIGIN=http://10.0.2.2:18999; fi
fi
accel="${NOVATUBE_EMULATOR_ACCEL:-on}"
emulator_pid=''
receiver_pid=''
ssdp_pid=''
mkdir -p "$out/media" "$out/dex" "$out/java"
if [[ "$pkg" == com.sevenmotion.novatube.tv ]]; then
  cp "$(dirname "$apk")/build-identity.json" "$out/build-identity.json"
  test -n "${NOVATUBE_BUILD_COMMIT:?Commit source attendu absent}"
else
  [[ "$digest" =~ ^[a-f0-9]{64}$ ]]
  test "$(sha256sum "$apk" | cut -d' ' -f1)" = "$digest"
fi
# Les versions récentes du SDK et de l'émulateur n'utilisent pas toutes le
# même répertoire utilisateur par défaut. Ce chemin explicite évite l'écart.
export ANDROID_AVD_HOME="$(dirname "$out")/novatube_review_avd"
mkdir -p "$ANDROID_AVD_HOME"

finish() {
  status=$?
  if [[ -n "$profile" && "$vpn" == on && -f "$out/vpn-started" ]]; then
    bash "$tunnel" stop "$serial" "$pkg" "$out/vpn" || true
  fi
  adb -s "$serial" logcat -d -v threadtime PlaybackFgSvc:I AndroidRuntime:E '*:S' > "$out/service-logcat.txt" 2>/dev/null || true
  if [[ ! -f "$(dirname "$out")/private-input-active" ]]; then
    timeout 60 adb -s "$serial" exec-out screencap -p > "$out/99-emulator.png" 2>/dev/null || true
    if [[ -f "$(dirname "$out")/private-input-active" ]]; then rm -f "$out/99-emulator.png"; fi
  fi
  printf '%s\n' "$status" > "$out/exit-code.txt"
  for process in "$receiver_pid" "$ssdp_pid"; do
    if [[ -n "$process" ]]; then kill "$process" >/dev/null 2>&1 || true; fi
  done
  if [[ -n "$emulator_pid" ]]; then
    if [[ "$cast_transport" == slirp ]]; then
      adb -s "$serial" emu redir del tcp:19001 > /dev/null 2>&1 || true
    fi
    adb -s "$serial" emu kill >/dev/null 2>&1 || true
    kill "$emulator_pid" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap finish EXIT

sdkmanager platform-tools emulator 'build-tools;35.0.0' 'platforms;android-34' "$image" > "$out/sdk-install.txt" 2>&1
bt="$sdk/build-tools/35.0.0"
"$bt/aapt" dump badging "$apk" > "$out/installed-badging.txt"
rg -Fq "package: name='$pkg'" "$out/installed-badging.txt"
rg -Fq "versionCode='$version'" "$out/installed-badging.txt"

# Mire animée + tonalité, produites exprès pour ce contrôle. Aucun service IPTV.
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -f lavfi -i 'testsrc2=size=640x360:rate=25' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
  -t 180 -map 0:v -map 1:a -threads 2 \
  -c:v libx264 -preset ultrafast -profile:v baseline -pix_fmt yuv420p \
  -b:v 700k -g 25 -c:a aac -b:a 64k -ac 2 -f mpegts "$out/media/pattern.ts"
cat > "$out/media/review.m3u" <<'M3U'
#EXTM3U
#EXTINF:-1 tvg-id="novatube.local.pattern" group-title="Local test",Mire locale NOVATUBE MAX
http://127.0.0.1:18999/pattern.ts
M3U

if [[ -n "$profile" ]]; then
  mkdir -p "$out/media/movie/qa/lab"
  ffmpeg -nostdin -loglevel error -y -i "$out/media/pattern.ts" -t 100 \
    -map 0:v:0 -map 0:a:0 -c copy -movflags +faststart "$out/media/movie/qa/lab/777.mp4"
  cat > "$out/media/review.m3u" <<M3U
#EXTM3U
#EXTINF:-1 tvg-id="novatube.local.pattern" group-title="Test",Mire locale
$NOVATUBE_QA_ORIGIN/pattern.ts
#EXTINF:-1 group-title="Films",Orion
$NOVATUBE_QA_ORIGIN/movie/qa/lab/777.mp4
M3U
fi
# Le répondeur utilise le groupe SSDP Android et publie l'adresse du mode choisi.
javac --release 8 -d "$out/java" "$scripts/SsdpResponder.java"
"$bt/d8" --min-api 24 --output "$out/dex" "$out/java/SsdpResponder.class"
jar cf "$out/ssdp-responder.jar" -C "$out/dex" classes.dex

printf 'no\n' | avdmanager create avd --force --name novatube_play_review \
  --path "$ANDROID_AVD_HOME/novatube_play_review.avd" \
  --package "$image" --device "$hardware" > "$out/avd-create.txt" 2>&1
if [[ "$accel" == off ]]; then
  # Mode logiciel documenté par Android ; lent, réservé au diagnostic local.
  export ANDROID_I_WANT_MY_TCG=yes
fi
"$sdk/emulator/emulator" -avd novatube_play_review -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data -no-metrics \
  -gpu swiftshader -accel "$accel" -memory "$memory" -cores 2 \
  -camera-back none -camera-front none > "$out/emulator.txt" 2>&1 &
emulator_pid=$!
booted=false
for ((attempt = 0; attempt < 180; attempt++)); do
  kill -0 "$emulator_pid"
  if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    booted=true
    break
  fi
  sleep 5
done
test "$booted" = true
if [[ "$profile" != tv ]]; then adb -s "$serial" root > "$out/adb-root.txt" 2>&1; fi
adb -s "$serial" wait-for-device
test "$(adb -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')" = "$api"
adb -s "$serial" shell pm list features > "$out/android-features.txt"
if [[ "$profile" == tv ]]; then
  rg -q 'android.software.leanback' "$out/android-features.txt"
else
  rg -q 'android.hardware.touchscreen' "$out/android-features.txt"
  ! rg -q 'android.software.leanback' "$out/android-features.txt" || exit 1
fi
adb -s "$serial" shell settings put global window_animation_scale 0
adb -s "$serial" shell settings put global transition_animation_scale 0
adb -s "$serial" shell settings put global animator_duration_scale 0
adb -s "$serial" shell settings put system screen_off_timeout 600000
adb -s "$serial" shell settings put system accelerometer_rotation 0
adb -s "$serial" shell settings put system user_rotation 0
adb -s "$serial" shell svc power stayon true
adb -s "$serial" shell wm size 1920x1080
adb -s "$serial" shell wm density 320
adb -s "$serial" shell input keyevent 82
if [[ "$pkg" == com.sevenmotion.novatube.tv.lab.retour.rec || -n "$profile" ]]; then
  # Amorcer la lecture du compositeur sur l'accueil système avant installation.
  # Les octets de cette capture sont seulement jetés.
  for attempt in 1 2 3; do
    if timeout 60 adb -s "$serial" exec-out screencap -p > /dev/null; then break; fi
    timeout 12 adb -s "$serial" wait-for-device || true
    sleep 1
  done
fi

adb -s "$serial" install -r "$apk" > "$out/install.txt"
if [[ -n "$profile" && "$vpn" == on ]]; then
  touch "$out/vpn-started"
  bash "$tunnel" start "$serial" "$pkg" "$out/vpn"
fi
python3 -u "$scripts/dlna_receiver.py" --out "$out" --media "$out/media" --serial "$serial" --transport "$cast_transport" > "$out/receiver-console.txt" 2>&1 &
receiver_pid=$!
sleep 1
curl --fail --silent http://127.0.0.1:18999/device.xml > "$out/receiver-description.xml"
if [[ "$cast_transport" == slirp ]]; then
  # Ces ports sont réservés par ce banc sur un émulateur neuf.
  adb -s "$serial" forward --list > "$out/adb-forwards.txt"
  adb -s "$serial" reverse --list > "$out/adb-reverses.txt"
  if rg -q 'tcp:(18999|19001)([[:space:]]|$)' "$out/adb-forwards.txt" "$out/adb-reverses.txt"; then
    echo 'Transfert ADB inattendu sur un port du récepteur' >&2
    exit 1
  fi
else
  adb -s "$serial" reverse tcp:18999 tcp:18999
fi
adb -s "$serial" push "$out/ssdp-responder.jar" /data/local/tmp/novatube-ssdp.jar > "$out/ssdp-install.txt"
adb -s "$serial" shell CLASSPATH=/data/local/tmp/novatube-ssdp.jar app_process /system/bin SsdpResponder "$cast_transport" > "$out/ssdp-discovery.txt" 2>&1 &
ssdp_pid=$!
sleep 2
kill -0 "$ssdp_pid"

component="$(adb -s "$serial" shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER "$pkg" | tr -d '\r' | tail -1)"
[[ "$component" == "$pkg/"* ]]
adb -s "$serial" logcat -c
adb -s "$serial" shell am start -W -n "$component" > "$out/app-start.txt"
pilot="$scripts/record_review.py"
if [[ -n "$profile" ]]; then pilot="$scripts/../novatube_vpn/measure.py"; fi
python3 -u "$pilot" --out "$out" --serial "$serial" --component "$component" \
  --package "$pkg" --expected-version "$version" --expected-digest "$digest"
if [[ -n "$profile" && "$vpn" == on ]]; then
  bash "$tunnel" verify "$serial" "$pkg" "$out/vpn" 18999
fi

if [[ "$cast_transport" == slirp ]]; then
  # Chaque décodage a sa propre preuve de connexion entrante côté Android.
  jq -se '
    any(.[]; .event == "device_description" and .host == "10.0.2.2:18999")
    and any(.[]; .event == "soap" and .action == "Play" and .host == "10.0.2.2:18999")
    and ([.[] | select(.event == "decoder_started") | .generation] | length > 0)
    and (([.[] | select(.event == "decoder_started") | .generation] -
          [.[] | select(.event == "relay_socket_on_guest") | .generation]) | length == 0)
  ' "$out/receiver-events.jsonl" > "$out/cast-lan-proof.txt"
fi

# Les gros intermédiaires synthétiques ne sont pas utiles à la revue finale.
rm -rf "$out/media" "$out/java" "$out/dex"
