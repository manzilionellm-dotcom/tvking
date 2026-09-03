// =========================================================
//  settings_screen.dart — Réglages globaux de l'app
// =========================================================
//  Hub central des réglages. Sections :
//    - Lecteur (buffer, hwdec, stats overlay)
//    - Playlists (gestion)
//    - Cache (vider logos, vider l'historique)
//    - À propos (version, GitHub, mises à jour)
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../../core/update/update_prompt.dart';
import '../../../core/i18n/locale_repository.dart';
import '../../../core/support/vip_help_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../about/presentation/about_screen.dart';
import '../../cast/presentation/cast_diagnostics_screen.dart';
import 'notifications_settings_screen.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../player/data/player_settings.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import '../../playlists/presentation/playlists_screen.dart';
import '../../privacy/presentation/shield_settings_screen.dart';
import '../../profiles/presentation/profile_picker_screen.dart';
import '../../recordings/presentation/recordings_screen.dart';
import '../../security/data/app_pin_settings.dart';
import '../../security/data/biometric_auth.dart';
import '../../security/data/lock_settings.dart';
import '../../security/data/parental_controls.dart';
import '../../subscription/presentation/subscription_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: <Widget>[
            // ====== AIDE VIP — toujours en haut, très visible ======
            //  Le client doit pouvoir nous joindre en 1 tap, depuis
            //  l'écran qu'il consulte le plus quand quelque chose
            //  cloche (Réglages).
            _SectionTitle(context.l10n.settingsHelpSupport),
            const VipHelpCard.full(),
            const SizedBox(height: 4),

            // ====== ABONNEMENT ======
            //  Carte trial/abonnement TiViMate-style. Le user voit
            //  où il en est dans les 10j d'essai (ou si payé) + un
            //  CTA pour acheter sur 7themotion.com (paiement externe,
            //  pas d'in-app purchase Google Play).
            _SectionTitle(context.l10n.settingsMySubscription),
            const SubscriptionCard(),
            const SizedBox(height: 4),

            // ====== LANGUE ======
            _SectionTitle(context.l10n.settingsLanguage),
            const _LanguagePicker(),

            // ====== PROFILS FAMILLE ======
            //  Parité avec la TV (tv_profiles_screen) : chacun son univers
            //  (derniers vus, recherches, collections), favoris partagés.
            //  L'écran mobile réutilise le MÊME ProfilesRepository.
            _SectionTitle(context.l10n.tvProfilesTitle),
            _ActionTile(
              icon: Icons.people_alt_rounded,
              title: context.l10n.tvManageProfiles,
              subtitle: context.l10n.tvSettingsProfiles,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfilePickerScreen(),
                ),
              ),
            ),

            // ====== CONTRÔLE PARENTAL ======
            //  Parité avec la TV (tv_parental_screen) : Mode Enfants qui
            //  masque l'Adulte, gardé par le PIN de l'app (AppPinSettings).
            //  Le désactiver exige le code — un enfant ne peut pas le
            //  couper lui-même.
            _SectionTitle(context.l10n.tvParentalTitle),
            const _KidsModeTile(),
            const _ParentalPinTile(),

            // ====== MODE BOUCLIER (vie privée) ======
            //  Parité avec la TV (tv_shield_screen) : coupe-circuit VPN,
            //  HTTPS préféré, télémétrie minimale. Même PrivacyShield.
            _SectionTitle(context.l10n.tvShieldTitle),
            _ActionTile(
              icon: Icons.shield_rounded,
              title: context.l10n.tvSettingsShield,
              subtitle: context.l10n.tvShieldIntro,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ShieldSettingsScreen(),
                ),
              ),
            ),

            // ====== LECTEUR ======
            _SectionTitle(context.l10n.settingsPlayer),
            ListenableBuilder(
              listenable: PlayerSettings.instance,
              builder: (BuildContext context, _) {
                final PlayerSettings s = PlayerSettings.instance;
                return Column(
                  children: <Widget>[
                    _SliderTile(
                      icon: Icons.timer_outlined,
                      title: context.l10n.playerBufferSize,
                      subtitle:
                          context.l10n.settingsBufferSubtitle(s.bufferSeconds),
                      value: s.bufferSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      onChanged: (double v) =>
                          s.setBufferSeconds(v.toInt()),
                    ),
                    _SwitchTile(
                      icon: Icons.memory_rounded,
                      title: context.l10n.playerHwDecode,
                      subtitle: context.l10n.settingsHwDecodeSubtitle,
                      value: s.hardwareDecode,
                      onChanged: s.setHardwareDecode,
                    ),
                    _SwitchTile(
                      icon: Icons.analytics_outlined,
                      title: context.l10n.playerShowStats,
                      subtitle: context.l10n.settingsShowStatsSubtitle,
                      value: s.showStats,
                      onChanged: s.setShowStats,
                    ),
                    _SwitchTile(
                      icon: Icons.wifi_rounded,
                      title: context.l10n.settingsWifiOnly,
                      subtitle: context.l10n.settingsWifiOnlySubtitle,
                      value: s.wifiOnly,
                      onChanged: s.setWifiOnly,
                    ),
                    _SwitchTile(
                      icon: Icons.signal_cellular_alt_rounded,
                      title: context.l10n.settingsWarnCellular,
                      subtitle: context.l10n.settingsWarnCellularSubtitle,
                      value: s.warnOnCellular,
                      onChanged: s.setWarnOnCellular,
                    ),
                    _ActionTile(
                      icon: Icons.badge_outlined,
                      title: context.l10n.settingsUserAgentTitle,
                      subtitle: context.l10n.settingsUserAgentSubtitle(
                        _shortUserAgent(s.userAgent),
                      ),
                      onTap: () => _openUserAgentSheet(context),
                    ),
                  ],
                );
              },
            ),

            // NOTE: la section "Mes playlists / Ajouter M3U" a été
            // retirée. Le client ne gère plus ses playlists lui-même —
            // elles arrivent automatiquement via le revendeur (admin)
            // qui les pousse à distance grâce à l'identifiant The Few.
            // Si tu es l'admin et tu veux modifier des playlists, va
            // dans "Mode admin" en bas de cette page.
            //
            // RÉ-ACTIVÉE (mai 2026) — le user veut quand même un accès
            // direct depuis Réglages pour :
            //   a) Tester l'app avec ses propres URLs Xtream pendant
            //      le dev (le revendeur lui-même est aussi utilisateur)
            //   b) Les clients qui ARRIVENT avec leur propre abo IPTV
            //      ailleurs et veulent juste utiliser The Few comme
            //      lecteur, sans passer par le système de revendeur.
            // L'écosystème revendeur (Mode admin → push à distance via
            // backend Cloudflare) reste intact, c'est juste une porte
            // supplémentaire pour l'usage direct.
            _SectionTitle(context.l10n.settingsMySources),
            _ActionTile(
              icon: Icons.playlist_play_rounded,
              title: context.l10n.playlistsTitle,
              subtitle: context.l10n.settingsMyPlaylistsSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PlaylistsScreen(),
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.support_agent_rounded,
              title: context.l10n.settingsActivateCheckTitle,
              subtitle: context.l10n.settingsActivateCheckSubtitle,
              onTap: () => showSourceChoiceSheet(context),
            ),

            // ====== ENREGISTREMENTS ======
            _SectionTitle(context.l10n.settingsRecordings),
            _ActionTile(
              icon: Icons.movie_filter_outlined,
              title: context.l10n.recordingsTitle,
              subtitle: context.l10n.settingsRecordingsSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordingsScreen(),
                ),
              ),
            ),

            // ====== STOCKAGE ======
            _SectionTitle(context.l10n.settingsStorage),
            _ActionTile(
              icon: Icons.history_rounded,
              title: context.l10n.settingsClearHistory,
              subtitle: context.l10n.settingsClearHistorySubtitle,
              destructive: true,
              onTap: () async {
                final bool? confirm = await _confirm(
                  context,
                  title: context.l10n.settingsClearHistoryConfirmTitle,
                  message: context.l10n.settingsClearHistoryConfirmBody,
                );
                if (confirm == true) {
                  await RecentlyWatchedRepository.instance.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.settingsHistoryCleared),
                      ),
                    );
                  }
                }
              },
            ),

            // ====== NOTIFICATIONS ======
            //  Trois interrupteurs : rappels d'émission, annonces de
            //  l'équipe, dispo des mises à jour. Tout activé par défaut.
            _SectionTitle(context.l10n.notifTitle),
            _ActionTile(
              icon: Icons.notifications_active_outlined,
              title: context.l10n.notifTitle,
              subtitle: context.l10n.settingsNotificationsSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationsSettingsScreen(),
                ),
              ),
            ),

            // ====== CAST ======
            //  Outil de diagnostic pour identifier les TVs qui
            //  refusent le cast et lesquelles stratégies marchent
            //  (direct / relay / metadata minimale). Le rapport
            //  JSON copiable se colle dans une issue ou dans
            //  lib/features/cast/COMPATIBILITY.md pour empiler
            //  les données empiriques.
            _SectionTitle(context.l10n.profileCast),
            _ActionTile(
              icon: Icons.troubleshoot_rounded,
              title: context.l10n.settingsCastDiagTitle,
              subtitle: context.l10n.settingsCastDiagSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CastDiagnosticsScreen(),
                ),
              ),
            ),

            // ====== À PROPOS ======
            _SectionTitle(context.l10n.settingsApp),
            // Mise à jour MANUELLE : vérifie prod, propose l'installation
            // directe, ou confirme « tu as déjà la dernière version ».
            _ActionTile(
              icon: Icons.system_update_rounded,
              title: context.l10n.aboutCheckUpdates,
              subtitle: context.l10n.settingsUpdateSubtitle,
              onTap: () => checkForUpdatesInteractive(context),
            ),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              title: context.l10n.settingsAbout,
              subtitle: context.l10n.settingsAboutSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AboutScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: Text(context.l10n.buttonContinue),
          ),
        ],
      ),
    );
  }

  /// Ouvre la feuille de choix du User-Agent (préréglages + champ libre).
  Future<void> _openUserAgentSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _UserAgentSheet(),
    );
  }
}

