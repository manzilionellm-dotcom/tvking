// =========================================================
//  profile_switch.dart — Basculer de profil, UNE seule fois
// =========================================================
//  POURQUOI CE FICHIER EXISTE (30/08/2026).
//
//  Il existait TROIS écrans capables de changer de profil — « Qui
//  regarde ? » (TV), « Profils » (TV), « Profils » (mobile) — et donc
//  trois listes de dépôts à recharger, écrites à la main, qui avaient
//  divergé : la TV en rechargeait quatre, le mobile cinq, et aucun des
//  trois ne rechargeait l'historique des chaînes.
//
//  Le symptôme n'était pas un plantage — c'est pire : après une bascule,
//  un écran affichait encore les données du profil PRÉCÉDENT jusqu'à sa
//  prochaine ouverture. Un enfant voyait les derniers films de son père.
//
//  Une seule fonction, ici. Ajouter un dépôt par profil demain, c'est une
//  ligne à AJOUTER À UN SEUL ENDROIT — et les trois écrans en profitent.
//
//  ---------------------------------------------------------
//  LE CODE PIN
//  ---------------------------------------------------------
//  [ensureUnlocked] pose la question du code AVANT la bascule. Il vaut
//  mieux qu'elle vive ici, à côté du reste : mise dans les écrans, elle
//  aurait pu être oubliée dans le troisième — et un profil verrouillé
//  qu'on peut ouvrir depuis un autre écran ne verrouille rien.
//
//  On refuse EN SILENCE, sans dire « il reste 2 essais » ni bloquer après
//  N tentatives : sur une box familiale, un enfant qui tâtonne ne doit pas
//  pouvoir enfermer son parent dehors. Le PIN protège d'un curieux, pas
//  d'un attaquant — et c'est écrit ici pour que personne ne s'imagine le
//  contraire plus tard.
// =========================================================
import 'package:flutter/material.dart';

import '../../features/channels/data/hidden_categories_store.dart';
import '../../features/channels/data/recently_watched_repository.dart';
import '../../features/channels/data/search_history_repository.dart';
import '../../features/playlists/data/favorite_collections_repository.dart';
import '../../features/vod/data/followed_series_repository.dart';
import '../../features/vod/data/playback_position_repository.dart';
import '../../features/vod/data/recent_vod_repository.dart';
import '../../features/vod/data/vod_watchlist_repository.dart';
import '../observability/structured_logger.dart';
import 'profiles_repository.dart';

/// Active le profil [id] et remet TOUTES les données par profil à jour.
///
/// Ne vérifie pas le code : appeler [ensureUnlocked] avant (les écrans le
/// font). Ne throw jamais — un dépôt qui échoue n'empêche pas les autres de
/// se recharger, sinon une bascule ratée à mi-chemin laisserait l'app avec
/// un mélange de deux profils, le pire des états.
Future<void> activateProfile(String id) async {
  await ProfilesRepository.instance.setActive(id);

  // Chacun dans son propre try : voir plus haut. L'ordre n'a pas
  // d'importance, ils ne se parlent pas entre eux.
  Future<void> safe(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      StructuredLogger.instance.warn(
        domain: 'profiles',
        event: 'switch.reload_fail',
        ctx: <String, Object?>{'repo': what, 'error': e.toString()},
      );
    }
  }

  await safe('recentVod', RecentVodRepository.instance.load);
  await safe('searchHistory', SearchHistoryRepository.instance.load);
  await safe('collections', FavoriteCollectionsRepository.instance.load);
  await safe('watchlist', VodWatchlistRepository.instance.load);
  await safe('playbackPositions', PlaybackPositionRepository.instance.load);
  await safe('followedSeries', FollowedSeriesRepository.instance.load);
  // L'historique des CHAÎNES (« Continuer à regarder ») : celui que les
  // trois écrans oubliaient. C'est pourtant le plus visible des trois.
  await safe('recentChannels', RecentlyWatchedRepository.instance.reload);
  // Catégories masquées : le choix du client est par profil, et le verrou
  // du panel change avec le profil actif.
  await safe('hiddenCategories', HiddenCategoriesStore.instance.reload);

  // WatchStatsService et ParentalControls écoutent déjà ProfilesRepository
  // et se remettent à jour tout seuls — les appeler ici les rechargerait
  // deux fois.
}

/// Demande le code du profil [id] si nécessaire.
///
/// Renvoie `true` si l'on peut basculer : profil sans code, ou code juste
/// saisi correctement. `false` si l'utilisateur annule ou se trompe.
Future<bool> ensureUnlocked(BuildContext context, String id) async {
  final ProfilesRepository repo = ProfilesRepository.instance;
  if (!repo.requiresPin(id)) return true;
  final TvProfile? p = repo.byId(id);
  if (p == null) return false;

  final String? entered = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) => _PinDialog(profile: p),
  );
  if (entered == null || entered.isEmpty) return false;
  final bool ok = repo.verifyPin(id, entered);
  StructuredLogger.instance.info(
    domain: 'profiles',
    event: ok ? 'pin.ok' : 'pin.refused',
    ctx: <String, Object?>{'profile': id},
  );
  return ok;
}

/// Saisie du code, au pavé numérique.
///
///  UN PAVÉ DESSINÉ, PAS UN CLAVIER SYSTÈME : sur une TV il n'y a pas de
///  clavier, seulement une télécommande. Les mêmes touches (haut/bas/
///  gauche/droite/OK) suffisent à traverser une grille de boutons, alors
///  qu'un champ de texte y ouvrirait le clavier virtuel du constructeur —
///  différent sur chaque marque, et pénible à traverser.
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.profile});

  final TvProfile profile;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _code = '';

  /// Longueur maximale d'un code de profil (le panel accepte 4 à 8
  /// chiffres). On ne valide pas automatiquement à 4 : un code de 6
  /// chiffres serait refusé avant d'être fini.
  static const int _max = 8;

  void _push(String d) {
    if (_code.length >= _max) return;
    setState(() => _code += d);
  }

  void _back() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Text(widget.profile.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.profile.name)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Points, jamais les chiffres : quelqu'un debout derrière la
          // télé lirait un code affiché en clair sur un écran de 55".
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < (_code.isEmpty ? 4 : _code.length); i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    i < _code.length
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          for (final List<String> row in const <List<String>>[
            <String>['1', '2', '3'],
            <String>['4', '5', '6'],
            <String>['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final String d in row)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      width: 62,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _push(d),
                        child: Text(d, style: theme.textTheme.titleMedium),
                      ),
                    ),
                  ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 62,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _back,
                    child: const Icon(Icons.backspace_outlined, size: 18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 62,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _push('0'),
                    child: Text('0', style: theme.textTheme.titleMedium),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 62,
                  height: 48,
                  child: FilledButton(
                    // Un code trop court ne peut pas être bon : on garde le
                    // bouton inerte plutôt que d'afficher un échec.
                    onPressed: _code.length >= 4
                        ? () => Navigator.of(context).pop(_code)
                        : null,
                    child: const Icon(Icons.check_rounded, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
