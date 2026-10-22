#!/usr/bin/env bash
# Archive signée seulement. Aucun téléversement ou envoi en revue implicite.
set -euo pipefail
umask 077
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PHONE=$(cd "${1:?Dossier de source iPhone requis}" && pwd)
python3 "$SCRIPT_DIR/signing_preflight.py"
SIGN_DIR=$(mktemp -d "$RUNNER_TEMP/7motion-signing.XXXXXX")
KEYCHAIN="$SIGN_DIR/build.keychain-db"
PROFILE_DEST=""
# Restaurer exactement la liste d'origine du trousseau après l'archive.
security list-keychains -d user > "$SIGN_DIR/keychains.txt"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  python3 - "$SIGN_DIR/keychains.txt" <<'PY'
import shlex, subprocess, sys
subprocess.run(['security','list-keychains','-d','user','-s',*shlex.split(open(sys.argv[1]).read())],check=False)
PY
  if [ -n "$PROFILE_DEST" ]; then rm -f "$PROFILE_DEST"; fi
  rm -rf "$SIGN_DIR"
}
trap cleanup EXIT
export SIGN_DIR
python3 - <<'PY'
import base64, os
from pathlib import Path
p=Path(os.environ['SIGN_DIR'])
for name,file in [('APPLE_CERT_P12_BASE64','certificate.p12'),('APPLE_PROFILE_BASE64','profile.mobileprovision')]:
    (p/file).write_bytes(base64.b64decode(''.join(os.environ[name].split()),validate=True))
PY
security cms -D -i "$SIGN_DIR/profile.mobileprovision" > "$SIGN_DIR/profile.plist"
python3 - <<'PY'
import datetime, os, plistlib
from pathlib import Path
p=Path(os.environ['SIGN_DIR'])
v=plistlib.loads((p/'profile.plist').read_bytes())
e=v['Entitlements'];team=os.environ['APPLE_TEAM_ID'];bundle=os.environ['APPLE_BUNDLE_ID']
assert team in v['TeamIdentifier'], 'Team Apple différent du profil'
assert e['application-identifier']==team+'.'+bundle, 'Profil d’une autre app'
assert not v.get('ProvisionedDevices'), 'Un profil App Store est requis'
assert not v.get('ProvisionsAllDevices'), 'Profil entreprise non accepté'
assert not e.get('get-task-allow'), 'Profil de développement non accepté'
assert v['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Profil expiré'
(p/'profile-name').write_text(v['Name'])
export={'method':'app-store-connect','signingStyle':'manual','teamID':team,
        'uploadSymbols':True,'stripSwiftSymbols':True,'manageAppVersionAndBuildNumber':False,
        'provisioningProfiles':{bundle:v['Name']}}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(export))
PY
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGN_DIR/certificate.p12" -k "$KEYCHAIN" -P "$APPLE_CERT_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
python3 - "$SIGN_DIR/keychains.txt" "$KEYCHAIN" <<'PYKEY'
import shlex, subprocess, sys
subprocess.run(['security','list-keychains','-d','user','-s',sys.argv[2],*shlex.split(open(sys.argv[1]).read())],check=True)
PYKEY
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_DEST="$HOME/Library/MobileDevice/Provisioning Profiles/7motion-${GITHUB_RUN_ID}.mobileprovision"
cp "$SIGN_DIR/profile.mobileprovision" "$PROFILE_DEST"
export PROFILE_NAME=$(cat "$SIGN_DIR/profile-name")
cd "$PHONE"
flutter config --no-enable-swift-package-manager
flutter pub get
flutter gen-l10n
# Le build simulateur précédent a réécrit Generated.xcconfig : restaurer le
# mode release et les defines Apple avant l'archive signée.
flutter build ios --release --no-codesign --no-tree-shake-icons --target=lib/main.dart \
  --build-name=0.3.7 --build-number="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}" \
  --dart-define=APP_STORE_BUILD=true --dart-define=APP_BUILD_LABEL=1988121
# Le profil concerne Runner seulement ; imposer ces réglages globalement
# ferait demander un profil aux bibliothèques CocoaPods, qui n'en acceptent pas.
ruby -rxcodeproj <<'RUBY'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target missing' unless runner
runner.build_configurations.each do |config|
  config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('APPLE_TEAM_ID')
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = ENV.fetch('PROFILE_NAME')
end
project.save
RUBY
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/ios/archive/Runner.xcarchive archive
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa -exportOptionsPlist "$SIGN_DIR/ExportOptions.plist"
test -n "$(find build/ios/ipa -maxdepth 1 -name '*.ipa' -print -quit)"