/// Tronque un User-Agent pour l'affichage en sous-titre.
String _shortUserAgent(String ua) =>
    ua.length <= 26 ? ua : '${ua.substring(0, 26)}…';

// ============================================================
//  Composants internes
// ============================================================

/// Toggle "Verrouiller à l'ouverture". Si l'utilisateur active le
/// switch, on lance IMMÉDIATEMENT le prompt d'auth biométrique en
/// guise de test — si ça échoue (pas d'empreinte enrôlée, pas de
/// PIN configuré...), on n'active pas le réglage, pour éviter que
/// l'user se retrouve coincé hors de l'app à la prochaine ouverture.
class _LockToggleTile extends StatefulWidget {
  const _LockToggleTile();

  @override
  State<_LockToggleTile> createState() => _LockToggleTileState();
}

class _LockToggleTileState extends State<_LockToggleTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    LockSettings.instance.isLockEnabled().then((bool e) {
      if (mounted) setState(() => _enabled = e);
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Activation : on demande l'auth UNE FOIS pour vérifier que
      // l'utilisateur peut bien déverrouiller son téléphone.
      // La raison est lue AVANT l'await : le prompt système l'affiche
      // dans la langue courante de l'app.
      final String reason = context.l10n.settingsLockAuthReason;
      final bool ok = await BiometricAuth.instance.authenticate(
        reason: reason,
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.settingsLockNotEnabled),
            ),
          );
        }
        return;
      }
    }
    await LockSettings.instance.setLockEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled == null) {
      // Placeholder pendant le chargement SharedPreferences (~5 ms)
      return const SizedBox(height: 56);
    }
    return _SwitchTile(
      icon: Icons.fingerprint,
      title: context.l10n.settingsLockOnLaunch,
      subtitle: context.l10n.settingsLockOnLaunchSubtitle,
      value: _enabled!,
      onChanged: _toggle,
    );
  }
}

