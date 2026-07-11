// =========================================================
//  safe_mode_app.dart — Écran de RÉCUPÉRATION (mode sans échec)
// =========================================================
//  Affiché par main_tv.dart quand BootGuard détecte une BOUCLE de crash
//  (3 démarrages non réussis d'affilée). À ce stade, on n'a RIEN initialisé de
//  risqué (ni mpv, ni import, ni repos lourds) : cet écran est volontairement
//  MINIMAL et autonome, pour s'afficher même si la cause du crash était le
//  rendu ou la mémoire.
//
//  Il LIT la dernière phase atteinte au boot précédent (BootGuard.lastFailedPhase)
//  et propose une récupération CIBLÉE :
//    • crash AVANT/PENDANT le rendu (flutterUp/firstFrame) → piste RENDU/COMPAT ;
//    • crash PENDANT l'import (importStart) → piste MÉMOIRE/IMPORT.
//
//  Chaque action pose un drapeau persistant (BootGuard) puis remet le compteur
//  d'échecs à zéro et invite à rouvrir l'app : le prochain démarrage sera donc
//  NORMAL mais tiendra compte du choix (ex. ne pas réimporter).
//
//  NB COULEURS : on utilise des couleurs LITTÉRALES ici (et non AppColors /
//  TvTokens) — même principe que le widget de secours de guarded_main : cet
//  écran ne doit dépendre de RIEN qui pourrait être la cause du plantage.
//  NB TEXTES : traduits via AppLocalizations — cette MaterialApp étant
//  SÉPARÉE de l'app principale, elle déclare ses PROPRES
//  localizationsDelegates / supportedLocales (sinon `context.l10n` casse).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/playlists/data/playlist_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../i18n/l10n_extension.dart';
import 'boot_guard.dart';

// --- Palette Maison Noir (littérale, autonome) ---
const Color _bg = Color(0xFF0A0A0C);
const Color _card = Color(0xFF16151A);
const Color _line = Color(0xFF2A2730);
const Color _text = Color(0xFFF0EDE9);
const Color _muted = Color(0xFF9A958E);
const Color _gold = Color(0xFFD9A441);

class SafeModeApp extends StatelessWidget {
  const SafeModeApp({super.key, required this.failedPhase});

  /// Dernière phase atteinte au démarrage précédent → cible la récupération.
  final BootPhase failedPhase;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
      ),
      home: _SafeModeScreen(failedPhase: failedPhase),
    );
  }
}

class _SafeModeScreen extends StatefulWidget {
  const _SafeModeScreen({required this.failedPhase});
  final BootPhase failedPhase;

  @override
  State<_SafeModeScreen> createState() => _SafeModeScreenState();
}

class _SafeModeScreenState extends State<_SafeModeScreen> {
  bool _busy = false;
  String? _done; // message final (après une action) ; null = écran de choix

