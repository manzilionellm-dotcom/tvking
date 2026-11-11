#!/usr/bin/env bash
# Réutilise exclusivement la clé déjà autorisée des box. Aucun repli debug,
# génération de clé ou changement de package. Ne jamais activer « set -x ».
set -euo pipefail
test -n "${KS_PW:-}" || { echo 'Secret de signature absent.' >&2; exit 1; }
audit_key=android/app/release.jks
umask 077
if [[ -n "${KS_B64:-}" ]]; then
  printf '%s' "$KS_B64" | base64 --decode > "$audit_key"
elif [[ -f ci/release.jks.enc ]]; then
  openssl enc -d -aes-256-cbc -pbkdf2 -in ci/release.jks.enc \
    -out "$audit_key" -pass env:KS_PW
else
  echo 'Clé existante introuvable ; aucun APK ne sera construit.' >&2
  exit 1
fi
audit_alias="${KS_ALIAS:-sevenmotion}"
audit_key_password="${KEY_PW:-$KS_PW}"
audit_certificate="$(mktemp "${RUNNER_TEMP:-/tmp}/audit116-cert.XXXXXX")"
trap 'rm -f -- "$audit_certificate"' EXIT
keytool -exportcert -keystore "$audit_key" -storepass:env KS_PW \
  -alias "$audit_alias" -file "$audit_certificate" >/dev/null 2>&1
audit_digest="$(sha256sum "$audit_certificate" | cut -d' ' -f1)"
test "$audit_digest" = "$EXPECTED_CERT" || {
  echo 'Certificat différent de la référence : signature refusée.' >&2
  exit 1
}
cat > android/key.properties <<EOF
storeFile=release.jks
storePassword=$KS_PW
keyAlias=$audit_alias
keyPassword=$audit_key_password
EOF
printf 'SIGNING=release\n' >> "$GITHUB_ENV"
printf 'Certificat DER vérifié : %s\n' "$audit_digest"