// ============================================================
//  Contrôle parental (parité tv_parental_screen, en Material mobile)
// ============================================================

/// Interrupteur « Mode Enfants ». Activer = libre ; désactiver = code
/// parental obligatoire (sinon un enfant le couperait lui-même) — même
/// règle que la TV. L'état vient du ValueNotifier de ParentalControls,
/// donc la tuile se met à jour toute seule (y compris si la TV/le même
/// appareil bascule ailleurs).
class _KidsModeTile extends StatelessWidget {
  const _KidsModeTile();

  Future<void> _toggle(BuildContext context, bool wantOn) async {
    if (!wantOn) {
      final bool ok =
          await _askParentalPin(context, context.l10n.tvParentalEnterCode);
      if (!ok) return;
    }
    await ParentalControls.instance.setKidsMode(wantOn);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ParentalControls.instance.kidsMode,
      builder: (BuildContext context, bool kids, _) {
        // L'INTERRUPTEUR montre le réglage de l'APPAREIL, pas le mode
        // effectif : sinon, connecter un profil d'enfant le ferait passer
        // à « activé » tout seul et le parent croirait l'avoir mis.
        final bool device = ParentalControls.instance.deviceKidsMode;
        // Mode imposé par le PROFIL et non par l'appareil : on nomme le
        // profil responsable (« Activé · 🧒 Enfant 1 »). Pas de phrase à
        // traduire — un emoji et un prénom se lisent dans toutes les
        // langues, et disent exactement d'où vient le verrou.
        final TvProfile p = ProfilesRepository.instance.active;
        return _SwitchTile(
          icon: Icons.child_care_rounded,
          title: context.l10n.tvParentalKidsMode,
          subtitle: kids
              ? (device
                  ? context.l10n.tvParentalKidsOn
                  : '${context.l10n.tvParentalKidsOn} · ${p.emoji} ${p.name}')
              : context.l10n.tvParentalKidsOff,
          value: device,
          onChanged: (bool v) => _toggle(context, v),
        );
      },
    );
  }
}

