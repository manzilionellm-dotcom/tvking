#!/usr/bin/env bash
# Vérifie la télémétrie matérielle sans SDK Android ni appareil client.
set -euo pipefail

device_ci_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
device_app_dir="$(cd -- "$device_ci_dir/.." && pwd)"
device_test_dir="$(mktemp -d /tmp/zuno-device-hardware.XXXXXX)"
cleanup_device_hardware_test() {
  case "${device_test_dir:-}" in
    /tmp/zuno-device-hardware.??????) rm -rf -- "$device_test_dir" ;;
    *) printf '%s\n' 'Dossier temporaire inattendu : nettoyage refusé.' >&2 ;;
  esac
}
trap cleanup_device_hardware_test EXIT

device_javac=(javac)
if ! command -v javac >/dev/null 2>&1; then
  device_javac=(java -m jdk.compiler/com.sun.tools.javac.Main)
fi
"${device_javac[@]}" -encoding UTF-8 -d "$device_test_dir" \
  "$device_app_dir/packages/tvking_device/android/src/main/java/com/manzilionellm/tvking_device/DeviceHardwareKind.java" \
  "$device_app_dir/packages/tvking_device/logic-test/DeviceHardwareKindTest.java"
java -cp "$device_test_dir" com.manzilionellm.tvking_device.DeviceHardwareKindTest
