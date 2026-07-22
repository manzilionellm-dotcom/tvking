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

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/i18n/l10n_extension.dart';
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
    // PAS de BackdropFilter au-dessus d'une vidéo en lecture : le blur
    // (saveLayer + 2 passes) était RE-CALCULÉ À CHAQUE FRAME tant que la
    // sheet restait ouverte (la vidéo derrière invalide en continu). Le
    // fond était déjà à alpha 0.92 → un voile quasi opaque rend pareil
    // pour ~0 GPU (même parade que côté TV, cf. tv_live_screen).
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.97),
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
                    Text(context.l10n.tracksTitle,
                        style: AppTextStyles.headlineMedium),
                    const SizedBox(height: 18),

                    // ----- Audio -----
                    _section(context.l10n.tracksAudio, tracks.audio),
                    _audioList(context, tracks),
                    const SizedBox(height: 22),

                    // ----- Sous-titres -----
                    _section(context.l10n.tracksSubtitles, tracks.subtitle),
                    _subtitleList(context, tracks),
                  ],
                ),
              );
            },
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
      return _empty(context.l10n.tracksNoAudio);
    }
    return Column(
      children: tracks.audio.map((AudioTrack t) {
        final bool selected = t.id == player.state.track.audio.id;
        return _trackTile(
          selected: selected,
          title: _audioLabel(context, t),
          subtitle: _audioSubtitle(context, t),
          onTap: () => player.setAudioTrack(t),
        );
      }).toList(),
    );
  }

  Widget _subtitleList(BuildContext context, Tracks tracks) {
    if (tracks.subtitle.isEmpty) {
      return _empty(context.l10n.tracksNoSubtitles);
    }
    return Column(
      children: tracks.subtitle.map((SubtitleTrack t) {
        final bool selected = t.id == player.state.track.subtitle.id;
        return _trackTile(
          selected: selected,
          title: _subtitleLabel(context, t),
          subtitle: _subtitleSub(context, t),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
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

  String _audioLabel(BuildContext context, AudioTrack t) {
    if (t.title != null && t.title!.isNotEmpty) return t.title!;
    if (t.language != null && t.language!.isNotEmpty) {
      return _languageName(context, t.language!);
    }
    return context.l10n.trackFallback(t.id);
  }

  String _audioSubtitle(BuildContext context, AudioTrack t) {
    final List<String> parts = <String>[];
    if (t.language != null && t.language!.isNotEmpty && t.title != null) {
      parts.add(_languageName(context, t.language!));
    }
    if (t.channels != null) {
      // media_kit expose `channels` en String ("2", "6", parfois un
      // layout type "stereo"). Si c'est un nombre → clé plurielle
      // localisée « N canaux » ; sinon on affiche le layout technique.
      final int? count = int.tryParse(t.channels!);
      parts.add(
          count != null ? context.l10n.trackChannelCount(count) : t.channels!);
    }
    if (t.codec != null) {
      parts.add(t.codec!.toUpperCase());
    }
    return parts.join(' · ');
  }

  String _subtitleLabel(BuildContext context, SubtitleTrack t) {
    if (t.title != null && t.title!.isNotEmpty) return t.title!;
    if (t.language != null && t.language!.isNotEmpty) {
      return _languageName(context, t.language!);
    }
    if (t.id == 'no') return context.l10n.trackDisabled;
    return context.l10n.trackFallback(t.id);
  }

  String _subtitleSub(BuildContext context, SubtitleTrack t) {
    final List<String> parts = <String>[];
    if (t.language != null && t.language!.isNotEmpty && t.title != null) {
      parts.add(_languageName(context, t.language!));
    }
    return parts.join(' · ');
  }

  /// Nom LOCALISÉ de la langue d'une piste audio/sous-titres, à partir
  /// de son code ISO 639 (2 ou 3 lettres). Ces libellés désignent la
  /// langue de la PISTE (ex. « Anglais ») et suivent la langue de
  /// l'app via les clés trackLang*. Code inconnu → affiché tel quel
  /// en majuscules (repli technique).
  String _languageName(BuildContext context, String code) {
    switch (code.toLowerCase()) {
      case 'fr':
      case 'fre':
      case 'fra':
        return context.l10n.trackLangFrench;
      case 'en':
      case 'eng':
        return context.l10n.trackLangEnglish;
      case 'es':
      case 'spa':
        return context.l10n.trackLangSpanish;
      case 'de':
      case 'ger':
      case 'deu':
        return context.l10n.trackLangGerman;
      case 'it':
      case 'ita':
        return context.l10n.trackLangItalian;
      case 'ar':
      case 'ara':
        return context.l10n.trackLangArabic;
      case 'pt':
      case 'por':
        return context.l10n.trackLangPortuguese;
      case 'ru':
      case 'rus':
        return context.l10n.trackLangRussian;
      case 'zh':
      case 'chi':
        return context.l10n.trackLangChinese;
      case 'ja':
      case 'jpn':
        return context.l10n.trackLangJapanese;
      case 'ko':
      case 'kor':
        return context.l10n.trackLangKorean;
      default:
        return code.toUpperCase();
    }
  }
}
