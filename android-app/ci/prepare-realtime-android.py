"""Réglages du paquet de test généré dans CI (aucun fichier de production)."""
from pathlib import Path
import re

for path in [Path('android/app/build.gradle.kts'), Path('android/app/build.gradle')]:
    if not path.exists():
        continue
    text = path.read_text()
    text = re.sub(r'minSdk\s*=\s*flutter.minSdkVersion', 'minSdk = 24', text)
    text = re.sub(r'minSdkVersion\s+flutter.minSdkVersion', 'minSdkVersion 24', text)
    if path.suffix == '.kts':
        if 'isCoreLibraryDesugaringEnabled' not in text:
            text = text.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        if 'desugar_jdk_libs' not in text:
            text += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        if 'coreLibraryDesugaringEnabled' not in text:
            text = text.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        if 'desugar_jdk_libs' not in text:
            text += '\n\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
    path.write_text(text)
path = Path('android/app/src/main/AndroidManifest.xml')
text = path.read_text()
if 'usesCleartextTraffic' not in text:
    text = text.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
path.write_text(text)
