// =========================================================
//  player_settings_sheet.dart — Sheet de réglages avancés
// =========================================================
//  Bottom sheet glassmorphism qui permet à l'utilisateur
//  de modifier en cours de lecture :
//    - Mode d'affichage (16:9, 4:3, fit, fill, etc.)
//    - Qualité vidéo (variantes HLS : Auto / 1080p…) si ≥ 2 pistes
//    - Buffer (5-60s)
//    - Décodage hardware on/off
//    - Affichage des stats on/off
//    - Vitesse de lecture (0.5x à 2x)
// =========================================================

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/player_settings.dart';
import '../aspect_mode_label.dart';

class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({
    required this.currentSpeed,
    required this.onSpeedChange,
    required this.player,
    required this.videoTrackId,
    required this.onVideoTrackChanged,
    super.key,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedChange;

  /// Instance mpv COURANTE — sert à lister les variantes vidéo du flux
  /// (pistes HLS) et à appliquer la sélection via `setVideoTrack`.
  final Player player;

  /// Choix de qualité de la SESSION de lecture (id de piste mpv), `null`
  /// = « Auto » (mpv choisit). Mémorisé par l'écran appelant seulement —
  /// jamais persisté : un live n'a pas les mêmes variantes qu'un film.
  final String? videoTrackId;

  /// Prévient l'écran appelant du nouveau choix (id de piste, `null` =
  /// Auto) pour qu'il le mémorise le temps de la session.
  final ValueChanged<String?> onVideoTrackChanged;

  static const List<double> kSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  late double _speed;

  /// Choix de qualité local à la feuille (surligne la puce active tout de
  /// suite, sans attendre la ré-émission du track-list par mpv).
  String? _videoTrackId;

  @override
  void initState() {
    super.initState();
    _speed = widget.currentSpeed;
    _videoTrackId = widget.videoTrackId;
  }

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
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: PlayerSettings.instance,
            builder: (BuildContext context, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _grabber(),
                    const SizedBox(height: 18),
                    Text(context.l10n.playerSettingsTitle,
                        style: AppTextStyles.headlineMedium),
                    const SizedBox(height: 18),

                    // ----- Vitesse -----
                    _sectionTitle(context.l10n.playerSpeedSection),
                    _speedSelector(),
                    const SizedBox(height: 22),

                    // ----- Mode d'affichage -----
                    _sectionTitle(context.l10n.playerDisplayMode),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AspectRatioMode.values
                          .map((AspectRatioMode m) => _aspectChip(m))
                          .toList(),
                    ),
                    const SizedBox(height: 22),

                    // ----- Qualité vidéo (variantes HLS) -----
                    // N'apparaît que si le flux expose ≥ 2 vraies pistes
                    // vidéo (master playlist HLS multi-variantes). Le
                    // StreamBuilder suit `tracks` : la section apparaît /
                    // se met à jour quand mpv découvre les variantes, et
                    // l'abonnement est libéré avec la feuille.
                    _qualitySection(context),

                    // ----- Buffer -----
                    _sectionTitle(context.l10n.playerBufferSize),
                    Text(
                      context.l10n.playerBufferSeconds(
                          PlayerSettings.instance.bufferSeconds),
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.accentCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Slider(
                      value: PlayerSettings.instance.bufferSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${PlayerSettings.instance.bufferSeconds}s',
                      activeColor: AppColors.accentPink,
                      inactiveColor:
                          AppColors.accentPink.withValues(alpha: 0.2),
                      onChanged: (double v) =>
                          PlayerSettings.instance.setBufferSeconds(v.toInt()),
                    ),
                    Text(
                      context.l10n.playerBufferHelp,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ----- Anti-coupure (anti-buffering) -----
                    _toggle(
                      label: context.l10n.playerAntiFreeze,
                      sublabel: context.l10n.playerAntiFreezeHelp,
                      value: PlayerSettings.instance.antiFreeze,
                      onChanged: (bool v) =>
                          PlayerSettings.instance.setAntiFreeze(v),
                    ),
                    const SizedBox(height: 14),

                    // ----- Décodage hardware -----
                    _toggle(
                      label: context.l10n.playerHwDecode,
                      sublabel: context.l10n.playerHwDecodeHelp,
                      value: PlayerSettings.instance.hardwareDecode,
                      onChanged: (bool v) =>
                          PlayerSettings.instance.setHardwareDecode(v),
                    ),
                    const SizedBox(height: 14),

                    // ----- Affichage des stats -----
                    _toggle(
                      label: context.l10n.playerShowStats,
                      sublabel: context.l10n.playerShowStatsHelp,
                      value: PlayerSettings.instance.showStats,
                      onChanged: (bool v) =>
                          PlayerSettings.instance.setShowStats(v),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ----- Composants -----

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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _speedSelector() {
    return Wrap(
      spacing: 8,
      children: PlayerSettingsSheet.kSpeeds.map((double s) {
        final bool selected = (s - _speed).abs() < 0.01;
        return ChoiceChip(
          label: Text('${s}x'),
          selected: selected,
          showCheckmark: false,
          onSelected: (bool v) {
            if (!v) return;
            setState(() => _speed = s);
            widget.onSpeedChange(s);
            PlayerSettings.instance.setLastSpeed(s);
          },
          selectedColor: AppColors.accentPink,
          backgroundColor: AppColors.surface,
          labelStyle: AppTextStyles.bodyMedium.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(
            color: selected
                ? AppColors.accentPink
                : Colors.white.withValues(alpha: 0.06),
          ),
        );
      }).toList(),
    );
  }

  Widget _aspectChip(AspectRatioMode mode) {
    final bool selected = PlayerSettings.instance.aspectMode == mode;
    return ChoiceChip(
      label: Text(mode.localizedLabel(context)),
      selected: selected,
      showCheckmark: false,
      onSelected: (bool v) {
        if (!v) return;
        PlayerSettings.instance.setAspectMode(mode);
      },
      selectedColor: AppColors.accentCyan,
      backgroundColor: AppColors.surface,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: selected ? Colors.black : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.accentCyan
            : Colors.white.withValues(alpha: 0.06),
      ),
    );
  }

  // ----- Qualité vidéo -----

  /// Section « Qualité » : Auto + une puce par variante vidéo réelle du
  /// flux (HLS multi-débits). Rendue UNIQUEMENT si ≥ 2 vraies pistes —
  /// sinon il n'y a rien à choisir et on n'affiche rien du tout
  /// (pas même le titre).
  Widget _qualitySection(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: widget.player.stream.tracks,
      initialData: widget.player.state.tracks,
      builder: (BuildContext context, AsyncSnapshot<Tracks> snap) {
        final Tracks tracks = snap.data ?? widget.player.state.tracks;
        // media_kit préfixe la liste par les pseudo-pistes « auto » et
        // « no » (cf. player_tracks_sheet, même filtre côté sous-titres).
        final List<VideoTrack> real = tracks.video
            .where((VideoTrack t) => t.id != 'auto' && t.id != 'no')
            .toList()
          // Plus haute qualité en premier (hauteur, puis débit).
          ..sort((VideoTrack a, VideoTrack b) {
            final int h = (b.h ?? 0).compareTo(a.h ?? 0);
            if (h != 0) return h;
            return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
          });
        if (real.length < 2) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _sectionTitle(context.l10n.detailQuality),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                // « Auto » : mpv reprend la main (ABR / 1re variante).
                _qualityChip(
                  label: context.l10n.deviceAuto,
                  selected: _videoTrackId == null,
                  onSelected: () {
                    widget.player.setVideoTrack(VideoTrack.auto());
                    setState(() => _videoTrackId = null);
                    widget.onVideoTrackChanged(null);
                  },
                ),
                ...real.map((VideoTrack t) => _qualityChip(
                      label: _videoTrackLabel(context, t),
                      selected: _videoTrackId == t.id,
                      onSelected: () {
                        widget.player.setVideoTrack(t);
                        setState(() => _videoTrackId = t.id);
                        widget.onVideoTrackChanged(t.id);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 22),
          ],
        );
      },
    );
  }

  Widget _qualityChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (bool v) {
        if (!v) return;
        onSelected();
      },
      selectedColor: AppColors.accentPink,
      backgroundColor: AppColors.surface,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.accentPink
            : Colors.white.withValues(alpha: 0.06),
      ),
    );
  }

  /// Libellé LISIBLE d'une variante : « 1080p — 8 Mb/s » quand mpv
  /// expose hauteur/débit (`demux-h` / `demux-bitrate`), sinon le title
  /// de la piste, sinon le repli technique « Piste {id} ».
  String _videoTrackLabel(BuildContext context, VideoTrack t) {
    final List<String> parts = <String>[];
    final int? h = t.h;
    if (h != null && h > 0) parts.add('${h}p');
    final int? bitrate = t.bitrate;
    if (bitrate != null && bitrate > 0) parts.add(_bitrateLabel(bitrate));
    if (parts.isNotEmpty) return parts.join(' — ');
    final String? title = t.title;
    if (title != null && title.isNotEmpty) return title;
    return context.l10n.trackFallback(t.id);
  }

  /// `demux-bitrate` mpv est en bits/s. Unités techniques (Mb/s, kb/s)
  /// volontairement non localisées — mêmes symboles dans toutes les
  /// langues de l'app.
  String _bitrateLabel(int bitsPerSecond) {
    if (bitsPerSecond >= 1000000) {
      final double mbps = bitsPerSecond / 1000000;
      return mbps >= 10
          ? '${mbps.round()} Mb/s'
          : '${mbps.toStringAsFixed(1)} Mb/s';
    }
    return '${(bitsPerSecond / 1000).round()} kb/s';
  }

  Widget _toggle({
    required String label,
    required String sublabel,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: AppTextStyles.bodyLarge
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.accentPink,
        ),
      ],
    );
  }
}
