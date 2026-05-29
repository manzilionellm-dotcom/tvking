// =========================================================
//  profile_screen.dart — Onglet Profil (Phase 1.0b redesign)
// =========================================================
//  Brief Phase 1.0b : la AppBar du home etait surchargee de 5
//  boutons utilitaires (Refresh, Cast, Guide TV, Recherche,
//  Reglages) — l'app ressemblait a un outil, pas a une
//  plateforme premium. Sur Netflix / Disney+ / Mubi le top bar
//  ne contient que logo + 1-2 actions cles (recherche, profil).
//
//  Cet ecran absorbe TOUT ce qu'on a retire de la AppBar :
//    - Reglages
//    - Guide TV (EPG)
//    - Cast (ouverture du picker)
//    - A propos
//
//  Ainsi que le compte / l'abonnement / l'identifiant
//  appareil (pour que l'utilisateur sache ce qu'il a).
//
//  Style : aere, lignes fines, regroupement logique. Pas de
//  surcharge. C'est l'inverse exact de la AppBar d'origine.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/cinematic_spacing.dart';
import '../../about/presentation/about_screen.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/domain/cast_device.dart';
import '../../cast/presentation/cast_picker_sheet.dart';
import '../../device/data/device_identity.dart';
import '../../epg/presentation/tv_guide_screen.dart';
import '../../settings/presentation/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _mac;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String v) {
      if (mounted) setState(() => _mac = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CinematicSpacing.l,
            CinematicSpacing.xl,
            CinematicSpacing.l,
            CinematicSpacing.theater,
          ),
          children: <Widget>[
            // ===== Header : logo + nom flavor + identifiant =====
            const _Header(),
            const SizedBox(height: CinematicSpacing.xl),
            _AccountCard(mac: _mac),
            const SizedBox(height: CinematicSpacing.xl),

            // ===== Groupe Decouverte =====
            _SectionLabel('Decouverte'),
            const SizedBox(height: CinematicSpacing.s),
            _MenuTile(
              icon: Icons.event_note_rounded,
              title: 'Guide TV',
              subtitle: 'Programme en cours et a venir',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const TvGuideScreen(),
                ),
              ),
            ),
            _CastTile(),
            const SizedBox(height: CinematicSpacing.xl),

            // ===== Groupe Compte =====
            _SectionLabel('Compte'),
            const SizedBox(height: CinematicSpacing.s),
            _MenuTile(
              icon: Icons.settings_outlined,
              title: 'Reglages',
              subtitle: 'Lecture, securite, langue, theme',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
            _MenuTile(
              icon: Icons.info_outline_rounded,
              title: 'A propos',
              subtitle: 'Version, equipe, mentions legales',
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
}

// =========================================================
//  Header : logo brand + nom flavor (Red Room / 7 MOTION)
// =========================================================
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final FlavorConfig flavor = FlavorConfig.current;
    return Center(
      child: Column(
        children: <Widget>[
          const BrandLogo.medium(),
          const SizedBox(height: CinematicSpacing.m),
          Text(
            flavor.appName,
            style: AppTextStyles.headlineLarge.copyWith(fontSize: 24),
          ),
          const SizedBox(height: CinematicSpacing.micro),
          Text(
            flavor.appTagline,
            style: AppTextStyles.eyebrowChampagne.copyWith(
              color: AppColors.champagneDeep,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Carte "Mon compte" : identifiant appareil + statut
// =========================================================
//  Reprend les infos clefs : la MAC (pour activation
//  revendeur a distance) + un libelle "Compte premium" qui
//  fait pro et evite "abonnement IPTV".
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.mac});
  final String? mac;

  @override
  Widget build(BuildContext context) {
    final String display = mac ?? 'MK:??:??:??:??:??';
    return Container(
      padding: const EdgeInsets.all(CinematicSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(CinematicSpacing.radiusL),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.champagne,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Compte premium',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: CinematicSpacing.s),
          Text(
            'IDENTIFIANT APPAREIL',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            display,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Tile generique : icone + titre + sous-titre + chevron
// =========================================================
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CinematicSpacing.s,
            vertical: CinematicSpacing.s,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, size: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(width: CinematicSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                        color: AppColors.textTertiary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  Tile Cast — affiche l'etat connecte ou non via CastManager
// =========================================================
class _CastTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CastManager.instance,
      builder: (BuildContext context, _) {
        final CastManager mgr = CastManager.instance;
        final bool connected = mgr.hasTarget;
        final CastDevice? dev = mgr.selectedDevice;
        final String subtitle = connected
            ? 'Connecte a ${dev?.name ?? "appareil"}'
            : 'Diffuser sur un televiseur';
        return _MenuTile(
          icon: connected ? Icons.cast_connected_rounded : Icons.cast_rounded,
          title: 'Cast',
          subtitle: subtitle,
          onTap: () => showCastPickerGlobal(context),
        );
      },
    );
  }
}

// =========================================================
//  Label de groupe — uppercase eyebrow style premium
// =========================================================
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: CinematicSpacing.s),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textTertiary,
          fontSize: 10,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