  /// `true` si le crash s'est produit pendant l'import → piste mémoire.
  bool get _isImportCrash => widget.failedPhase == BootPhase.importStart;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      // On ne bloque jamais la sortie de boucle : même en cas d'échec d'une
      // action (DB indisponible…), on a au moins remis le compteur à zéro.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = doneMessage;
    });
  }

  // --- Actions de récupération ---

  Future<void> _startWithoutImport() => _run(() async {
        await BootGuard.instance.setSkipAutoImportOnce(true);
        await BootGuard.instance.clearFailures();
      }, context.l10n.safeModeStartNoReloadDone);

  Future<void> _deleteSource() => _run(() async {
        await PlaylistRepository.instance.deleteAllPlaylists();
        await BootGuard.instance.setSkipAutoImportOnce(true);
        await BootGuard.instance.clearFailures();
      }, context.l10n.safeModeSourceDeletedDone);

  Future<void> _compatMode() => _run(() async {
        await BootGuard.instance.setCompatMode(true);
        await BootGuard.instance.clearFailures();
      }, context.l10n.safeModeCompatDone);

  Future<void> _retryNormal() => _run(() async {
        await BootGuard.instance.clearFailures();
      }, context.l10n.safeModeRetryDone);

  Future<void> _closeApp() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: _done != null ? _buildDone() : _buildChoices(),
          ),
        ),
      ),
    );
  }

  Widget _buildDone() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.check_circle_rounded, color: _gold, size: 48),
        const SizedBox(height: 16),
        Text(_done!,
            style: const TextStyle(
                color: _text, fontSize: 20, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 28),
        _SafeButton(
          icon: Icons.power_settings_new_rounded,
          label: context.l10n.safeModeCloseApp,
          autofocus: true,
          recommended: true,
          onSelect: _closeApp,
        ),
      ],
    );
  }

  Widget _buildChoices() {
    final List<Widget> actions = _isImportCrash
        ? <Widget>[
            _SafeButton(
              icon: Icons.play_arrow_rounded,
              label: context.l10n.safeModeStartNoReload,
              hint: context.l10n.safeModeStartNoReloadHint,
              autofocus: true,
              recommended: true,
              onSelect: _busy ? null : _startWithoutImport,
            ),
            const SizedBox(height: 12),
            _SafeButton(
              icon: Icons.delete_sweep_rounded,
              label: context.l10n.safeModeDeleteSource,
              hint: context.l10n.safeModeDeleteSourceHint,
              onSelect: _busy ? null : _deleteSource,
            ),
            const SizedBox(height: 12),
            _SafeButton(
              icon: Icons.refresh_rounded,
              label: context.l10n.safeModeRetryNormal,
              hint: context.l10n.safeModeRetryHintImport,
              onSelect: _busy ? null : _retryNormal,
            ),
          ]
        : <Widget>[
            _SafeButton(
              icon: Icons.tune_rounded,
              label: context.l10n.safeModeCompat,
              hint: context.l10n.safeModeCompatHint,
              autofocus: true,
              recommended: true,
              onSelect: _busy ? null : _compatMode,
            ),
            const SizedBox(height: 12),
            _SafeButton(
              icon: Icons.refresh_rounded,
              label: context.l10n.safeModeRetryNormal,
              hint: context.l10n.safeModeRetryHint,
              onSelect: _busy ? null : _retryNormal,
            ),
            const SizedBox(height: 12),
            _SafeButton(
              icon: Icons.delete_sweep_rounded,
              label: context.l10n.safeModeReset,
              hint: context.l10n.safeModeResetHint,
              onSelect: _busy ? null : _deleteSource,
            ),
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.health_and_safety_rounded, color: _gold, size: 48),
        const SizedBox(height: 16),
        Text(context.l10n.safeModeTitle,
            style: const TextStyle(
                color: _text, fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          _isImportCrash
              ? context.l10n.safeModeBodyImport
              : context.l10n.safeModeBody,
          style: const TextStyle(color: _muted, fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 26),
        FocusTraversalGroup(child: Column(children: actions)),
        if (_busy) ...<Widget>[
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _gold)),
              const SizedBox(width: 12),
              Text(context.l10n.safeModeWait,
                  style: const TextStyle(color: _muted, fontSize: 15)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Bouton focusable D-pad de l'écran de récupération. Met en évidence le focus
/// (bordure + fond or) — indispensable à la télécommande (pas de souris).
class _SafeButton extends StatefulWidget {
  const _SafeButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.hint,
    this.autofocus = false,
    this.recommended = false,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool recommended;

  @override
  State<_SafeButton> createState() => _SafeButtonState();
}

class _SafeButtonState extends State<_SafeButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onSelect != null;
    final Color bg = _focused ? _gold : _card;
    final Color fg = _focused ? const Color(0xFF1A1206) : _text;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (bool f) => setState(() => _focused = f),
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (!enabled) return KeyEventResult.ignored;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? _gold
                    : (widget.recommended ? _gold.withValues(alpha: 0.5) : _line),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(widget.icon, color: fg, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(widget.label,
                          style: TextStyle(
                              color: fg,
                              fontSize: 19,
                              fontWeight: FontWeight.w700)),
                      if (widget.hint != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(widget.hint!,
                            style: TextStyle(
                                color: _focused
                                    ? const Color(0xFF3A2E10)
                                    : _muted,
                                fontSize: 14,
                                height: 1.25)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
