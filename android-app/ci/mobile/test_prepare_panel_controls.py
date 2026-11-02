#!/usr/bin/env python3
"""Teste l'overlay sur le VRAI téléphone préparé par 37fdf + 69eee01.

La recette appelle ces tests avant d'écrire. Ils contrôlent le périmètre du
report, le maintien des contrats historiques et le refus atomique d'une base
inconnue. Aucune copie du moteur Cast Zuno, aucun build ni publication.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import tempfile
import unittest

import prepare_panel_controls as overlay


SOURCE: Path
TARGET: Path
FILES: dict[str, str]
AD = 'lib/features/ads/presentation/startup_ad_screen.dart'
BANNER = 'lib/features/simple_home/presentation/widgets/announcement_banner.dart'
NOTICE = 'lib/features/simple_home/data/announcement_repository.dart'
IDENTITY = 'lib/features/device/data/device_identity.dart'
HEARTBEAT = 'lib/features/subscription/data/subscription_backend.dart'
PLUGIN = 'packages/tvking_device/android/src/main/kotlin/com/manzilionellm/tvking_device/TvkingDevicePlugin.kt'
ACTIVITY = 'android_overlay/google_cast/MainActivity.kt'
LEGACY_TEST = 'test/features/subscription/panel_settings_refresh_test.dart'
OLD_READS = ['lib/main.dart', AD, BANNER, IDENTITY, HEARTBEAT, PLUGIN, ACTIVITY, LEGACY_TEST,
    'lib/core/theme/accent_controller.dart', 'lib/core/theme/lumiere_tokens.dart',
    'lib/core/theme/app_theme.dart', 'lib/features/simple_home/presentation/widgets/category_browser_view.dart',
    'lib/features/playlists/presentation/widgets/xtream_login_form.dart',
    'lib/features/playlists/presentation/m3u_login_sheet.dart',
    'lib/features/simple_home/presentation/simple_home_screen.dart',
    'lib/features/profile/presentation/profile_screen.dart',
    'test/features/simple_home/premium_home_visual_test.dart']


def old(path: str) -> str:
    return (TARGET / path).read_text(encoding='utf-8')


class MobileOverlayTest(unittest.TestCase):
    def test_perimetre_exhaustif_sans_version_ni_moteur_cast(self) -> None:
        expected = set(OLD_READS) | {
            NOTICE, 'lib/features/ads/data/startup_ad_repository.dart',
            'lib/features/simple_home/presentation/widgets/announcement_refresh.dart',
            'packages/tvking_device/android/src/main/java/com/manzilionellm/tvking_device/DeviceHardwareKind.java',
            'packages/tvking_device/android/src/main/kotlin/com/manzilionellm/tvking_device/DeviceHardwareInfo.kt',
            'packages/tvking_device/logic-test/DeviceHardwareKindTest.java',
            'ci/test-device-hardware-kind.sh',
            'test/features/device/device_info_retry_test.dart',
            'test/features/ads/startup_ad_repository_test.dart',
            'test/features/subscription/heartbeat_mobile_device_kind_test.dart',
            'test/features/simple_home/announcement_sync_test.dart',
            'test/features/subscription/mobile_panel_controls_contract_test.dart',
            'lib/core/theme/theme_mode_repository.dart', 'lib/core/theme/remote_theme_settings.dart',
            'lib/features/theme/data/remote_theme_repository.dart',
            'lib/features/simple_home/data/home_layout_repository.dart',
            'lib/features/country_home/data/featured_repository.dart',
            'lib/features/simple_home/presentation/widgets/mobile_panel_sections.dart',
            'test/features/simple_home/mobile_panel_sections_test.dart',
            'test/core/theme/accent_controller_test.dart',
            'test/features/theme/mobile_remote_theme_test.dart',
            'lib/features/feedback/data/feedback_repository.dart',
            'lib/features/feedback/presentation/feedback_sheet.dart',
            'lib/features/playlists/data/default_servers.dart',
            'lib/features/pricing/data/pricing_repository.dart',
            'test/features/pricing/pricing_repository_test.dart',
            'lib/features/pricing/presentation/pricing_banner.dart',
            'test/features/pricing/mobile_pricing_test.dart',
            'test/features/subscription/mobile_panel_freshness_test.dart',
            'lib/features/playlists/presentation/widgets/configured_servers_picker.dart',
            'test/features/playlists/configured_servers_picker_test.dart',
        }
        self.assertEqual(set(FILES), expected)
        self.assertNotIn('pubspec.yaml', FILES)
        self.assertFalse(any(path.startswith('lib/features/cast/') for path in FILES))
        self.assertFalse(any(path.startswith('lib/features/tv/') for path in FILES))

    def test_main_conserve_tout_le_parcours_hors_pub(self) -> None:
        # On retire uniquement les ajouts annoncés ; tout le reste doit retrouver
        # exactement la recette déjà revue, y compris gestes, abonnement et PiP.
        text = FILES['lib/main.dart']
        text = text.replace('theme: AppTheme.daylight,', 'theme: AppTheme.cinema,', 1)
        text = text.replace('themeMode: ThemeModeRepository.instance.mode,', 'themeMode: ThemeMode.dark,', 1)
        start = '  Future<void> _resolveAd() async {'
        end = '  /// MISE À JOUR FORCÉE — pilotée à distance depuis le panel.'
        text = overlay.replace_section(text, old('lib/main.dart'), start, end, 'inverse résolution')
        text = text.replace('    CastManager.instance.addListener(_onCastForAd);\n', '', 1)
        text = text.replace('    CastManager.instance.removeListener(_onCastForAd);\n', '', 1)
        helper_start = '  // L\'ancien moteur téléphone expose isCasting/hasTarget'
        helper_end = '  @override\n  void dispose() {\n    ForceUpdateChecker.instance.revision.removeListener(_checkForcedUpdate);'
        text = overlay.once(text, overlay.section(text, helper_start, helper_end, 'garde Cast'), '', 'garde Cast')
        text = overlay.once(text, '                onDone: () {\n                  if (mounted)',
                            '                onDone: () {\n                  StartupAdRepository.instance.markShown();\n                  if (mounted)', 'ancien comptage')
        text = overlay.replace_section(text, old('lib/main.dart'), '          // Thème ', '          // Internationalisation', 'thème explicite')
        self.assertEqual(text, old('lib/main.dart'))
        self.assertIn('if (mounted && !_adResolved)', FILES['lib/main.dart'])
        self.assertIn('CastManager.instance.state == CastState.connecting', FILES['lib/main.dart'])
        self.assertNotIn('hasActiveSession', FILES['lib/main.dart'])

    def test_les_traductions_et_le_bail_audio_mobile_restent(self) -> None:
        marker = '  @override\n  Widget build(BuildContext context) {'
        self.assertEqual(FILES[AD][FILES[AD].index(marker):], old(AD)[old(AD).index(marker):])
        for retained in ['ExclusiveAudio.shared.register', 'ExclusiveAudio.shared.claim',
                         'ExclusiveAudio.shared.unregister', 'context.l10n.buttonSkip']:
            self.assertIn(retained, FILES[AD])
        for retained in ['l10n.announcementBadgeNew', 'l10n.announcementBadgePromo',
                         'l10n.announcementBadgeMaintenance', 'context.l10n.announcementOpen']:
            self.assertIn(retained, FILES[BANNER])
        self.assertIn("'lang': l10nNow.localeName.split('_').first", FILES[NOTICE])

    def test_ancien_temps_reel_garde_les_erreurs_strictes(self) -> None:
        notice, ad = FILES[NOTICE], FILES['lib/features/ads/data/startup_ad_repository.dart']
        self.assertIn('fetchLatest({bool strict = false})', notice)
        self.assertIn('await fetchLatest(strict: true);', notice)
        self.assertIn('static void notifyChanged()', notice)
        self.assertIn('if (strict) rethrow;', notice)
        self.assertIn('fetch({bool strict = false})', ad)
        self.assertIn('if (strict) rethrow;', ad)
        self.assertIn('mobile_panel_controls_contract_test.dart', '\n'.join(FILES))

    def test_heartbeat_ne_change_ni_identite_ni_bouclier_ni_produit(self) -> None:
        text = FILES[HEARTBEAT]
        start, end = "        'build': info['build'] ?? '',\n", "        'androidId': androidId,"
        text = overlay.once(text, overlay.section(text, start, end, 'type matériel'), start, 'type matériel')
        self.assertEqual(text, old(HEARTBEAT))
        for field in ["'buildLabel': kBuildLabel", "'platform': AppPlatform.id", "'channel': shielded ? ''", "'sources': shielded"]:
            self.assertIn(field, text)
        self.assertIn("body['platform'] == 'mobile'", FILES['test/features/subscription/heartbeat_mobile_device_kind_test.dart'])

    def test_native_ne_remplace_que_la_fiche_materielle(self) -> None:
        for path, context in [(PLUGIN, 'appContext'), (ACTIVITY, 'applicationContext')]:
            before, after = old(path), FILES[path]
            info_start = before.index('"getDeviceInfo" -> {')
            next_handler = before.index('else -> result.notImplemented()', info_start) if path == ACTIVITY else before.index('// RAM de l\'appareil', info_start)
            # Retirer la seule branche getDeviceInfo des deux côtés rend les
            # fichiers identiques ; toutes les autres méthodes sont conservées.
            old_part = before[info_start:next_handler]
            expected_part = overlay.native_info(old_part, context)
            restored = overlay.once(after, expected_part, old_part, 'branche native')
            if path == ACTIVITY:
                restored = restored.replace('import com.manzilionellm.tvking_device.DeviceHardwareInfo\n', '', 1)
            self.assertEqual(restored, before)

    def test_derive_de_recette_refusee_sans_ecriture_partielle(self) -> None:
        with tempfile.TemporaryDirectory(prefix='mobile-panel-overlay-test-') as folder:
            target = Path(folder)
            for name in OLD_READS:
                (target / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(TARGET / name, target / name)
            main = target / 'lib/main.dart'
            main.write_text(main.read_text().replace('Future<void> _resolveAd()', 'Future<void> _nouvelleRecetteAd()'))
            before = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
            with self.assertRaises(overlay.OverlayError):
                overlay.apply(SOURCE, target)
            after = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
            self.assertEqual(after, before)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-app', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--prepared-tree', required=True, type=Path)
    args = parser.parse_args()
    SOURCE, TARGET = args.source_app.resolve(), args.prepared_tree.resolve()
    FILES = overlay.plan(SOURCE, TARGET)
    unittest.main(argv=['test_prepare_panel_controls.py'], verbosity=2)
