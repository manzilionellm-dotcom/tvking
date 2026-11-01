#!/usr/bin/env bash
# Test JVM isolé de la décision téléphone/TV. Aucun SDK Android, secret,
# serveur ou fichier de production modifié ; les classes restent temporaires.
set -euo pipefail

zuno_ci_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
zuno_app_dir="$(cd -- "$zuno_ci_dir/.." && pwd)"
zuno_test_dir="$(mktemp -d /tmp/zuno-device-capabilities.XXXXXX)"

cleanup_zuno_device_test() {
  # Le nettoyage est limité au dossier unique créé ci-dessus, jamais à un
  # répertoire du projet ou à une variable système réutilisée comme cible.
  case "${zuno_test_dir:-}" in
    /tmp/zuno-device-capabilities.??????)
      rm -rf -- "$zuno_test_dir"
      ;;
    *)
      printf '%s\n' 'Dossier temporaire inattendu : nettoyage refusé.' >&2
      ;;
  esac
}
trap cleanup_zuno_device_test EXIT

# Certaines images conservent le module du compilateur JDK sans installer
# son lanceur javac. Le repli appelle le même compilateur via Java, sans
# télécharger ni installer un outil supplémentaire.
zuno_javac=(javac)
if ! command -v javac >/dev/null 2>&1; then
  zuno_javac=(java -m jdk.compiler/com.sun.tools.javac.Main)
fi

"${zuno_javac[@]}" -encoding UTF-8 -d "$zuno_test_dir" \
  "$zuno_app_dir/packages/zuno_cast/android/src/main/java/com/sevenmotion/zuno_cast/ZunoDeviceCapabilities.java" \
  "$zuno_app_dir/packages/zuno_cast/logic-test/ZunoDeviceCapabilitiesTest.java"
java -cp "$zuno_test_dir" com.sevenmotion.zuno_cast.ZunoDeviceCapabilitiesTest