/// Tuile « Changer le code PIN » parental. Le sous-titre alerte tant que
/// le code par défaut (0000) est en place — même avertissement que la TV.
class _ParentalPinTile extends StatefulWidget {
  const _ParentalPinTile();

  @override
  State<_ParentalPinTile> createState() => _ParentalPinTileState();
}

class _ParentalPinTileState extends State<_ParentalPinTile> {
  bool _usingDefaultPin = true;

  @override
  void initState() {
    super.initState();
    AppPinSettings.instance.isUsingDefault().then((bool v) {
      if (mounted) setState(() => _usingDefaultPin = v);
    });
  }

  Future<void> _changePin() async {
    // 1) Code actuel, 2) nouveau code + confirmation, 3) persistance.
    final bool ok =
        await _askParentalPin(context, context.l10n.tvParentalCurrentCode);
    if (!ok || !mounted) return;
    final String? next = await _pickNewParentalPin(context);
    if (next == null) return;
    try {
      await AppPinSettings.instance.setPin(next);
    } catch (_) {
      // Le dialog a déjà validé longueur/format — ceinture et bretelles.
    }
    final bool def = await AppPinSettings.instance.isUsingDefault();
    if (!mounted) return;
    setState(() => _usingDefaultPin = def);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tvParentalUpdated)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      icon: Icons.pin_rounded,
      title: context.l10n.tvParentalChangePin,
      subtitle: _usingDefaultPin
          ? context.l10n.tvParentalDefaultPinWarning
          : context.l10n.tvParentalCustomPinSet,
      onTap: _changePin,
    );
  }
}

