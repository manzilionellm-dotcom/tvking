// =========================================================
//  tv_add_source_screen.dart — « J'ajoute ma propre liste » (Xtream)
// =========================================================
//  The Few NE VEND PAS de liste : le client a le DROIT d'apporter la
//  sienne. Saisie au clavier télécommande (3 champs : serveur, identifiant,
//  mot de passe) → on charge via PlaylistRepository → l'app s'ouvre.
// =========================================================
import 'package:flutter/material.dart';

import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key});
  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  final List<String> _vals = <String>['', '', '']; // serveur, user, pass
  int _active = 0;
  bool _busy = false;
  String? _error;

  static const List<String> _labels = <String>['Serveur', 'Identifiant', 'Mot de passe'];
  static const List<String> _keys = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    '.', ':', '/', '-', '_', '@',
  ];

  void _type(String c) => setState(() => _vals[_active] += c);
  void _back() {
    final String v = _vals[_active];
    if (v.isNotEmpty) setState(() => _vals[_active] = v.substring(0, v.length - 1));
  }

  Future<void> _validate() async {
    if (_vals[0].trim().isEmpty || _vals[1].trim().isEmpty || _vals[2].trim().isEmpty) {
      setState(() => _error = 'Remplis le serveur, l\'identifiant et le mot de passe.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: 'Ma liste',
        serverUrl: _vals[0].trim(),
        username: _vals[1].trim(),
        password: _vals[2].trim(),
      );
      if (mounted) Navigator.of(context).pop(); // le gate ouvre l'app
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Connexion impossible. Vérifie les infos.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Ajouter ma liste', style: TvTokens.display(34, color: TvTokens.text)),
            const SizedBox(height: 6),
            Text('Code Xtream — apporte ta propre playlist.',
                style: TvTokens.ui(16, color: TvTokens.mutedDim)),
            const SizedBox(height: 22),

            // ----- Champs -----
            for (int i = 0; i < 3; i++) ...<Widget>[
              _Field(
                label: _labels[i],
                value: i == 2 ? '•' * _vals[i].length : _vals[i],
                active: _active == i,
                onSelect: () => setState(() => _active = i),
              ),
              const SizedBox(height: 10),
            ],

            if (_error != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(_error!, style: TvTokens.ui(14, color: const Color(0xFFE0746A))),
            ],
            const SizedBox(height: 16),

            // ----- Clavier -----
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final String k in _keys) _Key(label: k, onTap: () => _type(k)),
                _Key(label: '⌫', onTap: _back),
                _Key(label: '✕', onTap: () => setState(() => _vals[_active] = '')),
              ],
            ),
            const SizedBox(height: 22),

            TvCtaButton(
              label: _busy ? 'Connexion…' : 'Valider et charger ma liste',
              onSelect: _busy ? null : _validate,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.active, required this.onSelect});
  final String label;
  final String value;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: (active || focused) ? TvTokens.gold : TvTokens.line),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 160,
              child: Text(label.toUpperCase(),
                  style: TvTokens.ui(11, weight: FontWeight.w600, color: TvTokens.mutedDim, spacing: 2)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(18, weight: FontWeight.w500, color: TvTokens.text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rSmall),
          ),
          child: Text(label,
              style: TvTokens.ui(20,
                  weight: FontWeight.w600,
                  color: focused ? const Color(0xFF1A1206) : TvTokens.text)),
        ),
      ),
    );
  }
}
