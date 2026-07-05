// =========================================================
//  tv_profiles_screen.dart — Profils famille (TV, façon Netflix)
// =========================================================
//  Chaque membre a SON profil : ses « Derniers vus », son historique de
//  recherche, ses collections. Ici on choisit le profil ACTIF, on en crée
//  (pastilles prêtes, pas de clavier) et on en supprime (2 temps).
//
//  STABILITÉ : zéro contact lecteur / écran Direct. Changer de profil
//  recharge simplement les 3 petits dépôts locaux concernés.
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

/// Modèles proposés à la création (un clic, pas de clavier fastidieux).
const List<({String name, String emoji})> _kPresets =
    <({String name, String emoji})>[
  (name: 'Papa', emoji: '👨'),
  (name: 'Maman', emoji: '👩'),
  (name: 'Enfants', emoji: '🧒'),
  (name: 'Ado', emoji: '🧑'),
  (name: 'Invité', emoji: '🛋️'),
];

class TvProfilesScreen extends StatefulWidget {
  const TvProfilesScreen({super.key});

  @override
  State<TvProfilesScreen> createState() => _TvProfilesScreenState();
}

class _TvProfilesScreenState extends State<TvProfilesScreen> {
  String? _confirmDeleteId;

  @override
  void initState() {
    super.initState();
    ProfilesRepository.instance.load();
  }

  /// Active [id] puis recharge les données PAR PROFIL (récents, recherches,
  /// collections) — les écrans concernés relisent ces dépôts à l'ouverture.
  Future<void> _activate(String id) async {
    await ProfilesRepository.instance.setActive(id);
    await RecentVodRepository.instance.load();
    await SearchHistoryRepository.instance.load();
    await FavoriteCollectionsRepository.instance.load();
    await VodWatchlistRepository.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final ProfilesRepository repo = ProfilesRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final List<TvProfile> all = repo.profiles;
          final List<({String name, String emoji})> available = _kPresets
              .where((({String name, String emoji}) p) =>
                  repo.byName(p.name) == null)
              .toList(growable: false);
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: ListView(
              children: <Widget>[
                const Text(
                  'Profils',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chacun son univers : derniers films vus, recherches et '
                  'collections sont propres à chaque profil. Les favoris '
                  'restent partagés par la famille.',
                  style: TextStyle(fontSize: 15, color: TvTokens.muted),
                ),
                const SizedBox(height: 22),
                // ----- Profils existants -----
                for (final TvProfile p in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TvFocusBuilder(
                            scale: TvFocusScale.large,
                            autofocus: p.id == repo.active.id,
                            onSelect: () => _activate(p.id),
                            builder: (BuildContext context, bool focused) {
                              final bool isActive = p.id == repo.active.id;
                              final Color bg =
                                  focused ? TvTokens.gold : TvTokens.sel;
                              final Color fg = focused
                                  ? const Color(0xFF1A1206)
                                  : TvTokens.goldBright;
                              return Container(
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(
                                      TvDimens.cardRadius),
                                  border: Border.all(
                                      color: isActive
                                          ? TvTokens.gold
                                          : TvTokens.lineSoft),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 16),
                                child: Row(
                                  children: <Widget>[
                                    Text(p.emoji,
                                        style:
                                            const TextStyle(fontSize: 26)),
                                    const SizedBox(width: 14),
                                    Text(p.name,
                                        style: TextStyle(
                                            fontSize: TvDimens.title,
                                            fontWeight: FontWeight.w700,
                                            color: fg)),
                                    const Spacer(),
                                    if (isActive)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(Icons.check_circle_rounded,
                                              size: 20,
                                              color: focused
                                                  ? fg
                                                  : TvTokens.gold),
                                          const SizedBox(width: 6),
                                          Text('Actif',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: focused
                                                      ? fg
                                                      : TvTokens.gold)),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // Suppression (jamais pour « Famille »), en 2 temps.
                        if (p.id != ProfilesRepository.familyProfile.id) ...<Widget>[
                          const SizedBox(width: 10),
                          TvFocusBuilder(
                            scale: TvFocusScale.small,
                            onSelect: () {
                              if (_confirmDeleteId == p.id) {
                                repo.delete(p.id);
                                setState(() => _confirmDeleteId = null);
                              } else {
                                setState(() => _confirmDeleteId = p.id);
                              }
                            },
                            builder: (BuildContext context, bool focused) {
                              final bool confirming =
                                  _confirmDeleteId == p.id;
                              final Color bg = focused
                                  ? (confirming
                                      ? TvTokens.live
                                      : TvTokens.gold)
                                  : TvTokens.card;
                              final Color fg = focused
                                  ? Colors.white
                                  : (confirming
                                      ? TvTokens.live
                                      : TvTokens.muted);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(
                                      TvDimens.cardRadius),
                                  border:
                                      Border.all(color: TvTokens.lineSoft),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.delete_outline_rounded,
                                        size: 20, color: fg),
                                    if (confirming) ...<Widget>[
                                      const SizedBox(width: 6),
                                      Text('Confirmer ?',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: fg)),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // ----- Création (pastilles) -----
                if (available.isNotEmpty &&
                    all.length < ProfilesRepository.maxProfiles) ...<Widget>[
                  const Text(
                    'AJOUTER UN PROFIL',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.mutedDim,
                        letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      for (final ({String name, String emoji}) p in available)
                        TvFocusBuilder(
                          scale: TvFocusScale.small,
                          onSelect: () => repo.create(p.name, p.emoji),
                          builder: (BuildContext context, bool focused) {
                            final Color bg =
                                focused ? TvTokens.gold : TvTokens.card;
                            final Color fg = focused
                                ? const Color(0xFF1A1206)
                                : TvTokens.text;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(
                                    TvDimens.cardRadius),
                                border:
                                    Border.all(color: TvTokens.lineSoft),
                              ),
                              child: Text('${p.emoji}  ${p.name}',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
