// =========================================================
//  tv_who_watching_screen.dart — « Qui regarde ? » (TV, façon Netflix)
// =========================================================
//  L'écran d'accueil des PROFILS, exactement comme Netflix : une grille
//  d'avatars ronds centrée. On choisit son profil → l'app active ce profil
//  (recharge « Derniers vus », recherches, collections, Ma Liste) et ouvre
//  l'accueil avec SON univers.
//
//  Deux usages :
//    • AU LANCEMENT : TvGate l'affiche AVANT l'accueil quand la famille a
//      plusieurs profils (fournir un [onPicked] → l'accueil s'affiche après).
//    • DEPUIS L'ACCUEIL : la pastille de profil (en haut) le POUSSE en route
//      (pas de [onPicked] → il se referme tout seul au choix).
//
//  STABILITÉ : zéro contact lecteur / écran Direct. Choisir un profil
//  recharge seulement les petits dépôts locaux par profil.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/profiles/profile_switch.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/family_backend.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_profiles_screen.dart';
import 'tv_shell.dart';

class TvWhoWatchingScreen extends StatefulWidget {
  const TvWhoWatchingScreen({super.key, this.onPicked});

  /// Appelé quand un profil est choisi. `null` = écran POUSSÉ en route
  /// (il se referme alors tout seul via Navigator.pop).
  final VoidCallback? onPicked;

  /// Pousse l'écran en route (usage « pastille profil » de l'accueil).
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const TvShell(child: TvWhoWatchingScreen()),
    ));
  }

  @override
  State<TvWhoWatchingScreen> createState() => _TvWhoWatchingScreenState();
}

class _TvWhoWatchingScreenState extends State<TvWhoWatchingScreen> {
  /// FAMILLE : prénom du proche qui regarde EN CE MOMENT sur un autre
  /// appareil de la ligne (null = personne). Affiché en bandeau : sur une
  /// ligne à une connexion, mieux vaut le savoir AVANT de lancer une chaîne
  /// que de découvrir « connexion déjà utilisée ». Best-effort, un GET.
  String? _busyName;

  @override
  void initState() {
    super.initState();
    // Au cas où l'appli n'aurait pas encore chargé la liste des profils.
    if (!ProfilesRepository.instance.isLoaded) {
      ProfilesRepository.instance.load();
    }
    unawaited(_loadFamilyBusy());
  }

