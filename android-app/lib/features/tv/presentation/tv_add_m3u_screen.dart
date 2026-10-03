// =========================================================
//  tv_add_m3u_screen.dart — Ajouter une liste par son adresse
// =========================================================
//  Le client colle l'adresse de son fichier .m3u / .m3u8, ou un lien
//  de lecteur get.php (+ adresse EPG optionnelle pour une liste M3U).
//  La vérification est la même que l'écran « Ajouter ma source » :
//  n'importe quel fournisseur, message en français si ça ne va pas.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/domain/open_source_input.dart';
import 'tv_import_progress_label.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

class TvAddM3uScreen extends StatefulWidget {
  const TvAddM3uScreen({super.key});

  @override
  State<TvAddM3uScreen> createState() => _TvAddM3uScreenState();
}

class _TvAddM3uScreenState extends State<TvAddM3uScreen> {
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _urlC = TextEditingController();
  final TextEditingController _epgC = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameC.dispose();
    _urlC.dispose();
    _epgC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // M3U, M3U8, ou get.php : la même vérification, sans domaine imposé.
    final OpenSourceParse parsed = OpenSourceInput.playlistLink(_urlC.text);
    if (!parsed.isValid || parsed.draft == null) {
      setState(() => _error = parsed.error ?? context.l10n.tvAddM3uInvalidUrl);
      return;
    }
    final OpenSourceDraft draft = parsed.draft!;
    setState(() {
      _busy = true;
      _error = null;
    });
    ImportProgressBus.clear();
    final String name = _nameC.text.trim().isEmpty
        ? context.l10n.tvMyM3uList
        : _nameC.text.trim();
    try {
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
          epgUrl: _epgC.text.trim().isEmpty ? null : _epgC.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.tvAddM3uFailed);
      }
    } finally {
      ImportProgressBus.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.tvAddM3uTitle,
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const SizedBox(height: 6),
            Text(
                'Adresse .m3u, .m3u8, ou lien de lecteur get.php. '
                'Avec ou sans identifiants.',
                style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
            const SizedBox(height: 22),
            _Field(controller: _nameC, label: context.l10n.tvFieldNameOptional, hint: context.l10n.tvMyListHint),
            const SizedBox(height: 14),
            _Field(
                controller: _urlC,
                label: context.l10n.tvFieldM3uUrl,
                hint: 'http://exemple.test/liste.m3u'),
            const SizedBox(height: 14),
            _Field(
                controller: _epgC,
                label: context.l10n.tvFieldEpgUrlOptional,
                hint: 'http://exemple.test/xmltv.php'),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(_error!,
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w600,
                      color: TvTokens.live)),
            ],
            const SizedBox(height: 22),
            ValueListenableBuilder<ImportProgress?>(
              valueListenable: ImportProgressBus.current,
              builder: (BuildContext context, ImportProgress? p, Widget? _) {
                return TvCtaButton(
                  label: !_busy ? context.l10n.tvAddM3uValidate : (p == null ? context.l10n.tvAddM3uBusy : importProgressLabel(context, p)),
                  autofocus: true,
                  expand: false,
                  onSelect: _busy ? null : _submit,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: TextStyle(
                fontSize: TvDimens.label,
                fontWeight: FontWeight.w600,
                color: TvTokens.mutedDim)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: TvDimens.title, color: TvTokens.text),
          cursorColor: TvTokens.accent,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: TvTokens.mutedDim),
            filled: true,
            fillColor: TvTokens.card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              borderSide: BorderSide(color: TvTokens.lineSoft),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              borderSide: const BorderSide(color: TvTokens.accent, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
