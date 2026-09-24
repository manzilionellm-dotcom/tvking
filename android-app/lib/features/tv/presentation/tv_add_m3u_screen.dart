// =========================================================
//  tv_add_m3u_screen.dart — Ajouter une liste M3U (URL)
// =========================================================
//  Le client colle l'URL de son fichier .m3u (+ URL EPG optionnelle). On
//  télécharge/parse via PlaylistRepository.addM3uPlaylist, puis on revient.
// =========================================================
import 'package:flutter/material.dart';

import '../../playlists/data/playlist_repository.dart';
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
      setState(() => _error = 'Entre une URL M3U valide (http…).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaylistRepository.instance.addM3uPlaylist(
        name: _nameC.text.trim().isEmpty ? 'Ma liste M3U' : _nameC.text.trim(),
        url: url,
        epgUrl: _epgC.text.trim().isEmpty ? null : _epgC.text.trim(),
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Échec : liste injoignable ou vide.');
      }
    } finally {
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
            Text('Ajouter une liste M3U',
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const SizedBox(height: 6),
            Text('Colle l\'URL de ton fichier .m3u (et l\'EPG si tu en as une).',
                style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
            const SizedBox(height: 22),
            _Field(controller: _nameC, label: 'Nom (optionnel)', hint: 'Ma liste'),
            const SizedBox(height: 14),
            _Field(
                controller: _urlC,
                label: 'URL M3U',
                hint: 'http://serveur.com/playlist.m3u'),
            const SizedBox(height: 14),
            _Field(
                controller: _epgC,
                label: 'URL EPG (optionnel)',
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
            TvCtaButton(
              label: _busy ? 'Ajout…' : 'Ajouter la liste',
              autofocus: true,
              expand: false,
              onSelect: _busy ? null : _submit,
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
          cursorColor: TvTokens.gold,
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
              borderSide: const BorderSide(color: TvTokens.gold, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