  Future<void> _loadFamilyBusy() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (mac.isEmpty) return;
      final Map<String, dynamic>? info = await FamilyBackend.info(mac);
      if (!mounted || info == null) return;
      final List<dynamic> who =
          (info['who'] as List<dynamic>?) ?? const <dynamic>[];
      String? name;
      for (final dynamic w in who) {
        if (w is! Map<String, dynamic>) continue;
        if (w['me'] == true || w['playing'] != true) continue;
        final Object? label = w['label'];
        name = (label is String && label.isNotEmpty)
            ? label
            : (w['role'] == 'owner'
                ? context.l10n.tvFamilyOwnerLabel
                : context.l10n.tvFamilyUnnamedMember);
        break;
      }
      if (name != _busyName) setState(() => _busyName = name);
    } catch (_) {
      // Réseau muet : pas de bandeau, l'écran reste utilisable.
    }
  }

  /// Demande le code s'il y en a un, puis bascule. La liste des dépôts à
  /// recharger vit dans `activateProfile` — un seul endroit pour les trois
  /// écrans qui savent changer de profil (cf. profile_switch.dart).
  Future<void> _pick(String id) async {
    // Profil coupé depuis le panel : on ne fait rien. La tuile est déjà
    // grisée, ce chemin ne sert que de garde — un écran affiché avant la
    // synchro pourrait proposer un profil qui vient d'être désactivé.
    if (ProfilesRepository.instance.byId(id)?.enabled == false) return;
    if (!await ensureUnlocked(context, id)) return;
    if (!mounted) return;
    await activateProfile(id);
    if (!mounted) return;
    if (widget.onPicked != null) {
      widget.onPicked!.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProfilesRepository repo = ProfilesRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final List<TvProfile> all = repo.profiles;
          final bool canAdd = all.length < ProfilesRepository.maxProfiles;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  context.l10n.tvWhoWatching,
                  style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
                // Bandeau famille : un proche regarde déjà sur la ligne.
                if (_busyName != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: TvTokens.badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: TvTokens.gold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.play_circle_fill_rounded,
                            size: 20, color: TvTokens.goldBright),
                        const SizedBox(width: 10),
                        Text(
                          context.l10n.tvFamilyBusyBanner(_busyName!),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.goldBright),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 34),
                // ----- Grille d'avatars centrée -----
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 28,
                  runSpacing: 28,
                  children: <Widget>[
                    for (int i = 0; i < all.length; i++)
                      _AvatarTile(
                        profile: all[i],
                        active: all[i].id == repo.active.id,
                        autofocus: i == 0,
                        onSelect: () => _pick(all[i].id),
                      ),
                    if (canAdd) _AddTile(),
                  ],
                ),
                const SizedBox(height: 40),
                // ----- Gérer les profils (renommer / supprimer) -----
                _GhostButton(
                  icon: Icons.manage_accounts_rounded,
                  label: context.l10n.tvManageProfiles,
                  onSelect: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const TvShell(child: TvProfilesScreen()),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Une pastille ronde d'avatar (emoji) + nom dessous, focusable au D-pad.
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.profile,
    required this.active,
    required this.onSelect,
    this.autofocus = false,
  });

  final TvProfile profile;
  final bool active;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Profil COUPÉ depuis le panel : la tuile reste visible mais éteinte.
    // Volontairement grisée plutôt que retirée — un enfant dont le profil
    // disparaît croit à une panne et vient réclamer ; grisé, le message
    // « c'est fermé » se lit tout seul.
    final bool off = !profile.enabled;
    final bool locked = profile.pin != null;
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color ring = off
            ? TvTokens.lineSoft
            : (focused || active ? TvTokens.gold : TvTokens.lineSoft);
        return Opacity(
          opacity: off ? 0.38 : 1,
          child: SizedBox(
            width: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    Container(
                      width: 132,
                      height: 132,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: focused && !off ? TvTokens.sel : TvTokens.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: ring,
                            width: (focused || active) && !off ? 3 : 1),
                      ),
                      child: Text(profile.emoji,
                          style: const TextStyle(fontSize: 62)),
                    ),
                    // Cadenas : le profil demandera un code. On le montre
                    // AVANT le clic — découvrir le verrou seulement après
                    // avoir choisi donne l'impression d'un refus.
                    if (locked || off)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(
                          off ? Icons.block_rounded : Icons.lock_rounded,
                          size: 20,
                          color: off ? TvTokens.muted : TvTokens.gold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  // Profil par défaut → nom localisé (« Famille »/« Family »…).
                  tvProfileDisplayName(context, profile),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: focused && !off
                          ? TvTokens.goldBright
                          : TvTokens.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pastille « + » pour créer un profil (mène à l'écran Profils).
class _AddTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      onSelect: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TvShell(child: TvProfilesScreen()),
        ),
      ),
      builder: (BuildContext context, bool focused) {
        return SizedBox(
          width: 150,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 132,
                height: 132,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused ? TvTokens.sel : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: focused ? TvTokens.gold : TvTokens.lineSoft,
                      width: focused ? 3 : 1),
                ),
                child: Icon(Icons.add_rounded,
                    size: 54,
                    color: focused ? TvTokens.goldBright : TvTokens.muted),
              ),
              const SizedBox(height: 12),
              Text(context.l10n.tvAddProfile,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: focused ? TvTokens.goldBright : TvTokens.muted)),
            ],
          ),
        );
      },
    );
  }
}

/// Petit bouton discret (contour) sous la grille.
class _GhostButton extends StatelessWidget {
  const _GhostButton(
      {required this.icon, required this.label, required this.onSelect});

  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg =
            focused ? const Color(0xFF1A1206) : TvTokens.muted;
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(color: TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}
