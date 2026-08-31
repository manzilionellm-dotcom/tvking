// =========================================================
//  profile_picker_screen.dart — Profils famille (MOBILE)
// =========================================================
//  Équivalent téléphone de tv_profiles_screen.dart : chaque membre choisit
//  SON profil (derniers films vus, recherches, collections propres — les
//  favoris restent partagés). Sélection, création (pastilles prêtes, pas de
//  clavier) et suppression (confirmation) via la MÊME API ProfilesRepository
//  que la TV — les données sont donc partagées entre les deux mondes.
//
//  BASCULE : pas de RestartWidget côté mobile — on recharge EXPLICITEMENT
//  les dépôts suffixés par profil (même liste que tv_profiles_screen
//  `_activate`, + PlaybackPositionRepository car la rangée « Reprendre »
//  est affichée sur l'accueil mobile). WatchStatsService, lui, écoute déjà
//  ProfilesRepository et se recharge tout seul.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/profiles/profile_switch.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Nom AFFICHÉ d'un profil : « Famille » est montré dans la langue active
/// alors que le nom STOCKÉ reste 'Famille' (partagé avec la TV — on ne
/// touche pas au dépôt). Même règle que tvProfileDisplayName côté TV.
String _displayName(BuildContext context, TvProfile p) =>
    p.id == ProfilesRepository.familyProfile.id
        ? context.l10n.tvProfileFamily
        : p.name;

/// Modèles proposés à la création (un tap, pas de clavier), traduits dans
/// la langue active — mêmes presets que la TV pour rester cohérent.
List<({String name, String emoji})> _presets(BuildContext context) =>
    <({String name, String emoji})>[
      (name: context.l10n.tvProfilePresetDad, emoji: '👨'),
      (name: context.l10n.tvProfilePresetMom, emoji: '👩'),
      (name: context.l10n.tvProfilePresetKids, emoji: '🧒'),
      (name: context.l10n.tvProfilePresetTeen, emoji: '🧑'),
      (name: context.l10n.tvProfileGuest, emoji: '🛋️'),
    ];

class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  @override
  void initState() {
    super.initState();
    // Idempotent — filet de sécurité si le boot a timeouté sur prefs.
    // ignore: discarded_futures
    ProfilesRepository.instance.load();
  }

  /// Demande le code s'il y en a un, puis bascule. La liste des dépôts à
  /// recharger vit dans `activateProfile` (profile_switch.dart), partagée
  /// avec les deux écrans TV : c'est CETTE liste qui avait divergé entre
  /// mobile et TV, et un écran qui n'était pas rechargé affichait encore
  /// les données du profil précédent.
  Future<void> _activate(String id) async {
    if (ProfilesRepository.instance.byId(id)?.enabled == false) return;
    if (!await ensureUnlocked(context, id)) return;
    await activateProfile(id);
  }

  Future<void> _confirmDelete(TvProfile p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(ctx.l10n.tvConfirmAsk),
        content: Text('${p.emoji}  ${_displayName(ctx, p)}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: Text(ctx.l10n.buttonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final bool wasActive = ProfilesRepository.instance.active.id == p.id;
    await ProfilesRepository.instance.delete(p.id);
    // Supprimer le profil ACTIF rebascule sur « Famille » (règle du dépôt) :
    // on recharge donc les données par profil comme pour une bascule.
    if (wasActive) await _activate(ProfilesRepository.familyProfile.id);
  }

  @override
  Widget build(BuildContext context) {
    final ProfilesRepository repo = ProfilesRepository.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.tvProfilesTitle),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final List<TvProfile> all = repo.profiles;
          final List<({String name, String emoji})> available =
              _presets(context)
                  .where((({String name, String emoji}) p) =>
                      repo.byName(p.name) == null)
                  .toList(growable: false);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
                child: Text(
                  context.l10n.tvProfilesSubtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              // ----- Profils existants -----
              for (final TvProfile p in all)
                _ProfileTile(
                  profile: p,
                  active: p.id == repo.active.id,
                  onTap: () => _activate(p.id),
                  // « Famille » est indestructible, et un profil VENU DU
                  // PANEL ne se supprime pas depuis l'appareil : sinon le
                  // contrôle parental se contournerait en supprimant le
                  // profil qui le porte. Le dépôt refuse déjà ; on n'affiche
                  // pas non plus un bouton qui ne ferait rien.
                  onDelete: p.id == ProfilesRepository.familyProfile.id ||
                          p.managed
                      ? null
                      : () => _confirmDelete(p),
                ),
              // ----- Création (pastilles, comme la TV) -----
              if (available.isNotEmpty &&
                  all.length < ProfilesRepository.maxProfiles) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                  child: Text(
                    context.l10n.tvProfileAddSection,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final ({String name, String emoji}) p in available)
                      ActionChip(
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: AppColors.border),
                        label: Text(
                          '${p.emoji}  ${p.name}',
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => repo.create(p.name, p.emoji),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tuile d'un profil — même gabarit visuel que les tuiles de Réglages
/// (surface arrondie + bord discret), avec avatar emoji et badge « Actif ».
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final TvProfile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    // Profil COUPÉ depuis le panel : tuile visible mais éteinte, et non
    // retirée — un membre dont le profil disparaît croit à une panne, un
    // profil grisé dit clairement « c'est fermé ».
    final bool off = !profile.enabled;
    return Opacity(
      opacity: off ? 0.4 : 1,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: off ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active && !off ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  profile.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _displayName(context, profile),
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Cadenas / interdit : dit AVANT le tap qu'un code sera
              // demandé, ou que le profil est fermé. Découvrir le verrou
              // seulement après avoir choisi donne l'impression d'un refus.
              if (off || profile.pin != null) ...<Widget>[
                Icon(off ? Icons.block_rounded : Icons.lock_rounded,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
              ],
              if (active) ...<Widget>[
                Icon(Icons.check_circle_rounded,
                    color: AppColors.accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  context.l10n.tvProfileActiveBadge,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
