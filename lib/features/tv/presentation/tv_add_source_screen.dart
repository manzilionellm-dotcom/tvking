// =========================================================
//  tv_add_source_screen.dart — Ajouter sa source SUR LA TV
// =========================================================
//  Manque critique corrigé : sur TV, le client pouvait seulement LIRE sa
//  MAC. Ici il peut saisir LUI-MÊME son abonnement, à la télécommande :
//    - Xtream Codes : serveur + identifiant + mot de passe ;
//    - M3U          : URL de playlist.
//
//  Réutilise la logique existante (PlaylistRepository.addXtreamPlaylist /
//  addM3uPlaylist) — on ne réécrit pas le parsing. UI 10-foot : gros
//  textes, champs focalisables (clavier Android TV à l'OK), bouton
//  « Connecter » focusable. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/tv_palette.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../../playlists/data/playlist_repository.dart';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key});

  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

enum _Mode { xtream, m3u }

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  _Mode _mode = _Mode.xtream;
  bool _busy = false;
  String? _error;

  final TextEditingController _server = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _m3u = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    _m3u.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == _Mode.xtream) {
        final String server = _server.text.trim();
        final String user = _user.text.trim();
        final String pass = _pass.text.trim();
        if (server.isEmpty || user.isEmpty || pass.isEmpty) {
          throw Exception('Remplis le serveur, l\'identifiant et le mot de passe.');
        }
        await PlaylistRepository.instance.addXtreamPlaylist(
          name: 'Mon abonnement',
          serverUrl: server,
          username: user,
          password: pass,
        );
      } else {
        final String url = _m3u.text.trim();
        if (url.isEmpty) throw Exception('Colle l\'URL de ta playlist M3U.');
        await PlaylistRepository.instance.addM3uPlaylist(
          name: 'Ma playlist',
          url: url,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Abonnement connecté ✅'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvRoyal.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Ajouter ma playlist',
                      style: AppTextStyles.headlineLarge
                          .copyWith(fontSize: 34, color: TvRoyal.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'Saisis ton abonnement IPTV. Sélectionne un champ avec la '
                    'télécommande et appuie sur OK pour écrire.',
                    style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 17, color: TvRoyal.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 28),

                  // Choix du type.
                  Row(
                    children: <Widget>[
                      _ModeChip(
                        label: 'Xtream Codes',
                        active: _mode == _Mode.xtream,
                        autofocus: true,
                        onTap: () => setState(() => _mode = _Mode.xtream),
                      ),
                      const SizedBox(width: 14),
                      _ModeChip(
                        label: 'M3U / URL',
                        active: _mode == _Mode.m3u,
                        onTap: () => setState(() => _mode = _Mode.m3u),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),

                  // Champs.
                  if (_mode == _Mode.xtream) ...<Widget>[
                    _TvField(controller: _server, label: 'Serveur (URL)',
                        hint: 'http://exemple.com:8080', keyboard: TextInputType.url),
                    const SizedBox(height: 16),
                    _TvField(controller: _user, label: 'Identifiant'),
                    const SizedBox(height: 16),
                    _TvField(controller: _pass, label: 'Mot de passe', obscure: true),
                  ] else ...<Widget>[
                    _TvField(controller: _m3u, label: 'URL de la playlist M3U',
                        hint: 'http://exemple.com/get.php?...',
                        keyboard: TextInputType.url),
                  ],

                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: TvRoyal.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: TvRoyal.accent.withValues(alpha: 0.5)),
                      ),
                      child: Text(_error!,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 16, color: TvRoyal.textPrimary)),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Bouton Connecter.
                  Row(
                    children: <Widget>[
                      _BigButton(
                        label: _busy ? 'Connexion…' : 'Connecter',
                        icon: Icons.link_rounded,
                        primary: true,
                        onTap: _busy ? null : _connect,
                      ),
                      const SizedBox(width: 14),
                      _BigButton(
                        label: 'Retour',
                        icon: Icons.arrow_back_rounded,
                        primary: false,
                        onTap: _busy ? null : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Sous-widgets ----

/// Puce de choix Xtream / M3U (focalisable D-pad).
class _ModeChip extends StatelessWidget {
  const _ModeChip(
      {required this.label,
      required this.active,
      required this.onTap,
      this.autofocus = false});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: active ? TvRoyal.accentSurface : TvRoyal.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? TvRoyal.accent : TvRoyal.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Text(label,
            style: AppTextStyles.button.copyWith(
                fontSize: 18,
                color: active ? TvRoyal.accentGlow : TvRoyal.textSecondary)),
      ),
    );
  }
}

/// Champ de saisie TV : grand, bordure d'accent au focus (le clavier
/// Android TV s'ouvre à l'appui OK).
class _TvField extends StatefulWidget {
  const _TvField(
      {required this.controller,
      required this.label,
      this.hint,
      this.obscure = false,
      this.keyboard});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  State<_TvField> createState() => _TvFieldState();
}

class _TvFieldState extends State<_TvField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
                fontSize: 12,
                letterSpacing: 1.5,
                color: TvRoyal.textTertiary)),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: TvRoyal.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? TvRoyal.accent : TvRoyal.border,
              width: _focused ? 2.4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: widget.controller,
            focusNode: _node,
            obscureText: widget.obscure,
            keyboardType: widget.keyboard,
            style: AppTextStyles.bodyLarge
                .copyWith(fontSize: 22, color: TvRoyal.textPrimary),
            cursorColor: TvRoyal.accent,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              hintText: widget.hint,
              hintStyle: AppTextStyles.bodyMedium
                  .copyWith(fontSize: 18, color: TvRoyal.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gros bouton d'action focalisable.
class _BigButton extends StatelessWidget {
  const _BigButton(
      {required this.label,
      required this.icon,
      required this.primary,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: primary ? TvRoyal.accent : TvRoyal.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: primary ? TvRoyal.accent : TvRoyal.border, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon,
              size: 22,
              color: primary ? Colors.white : TvRoyal.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: AppTextStyles.button.copyWith(
                  fontSize: 18,
                  color: primary ? Colors.white : TvRoyal.textSecondary)),
        ],
      ),
    );
    if (onTap == null) return Opacity(opacity: 0.6, child: inner);
    return TvFocusable(
      onTap: onTap!,
      borderRadius: BorderRadius.circular(14),
      child: inner,
    );
  }
}
