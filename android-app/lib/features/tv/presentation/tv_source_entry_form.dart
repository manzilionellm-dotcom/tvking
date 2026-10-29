// =========================================================
//  Saisie directe de la liste, sur l'accueil ou dans un écran dédié.
// =========================================================
//  Les contrôleurs persistent entre onglets et erreurs. Le dépôt sérialise
//  cet import avec ceux du panel : aucun compteur partagé n'est effacé par
//  un formulaire qui attend encore son tour.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/open_source_input.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'source_http_input_formatter.dart';
import 'tv_channel_loading_status.dart';
import 'tv_components.dart';
import 'tv_source_error_text.dart';

class TvSourceEntryForm extends StatefulWidget {
  const TvSourceEntryForm({
    this.initialMode = OpenEntryMode.xtream,
    this.onAdded,
    this.autofocus = false,
    this.externalBusy = false,
    this.submitForTesting,
    super.key,
  });

  final OpenEntryMode initialMode;
  final VoidCallback? onAdded;
  final bool autofocus;

  /// Une autre opération occupe le dépôt. La saisie reste possible ; seul
  /// l'envoi et le choix du mode attendent pour éviter un import concurrent.
  final bool externalBusy;

  /// Frontière de test, sans fournisseur ni identifiants réels enregistrés.
  final Future<void> Function(OpenSourceDraft draft, String name)? submitForTesting;

  @override
  State<TvSourceEntryForm> createState() => _TvSourceEntryFormState();
}

class _TvSourceEntryFormState extends State<TvSourceEntryForm> {
  final TextEditingController _server = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _link = TextEditingController();
  final FocusNode _serverFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _linkFocus = FocusNode();
  late OpenEntryMode _mode;
  bool _busy = false;
  bool _importStarted = false;
  bool _passwordVisible = false;
  String? _error;

  bool get _blocked => _busy || widget.externalBusy;

