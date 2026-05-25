// =========================================================
//  player_tracks_sheet.dart — Sélection des pistes audio/sous-titres
// =========================================================
//  Bottom sheet qui montre les pistes audio et sous-titres
//  disponibles dans le flux courant et permet à l'utilisateur
//  d'en sélectionner une.
//
//  Pour un IPTV live, on a typiquement 1-3 pistes audio
//  (français / VO / VF) et 0-2 sous-titres. Pour de la VOD,
//  ça peut monter à 10+.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class PlayerTracksSheet extends StatelessWidget {
  const PlayerTracksSheet({
    required this.player,
    super.key,
  });

  final Player player;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SafeArea(
            top: false,
            child: StreamBuilder<Tracks>(
              stream: player.stream.tracks,
              initialData: player.state.tracks,
              builder: (BuildContext context, AsyncSnapshot<Tracks> snap) {
                final Tracks tracks = snap.data ?? player.state.tracks;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _grabber(),
                      const SizedBox(height: 18),
                      Text('Pistes', style: AppTextStyles.headlineMedium),
                      const SizedBox(height: 18),

                      // ----- Audio -----
                      _section('Audio', tracks.audio),
                      _audioList(context, tracks),
                      const SizedBox(height: 22),

                      // ----- Sous-titres -----
                      _section('Sous-titres', tracks.subtitle),
                      _subtitleList(context, tracks),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _section(String title, List<dynamic> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${items.length}',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audioList(BuildContext context, Tracks tracks) {
    if (tracks.audio.isEmpty) {
      return _empty('Aucune piste audio détectée.');
    }
    return Column(
      children: tracks.audio.map((AudioTrack t) {
        final bool selected = t.id == player.state.track.audio.id;
        return _trackTile(
          selected: selected,
          title: _audioLabel(t),
          subtitle: _audioSubtitle(t),
          onTap: () => player.setAudioTrack(t),
        );
      }).toList(),
    );
  }

  Widget _subtitleList(BuildContext context, Tracks tracks) {
    if (tracks.subtitle.isEmpty) {
      return _empty(
        'Aucun sous-titre. Astuce : sur certains flux, ils sont '
        'embarqués mais détectés tardivement.',
      );
    }
    return Column(
      children: tracks.subtitle.map((SubtitleTrack t) {
        final bool selected = t.id == player.state.track.subtitle.id;
        return _trackTile(
          selected: selected,
          title: _subtitleLabel(t),
          subtitle: _subtitleSub(t),
          onTap: () => player.setSubtitleTrack(t),
        );
      }).toList(),
    );
  }

  Widget _trackTile({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentPink.withValues(alpha: 0.18)
                : AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.accentPink
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: selected ? AppColors.accentPink : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
      ),
    );
  }

  // ----- Format des labels -----

  String _audioLabel(AudioTrack t) {
    if (t.title != null && t.title!.isNotEmpty) return t.title!;
    if (t.language != null && t.language!.isNotEmpty) {
      return _languageName(t.language!);
    }
    return 'Piste ${t.id}';
  }

  String _audioSubtitle(AudioTrack t) {
    final List<String> parts = <String>[];
    if (t.language != null && t.language!.isNotEmpty && t.title != null) {
      parts.add(_languageName(t.language!));
    }
    if (t.channels != null) {
      parts.add('${t.channels} canaux');
    }
    if (t.codec != null) {
      parts.add(t.codec!.toUpperCase());
    }
    return parts.join(' · ');
  }

  String _subtitleLabel(SubtitleTrack t) {
    if (t.title != null && t.title!.isNotEmpty) return t.title!;
    if (t.language != null && t.language!.isNotEmpty) {
      return _languageName(t.language!);
    }
    if (t.id == 'no') return 'Désactivés';
    return 'Piste ${t.id}';
  }

  String _subtitleSub(SubtitleTrack t) {
    final List<String> parts = <String>[];
    if (t.language != null && t.language!.isNotEmpty && t.title != null) {
      parts.add(_languageName(t.language!));
    }
    return parts.join(' · ');
  }

  String _languageName(String code) {
    const Map<String, String> map = <String, String>{
      'fr': 'Français',
      'fre': 'Français',
      'fra': 'Français',
      'en': 'Anglais',
      'eng': 'Anglais',
      'es': 'Espagnol',
      'spa': 'Espagnol',
      'de': 'Allemand',
      'ger': 'Allemand',
      'deu': 'Allemand',
      'it': 'Italien',
      'ita': 'Italien',
      'ar': 'Arabe',
      'ara': 'Arabe',
      'pt': 'Portugais',
      'por': 'Portugais',
      'ru': 'Russe',
      'rus': 'Russe',
      'zh': 'Chinois',
      'chi': 'Chinois',
      'ja': 'Japonais',
      'jpn': 'Japonais',
      'ko': 'Coréen',
      'kor': 'Coréen',
    };
    return map[code.toLowerCase()] ?? code.toUpperCase();
  }
}
