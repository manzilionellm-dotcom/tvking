// =========================================================
//  tv_sources_screen.dart — « Mes sources » (gérer M3U / Xtream)
// =========================================================
//  Le client gère SES sources : en ajouter (Xtream ou M3U), en activer une
//  (= celle dont les chaînes s'affichent), ou en supprimer. Modèle « une source
//  active à la fois » (activer une autre = désactiver la précédente).
// =========================================================
import 'package:flutter/material.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';
import 'tv_smart_add_screen.dart';

class TvSourcesScreen extends StatelessWidget {
  const TvSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Mes sources',
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const Spacer(),
            // UNE SEULE porte d'entrée : l'aiguillage intelligent devine
            // tout seul si le lien collé est M3U ou Xtream — le client n'a
            // plus à choisir un jargon qu'il ne connaît pas.
            _Pill(
              icon: Icons.add_rounded,
              label: 'Ajouter une source',
              autofocus: true,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => const TvShell(child: TvSmartAddScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<Playlist>>(
            stream: PlaylistRepository.instance.playlistsStream,
            initialData: PlaylistRepository.instance.currentPlaylists,
            builder: (BuildContext context, AsyncSnapshot<List<Playlist>> snap) {
              final List<Playlist> items = snap.data ?? const <Playlist>[];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Aucune source pour le moment.\nAppuie sur « Ajouter une source » et colle ton lien : on s\'occupe du reste.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: TvDimens.body, color: TvTokens.mutedDim),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(right: 6, bottom: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int i) =>
                    _SourceRow(playlist: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.playlist});
  final Playlist playlist;

  bool get _xtream => playlist.type == PlaylistType.xtream;

  Future<void> _delete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Text('Supprimer ?', style: TextStyle(color: TvTokens.text)),
        content: Text('Supprimer la source « ${playlist.name} » ?',
            style: TextStyle(color: TvTokens.muted)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: TvTokens.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Supprimer', style: TextStyle(color: TvTokens.live))),
        ],
      ),
    );
    if (ok != true || playlist.id == null) return;
    try {
      await PlaylistRepository.instance.deletePlaylist(playlist.id!);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final Color badge = _xtream ? TvTokens.gold : const Color(0xFF5AA0E8);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: TvTokens.panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(
            color: playlist.isActive ? TvTokens.gold : TvTokens.lineSoft,
            width: playlist.isActive ? 1.5 : 1),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(_xtream ? 'XTREAM' : 'M3U',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: badge)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 2),
                Text(
                    '${playlist.channelCount} chaînes'
                    '${playlist.isActive ? '  ·  ✓ active' : ''}',
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        color: playlist.isActive
                            ? TvTokens.gold
                            : TvTokens.muted)),
              ],
            ),
          ),
          if (!playlist.isActive && playlist.id != null) ...<Widget>[
            _Pill(
                icon: Icons.play_arrow_rounded,
                label: 'Activer',
                onSelect: () =>
                    PlaylistRepository.instance.setActivePlaylist(playlist.id!)),
            const SizedBox(width: 10),
          ],
          _IconBtn(
              icon: Icons.delete_outline_rounded,
              onSelect: () => _delete(context)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.icon,
      required this.label,
      required this.onSelect,
      this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onSelect});
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused ? TvTokens.live : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 24, color: focused ? Colors.white : TvTokens.muted),
        );
      },
    );
  }
}
