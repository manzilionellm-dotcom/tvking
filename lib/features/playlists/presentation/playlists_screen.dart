// =========================================================
//  playlists_screen.dart — Gestion des playlists ajoutées
// =========================================================
//  Affiche la liste des playlists déjà importées avec :
//    - leur nom + type (M3U / Xtream)
//    - nombre de chaînes
//    - date de dernière synchro
//    - bouton ➕ Ajouter une autre playlist
//    - swipe-to-delete ou bouton 🗑 par playlist
//
//  Phase 1 : on s'autorise UNE seule playlist active à la
//  fois côté UI (les chaînes affichées sur l'accueil sont
//  la fusion de toutes). On ajoutera le toggle "active/
//  inactive" plus tard.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist.dart';
import 'add_playlist_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mes playlists'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Ajouter une playlist',
            onPressed: () => _openAdd(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Playlist>>(
        stream: PlaylistRepository.instance.playlistsStream,
        initialData: PlaylistRepository.instance.currentPlaylists,
        builder: (BuildContext context, AsyncSnapshot<List<Playlist>> snap) {
          final List<Playlist> playlists = snap.data ?? <Playlist>[];
          if (playlists.isEmpty) {
            return _buildEmpty(context);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const BouncingScrollPhysics(),
            itemCount: playlists.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              return _PlaylistTile(playlist: playlists[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.playlist_play_rounded,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucune playlist',
              style: AppTextStyles.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Ajoute ta première playlist pour commencer.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => _openAdd(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPink,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter une playlist'),
            ),
          ],
        ),
      ),
    );
  }

  void _openAdd(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AddPlaylistScreen(),
        fullscreenDialog: true,
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final Playlist playlist;

  String get _typeLabel =>
      playlist.type == PlaylistType.m3u ? 'M3U / URL' : 'Xtream Codes';

  String get _sourceLine {
    if (playlist.type == PlaylistType.m3u) {
      return playlist.m3uUrl ?? '';
    }
    return '${playlist.xtreamServer ?? ''} · ${playlist.xtreamUsername ?? ''}';
  }

  String get _lastSyncLabel {
    final int? ts = playlist.lastSyncedAt;
    if (ts == null) return 'Jamais synchronisée';
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return 'Synchro : ${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: <Widget>[
          // Icône type
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.accentCyan.withValues(alpha: 0.18),
            ),
            child: Icon(
              playlist.type == PlaylistType.m3u
                  ? Icons.link
                  : Icons.dns_rounded,
              color: AppColors.accentCyan,
            ),
          ),
          const SizedBox(width: 14),

          // Texte
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        playlist.name,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _typeLabel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.accentCyan,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _sourceLine,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${playlist.channelCount} chaîne${playlist.channelCount > 1 ? 's' : ''} · $_lastSyncLabel',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Actions
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: AppColors.accent,
            ),
            tooltip: 'Re-synchroniser',
            onPressed: () => _refresh(context),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: AppColors.live,
            ),
            tooltip: 'Supprimer',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Re-synchronisation en cours...'),
        duration: Duration(seconds: 30),
      ),
    );
    try {
      final bool ok =
          await PlaylistRepository.instance.refreshPlaylist(playlist);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? AppColors.success : AppColors.live,
          content: Text(
            ok
                ? 'Playlist "${playlist.name}" à jour'
                : 'Re-synchronisation impossible',
          ),
        ),
      );
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.live,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          title: const Text('Supprimer cette playlist ?'),
          content: Text(
            'Toutes les chaînes liées à "${playlist.name}" '
            'seront retirées de l\'app.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.live),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm == true && playlist.id != null) {
      await PlaylistRepository.instance.deletePlaylist(playlist.id!);
    }
  }
}
