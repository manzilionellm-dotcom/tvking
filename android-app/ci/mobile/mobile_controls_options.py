"""Consommateurs des options panel sur le téléphone figé, sans toucher au Cast."""
from pathlib import Path
import re


def extend(source: Path, target: Path, files: dict[str, str], once) -> None:
    def old(path): return (target / path).read_text()
    def asset(path): return (source / 'ci/mobile/options' / path).read_text()
    for path in ['lib/core/theme/theme_mode_repository.dart',
                 'lib/core/theme/remote_theme_settings.dart',
                 'lib/features/theme/data/remote_theme_repository.dart',
                 'lib/features/simple_home/data/home_layout_repository.dart',
                 'lib/features/country_home/data/featured_repository.dart',
                 'lib/features/feedback/data/feedback_repository.dart',
                 'lib/features/feedback/presentation/feedback_sheet.dart',
                 'lib/features/playlists/data/default_servers.dart',
                 'lib/features/pricing/data/pricing_repository.dart',
                 'lib/features/playlists/presentation/widgets/configured_servers_picker.dart',
                 'test/features/playlists/configured_servers_picker_test.dart',
                 'test/features/pricing/pricing_repository_test.dart']:
        files[path] = (source / path).read_text()
    # Les clés d'accent locales historiques restent conservées. Seule une
    # commande explicite du panel surcharge la palette du téléphone.
    p = 'lib/core/theme/accent_controller.dart'
    text = old(p)
    text = once(text, '  AccentTheme get current => kMotionAccent;',
                '  AccentTheme? _remote;\n  AccentTheme get current => _remote ?? kMotionAccent;', 'accent distant')
    text = once(text, '  void applyCustom(Color accent) {}', '''  void applyCustom(Color accent) {
    _remote = AccentTheme.derive(id: 'panel', label: 'Panel', accent: accent);
    notifyListeners();
  }

  void clearCustom() {
    if (_remote == null) return;
    _remote = null;
    notifyListeners();
  }''', 'application de l’accent')
    files[p] = text
    p = 'lib/core/theme/lumiere_tokens.dart'
    text = once(old(p), '  static const LumiereColors daylight = cinema;', asset('daylight.txt').rstrip(), 'vraie palette claire')
    text = text.replace('    - Daylight : alias conservé pour les appels des anciennes versions.',
                        '    - Daylight : palette claire pilotable depuis le panel.')
    text = text.replace('  /// Alias historique : tous les écrans mobiles gardent l’identité noire,\n  /// même si un ancien appel demande encore la palette Daylight.',
                        '  /// Palette claire pour les surfaces de navigation et de saisie.')
    files[p] = text
    p = 'lib/core/theme/app_theme.dart'
    text = old(p)
    text = once(text, "import 'app_colors.dart';", "import 'app_colors.dart';\nimport 'accent_controller.dart';", 'thème accent')
    text = once(text, '  static ThemeData get daylight => cinema;', '''  static ThemeData get daylight => _buildTheme(
    brightness: Brightness.light,
    palette: _panelPalette(LumiereColors.daylight),
    primaryOnAccent: _onAccent(_panelPalette(LumiereColors.daylight).accentEmber),
  );

  // Le fond vidéo et les contrôles Cast gardent leurs tokens AppColors fixes.
  // Les écrans modernes consomment cette extension contextuelle.
  static LumiereColors _panelPalette(LumiereColors base) {
    if (AccentController.instance.current.id != 'panel') return base;
    final accent = AccentController.instance.current.accent;
    return base.copyWith(accentEmber: accent, emberGlow: accent,
      emberHalo: accent, emberDeep: AccentController.instance.current.muted);
  }

  static Color _onAccent(Color color) => color.computeLuminance() > .179
      ? AppColors.onAccent : AppColors.textPrimary;''', 'thème clair')
    text = once(text, '        palette: LumiereColors.cinema,', '        palette: _panelPalette(LumiereColors.cinema),', 'palette sombre')
    text = once(text, '        primaryOnAccent: AppColors.onAccent,\n        monochrome: true,',
                "        primaryOnAccent: _onAccent(AccentController.instance.current.accent),\n        monochrome: AccentController.instance.current.id != 'panel',", 'accent du thème sombre')
    text = text.replace("//  Cinema et l'alias historique Daylight partagent la charte mobile noire.",
                        '//  Cinema garde la charte noire ; Daylight rend la commande claire du panel.')
    text = text.replace('  /// Compatibilité : une ancienne demande de mode clair garde la charte noire.',
                        '  /// Palette claire pour les écrans et saisies du téléphone.')
    files[p] = text
    p = 'lib/main.dart'
    text = files[p]
    text = once(text, '          theme: AppTheme.cinema,\n          darkTheme: AppTheme.cinema,\n          themeMode: ThemeMode.dark,',
                '          theme: AppTheme.daylight,\n          darkTheme: AppTheme.cinema,\n          themeMode: ThemeModeRepository.instance.mode,', 'choix du thème visible')
    start = text.index('          // Thème VERROUILLÉ')
    end = text.index('          theme:', start)
    text = text[:start] + '          // Thème du panel : palette réactive, Cast/vidéo gardent leurs tokens sombres.\n' + text[end:]
    files[p] = text
    p = 'lib/features/simple_home/presentation/widgets/category_browser_view.dart'
    text = old(p)
    text = once(text, "import 'adult_access_dialog.dart';", "import 'adult_access_dialog.dart';\nimport 'mobile_panel_sections.dart';", 'rangées panel')
    text = once(text, '                _buildRecentRail(),\n                LiveNowFavoritesRow(allowedChannels: _visibleChannels),', '''                MobilePanelSections(
                  channels: _visibleChannels,
                  recent: _buildRecentRail(),
                  favorites: LiveNowFavoritesRow(allowedChannels: _visibleChannels),
                  onChannel: (channel) => playChannel(context, channel,
                    zapPlaylist: _visibleChannels),
                ),''', 'consommation disposition et favori')
    files[p] = text
    files['lib/features/simple_home/presentation/widgets/mobile_panel_sections.dart'] = asset('mobile_panel_sections.dart.fixture')
    files['test/features/simple_home/mobile_panel_sections_test.dart'] = asset('mobile_panel_sections_test.dart.fixture')
    files['test/core/theme/accent_controller_test.dart'] = asset('accent_controller_test.dart.fixture')
    files['test/features/theme/mobile_remote_theme_test.dart'] = asset('mobile_remote_theme_test.dart.fixture')
    files['lib/features/pricing/presentation/pricing_banner.dart'] = asset('mobile_pricing_banner.dart.fixture')
    files['test/features/pricing/mobile_pricing_test.dart'] = asset('mobile_pricing_test.dart.fixture')
    files['test/features/subscription/mobile_panel_freshness_test.dart'] = asset('mobile_panel_freshness_test.dart.fixture')

    for p, anchor in [
        ('lib/features/playlists/presentation/widgets/xtream_login_form.dart',
         '          // Lien du serveur (URL).'),
        ('lib/features/playlists/presentation/m3u_login_sheet.dart',
         '                  _label(context.l10n.loginServerXtream),'),
    ]:
        text = old(p)
        prefix = '' if '/widgets/' in p else 'widgets/'
        import_line = "import '" + prefix + "configured_servers_picker.dart';\n"
        text = import_line + text
        indent = '          ' if '/widgets/' in p else '                  '
        text = once(text, anchor, indent + 'ConfiguredServersPicker(serverController: _serverCtrl, enabled: !_busy),\n' + anchor,
                    'serveurs explicites mobile')
        files[p] = text

    # Les surfaces de saisie et l'accueil lisent la même palette contextuelle.
    # Les tokens fixes du lecteur/Cast et leur code ne sont jamais réécrits.
    themed = [
        'lib/features/simple_home/presentation/simple_home_screen.dart',
        'lib/features/simple_home/presentation/widgets/category_browser_view.dart',
        'lib/features/playlists/presentation/widgets/xtream_login_form.dart',
        'lib/features/playlists/presentation/m3u_login_sheet.dart',
        'lib/features/feedback/presentation/feedback_sheet.dart',
        'lib/features/profile/presentation/profile_screen.dart',
    ]
    colors = {'background': 'canvas', 'surface': 'elevated',
              'border': 'border', 'textPrimary': 'textPrimary',
              'textSecondary': 'textSecondary', 'textTertiary': 'textTertiary',
              'live': 'statusError', 'warning': 'statusWarning'}
    for p in themed:
        text = files[p] if p in files else old(p)
        for legacy, role in colors.items():
            text = re.sub(r'AppColors\.' + legacy + r'\b',
                          'AppColors.lumiere(context).' + role, text)
        text = re.sub(r'AppColors\.accent\b', 'Theme.of(context).colorScheme.primary', text)
        text = re.sub(r'AppColors\.onAccent\b', 'Theme.of(context).colorScheme.onPrimary', text)
        for constructor in ['BoxDecoration', 'Icon', 'TextStyle', 'LinearGradient']:
            text = text.replace('const ' + constructor + '(', constructor + '(')
        text = text.replace('const AlwaysStoppedAnimation<Color>(', 'AlwaysStoppedAnimation<Color>(')
        text = text.replace('style: AppTextStyles.brandTagline,',
            'style: AppTextStyles.brandTagline.copyWith(color: AppColors.lumiere(context).textSecondary),')
        text = text.replace('AppTextStyles.headlineMedium.copyWith(fontSize: 17)',
            'AppTextStyles.headlineMedium.copyWith(fontSize: 17, color: AppColors.lumiere(context).textPrimary)')
        # Deux anciens styles de formulaire portaient un blanc explicite.
        if '/playlists/presentation/' in p:
            text = text.replace('AppTextStyles.headlineLarge.copyWith(fontSize: 22)',
                'AppTextStyles.headlineLarge.copyWith(fontSize: 22, color: AppColors.lumiere(context).textPrimary)')
            text = re.sub(r'AppTextStyles\.bodyMedium\s*\.copyWith\(fontSize: 12\)',
                'AppTextStyles.bodyMedium.copyWith(fontSize: 12, color: AppColors.lumiere(context).textPrimary)', text)
            text = text.replace('style: AppTextStyles.bodyMedium,',
                'style: Theme.of(context).snackBarTheme.contentTextStyle,')
        files[p] = text

    p = 'lib/features/feedback/presentation/feedback_sheet.dart'
    files[p] = files[p].replace('context.l10n.tvLater', 'context.l10n.resumeBannerDismiss')

    # Le catalogue est paresseux : les rangées ajoutées peuvent placer « Sport »
    # hors de la première fenêtre. Finder.last lève avant de pouvoir défiler.
    p = 'test/features/simple_home/premium_home_visual_test.dart'
    files[p] = once(old(p), "scrollUntilVisible(find.text('Sport').last, 160,",
                    "scrollUntilVisible(find.text('Sport'), 160,",
                    'navigation après les rangées du panel')

    p = 'test/features/subscription/panel_settings_refresh_test.dart'
    files[p] = once(files[p], "'/api/pricing': <String, Object>{'currency':",
                    "'/api/pricing': <String, Object>{'configured':true,'currency':",
                    'tarifs explicitement configurés')

    # La carte et l'invitation différée peuvent arriver ensemble ; une seule
    # feuille est autorisée et le verrou est libéré même après fermeture Retour.
    p = 'lib/features/feedback/presentation/feedback_sheet.dart'
    text = files[p]
    start = text.index('Future<void> maybeShowFeedbackSheet(BuildContext context) async {')
    end = text.index('class _FeedbackSheet extends StatefulWidget', start)
    original = text[start:end]
    body = original[original.index('{') + 1:original.rfind('}')]
    replacement = ('bool _feedbackSheetOpen = false;\n\n'
        'Future<void> maybeShowFeedbackSheet(BuildContext context) async {\n'
        '  if (_feedbackSheetOpen) return;\n'
        '  _feedbackSheetOpen = true;\n'
        '  try {' + body + '\n  } finally {\n    _feedbackSheetOpen = false;\n  }\n}\n\n')
    files[p] = once(text, original, replacement, 'une seule invitation mobile')
