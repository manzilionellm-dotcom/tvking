// =========================================================
//  tv_add_m3u_screen.dart — Ajouter une liste M3U (URL)
// =========================================================
//  Le client colle l'URL de son fichier .m3u (+ URL EPG optionnelle). On
//  télécharge/parse via PlaylistRepository.addM3uPlaylist, puis on revient.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/import_progress.dart';
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
    final String url = _urlC.text.trim();
    if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      setState(() => _error = context.l10n.tvAddM3uInvalidUrl);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    ImportProgressBus.clear();
    try {
      await PlaylistRepository.instance.addM3uPlaylist(
        name: _nameC.text.trim().isEmpty ? context.l10n.tvMyM3uList : _nameC.text.trim(),
        url: url,
        epgUrl: _epgC.text.trim().isEmpty ? null : _epgC.text.trim(),
      );
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
            Text(context.l10n.tvAddM3uSubtitle,
                style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
            const SizedBox(height: 22),
            _Field(controller: _nameC, label: context.l10n.tvFieldNameOptional, hint: context.l10n.tvMyListHint),
            const SizedBox(height: 14),
            _Field(
                controller: _urlC,
                label: context.l10n.tvFieldM3uUrl,
                hint: 'http://serveur.com/playlist.m3u'),
            const SizedBox(height: 14),
            _Field(
                controller: _epgC,
                label: context.l10n.tvFieldEpgUrlOptional,
                hint: 'http://serveur.com/xmltv.php'),
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
