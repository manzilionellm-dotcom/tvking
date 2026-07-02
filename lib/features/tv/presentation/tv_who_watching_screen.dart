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
import 'package:flutter/material.dart';

import '../../../core/profiles/profiles_repository.dart';
import '../../channels/data/search_history_repository.dart';
import '../../playlists/data/favorite_collections_repository.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/vod_watchlist_repository.dart';
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
  @override
  void initState() {
    super.initState();
    // Au cas où l'appli n'aurait pas encore chargé la liste des profils.
    if (!ProfilesRepository.instance.isLoaded) {
      ProfilesRepository.instance.load();
    }
  }

  /// Active [id] puis recharge TOUS les dépôts par profil (récents, recherches,
  /// collections, Ma Liste) — les écrans relisent ces dépôts à l'ouverture.
  Future<void> _pick(String id) async {
    await ProfilesRepository.instance.setActive(id);
    await RecentVodRepository.instance.load();
    await SearchHistoryRepository.instance.load();
    await FavoriteCollectionsRepository.instance.load();
    await VodWatchlistRepository.instance.load();
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
                const Text(
                  'Qui regarde ?',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
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
                  label: 'Gérer les profils',
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
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color ring = focused
            ? TvTokens.gold
            : (active ? TvTokens.gold : TvTokens.lineSoft);
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
                  color: focused ? TvTokens.sel : TvTokens.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: ring, width: focused || active ? 3 : 1),
                ),
                child: Text(profile.emoji,
                    style: const TextStyle(fontSize: 62)),
              ),
              const SizedBox(height: 12),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: focused ? TvTokens.goldBright : TvTokens.muted),
              ),
            ],
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
              Text('Ajouter',
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
