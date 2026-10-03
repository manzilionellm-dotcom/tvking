// =========================================================
//  tv_add_source_screen.dart — « J'ajoute ma propre source »
// =========================================================
//  Plus de pastilles « Serveur 1 / Serveur 2 ». La personne choisit
//  comment elle apporte SA source, chez n'importe quel fournisseur :
//    • Xtream Codes (adresse, nom, mot de passe) ;
//    • une adresse M3U ou M3U8, avec ou sans identifiants ;
//    • une adresse de lecteur (get.php).
//
//  Les champs sont de vrais TextField : télécommande de la box,
//  clavier, copier-coller, et le téléphone déjà appairé (le texte
//  du QR « Télécommande » remplit le champ qui a le focus — voir
//  remote_actions.dart). On ne refait pas ce mécanisme ici.
//
//  Plusieurs sources : cet écran en ajoute une. Les autres restent.
//  Une liste déjà en base n'est pas touchée.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/open_source_input.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_import_progress_label.dart';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({
    super.key,
    this.initialMode = OpenEntryMode.xtream,
  });

  /// Onglet ouvert en premier. Les trois restent accessibles.
  final OpenEntryMode initialMode;

  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  final TextEditingController _serverC = TextEditingController();
  final TextEditingController _userC = TextEditingController();
  final TextEditingController _passC = TextEditingController();
  final TextEditingController _linkC = TextEditingController();

  late OpenEntryMode _mode;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _serverC.dispose();
    _userC.dispose();
    _passC.dispose();
    _linkC.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final OpenSourceParse parsed = switch (_mode) {
      OpenEntryMode.xtream => OpenSourceInput.xtream(
          server: _serverC.text,
          username: _userC.text,
          password: _passC.text,
        ),
      OpenEntryMode.m3u => OpenSourceInput.playlistLink(_linkC.text),
      OpenEntryMode.player => OpenSourceInput.playerLink(_linkC.text),
    };
    if (!parsed.isValid || parsed.draft == null) {
      setState(() => _error = parsed.error ?? OpenSourceInput.errNeedUrl);
      return;
    }
    final OpenSourceDraft draft = parsed.draft!;
    setState(() {
      _busy = true;
      _error = null;
    });
    ImportProgressBus.clear();
    // Pas d'adresse ni de mot de passe dans le journal : seulement le mode.
    BlackBox.instance.breadcrumb('Ajout source ouverte (${_mode.name})');
    try {
      final String name = context.l10n.tvMyListHint;
      if (draft.kind == OpenSourceKind.xtream) {
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
      BlackBox.instance.breadcrumb('');
      BlackBox.instance.info('SOURCE', 'source ouverte ajoutée');
      ImportProgressBus.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      BlackBox.instance.error('SOURCE', 'ajout source ouverte ÉCHEC', e);
      BlackBox.instance.breadcrumb('');
      ImportProgressBus.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _safeMessage(e);
        });
      }
    }
  }

  /// Phrase du dépôt si elle est déjà en français et sans secret.
  /// Sinon la phrase courte déjà traduite.
  String _safeMessage(Object error) {
    final String raw =
        error.toString().replaceFirst('Exception: ', '').trim();
    final String lower = raw.toLowerCase();
    if (raw.isEmpty ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('password') ||
        lower.contains('mot de passe=')) {
      return context.l10n.tvConnectError;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Titre traduit (clé tvAddListTitle, « Ajouter ma source » en
              // français) : un texte en dur cassait les autres langues et le
              // test removed_list_prompt_test (retour après une liste retirée).
              Text(context.l10n.tvAddListTitle,
                  style: TvTokens.display(34, color: TvTokens.text)),
              const SizedBox(height: 6),
              Text(
                'Colle ton lien ou tes identifiants. '
                'N\'importe quel fournisseur M3U ou Xtream.',
                style: TvTokens.ui(16, color: TvTokens.mutedDim),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _ModeChip(
                    label: context.l10n.playlistTypeXtream,
                    selected: _mode == OpenEntryMode.xtream,
                    onSelect: () => _select(OpenEntryMode.xtream),
                  ),
                  _ModeChip(
                    label: context.l10n.playlistTypeM3u,
                    selected: _mode == OpenEntryMode.m3u,
                    onSelect: () => _select(OpenEntryMode.m3u),
                  ),
                  _ModeChip(
                    label: OpenSourceInput.playerLabel,
                    selected: _mode == OpenEntryMode.player,
                    onSelect: () => _select(OpenEntryMode.player),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_mode == OpenEntryMode.xtream) ...<Widget>[
                _TextField(
                  controller: _serverC,
                  label: context.l10n.tvFieldServer,
                  hint: 'http://exemple.test:8080',
                  autofocus: true,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 10),
                _TextField(
                  controller: _userC,
                  label: context.l10n.tvFieldUser,
                ),
                const SizedBox(height: 10),
                _TextField(
                  controller: _passC,
                  label: context.l10n.tvFieldPass,
                  obscure: true,
                ),
              ] else ...<Widget>[
                _TextField(
                  controller: _linkC,
                  label: _mode == OpenEntryMode.player
                      ? OpenSourceInput.playerLabel
                      : context.l10n.tvFieldM3uUrl,
                  hint: _mode == OpenEntryMode.player
                      ? 'http://exemple.test:8080/get.php?username=…&password=…'
                      : 'http://exemple.test/liste.m3u',
                  autofocus: true,
                  keyboardType: TextInputType.url,
                ),
              ],
              const SizedBox(height: 10),
              Text(context.l10n.tvKeyboardHint,
                  style: TvTokens.ui(12, color: TvTokens.mutedDim)),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TvTokens.ui(14, color: TvTokens.live)),
              ],
              const SizedBox(height: 20),
              ValueListenableBuilder<ImportProgress?>(
                valueListenable: ImportProgressBus.current,
                builder: (BuildContext context, ImportProgress? p, Widget? _) {
                  final String label = !_busy
                      ? context.l10n.tvAddListValidate
                      : (p == null
                          ? context.l10n.tvConnecting
                          : importProgressLabel(context, p));
                  return TvCtaButton(
                    label: label,
                    onSelect: _busy ? null : _validate,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(OpenEntryMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }
}

/// Champ texte. Un vrai TextField : clavier de la box, clavier
/// physique, copier-coller, et saisie venue du téléphone appairé.
class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: TvTokens.accent,
      style: TvTokens.ui(18, weight: FontWeight.w500, color: TvTokens.text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TvTokens.ui(13, color: TvTokens.muted),
        hintStyle: TvTokens.ui(14, color: TvTokens.mutedDim),
        floatingLabelStyle: TvTokens.ui(13, color: TvTokens.accentBright),
        filled: true,
        fillColor: TvTokens.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: border(TvTokens.line, 1),
        focusedBorder: border(TvTokens.accent, 2),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelect,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final bool hl = focused || selected;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.accent
                : (selected ? TvTokens.sel : Colors.transparent),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: hl ? TvTokens.accent : TvTokens.line),
          ),
          child: Text(label,
              style: TvTokens.ui(15,
                  weight: FontWeight.w600,
                  color: focused
                      ? TvTokens.onAccent
                      : (selected ? TvTokens.accentBright : TvTokens.muted))),
        );
      },
    );
  }
}
