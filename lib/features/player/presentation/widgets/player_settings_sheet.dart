// =========================================================
//  player_settings_sheet.dart — Sheet de réglages avancés
// =========================================================
//  Bottom sheet glassmorphism qui permet à l'utilisateur
//  de modifier en cours de lecture :
//    - Mode d'affichage (16:9, 4:3, fit, fill, etc.)
//    - Buffer (5-60s)
//    - Décodage hardware on/off
//    - Affichage des stats on/off
//    - Vitesse de lecture (0.5x à 2x)
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/player_settings.dart';

class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({
    required this.currentSpeed,
    required this.onSpeedChange,
    super.key,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedChange;

  static const List<double> kSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = widget.currentSpeed;
  }

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
                        value: PlayerSettings.instance.bufferSeconds
                            .toDouble(),
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
      label: Text(mode.label),
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