  @override
  void initState() {
    super.initState();
    // Le raccourci historique « Lien lecteur » ouvre M3U. playlistLink
    // reconnaît déjà get.php/player_api.php avec leurs identifiants.
    _mode = widget.initialMode == OpenEntryMode.xtream
        ? OpenEntryMode.xtream : OpenEntryMode.m3u;
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _link.dispose();
    _serverFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  void _select(OpenEntryMode mode) {
    if (_blocked || mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    // Garde synchrone : deux gestes dans la même frame ne lancent qu'un job.
    if (_blocked) return;
    final OpenSourceParse parsed = _mode == OpenEntryMode.xtream
        ? OpenSourceInput.xtream(server: _server.text,
            username: _username.text, password: _password.text)
        : OpenSourceInput.playlistLink(_link.text);
    if (!parsed.isValid || parsed.draft == null) {
      setState(() => _error = parsed.error ?? OpenSourceInput.errNeedUrl);
      return;
    }
    // Capturer la saisie et la traduction avant toute attente. Le formulaire
    // peut disparaître dès le premier lot de chaînes, l'import doit finir.
    final OpenSourceDraft draft = parsed.draft!;
    final String name = context.l10n.tvMyListHint;
    final submit = widget.submitForTesting;
    setState(() {
      _busy = true;
      _importStarted = false;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    bool added = false;
    try {
      await RemoteSourceRepository.runUserImport<void>(() async {
        if (mounted) setState(() => _importStarted = true);
        if (submit != null) {
          await submit(draft, name);
        } else if (draft.kind == OpenSourceKind.xtream) {
          await PlaylistRepository.instance.addXtreamPlaylist(
            allowHttpCompatibility: true,
            name: name,
            serverUrl: draft.serverUrl!,
            username: draft.username!,
            password: draft.password!,
          );
        } else {
          await PlaylistRepository.instance.addM3uPlaylist(
            allowHttpCompatibility: true,
            name: name,
            url: draft.m3uUrl!,
          );
        }
      });
      added = true;
      BlackBox.instance.info('SOURCE', 'source ouverte ajoutée');
    } catch (error) {
      // Une exception fournisseur peut contenir des identifiants dans l'URL.
      // Seul son type est journalisé ; le message public reste traduit.
      BlackBox.instance.warn('SOURCE',
          'ajout source ouverte échoué (${error.runtimeType})');
      if (mounted) setState(() => _error = 'connect_failed');
    } finally {
      // Le wrapper du dépôt a déjà nettoyé le bus AVANT de libérer la file.
      if (mounted) setState(() {
        _busy = false;
        _importStarted = false;
      });
    }
    if (mounted && added) widget.onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Container(
        key: const ValueKey<String>('tv-source-entry-form'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TvTokens.panel,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.accentDeep),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.tvAddListTitle,
                style: TvTokens.display(28, color: TvTokens.text)),
            const SizedBox(height: 6),
            Text(l10n.tvSourcePasteHelp,
                style: TvTokens.ui(13, color: TvTokens.muted)),
            const SizedBox(height: 18),
            Row(children: <Widget>[
              Expanded(child: _ModeChip(
                key: const ValueKey<String>('tv-source-mode-xtream'),
                label: l10n.playlistTypeXtream,
                selected: _mode == OpenEntryMode.xtream,
                enabled: !_blocked,
                onSelect: () => _select(OpenEntryMode.xtream),
              )),
              const SizedBox(width: 8),
              Expanded(child: _ModeChip(
                key: const ValueKey<String>('tv-source-mode-m3u'),
                label: l10n.playlistTypeM3u,
                selected: _mode == OpenEntryMode.m3u,
                enabled: !_blocked,
                onSelect: () => _select(OpenEntryMode.m3u),
              )),
            ]),
            const SizedBox(height: 16),
            if (_mode == OpenEntryMode.xtream) ...<Widget>[
              _SourceField(
                key: const ValueKey<String>('tv-source-server'),
                controller: _server, focusNode: _serverFocus,
                label: l10n.tvFieldServer, hint: 'http://',
                enabled: !_busy, autofocus: widget.autofocus,
                keyboardType: TextInputType.url,
                inputFormatters: const <TextInputFormatter>[
                  SourceHttpInputFormatter(),
                ],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _usernameFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              _SourceField(
                key: const ValueKey<String>('tv-source-user'),
                controller: _username, focusNode: _usernameFocus,
                label: l10n.tvFieldUser, enabled: !_busy,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              _SourceField(
                key: const ValueKey<String>('tv-source-password'),
                controller: _password, focusNode: _passwordFocus,
                label: l10n.tvFieldPass, enabled: !_busy,
                obscure: !_passwordVisible,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffix: IconButton(
                  tooltip: _passwordVisible
                      ? l10n.tvHidePassword : l10n.tvShowPassword,
                  onPressed: _busy ? null : () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(_passwordVisible
                      ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: TvTokens.accentBright),
                ),
              ),
            ] else
              _SourceField(
                key: const ValueKey<String>('tv-source-m3u'),
                controller: _link, focusNode: _linkFocus,
                label: l10n.tvFieldM3uUrl, hint: 'http://',
                enabled: !_busy, autofocus: widget.autofocus,
                keyboardType: TextInputType.url,
                inputFormatters: const <TextInputFormatter>[
                  SourceHttpInputFormatter(),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(
                sourceErrorText(context, _error!),
                key: const ValueKey<String>('tv-source-error'),
                style: TvTokens.ui(14, color: TvTokens.live),
              )),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              ValueListenableBuilder<ImportProgress?>(
                valueListenable: ImportProgressBus.current,
                builder: (context, progress, _) => TvChannelLoadingStatus(
                  checking: false,
                  importing: true,
                  progress: _importStarted ? progress
                      : const ImportProgress(ImportStage.connecting),
                ),
              ),
            ],
            const SizedBox(height: 18),
            // Le bouton conserve le comportement TV. Focus et toucher sont
            // aussi désactivés pendant un import, pas seulement le callback.
            ExcludeFocus(excluding: _blocked, child: IgnorePointer(
              ignoring: _blocked,
              child: Opacity(opacity: _blocked ? 0.55 : 1,
                child: TvCtaButton(
                  key: const ValueKey<String>('tv-source-submit'),
                  label: _busy ? l10n.tvConnecting : l10n.loginConnectLoad,
                  onSelect: _blocked ? null : _submit,
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

/// Vrai TextField : tactile, clavier physique, D-pad et copier-coller.
class _SourceField extends StatelessWidget {
  const _SourceField({
    required this.controller, required this.focusNode, required this.label,
    required this.enabled, required this.textInputAction, required this.onSubmitted,
    this.hint, this.obscure = false, this.autofocus = false,
    this.keyboardType, this.inputFormatters, this.suffix, super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String> onSubmitted;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(TvTokens.rButton),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      controller: controller, focusNode: focusNode, enabled: enabled,
      autofocus: autofocus, obscureText: obscure, keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onSubmitted: enabled ? onSubmitted : null,
      autocorrect: false, enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      cursorColor: TvTokens.accent,
      style: TvTokens.ui(17, weight: FontWeight.w500, color: TvTokens.text),
      decoration: InputDecoration(
        labelText: label, hintText: hint, suffixIcon: suffix,
        labelStyle: TvTokens.ui(13, color: TvTokens.muted),
        hintStyle: TvTokens.ui(14, color: TvTokens.mutedDim),
        floatingLabelStyle: TvTokens.ui(13, color: TvTokens.accentBright),
        filled: true, fillColor: TvTokens.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: border(TvTokens.line, 1),
        disabledBorder: border(TvTokens.lineSoft, 1),
        focusedBorder: border(TvTokens.accent, 2),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected,
    required this.enabled, required this.onSelect, super.key});

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, selected: selected, enabled: enabled,
    child: TvFocusBuilder(
      enabled: enabled, scale: TvFocusScale.none,
      onSelect: enabled ? onSelect : null,
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: focused ? TvTokens.accent
              : selected ? TvTokens.sel : TvTokens.panel,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: focused || selected
              ? TvTokens.accent : TvTokens.line),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TvTokens.ui(15, weight: FontWeight.w600,
            color: focused ? TvTokens.onAccent
                : selected ? TvTokens.accentBright : TvTokens.muted,
          ),
        ),
      ),
    ),
  );
}
