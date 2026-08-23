// =========================================================
//  notifications_settings_screen.dart — Réglages des notifications
// =========================================================
//  Trois interrupteurs, tous activés par défaut (opt-out) :
//
//    1. Rappels d'émission  → « ton programme commence dans X min »
//                              (posés depuis le guide TV / EPG).
//    2. Nouveautés & annonces → messages que l'admin envoie à tous
//                              les utilisateurs depuis le panel.
//    3. Mise à jour de l'app → notif quand une nouvelle APK est dispo.
//
//  L'état est stocké côté [NotificationService] (SharedPreferences).
//  Activer un interrupteur (re)demande la permission système Android 13+
//  pour qu'on ne se retrouve pas avec un réglage ON qui ne notifie jamais.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../sports/data/match_alerts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  // `null` = encore en cours de lecture depuis les préférences.
  bool? _reminders;
  bool? _announcements;
  bool? _appUpdates;
  /// Alertes des GRANDS MATCHS (demande propriétaire du 22/08).
  bool? _matches;
  bool? _goalSound;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final NotificationService n = NotificationService.instance;
    final bool r = await n.isEnabled(NotificationService.prefReminders);
    final bool a = await n.isEnabled(NotificationService.prefAnnouncements);
    final bool u = await n.isEnabled(NotificationService.prefAppUpdates);
    final bool m = await n.isEnabled(MatchAlertsService.prefMatches);
    final bool g = await n.isEnabled(NotificationService.prefGoalSound);
    if (!mounted) return;
    setState(() {
      _reminders = r;
      _announcements = a;
      _appUpdates = u;
      _matches = m;
      _goalSound = g;
    });
  }

  Future<void> _set(String key, bool value) async {
    // Optimiste : on met l'UI à jour tout de suite, puis on persiste.
    setState(() {
      if (key == NotificationService.prefReminders) _reminders = value;
      if (key == NotificationService.prefAnnouncements) _announcements = value;
      if (key == NotificationService.prefAppUpdates) _appUpdates = value;
      if (key == MatchAlertsService.prefMatches) _matches = value;
      if (key == NotificationService.prefGoalSound) _goalSound = value;
    });
    await NotificationService.instance.setEnabled(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.notifTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          Text(
            context.l10n.notifIntro,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _NotifSwitch(
            icon: Icons.alarm_rounded,
            title: context.l10n.notifRemindersTitle,
            subtitle: context.l10n.notifRemindersSubtitle,
            value: _reminders,
            onChanged: (bool v) => _set(NotificationService.prefReminders, v),
          ),
          _NotifSwitch(
            icon: Icons.campaign_rounded,
            title: context.l10n.notifAnnouncementsTitle,
            subtitle: context.l10n.notifAnnouncementsSubtitle,
            value: _announcements,
            onChanged: (bool v) =>
                _set(NotificationService.prefAnnouncements, v),
          ),
          _NotifSwitch(
            icon: Icons.system_update_rounded,
            title: context.l10n.notifUpdatesTitle,
            subtitle: context.l10n.notifUpdatesSubtitle,
            value: _appUpdates,
            onChanged: (bool v) => _set(NotificationService.prefAppUpdates, v),
          ),
          // GRANDS MATCHS : coup d'envoi (15 min avant) + score final.
          _NotifSwitch(
            icon: Icons.sports_soccer_rounded,
            title: context.l10n.notifMatchesToggle,
            subtitle: context.l10n.notifMatchSoonTitle,
            value: _matches,
            onChanged: (bool v) => _set(MatchAlertsService.prefMatches, v),
          ),
          // LE « WOUAAAH » DE BUT. Interrupteur SÉPARÉ, volontairement :
          // c'est la seule notification de l'app qui fasse du bruit fort.
          // Quelqu'un peut vouloir suivre ses matchs SANS que son
          // téléphone crie dans un bureau — et doit pouvoir le couper
          // sans perdre les alertes de match.
          _NotifSwitch(
            icon: Icons.celebration_rounded,
            title: context.l10n.notifGoalSoundTitle,
            subtitle: context.l10n.notifGoalSoundSubtitle,
            value: _goalSound,
            onChanged: (bool v) =>
                _set(NotificationService.prefGoalSound, v),
          ),
        ],
      ),
    );
  }
}

/// Interrupteur de notification (variante locale à cet écran pour ne pas
/// dépendre d'un widget privé d'un autre fichier). Affiche un état
/// "désactivé" tant que la préférence n'est pas lue.
class _NotifSwitch extends StatelessWidget {
  const _NotifSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool v = value ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: v,
            onChanged: value == null ? null : onChanged,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