/// Demande le code parental (clavier numérique) et le vérifie via
/// AppPinSettings (anti-brute-force inclus : le blocage croissant est
/// affiché avec son compte à rebours). Retourne true si le code est bon.
Future<bool> _askParentalPin(BuildContext context, String title) async {
  final TextEditingController ctrl = TextEditingController();
  String? error;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setState) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ctx.l10n.tvParentalPinSubtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              maxLength: 8,
              keyboardType: TextInputType.number,
            ),
            if (error != null)
              Text(
                error!,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.live,
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () async {
              final String pin = ctrl.text.trim();
              if (pin.length < 4) {
                setState(() => error = ctx.l10n.lockPinTooShort);
                return;
              }
              final bool good = await AppPinSettings.instance.verify(pin);
              if (good) {
                if (ctx.mounted) Navigator.of(ctx).pop(true);
                return;
              }
              final Duration lock =
                  await AppPinSettings.instance.lockoutRemaining();
              if (!ctx.mounted) return;
              setState(() => error = lock > Duration.zero
                  ? ctx.l10n.lockPinLocked(lock.inSeconds)
                  : ctx.l10n.tvParentalWrongCode);
            },
            child: Text(ctx.l10n.buttonContinue),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Choisit un NOUVEAU code parental (saisie + confirmation dans le même
/// dialog). Retourne le code validé (4-8 chiffres), ou null si annulé.
Future<String?> _pickNewParentalPin(BuildContext context) async {
  final TextEditingController first = TextEditingController();
  final TextEditingController second = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setState) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(ctx.l10n.tvParentalNewCode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ctx.l10n.tvParentalNewCodeSubtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: first,
              autofocus: true,
              obscureText: true,
              maxLength: 8,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ctx.l10n.tvParentalNewCode,
              ),
            ),
            TextField(
              controller: second,
              obscureText: true,
              maxLength: 8,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ctx.l10n.tvParentalConfirmCode,
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.live,
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () {
              final String pin = first.text.trim();
              // Mêmes règles que AppPinSettings.setPin (4-8 chiffres).
              if (pin.length < 4 ||
                  pin.length > 8 ||
                  !RegExp(r'^\d+$').hasMatch(pin)) {
                setState(() => error = ctx.l10n.lockPinTooShort);
                return;
              }
              if (pin != second.text.trim()) {
                setState(() => error = ctx.l10n.tvParentalCodesMismatch);
                return;
              }
              Navigator.of(ctx).pop(pin);
            },
            child: Text(ctx.l10n.buttonContinue),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        destructive ? AppColors.live : AppColors.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
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
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
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
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
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
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toInt().toString(),
            activeColor: AppColors.accent,
            inactiveColor: AppColors.accent.withValues(alpha: 0.2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  _LanguagePicker — Choix de langue
// ============================================================
//  Bottom sheet listant chaque langue dans sa graphie native +
//  l'option "Système" (suit l'OS). Choix persistant via
//  LocaleRepository.
// ============================================================

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleRepository.instance,
      builder: (BuildContext context, _) {
        final Locale? current = LocaleRepository.instance.locale;
        final String label = current == null
            ? context.l10n.settingsLanguageSystem
            : LocaleRepository.localeLabels[current.languageCode] ??
                current.languageCode;
        return _ActionTile(
          icon: Icons.translate_rounded,
          title: context.l10n.settingsAppLanguage,
          subtitle: label,
          onTap: () => _openSheet(context),
        );
      },
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: LocaleRepository.instance,
            builder: (BuildContext context, _) {
              final Locale? current = LocaleRepository.instance.locale;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.translate_rounded,
                            color: AppColors.accent, size: 20),
                        const SizedBox(width: 10),
                        Text(context.l10n.settingsLanguage,
                            style: AppTextStyles.headlineMedium),
                      ],
                    ),
                  ),
                  // ----- Option Système -----
                  _LanguageTile(
                    label: context.l10n.settingsLanguageSystem,
                    sublabel: context.l10n.settingsFollowsOsLanguage,
                    selected: current == null,
                    onTap: () async {
                      await LocaleRepository.instance.setLocale(null);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  const Divider(height: 1),
                  // ----- Liste des langues supportées -----
                  ...LocaleRepository.supportedLocales.map((Locale loc) {
                    return _LanguageTile(
                      label: LocaleRepository
                              .localeLabels[loc.languageCode] ??
                          loc.languageCode,
                      sublabel: loc.languageCode.toUpperCase(),
                      selected: current?.languageCode == loc.languageCode,
                      onTap: () async {
                        await LocaleRepository.instance.setLocale(loc);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 15,
                        color: selected
                            ? AppColors.accent
                            : AppColors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
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
              if (selected)
                Icon(Icons.check_rounded,
                    color: AppColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  _UserAgentSheet — Choix du User-Agent (signature de lecture)
// ============================================================
//  Préréglages (VLC, ExoPlayer/IBO, OkHttp, Smarters…) + champ
//  libre. Sert à débloquer les serveurs IPTV qui n'autorisent le
//  vrai flux qu'aux signatures de lecteurs connus (sinon : pub).
// ============================================================

class _UserAgentSheet extends StatefulWidget {
  const _UserAgentSheet();

  @override
  State<_UserAgentSheet> createState() => _UserAgentSheetState();
}

class _UserAgentSheetState extends State<_UserAgentSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: PlayerSettings.instance.userAgent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String value) async {
    await PlayerSettings.instance.setUserAgent(value);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.settingsUserAgentChanged),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListenableBuilder(
          listenable: PlayerSettings.instance,
          builder: (BuildContext context, _) {
            final String current = PlayerSettings.instance.userAgent;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.badge_outlined,
                            color: AppColors.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.l10n.settingsUserAgentSheetTitle,
                            style: AppTextStyles.headlineMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      context.l10n.settingsUserAgentSheetDesc,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  ...PlayerSettings.userAgentPresets.entries
                      .map<Widget>((MapEntry<String, String> entry) {
                    final bool selected = entry.value == current;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _apply(entry.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      entry.key,
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected
                                            ? AppColors.accent
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          AppTextStyles.bodyMedium.copyWith(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_rounded,
                                    color: AppColors.accent, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Text(
                      context.l10n.settingsUserAgentCustomHeader,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      style:
                          AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: context.l10n.settingsUserAgentHint,
                        filled: true,
                        fillColor: AppColors.surfaceHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _apply(PlayerSettings.kDefaultUserAgent),
                            child: Text(context.l10n.settingsReset),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _apply(_controller.text),
                            child: Text(context.l10n.settingsApply),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
