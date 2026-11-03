#!/usr/bin/env bash
# Vrai rendu Android, sans écran physique et sans flux fournisseur. KVM accélère
# le CPU ; SwiftShader exécute les shaders GLES sur le runner sans GPU dédié.
set -euo pipefail

contrast_api="${CONTRAST_API_LEVEL:?CONTRAST_API_LEVEL doit valoir 29 ou 35}"
case "$contrast_api" in 29|35) ;; *) exit 2 ;; esac
contrast_repo="$(git rev-parse --show-toplevel)"
contrast_out="$contrast_repo/artifacts/contrast-api-$contrast_api"
contrast_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?SDK Android absent}}"
contrast_image="system-images;android-$contrast_api;google_apis;x86_64"
contrast_avd="zuno_contrast_api_$contrast_api"
contrast_serial=emulator-5554
contrast_pid=''
contrast_phase=baseline
contrast_test_classes=com.manzilionellm.native_video_player.NativeContrastPixelTest,com.manzilionellm.native_video_player.NativeRecoveryPlaybackTest
contrast_gate="$contrast_repo/android-app/packages/native_video_player/android/src/main/kotlin/com/manzilionellm/native_video_player/logic/PictureTune.kt"
contrast_original=''
mkdir -p "$contrast_out"

# Les APK restent installés jusqu'à la collecte : sinon AGP efface également
# leurs captures externes en fin de test. Le runner entier est ensuite jeté.
contrast_collect() {
  local contrast_phase_out="$contrast_out/$contrast_phase"
  mkdir -p "$contrast_phase_out"
  if adb -s "$contrast_serial" get-state >/dev/null 2>&1; then
    adb -s "$contrast_serial" logcat -d > "$contrast_phase_out/logcat.txt" 2>&1 || true
    adb -s "$contrast_serial" shell dumpsys SurfaceFlinger > "$contrast_phase_out/surface-flinger.txt" 2>&1 || true
    adb -s "$contrast_serial" exec-out screencap -p > "$contrast_phase_out/emulator-final.png" 2>/dev/null || true
    adb -s "$contrast_serial" pull \
      /sdcard/Android/data/com.manzilionellm.native_video_player.test/files/contrast-pixels \
      "$contrast_phase_out/" > "$contrast_phase_out/pull-pixels.txt" 2>&1 || true
  fi
  local contrast_build
  for contrast_build in \
    "$contrast_repo/android-app/build/native_video_player" \
    "$contrast_repo/android-app/packages/native_video_player/android/build"; do
    if [[ -d "$contrast_build/outputs/androidTest-results" ]]; then
      mkdir -p "$contrast_phase_out/junit"
      cp -R "$contrast_build/outputs/androidTest-results/." "$contrast_phase_out/junit/"
    fi
    if [[ -d "$contrast_build/reports/androidTests" ]]; then
      mkdir -p "$contrast_phase_out/reports"
      cp -R "$contrast_build/reports/androidTests/." "$contrast_phase_out/reports/"
    fi
  done
}

contrast_cleanup() {
  local contrast_status=$?
  trap - EXIT
  if [[ -n "$contrast_original" ]]; then
    cp "$contrast_original" "$contrast_gate"
  fi
  contrast_collect
  if [[ -n "$contrast_pid" ]]; then
    adb -s "$contrast_serial" emu kill >/dev/null 2>&1 || true
    kill "$contrast_pid" >/dev/null 2>&1 || true
  fi
  exit "$contrast_status"
}
trap contrast_cleanup EXIT

git -C "$contrast_repo" rev-parse HEAD > "$contrast_out/source-sha.txt"
contrast_fixture="$contrast_repo/android-app/packages/native_video_player/android/src/androidTest/assets/contrast_sdr.mp4"
sha256sum "$contrast_fixture" > "$contrast_out/fixture.sha256"
cp "$contrast_fixture" "$contrast_out/contrast_sdr.mp4"
sdkmanager "platform-tools" "emulator" "platforms;android-35" "build-tools;35.0.0" "$contrast_image" \
  > "$contrast_out/sdk-install.txt" 2>&1
"$contrast_sdk/emulator/emulator" -version > "$contrast_out/emulator-version.txt" 2>&1
"$contrast_sdk/emulator/emulator" -accel-check > "$contrast_out/kvm.txt" 2>&1
printf 'no\n' | avdmanager create avd --force --name "$contrast_avd" \
  --package "$contrast_image" --device pixel_2 > "$contrast_out/avd-create.txt" 2>&1

"$contrast_sdk/emulator/emulator" -avd "$contrast_avd" -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
  -gpu swiftshader -accel on -memory 2048 -cores 2 -skin 1280x720 \
  -camera-back none -camera-front none > "$contrast_out/emulator.txt" 2>&1 &
