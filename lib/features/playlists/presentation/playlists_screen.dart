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
//  Plusieurs playlists peuvent coexister : une seule est ACTIVE à la
//  fois (ses chaînes alimentent l'accueil). On peut basculer d'une
//  playlist à l'autre en touchant le bouton d'activation — pratique
//  pour jongler entre plusieurs abonnements et revenir au premier.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import 'source_calibration_sheet.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.playlistsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: context.l10n.playlistsAddTooltip,
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
              context.l10n.playlistsEmptyTitle,
              style: AppTextStyles.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.playlistsEmptySubtitle,
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
              label: Text(context.l10n.playlistsAddTooltip),
            ),
          ],
        ),
      ),
    );
  }

  // Modèle « tout géré par le revendeur » : plus de saisie de code.
  // On ouvre la feuille qui montre la MAC + « Vérifier mon abonnement ».
  void _openAdd(BuildContext context) {
    showSourceChoiceSheet(context);
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final Playlist playlist;

  String _typeLabel(BuildContext context) => playlist.type == PlaylistType.m3u
      ? context.l10n.playlistTypeM3u
      : context.l10n.playlistTypeXtream;

  /// Lien EXACT de la source (serveur Xtream ou URL M3U). Affiché en
  /// entier + copiable → indispensable pour diagnostiquer à distance le
  /// problème d'un client (« quel serveur / quel username tu vois ? »).
  String get _diagLink {
    if (playlist.type == PlaylistType.m3u) {
      return (playlist.m3uUrl ?? '').trim();
    }
    return (playlist.xtreamServer ?? '').trim();
  }

  /// Identifiant Xtream (username) — vide pour une source M3U. Le mot de
  /// passe n'est JAMAIS affiché.
  String get _diagUser => (playlist.xtreamUsername ?? '').trim();

  /// Ligne « icône + valeur » copiable (SelectableText) pour lire le lien
  /// exact même très long, sans troncature.
  Widget _diagRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: AppTextStyles.bodyMedium.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _lastSyncLabel(BuildContext context) {
    final int? ts = playlist.lastSyncedAt;
    if (ts == null) return context.l10n.playlistNeverSynced;
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
    // Date + heure formatées selon la locale courante (jamais de
    // '${dt.day}/${dt.month}' en dur : l'ordre jour/mois et le format
    // 12h/24h varient d'une langue à l'autre).
    final MaterialLocalizations ml = MaterialLocalizations.of(context);
    return context.l10n.syncedAtLabel(
      ml.formatCompactDate(dt),
      ml.formatTimeOfDay(TimeOfDay.fromDateTime(dt)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        // Bordure accent + glow quand cette playlist est l'active.
        border: Border.all(
          color: playlist.isActive
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.06),
          width: playlist.isActive ? 1.4 : 1,
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
                        _typeLabel(context),
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
                  '${context.l10n.channelCount(playlist.channelCount)} · ${_lastSyncLabel(context)}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                  ),
                ),
                // Lien + identifiant EXACTS (diagnostic à distance).
                if (_diagLink.isNotEmpty)
                  _diagRow(Icons.link_rounded, _diagLink),
                if (_diagUser.isNotEmpty)
                  _diagRow(Icons.person_outline_rounded, _diagUser),
              ],
            ),
          ),

          // Actions
          // Activation : coche pleine (verte) si déjà active, sinon
          // cercle vide qui bascule cette playlist en active au tap.
          IconButton(
            icon: Icon(
              playlist.isActive
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: playlist.isActive
                  ? AppColors.success
                  : AppColors.textTertiary,
            ),
            tooltip: playlist.isActive
                ? context.l10n.playlistActiveBadge
                : context.l10n.playlistTapToActivate,
            onPressed:
                playlist.isActive ? null : () => _activate(context),
          ),
          // « Optimiser la source » : calibration automatique (compte,
          // format d'URL gagnant, signature, temps de démarrage). Or
          // royal Maison Noir — geste premium, jamais critique.
          IconButton(
            icon: const Icon(
              Icons.auto_fix_high_rounded,
              color: AppColors.royalGold,
            ),
            tooltip: context.l10n.calibrateAction,
            onPressed: () => showSourceCalibrationSheet(context, playlist),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: AppColors.accent,
            ),
            tooltip: context.l10n.playlistResyncTooltip,
            onPressed: () => _refresh(context),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: AppColors.live,
            ),
            tooltip: context.l10n.playlistDeleteTooltip,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  /// Bascule cette playlist en active (les autres passent inactives via
  /// `setActivePlaylist`, qui recharge aussi les chaînes de l'accueil).
  Future<void> _activate(BuildContext context) async {
    if (playlist.id == null) return;
    await PlaylistRepository.instance.setActivePlaylist(playlist.id!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(context.l10n.playlistNowActive(playlist.name)),
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.playlistResyncing),
        duration: const Duration(seconds: 30),
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
                ? context.l10n.playlistUpToDate(playlist.name)
                : context.l10n.playlistResyncFailed,
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
          title: Text(context.l10n.playlistDeleteConfirmTitle),
          content: Text(
            context.l10n.playlistDeleteConfirmBody(playlist.name),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.buttonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.live),
              child: Text(context.l10n.buttonDelete),
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
