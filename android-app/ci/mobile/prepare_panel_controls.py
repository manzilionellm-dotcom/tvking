#!/usr/bin/env python3
"""Reporte seulement les commandes panel sur le téléphone déjà préparé.

La recette 37fdf + 69eee01 reste la référence du téléphone. Ses traductions,
son bail audio, son protocole APPLIED et son moteur Cast ne sont pas remplacés
par leurs cousins Zuno. Les ancres sont vérifiées AVANT toute écriture : une
nouvelle recette doit être revue explicitement si elle ne correspond plus.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

import mobile_controls_options


class OverlayError(ValueError):
    pass


def once(text: str, before: str, after: str, label: str) -> str:
    count = text.count(before)
    if count != 1:
        raise OverlayError(f"{label} : une ancre attendue, {count} trouvée(s)")
    return text.replace(before, after, 1)


def section(text: str, start: str, end: str, label: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise OverlayError(f"{label} : limites ambiguës")
    first, last = text.index(start), text.index(end)
    if first >= last:
        raise OverlayError(f"{label} : limites inversées")
    return text[first:last]


def replace_section(old: str, new: str, start: str, end: str, label: str) -> str:
    return once(old, section(old, start, end, label),
                section(new, start, end, label), label)


def native_info(text: str, context: str) -> str:
    # Ce motif ne touche que la fiche Build de getDeviceInfo. Les méthodes
    # de Cast, PiP, identifiant Android, mémoire et chiffrement restent telles quelles.
    values = [r'"model"\s+to\s+Build\.MODEL',
              r'"manufacturer"\s+to\s+Build\.MANUFACTURER',
              r'"release"\s+to\s+Build\.VERSION\.RELEASE',
              r'"sdk"\s+to\s+Build\.VERSION\.SDK_INT\.toString\(\)',
              r'"build"\s+to\s+Build\.DISPLAY']
    pattern = r'result\.success\(\s*hashMapOf\(\s*' + r',\s*'.join(values) + r',?\s*\),?\s*\)'
    updated, count = re.subn(pattern, f'result.success(DeviceHardwareInfo.read({context}))', text)
    if count != 1:
        raise OverlayError(f"getDeviceInfo natif : une fiche attendue, {count} trouvée(s)")
    return updated


def mobile_announcement_repository(text: str) -> str:
    text = once(text, "import '../../subscription/data/subscription_backend.dart';",
                "import '../../../core/i18n/l10n_now.dart';\n"
                "import '../../subscription/data/subscription_backend.dart';", 'langue des annonces')
    # PanelLiveWait n'envoie APPLIED qu'après une lecture stricte réussie.
    if 'fetchLatest({bool strict = false})' not in text:
        raise OverlayError('Le repository annonce doit conserver son contrat strict')
    text = once(text, '  static Future<Announcement?> _fetch() async {',
                "  /// Compatibilité avec le temps réel téléphone déjà revu.\n"
                "  static Future<void> refreshFromPanel() async {\n"
                "    await fetchLatest(strict: true);\n  }\n\n"
                "  static void notifyChanged() => unawaited(fetchLatest());\n\n"
                '  static Future<Announcement?> _fetch() async {', 'signal et ACK mobile')
    text = once(text,
                ".get(Uri.parse('${baseUrl ?? kSubscriptionBaseUrl}/api/announcement'))",
                ".get(Uri.parse('${baseUrl ?? kSubscriptionBaseUrl}/api/announcement').replace(\n"
                "            queryParameters: <String, String>{'lang': l10nNow.localeName.split('_').first}))",
                'paramètre langue conservé')
    return text


def mobile_ad_repository(text: str) -> str:
    if 'fetch({bool strict = false})' not in text or 'if (strict) rethrow;' not in text:
        raise OverlayError('Le repository pub doit conserver son contrat strict')
    return text


def mobile_banner(old: str, new: str) -> str:
    # Le corps visuel ancien contient déjà toutes les traductions. On ne reporte
    # que le cycle de vie et le rafraîchissement, jamais les libellés français.
    text = replace_section(old, new,
                           'class _AnnouncementBannerState extends State<AnnouncementBanner> {',
                           '  Future<void> _openLink() async {', 'cycle du bandeau')
    text = once(text, "import '../../data/announcement_repository.dart';",
                "import '../../data/announcement_repository.dart';\nimport 'announcement_refresh.dart';", 'repli du bandeau')
    text = once(text, 'if (uri == null) return;',
                "if (uri == null || !<String>['http', 'https'].contains(uri.scheme)) return;", 'lien du bandeau')
    text = once(text, 'if (a == null) return const SizedBox.shrink();',
                'if (a == null) return const AnnouncementRefresh(child: SizedBox.shrink());', 'bandeau vide')
    text = once(text, '    return Padding(', '    return AnnouncementRefresh(child: Padding(', 'bandeau visible')
    text = once(text, '      ),\n    );\n  }\n}', '      ),\n    ));\n  }\n}', 'fin du bandeau')
    return text


def mobile_ad_screen(old: str, new: str) -> str:
    start = 'class _StartupAdScreenState extends State<StartupAdScreen>'
    end = '  @override\n  Widget build(BuildContext context) {'
    state = section(new, start, end, 'cycle du lecteur publicitaire')
    state = once(state, '  bool _done = false;', '  bool _done = false;\n  int? _leaseId;', 'bail audio pub')
    lease = section(old, '    // La pub et le film ne doivent pas parler en même temps.',
                    '    // Lance la vidéo (best-effort).', 'bail audio mobile revu')
    state = once(state, '    _controller = VideoController(_player);',
                 '    _controller = VideoController(_player);\n' + lease.rstrip(), 'prise audio conservée')
    state = once(state, '    _player.dispose();',
                 '    final int? lease = _leaseId;\n'
                 '    if (lease != null) ExclusiveAudio.shared.unregister(lease);\n'
                 '    _player.dispose();', 'libération audio conservée')
    return once(old, section(old, start, end, 'ancien lecteur publicitaire'), state, 'lecteur publicitaire mobile')


def mobile_main(old: str, new: str) -> str:
    start = '  Future<void> _resolveAd() async {'
    end = '  /// MISE À JOUR FORCÉE — pilotée à distance depuis le panel.'
    resolution = section(new, start, end, 'résolution pub récente').replace(
        'CastManager.instance.hasActiveSession', '_castBlocksAd')
    text = once(old, section(old, start, end, 'résolution pub mobile'), resolution, 'résolution pub')
    text = once(text, '    super.initState();\n    _checkForcedUpdate();',
                '    super.initState();\n    CastManager.instance.addListener(_onCastForAd);\n'
                '    _checkForcedUpdate();', 'écoute Cast sans modifier son moteur')
    helper = '''  // L'ancien moteur téléphone expose isCasting/hasTarget : aucune migration
  // de session ni de bouton Cast n'est nécessaire pour éviter une pub par-dessus.
  bool get _castBlocksAd => CastManager.instance.isCasting ||
      CastManager.instance.hasTarget || CastManager.instance.state == CastState.connecting;

  void _onCastForAd() {
    if (!mounted || _adDone || !_castBlocksAd) return;
    setState(() { _adDone = true; _adResolved = true; });
  }

'''
    text = once(text, '  @override\n  void dispose() {\n    ForceUpdateChecker.instance.revision.removeListener(_checkForcedUpdate);',
                helper + '  @override\n  void dispose() {\n'
                '    CastManager.instance.removeListener(_onCastForAd);\n'
                '    ForceUpdateChecker.instance.revision.removeListener(_checkForcedUpdate);', 'nettoyage AppEntry conservé')
    return once(text, '                  StartupAdRepository.instance.markShown();\n', '', 'comptage après vraie lecture seulement')


def mobile_heartbeat_test(text: str) -> str:
    text = once(text, '      final previousZuno = AppPlatform.isZuno;\n', '', 'test namespace mobile')
    text = once(text, '      AppPlatform.configureZuno(isAndroidHandset: false);',
                '      AppPlatform.isTv = false;', 'édition téléphone testée')
    text = once(text, '        AppPlatform.isZuno = previousZuno;\n', '', 'restauration namespace mobile')
    text = once(text, "body['platform'] == 'tv'", "body['platform'] == 'mobile'", 'namespace heartbeat mobile')
    text = once(text,
                '      // Une édition TV installée sur téléphone reste le produit ZUNO, mais le\n'
                '      // matériel déclaré au panel doit bien être android_phone.\n',
                '      // Le téléphone garde son produit mobile et déclare son vrai matériel.\n', 'commentaire du test mobile')
    text = text.replace('le produit ZUNO', 'le produit 7 MOTION')
    text = text.replace("appName: 'ZUNO'", "appName: '7 MOTION'")
    text = text.replace("packageName: 'com.sevenmotion.zuno.tv'", "packageName: 'com.manzilionellm.tvking'")
    return text


def plan(source: Path, target: Path) -> dict[str, str]:
    def src(path: str) -> str:
        return (source / path).read_text(encoding='utf-8')

    def dst(path: str) -> str:
        return (target / path).read_text(encoding='utf-8')

    files: dict[str, str] = {}
    ad = 'lib/features/ads/data/startup_ad_repository.dart'
    notice = 'lib/features/simple_home/data/announcement_repository.dart'
    banner = 'lib/features/simple_home/presentation/widgets/announcement_banner.dart'
    player = 'lib/features/ads/presentation/startup_ad_screen.dart'
    identity = 'lib/features/device/data/device_identity.dart'
    heartbeat = 'lib/features/subscription/data/subscription_backend.dart'
    plugin = 'packages/tvking_device/android/src/main/kotlin/com/manzilionellm/tvking_device/TvkingDevicePlugin.kt'
    activity = 'android_overlay/google_cast/MainActivity.kt'
    files[ad] = mobile_ad_repository(src(ad))
    files[notice] = mobile_announcement_repository(src(notice))
    files[banner] = mobile_banner(dst(banner), src(banner))
    files[player] = mobile_ad_screen(dst(player), src(player))
    files['lib/main.dart'] = mobile_main(dst('lib/main.dart'), src('lib/main.dart'))
    files[identity] = replace_section(dst(identity), src(identity),
                                     '  Future<Map<String, String>> deviceInfo() async {',
                                     '  /// Régénère un nouveau MAC', 'cache de fiche native')
    payload = section(src(heartbeat), "        'build': info['build'] ?? '',\n",
                      "        'androidId': androidId,", 'type matériel heartbeat')
    files[heartbeat] = once(dst(heartbeat), "        'build': info['build'] ?? '',\n", payload, 'heartbeat mobile')
    files[plugin] = native_info(dst(plugin), 'appContext')
    files[activity] = native_info(dst(activity), 'applicationContext')
    files[activity] = once(files[activity], 'import io.flutter.embedding.android.FlutterFragmentActivity',
                           'import com.manzilionellm.tvking_device.DeviceHardwareInfo\n'
                           'import io.flutter.embedding.android.FlutterFragmentActivity', 'import fiche native')
    for path in [
        'lib/features/simple_home/presentation/widgets/announcement_refresh.dart',
        'packages/tvking_device/android/src/main/java/com/manzilionellm/tvking_device/DeviceHardwareKind.java',
        'packages/tvking_device/android/src/main/kotlin/com/manzilionellm/tvking_device/DeviceHardwareInfo.kt',
        'packages/tvking_device/logic-test/DeviceHardwareKindTest.java',
        'ci/test-device-hardware-kind.sh',
        'test/features/device/device_info_retry_test.dart',
        'test/features/ads/startup_ad_repository_test.dart',
    ]:
        files[path] = src(path)
    files['test/features/subscription/heartbeat_mobile_device_kind_test.dart'] = mobile_heartbeat_test(
        src('test/features/subscription/heartbeat_device_kind_test.dart'))
    notice_test = src('test/features/simple_home/announcement_sync_test.dart')
    notice_test = once(notice_test, "import 'package:flutter/material.dart';",
                       "import 'package:flutter/material.dart';\n"
                       "import 'package:flutter_localizations/flutter_localizations.dart';\n"
                       "import 'package:tv_king/l10n/generated/app_localizations.dart';", 'localisations du test')
    notice_test = notice_test.replace('MaterialApp(', '''MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate],
      supportedLocales: const [Locale('fr')], locale: const Locale('fr'), ''')
    files['test/features/simple_home/announcement_sync_test.dart'] = notice_test
    files['test/features/subscription/mobile_panel_controls_contract_test.dart'] = src(
        'ci/mobile/fixtures/mobile_panel_controls_contract_test.dart.fixture')
    legacy_test = 'test/features/subscription/panel_settings_refresh_test.dart'
    files[legacy_test] = once(dst(legacy_test), 'throwsA(isA<StateError>())',
                             'throwsA(anyOf(isA<StateError>(), isA<FormatException>()))',
                             'le contrat exige un échec, y compris JSON malformé')
    mobile_controls_options.extend(source, target, files, once)
    return files


def apply(source: Path, target: Path) -> list[str]:
    # Construction complète en mémoire, puis écritures : une ancre inconnue
    # ne laisse pas un arbre à moitié reconstruit et trompeusement compilable.
    files = plan(source, target)
    for relative, contents in files.items():
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(contents, encoding='utf-8')
    return sorted(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-app', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--target', type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        changed = apply(args.source_app.resolve(), args.target.resolve())
    except (OverlayError, OSError) as error:
        parser.exit(1, f'Overlay panel mobile refusé : {error}\n')
    print(f'Panel mobile : {len(changed)} fichiers ciblés préparés ; moteur Cast et version conservés.')


if __name__ == '__main__':
    main()
