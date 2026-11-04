# Zuno — APK de test du 4 novembre 2026 (écran noir + image)

Branche de téléchargement uniquement : elle ne contient que l'APK de test.
Ce n'est ni la release `zuno-tv` (box clients) ni `zuno-tv-test`, et rien n'a
été publié par `zuno-app-production`. `version.json` n'est pas modifié.

| | |
|---|---|
| Fichier | `zuno-test-20261104.apk` |
| Taille | 42 065 462 octets |
| SHA-256 | `49dc7d03a7e541ee7711a5bf4ccd7f50000536b1d2b2eefb4399ddc93c877b8f` |
| Package | `com.sevenmotion.tv.seven_tv.essai` (variante « essai » existante) |
| Nom affiché | Zuno essai |
| Version | 116-qa, versionCode 1793820059, Android 5.0+ (minSdk 21) |
| ABI | armeabi-v7a, arm64-v8a (box réelles ; pas de x86_64) |
| Signature | clé de débogage Android de la machine de build (CN=Android Debug, certificat SHA-256 `576abfe0e3dba1150d85204cfdec793e23920cc906412c082f66e453ef2e0f55`), pas la clé des box clients |
| Source | commit `640b4b71` de `cursor/zuno-black-screen-qa-394f` : PR #194 + #195 + #198 + #205 + corrections QA |

Le package `.essai` s'installe à côté de Zuno déjà présent sur la box, sans le
remplacer ni toucher à ses données. Si un ancien « Zuno essai » signé par la
CI est installé, le désinstaller d'abord (autre signature).

Vérifier le fichier avant installation :

```bash
sha256sum zuno-test-20261104.apk
```
