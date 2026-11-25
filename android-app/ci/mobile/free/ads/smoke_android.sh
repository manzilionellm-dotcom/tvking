#!/usr/bin/env bash
# Compile le pont Flutter/AdMob contre les vrais SDK. Le paquet généré est
# exclusivement un APK debug jetable utilisant les identifiants de test Google.
set -euo pipefail
recipe="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
flutter create --no-pub --platforms=android --org com.manzilionellm --project-name tvking .
python3 "$recipe/prepare_ads.py" dart
python3 - <<'PY'
from pathlib import Path
gradle = Path("android/app/build.gradle.kts")
gradle.write_text(gradle.read_text().replace("minSdk = flutter.minSdkVersion", "minSdk = 24"))
# Même classe parente et même hook d'enregistrement que l'overlay Cast en production.
activity, = Path("android/app/src/main/kotlin").rglob("MainActivity.kt")
activity.write_text("""package com.manzilionellm.tvking

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }
}
""")
Path("lib/main.dart").write_text("""import 'package:flutter/material.dart';
import 'features/ads/presentation/seven_motion_ads.dart';
void main() => runApp(const MaterialApp(home: Scaffold(body: SevenMotionAdsBanner())));
""")
PY
SEVEN_ADMOB_APP_ID='' SEVEN_ADMOB_BANNER_ID='' SEVEN_ADMOB_TEST_ADS=true \
  python3 "$recipe/prepare_ads.py" android
cp "$recipe/ads_widget_test.dart.fixture" test/ads_widget_test.dart
flutter pub get
flutter analyze --no-pub lib
flutter test --no-pub test/ads_widget_test.dart
flutter build apk --debug --no-pub