contrast_pid=$!

# Délai total borné, avec un contrôle du processus : un émulateur cassé produit
# un échec CI et ses logs, jamais un test « ignoré » prétendument vert.
contrast_booted=false
for ((contrast_attempt=0; contrast_attempt<120; contrast_attempt++)); do
  kill -0 "$contrast_pid"
  if [[ "$(adb -s "$contrast_serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    contrast_booted=true
    break
  fi
  sleep 5
done
if [[ "$contrast_booted" != true ]]; then
  printf 'Émulateur non démarré après 600 secondes.\n' >&2
  exit 1
fi

adb -s "$contrast_serial" shell settings put global window_animation_scale 0
adb -s "$contrast_serial" shell settings put global transition_animation_scale 0
adb -s "$contrast_serial" shell settings put global animator_duration_scale 0
adb -s "$contrast_serial" shell svc power stayon true
adb -s "$contrast_serial" shell input keyevent 82
# La mire est embarquée ; les erreurs HTTP viennent seulement de 127.0.0.1.
# Aucun réseau extérieur ni fournisseur n'est nécessaire aux deux classes.
adb -s "$contrast_serial" shell svc wifi disable
adb -s "$contrast_serial" shell svc data disable
adb -s "$contrast_serial" shell getprop ro.build.version.sdk > "$contrast_out/api.txt"
adb -s "$contrast_serial" logcat -c

cd "$contrast_repo/android-app/android"
export ANDROID_SERIAL="$contrast_serial"
contrast_run() {
  mkdir -p "$contrast_out/$contrast_phase"
  ./gradlew :native_video_player:connectedDebugAndroidTest \
    "-Pandroid.testInstrumentationRunnerArguments.class=$contrast_test_classes" \
    -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true \
    '-Dorg.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g' \
    --max-workers=2 --no-daemon --stacktrace "$@" 2>&1 | tee "$contrast_out/$contrast_phase/gradle.txt"
}
contrast_run
contrast_collect
python3 "$contrast_repo/android-app/ci/verify-contrast-results.py" "$contrast_out/baseline" baseline

# Contre-preuve demandée : le même test doit déceler l'ancien défaut
# (contraste toujours refusé), pas seulement constater un booléen « true ».
# La source n'est changée que dans le runner ; le piège EXIT la restaure aussi
# si la compilation ou l'émulateur échoue pendant cette seconde exécution.
contrast_original="$contrast_out/PictureTune.original.kt"
cp "$contrast_gate" "$contrast_original"
python3 - "$contrast_gate" <<'PY'
from pathlib import Path
import sys

gate = Path(sys.argv[1])
source = gate.read_text()
before = "        requested && hardwareAllows\n"
after = "        requested && hardwareAllows && false // Mutation CI : ancien refus permanent.\n"
if source.count(before) != 1:
    raise SystemExit("Porte de contraste inattendue : mutation refusée.")
gate.write_text(source.replace(before, after, 1))
PY
git -C "$contrast_repo" diff -- "$contrast_gate" > "$contrast_out/mutation.patch"
contrast_phase=mutation
contrast_test_classes=com.manzilionellm.native_video_player.NativeContrastPixelTest
# Aucun XML ni PNG du premier passage ne doit pouvoir valider le second.
rm -rf "$contrast_repo/android-app/build/native_video_player/outputs/androidTest-results" \
  "$contrast_repo/android-app/build/native_video_player/reports/androidTests" \
  "$contrast_repo/android-app/packages/native_video_player/android/build/outputs/androidTest-results" \
  "$contrast_repo/android-app/packages/native_video_player/android/build/reports/androidTests"
adb -s "$contrast_serial" shell rm -rf \
  /sdcard/Android/data/com.manzilionellm.native_video_player.test/files/contrast-pixels
adb -s "$contrast_serial" logcat -c
if contrast_run --rerun-tasks; then
  contrast_mutation_status=0
else
  contrast_mutation_status=$?
fi
contrast_collect
cp "$contrast_original" "$contrast_gate"
contrast_original=''
git -C "$contrast_repo" diff --exit-code -- "$contrast_gate"
printf '%s\n' "$contrast_mutation_status" > "$contrast_out/mutation/gradle-exit-code.txt"
if [[ "$contrast_mutation_status" == 0 ]]; then
  printf 'Mutation non détectée : le test accepte un contraste toujours refusé.\n' >&2
  exit 1
fi
python3 "$contrast_repo/android-app/ci/verify-contrast-results.py" "$contrast_out/mutation" mutation
