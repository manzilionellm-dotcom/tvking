// =========================================================
//  Saisie directe de la liste, sur l'accueil ou dans un écran dédié.
// =========================================================
//  Les contrôleurs persistent entre onglets et erreurs. Le dépôt sérialise
//  cet import avec ceux du panel : aucun compteur partagé n'est effacé par
//  un formulaire qui attend encore son tour.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/local_m3u_bytes.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/open_source_input.dart';
import '../../playlists/presentation/widgets/configured_servers_picker.dart';
import '../core/tv_field_keys.dart';
import '../core/tv_focusable.dart';
import '../data/local_m3u_picker.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
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
    this.pickLocalFileForTesting,
    this.importLocalFileForTesting,
    this.readClipboardForTesting,
    super.key,
  });

  final OpenEntryMode initialMode;
  final VoidCallback? onAdded;
  final bool autofocus;

  /// Une autre opération occupe le dépôt. La saisie reste possible ; seul
  /// l'envoi et le choix du mode attendent pour éviter un import concurrent.
  final bool externalBusy;

  /// Frontière de test, sans fournisseur ni identifiants réels enregistrés.
  final Future<void> Function(OpenSourceDraft draft, String name)?
      submitForTesting;

  /// Test : ne lance pas le sélecteur Android.
  final Future<LocalM3uPick> Function()? pickLocalFileForTesting;

  /// Test : n'écrit pas la liste en base.
  final Future<void> Function(String path)? importLocalFileForTesting;

  /// Test : ne lit pas le presse-papiers du système.
  final Future<String?> Function()? readClipboardForTesting;

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
        ? OpenEntryMode.xtream
        : OpenEntryMode.m3u;
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
        ? OpenSourceInput.xtream(
            server: _server.text,
            username: _username.text,
            password: _password.text,
          )
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
            name: name,
            serverUrl: draft.serverUrl!,
            username: draft.username!,
            password: draft.password!,
          );
        } else {
          await PlaylistRepository.instance.addM3uPlaylist(
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
      BlackBox.instance.warn(
        'SOURCE',
        'ajout source ouverte échoué (${error.runtimeType})',
      );
      if (mounted) setState(() => _error = 'connect_failed');
    } finally {
      // Le wrapper du dépôt a déjà nettoyé le bus AVANT de libérer la file.
      if (mounted) {
        setState(() {
          _busy = false;
          _importStarted = false;
        });
      }
    }
    if (mounted && added) widget.onAdded?.call();
  }

  Future<void> _paste() async {
    if (_blocked) return;
    final Future<String?> Function()? read = widget.readClipboardForTesting;
    final String text = (read != null
            ? (await read())
            : (await Clipboard.getData(Clipboard.kTextPlain))?.text)
        ?.trim() ??
        '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _error = OpenSourceInput.errNeedUrl);
      return;
    }
    final OpenSourceParse parsed = OpenSourceInput.playlistLink(text);
    if (!parsed.isValid || parsed.draft == null) {
      setState(() => _error = parsed.error ?? OpenSourceInput.errNeedUrl);
      return;
    }
    final OpenSourceDraft draft = parsed.draft!;
    setState(() {
      _error = null;
      if (draft.kind == OpenSourceKind.xtream) {
        _mode = OpenEntryMode.xtream;
        _server.text = draft.serverUrl ?? '';
        _username.text = draft.username ?? '';
        _password.text = draft.password ?? '';
      } else {
        _mode = OpenEntryMode.m3u;
        _link.text = draft.m3uUrl ?? '';
      }
    });
  }

  Future<void> _pickFile() async {
    if (_blocked) return;
    final Future<LocalM3uPick> Function()? fake = widget.pickLocalFileForTesting;
    final LocalM3uPick pick =
        fake != null ? await fake() : await LocalM3uPick.ask();
    if (!mounted || pick.status == LocalM3uPickStatus.cancelled) return;
    if (pick.status != LocalM3uPickStatus.ok || (pick.path ?? '').isEmpty) {
      setState(() => _error = switch (pick.status) {
            LocalM3uPickStatus.empty => 'local_empty',
            LocalM3uPickStatus.tooBig => 'local_too_big',
            _ => 'local_unavailable',
          });
      return;
    }
    final String path = pick.path!;
    final String name = context.l10n.tvMyListHint;
    final Future<void> Function(String path)? importer =
        widget.importLocalFileForTesting;
    setState(() {
      _busy = true;
      _importStarted = false;
      _error = null;
    });
    bool added = false;
    try {
      if (importer != null) {
        await importer(path);
      } else {
        await RemoteSourceRepository.runUserImport<void>(() async {
          if (mounted) setState(() => _importStarted = true);
          await PlaylistRepository.instance.addM3uFromLocalFile(
            name: name,
            path: path,
          );
        });
      }
      added = true;
    } on LocalM3uRead catch (error) {
      if (mounted) setState(() => _error = error.code);
    } catch (error) {
      BlackBox.instance.warn(
        'SOURCE',
        'fichier M3U refusé (${error.runtimeType})',
      );
      if (mounted) setState(() => _error = 'm3u_failed');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importStarted = false;
        });
      }
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
          color: TvAppTokens.of(context).panel,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvAppTokens.of(context).accentDeep),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.tvAddListTitle,
              style: TvAppTokens.of(context)
                  .display(28, color: TvAppTokens.of(context).text),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.tvSourcePasteHelp,
              style: TvAppTokens.of(context)
                  .ui(13, color: TvAppTokens.of(context).muted),
            ),
            const SizedBox(height: 14),
            // Au-dessus des modes, jamais entre le dernier champ et
            // Connexion : Bas et Entrée passent du mot de passe (ou du
            // lien) directement à Connexion (TvFieldKeys).
            Row(
              children: <Widget>[
                Expanded(
                  child: _SideAction(
                    key: const ValueKey<String>('tv-source-paste'),
                    label: l10n.tvPasteClipboard,
                    enabled: !_blocked,
                    onSelect: _paste,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SideAction(
                    key: const ValueKey<String>('tv-source-file'),
                    label: l10n.tvPickLocalFile,
                    enabled: !_blocked,
                    onSelect: _pickFile,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ModeChip(
                    key: const ValueKey<String>('tv-source-mode-xtream'),
                    label: l10n.playlistTypeXtream,
                    selected: _mode == OpenEntryMode.xtream,
                    enabled: !_blocked,
                    onSelect: () => _select(OpenEntryMode.xtream),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeChip(
                    key: const ValueKey<String>('tv-source-mode-m3u'),
                    label: l10n.playlistTypeM3u,
                    selected: _mode == OpenEntryMode.m3u,
                    enabled: !_blocked,
                    onSelect: () => _select(OpenEntryMode.m3u),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == OpenEntryMode.xtream) ...<Widget>[
              ConfiguredServersPicker(
                serverController: _server,
                enabled: !_blocked,
                normalizeUrl: (url) => const SourceHttpInputFormatter()
                    .formatEditUpdate(
                        TextEditingValue.empty, TextEditingValue(text: url))
                    .text,
              ),
              _SourceField(
                key: const ValueKey<String>('tv-source-server'),
                controller: _server,
                focusNode: _serverFocus,
                label: l10n.tvFieldServer,
                hint: 'http://',
                enabled: !_busy,
                autofocus: widget.autofocus,
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
                controller: _username,
                focusNode: _usernameFocus,
                label: l10n.tvFieldUser,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              _SourceField(
                key: const ValueKey<String>('tv-source-password'),
                controller: _password,
                focusNode: _passwordFocus,
                label: l10n.tvFieldPass,
                enabled: !_busy,
                obscure: !_passwordVisible,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffix: IconButton(
                  tooltip: _passwordVisible
                      ? l10n.tvHidePassword
                      : l10n.tvShowPassword,
                  onPressed: _busy
                      ? null
                      : () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: TvAppTokens.of(context).accentBright,
                  ),
                ),
              ),
            ] else
              _SourceField(
                key: const ValueKey<String>('tv-source-m3u'),
                controller: _link,
                focusNode: _linkFocus,
                label: l10n.tvFieldM3uUrl,
                hint: 'http://',
                enabled: !_busy,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.url,
                inputFormatters: const <TextInputFormatter>[
                  SourceHttpInputFormatter(),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  sourceErrorText(context, _error!),
                  key: const ValueKey<String>('tv-source-error'),
                  style: TvAppTokens.of(context)
                      .ui(14, color: TvAppTokens.of(context).live),
                ),
              ),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              ValueListenableBuilder<ImportProgress?>(
                valueListenable: ImportProgressBus.current,
                builder: (context, progress, _) => TvChannelLoadingStatus(
                  checking: false,
                  importing: true,
                  progress: _importStarted
                      ? progress
                      : const ImportProgress(ImportStage.connecting),
                ),
              ),
            ],
            const SizedBox(height: 18),
            // Le bouton conserve le comportement TV. Focus et toucher sont
            // aussi désactivés pendant un import, pas seulement le callback.
            ExcludeFocus(
              excluding: _blocked,
              child: IgnorePointer(
                ignoring: _blocked,
                child: Opacity(
                  opacity: _blocked ? 0.55 : 1,
                  child: TvCtaButton(
                    key: const ValueKey<String>('tv-source-submit'),
                    label: _busy ? l10n.tvConnecting : l10n.loginConnectLoad,
                    onSelect: _blocked ? null : _submit,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vrai TextField : tactile, clavier physique, D-pad et copier-coller.
class _SourceField extends StatelessWidget {
  const _SourceField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.enabled,
    required this.textInputAction,
    required this.onSubmitted,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.suffix,
    super.key,
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
    return TvFieldKeys(
      child: TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onSubmitted: enabled ? onSubmitted : null,
      autocorrect: false,
      enableSuggestions: false,
      // Les codes et URL gardent leur ordre même dans une interface arabe.
      // Le clavier ne doit pas apprendre les identifiants de connexion.
      textDirection: TextDirection.ltr,
      enableIMEPersonalizedLearning: false,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      cursorColor: TvAppTokens.of(context).accent,
      style: TvAppTokens.of(context)
          .ui(17, weight: FontWeight.w500, color: TvAppTokens.of(context).text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix == null
            ? null
            : ExcludeFocus(child: suffix!),
        labelStyle: TvAppTokens.of(context)
            .ui(13, color: TvAppTokens.of(context).muted),
        hintStyle: TvAppTokens.of(context)
            .ui(14, color: TvAppTokens.of(context).mutedDim),
        floatingLabelStyle: TvAppTokens.of(context)
            .ui(13, color: TvAppTokens.of(context).accentBright),
        filled: true,
        fillColor: TvAppTokens.of(context).card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: border(TvAppTokens.of(context).line, 1),
        disabledBorder: border(TvAppTokens.of(context).lineSoft, 1),
        focusedBorder: border(TvAppTokens.of(context).accent, 2),
      ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: TvFocusBuilder(
          enabled: enabled,
          scale: TvFocusScale.none,
          onSelect: enabled ? onSelect : null,
          builder: (context, focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: focused
                  ? TvAppTokens.of(context).accent
                  : selected
                      ? TvAppTokens.of(context).sel
                      : TvAppTokens.of(context).panel,
              borderRadius: BorderRadius.circular(TvTokens.rButton),
              border: Border.all(
                color: focused || selected
                    ? TvAppTokens.of(context).accent
                    : TvAppTokens.of(context).line,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TvAppTokens.of(context).ui(
                15,
                weight: FontWeight.w600,
                color: focused
                    ? TvAppTokens.of(context).onAccent
                    : selected
                        ? TvAppTokens.of(context).accentBright
                        : TvAppTokens.of(context).muted,
              ),
            ),
          ),
        ),
      );
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    super.key,
    required this.label,
    required this.enabled,
    required this.onSelect,
  });

  final String label;
  final bool enabled;
  final Future<void> Function() onSelect;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: !enabled,
      child: TvFocusable(
        enabled: enabled,
        onSelect: enabled ? () => unawaited(onSelect()) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TvAppTokens.of(context).ui(16, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
