#!/usr/bin/env bash
# Témoin dérivé de l’AAB validé. La clé jetable reste sur le runner vierge.
set -euo pipefail
out="$PWD/zuno-witness"
mkdir -p "$out"
aab="$RUNNER_TEMP/official/ZUNO-auto-119.aab"
echo "43fcccd171434d18961a2c27aeed8064ab2f08aeffcf7364f0ae439560fa149d  $aab" | sha256sum -c -
jarsigner -verify "$aab" | tee "$out/bundle-verification.txt"
grep -q 'jar verified.' "$out/bundle-verification.txt"
curl --fail --location --retry 3 https://github.com/google/bundletool/releases/download/1.18.2/bundletool-all-1.18.2.jar -o "$RUNNER_TEMP/bundletool.jar"
echo "378b5434cd1378bef6b2bc527b8c7f0ff2584b273830335bce54d6d0813c8584  $RUNNER_TEMP/bundletool.jar" | sha256sum -c -
image='system-images;android-30;android-tv;x86_64'
sdkmanager --list > "$RUNNER_TEMP/available.txt"
if ! grep -Fq "$image " "$RUNNER_TEMP/available.txt"; then
    image='system-images;android-36;android-tv;x86_64'
fi
printf '%s\n' "$image" > "$out/system-image.txt"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" >/dev/null
keytool -genkeypair -keystore "$RUNNER_TEMP/lab-witness.jks" -alias lab -storepass android -keypass android -dname "CN=ZUNO laboratory witness" -keyalg RSA -keysize 2048 -validity 30
tools="$ANDROID_HOME/build-tools/35.0.0"
java -jar "$RUNNER_TEMP/bundletool.jar" build-apks --bundle="$aab" --output="$RUNNER_TEMP/witness.apks" --mode=universal --aapt2="$tools/aapt2" --ks="$RUNNER_TEMP/lab-witness.jks" --ks-key-alias=lab --ks-pass=pass:android --key-pass=pass:android
unzip -p "$RUNNER_TEMP/witness.apks" universal.apk > "$RUNNER_TEMP/witness.apk"
"$tools/apksigner" verify --print-certs "$RUNNER_TEMP/witness.apk" > "$out/apk-signature.txt"
"$tools/aapt" dump badging "$RUNNER_TEMP/witness.apk" | sed -n '/^package:/p;/^sdkVersion:/p;/^targetSdkVersion:/p;/^native-code:/p' > "$out/apk-badging.txt"
grep -q "name='com.sevenmotion.tv.seven_tv' versionCode='1794559152' versionName='119'" "$out/apk-badging.txt"
printf 'no\n' | avdmanager create avd -f -n witness -k "$image" >/dev/null
sudo chmod a+rw /dev/kvm
adb start-server
export ANDROID_SERIAL=emulator-5554
"$ANDROID_HOME/emulator/emulator" -avd witness -port 5554 -http-proxy http://127.0.0.1:9 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory 1536 -cores 2 > "$RUNNER_TEMP/emulator.log" 2>&1 &
trap 'adb emu kill >/dev/null 2>&1 || true' EXIT
for i in $(seq 1 210); do
    if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
    sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
for i in $(seq 1 60); do
    adb shell pm list features > "$RUNNER_TEMP/features.txt" 2>/dev/null || true
    if grep -Eq 'android.software.leanback|android.hardware.type.television' "$RUNNER_TEMP/features.txt"; then break; fi
    sleep 2
done
grep -E 'android.software.leanback|android.hardware.type.television' "$RUNNER_TEMP/features.txt" > "$out/leanback.txt"
adb shell wm size 1920x1080
adb shell svc power stayon true
adb shell input keyevent 82
# Appareil de test isolé avant toute ouverture ; aucune livraison sur le panel.
adb shell cmd connectivity airplane-mode enable
adb shell svc wifi disable
# Les téléviseurs purs n’ont pas de service de téléphonie. Le proxy de
# l’émulateur refuse déjà les connexions TCP externes ; adb reverse reste local.
if adb shell service list | grep -F 'phone:' >/dev/null; then
    adb shell svc data disable
fi
python3 android-app/ci/zuno_lab/device_smoke.py --apk "$RUNNER_TEMP/witness.apk" --package com.sevenmotion.tv.seven_tv --out "$out" --count 30
