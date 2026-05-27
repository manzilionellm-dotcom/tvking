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

import '../../../core/i18n/locale_repository.dart';
import '../../../core/support/vip_help_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_mode_repository.dart';
import '../../about/presentation/about_screen.dart';
import '../../admin/presentation/admin_pin_screen.dart';
import '../../cast/presentation/cast_diagnostics_screen.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../device/presentation/device_id_card.dart';
import '../../player/data/player_settings.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../../playlists/presentation/playlists_screen.dart';
import '../../recordings/presentation/recordings_screen.dart';
import '../../security/data/biometric_auth.dart';
import '../../security/data/lock_settings.dart';
import '../../subscription/presentation/subscription_card.dart';
import '../../vpn/presentation/vpn_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Réglages'),
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
            _SectionTitle('Aide & Support'),
            const VipHelpCard.full(),
            const SizedBox(height: 4),

            // ====== ABONNEMENT ======
            //  Carte trial/abonnement TiViMate-style. Le user voit
            //  où il en est dans les 10j d'essai (ou si payé) + un
            //  CTA pour acheter sur 7themotion.com (paiement externe,
            //  pas d'in-app purchase Google Play).
            _SectionTitle('Mon abonnement'),
            const SubscriptionCard(),
            const SizedBox(height: 4),

            // ====== APPARENCE ======
            //  Cinema (Maison Noir) = défaut, identité du produit.
            //  Daylight = version claire dérivée pour usage diurne.
            _SectionTitle('Apparence'),
            const _ThemeModePicker(),

            // ====== LANGUE ======
            _SectionTitle('Langue'),
            const _LanguagePicker(),

            // ====== LECTEUR ======
            _SectionTitle('Lecteur vidéo'),
            ListenableBuilder(
              listenable: PlayerSettings.instance,
              builder: (BuildContext context, _) {
                final PlayerSettings s = PlayerSettings.instance;
                return Column(
                  children: <Widget>[
                    _SliderTile(
                      icon: Icons.timer_outlined,
                      title: 'Taille du buffer',
                      subtitle:
                          '${s.bufferSeconds}s · plus c\'est haut, mieux la lecture résiste aux coupures réseau (mais plus de latence sur le live)',
                      value: s.bufferSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      onChanged: (double v) =>
                          s.setBufferSeconds(v.toInt()),
                    ),
                    _SwitchTile(
                      icon: Icons.memory_rounded,
                      title: 'Décodage matériel',
                      subtitle:
                          'Utilise le GPU pour décoder. Indispensable pour 4K / 8K.',
                      value: s.hardwareDecode,
                      onChanged: s.setHardwareDecode,
                    ),
                    _SwitchTile(
                      icon: Icons.analytics_outlined,
                      title: 'Afficher les statistiques',
                      subtitle:
                          'Résolution, codec, FPS en surimpression pendant la lecture.',
                      value: s.showStats,
                      onChanged: s.setShowStats,
                    ),
                  ],
                );
              },
            ),

            // NOTE: la section "Mes playlists / Ajouter M3U" a été
            // retirée. Le client ne gère plus ses playlists lui-même —
            // elles arrivent automatiquement via le revendeur (admin)
            // qui les pousse à distance grâce à l'identifiant 7 MOTION.
            // Si tu es l'admin et tu veux modifier des playlists, va
            // dans "Mode admin" en bas de cette page.
            //
            // RÉ-ACTIVÉE (mai 2026) — le user veut quand même un accès
            // direct depuis Réglages pour :
            //   a) Tester l'app avec ses propres URLs Xtream pendant
            //      le dev (le revendeur lui-même est aussi utilisateur)
            //   b) Les clients qui ARRIVENT avec leur propre abo IPTV
            //      ailleurs et veulent juste utiliser 7 MOTION comme
            //      lecteur, sans passer par le système de revendeur.
            // L'écosystème revendeur (Mode admin → push à distance via
            // backend Cloudflare) reste intact, c'est juste une porte
            // supplémentaire pour l'usage direct.
            _SectionTitle('Mes sources IPTV'),
            _ActionTile(
              icon: Icons.playlist_play_rounded,
              title: 'Mes playlists',
              subtitle:
                  'Liste des sources IPTV ajoutées (M3U + Xtream Codes).',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PlaylistsScreen(),
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.add_circle_outline_rounded,
              title: 'Ajouter une source',
              subtitle:
                  'Colle une URL M3U ou un compte Xtream Codes (host + user + mdp).',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AddPlaylistScreen(),
                ),
              ),
            ),

            // ====== ENREGISTREMENTS ======
            _SectionTitle('Enregistrements'),
            _ActionTile(
              icon: Icons.movie_filter_outlined,
              title: 'Mes enregistrements',
              subtitle:
                  'Liste des flux capturés via le bouton REC du lecteur.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordingsScreen(),
                ),
              ),
            ),

            // ====== SÉCURITÉ ======
            //  Verrouillage biométrique à l'ouverture. Demande
            //  l'empreinte digitale (ou le PIN/pattern système en
            //  fallback) au démarrage à froid. Aucun re-lock quand
            //  l'app revient du background — choix UX déclaré par
            //  le client. Si le device n'a aucune méthode d'auth
            //  configurée, le toggle n'a aucun effet (Android refuse
            //  de bloquer un device sans verrouillage).
            _SectionTitle('Sécurité'),
            const _LockToggleTile(),
            const SizedBox(height: 10),
            const VpnCard(),

            // ====== STOCKAGE ======
            _SectionTitle('Stockage'),
            _ActionTile(
              icon: Icons.history_rounded,
              title: 'Vider l\'historique de visionnage',
              subtitle:
                  'Supprime la liste "Reprendre" sur l\'accueil.',
              destructive: true,
              onTap: () async {
                final bool? confirm = await _confirm(
                  context,
                  title: 'Vider l\'historique ?',
                  message: 'La section "Reprendre" sera vide.',
                );
                if (confirm == true) {
                  await RecentlyWatchedRepository.instance.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Historique vidé'),
                      ),
                    );
                  }
                }
              },
            ),

            // ====== CAST ======
            //  Outil de diagnostic pour identifier les TVs qui
            //  refusent le cast et lesquelles stratégies marchent
            //  (direct / relay / metadata minimale). Le rapport
            //  JSON copiable se colle dans une issue ou dans
            //  lib/features/cast/COMPATIBILITY.md pour empiler
            //  les données empiriques.
            _SectionTitle('Cast'),
            _ActionTile(
              icon: Icons.troubleshoot_rounded,
              title: 'Diagnostic cast',
              subtitle:
                  'Teste plusieurs chaînes sur une TV et rapporte la stratégie qui marche.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CastDiagnosticsScreen(),
                ),
              ),
            ),

            // ====== À PROPOS ======
            _SectionTitle('Application'),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              title: 'À propos',
              subtitle: 'Version, mises à jour, crédits, légal.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AboutScreen(),
                ),
              ),
            ),

            // ====== ADMIN (discret, protégé par PIN) ======
            //  Visible pour tout le monde mais inutilisable sans le
            //  code admin. C'est moi (le revendeur) qui ai le code.
            _ActionTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Mode admin',
              subtitle: 'Gestion des clients (réservé revendeur).',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminPinScreen(),
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
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }
}

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
      final bool ok = await BiometricAuth.instance.authenticate(
        reason: 'Confirme avec ton empreinte ou PIN pour activer le verrouillage',
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Verrouillage non activé — auth échouée ou pas '
                'd\'empreinte / PIN configurés sur ce téléphone.',
              ),
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
      title: 'Verrouiller à l\'ouverture',
      subtitle:
          'Demande l\'empreinte ou PIN au démarrage de l\'app. '
          'Pas de re-verrouillage si tu reviens du multitâche.',
      value: _enabled!,
      onChanged: _toggle,
    );
  }
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
//  _ThemeModePicker — Sélecteur Cinema / Daylight / Système
// ============================================================
//  Trois pastilles côte à côte. La sélection active porte la
//  bordure champagne et un léger halo cuivré.
// ============================================================

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeRepository.instance,
      builder: (BuildContext context, _) {
        final ThemeMode current = ThemeModeRepository.instance.mode;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              _ThemeOption(
                icon: Icons.nightlight_round,
                label: 'Cinema',
                subtitle: 'Maison Noir',
                selected: current == ThemeMode.dark,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.dark),
              ),
              _ThemeOption(
                icon: Icons.wb_sunny_outlined,
                label: 'Daylight',
                subtitle: 'Lumière du jour',
                selected: current == ThemeMode.light,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.light),
              ),
              _ThemeOption(
                icon: Icons.brightness_auto_outlined,
                label: 'Auto',
                subtitle: 'Suit l\'OS',
                selected: current == ThemeMode.system,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.system),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Respect du système : si l'utilisateur a activé "réduire les
    // animations" dans l'OS, MediaQuery.disableAnimations remonte
    // true et on coupe la transition.
    final bool disableMotion =
        MediaQuery.disableAnimationsOf(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: AnimatedContainer(
              duration: disableMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accentSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? AppColors.accent
                      : AppColors.border,
                  width: selected ? 1.4 : 1,
                ),
                boxShadow: selected ? AppColors.champagneGlow : null,
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    icon,
                    color:
                        selected ? AppColors.accent : AppColors.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
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
            ? 'Système'
            : LocaleRepository.localeLabels[current.languageCode] ??
                current.languageCode;
        return _ActionTile(
          icon: Icons.translate_rounded,
          title: 'Langue de l\'application',
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
                        Text('Langue',
                            style: AppTextStyles.headlineMedium),
                      ],
                    ),
                  ),
                  // ----- Option Système -----
                  _LanguageTile(
                    label: 'Système',
                    sublabel: 'Suit la langue de l\'OS',
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
