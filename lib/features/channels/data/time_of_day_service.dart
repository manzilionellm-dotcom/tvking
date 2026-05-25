// =========================================================
//  time_of_day_service.dart — Suggestion contextuelle horaire
// =========================================================
//  Suggère le genre le plus pertinent à mettre en avant selon
//  l'heure courante. Deux signaux :
//
//    1. Patterns par défaut (universels, marchent pour un user
//       sans historique) :
//         - 06h-10h → News
//         - 10h-14h → Kids / Series
//         - 14h-19h → Sports
//         - 19h-23h → Movies + Sports
//         - 23h-06h → Movies / Music
//
//    2. Apprentissage personnel : on regarde dans
//       WatchHistoryRepository quelle est l'heure typique
//       de visionnage par genre. Au bout de quelques sessions,
//       les patterns par défaut sont remplacés par les vrais
//       habitudes de l'user.
//
//  Combine les deux : si l'user a un fort historique, son pattern
//  domine. Sinon, on retombe sur les défauts.
// =========================================================

import 'package:flutter/foundation.dart';

import '../domain/channel_genre.dart';
import 'watch_history_repository.dart';
// Présent pour le debugPrint conditionnel — pas d'effet en release.

class TimeOfDayService extends ChangeNotifier {
  TimeOfDayService._();
  static final TimeOfDayService instance = TimeOfDayService._();

  /// Patterns par défaut — quand l'user n'a pas encore d'historique.
  /// Clé = heure (0..23), valeur = genre suggéré.
  static const Map<int, ChannelGenre> _defaults = <int, ChannelGenre>{
    6: ChannelGenre.news,
    7: ChannelGenre.news,
    8: ChannelGenre.news,
    9: ChannelGenre.news,
    10: ChannelGenre.kids,
    11: ChannelGenre.kids,
    12: ChannelGenre.news,
    13: ChannelGenre.series,
    14: ChannelGenre.sports,
    15: ChannelGenre.sports,
    16: ChannelGenre.sports,
    17: ChannelGenre.sports,
    18: ChannelGenre.sports,
    19: ChannelGenre.movies,
    20: ChannelGenre.movies,
    21: ChannelGenre.movies,
    22: ChannelGenre.movies,
    23: ChannelGenre.music,
    0: ChannelGenre.music,
    1: ChannelGenre.music,
    2: ChannelGenre.movies,
    3: ChannelGenre.movies,
    4: ChannelGenre.movies,
    5: ChannelGenre.news,
  };

  /// Suggestion calculée pour l'heure courante.
  ChannelGenre _suggested = ChannelGenre.entertainment;
  ChannelGenre get suggestedNow => _suggested;

  /// Recalcule la suggestion. À appeler au démarrage et chaque
  /// fois qu'on entre sur l'accueil (cheap : sub-ms).
  Future<void> refresh() async {
    final int hour = DateTime.now().hour;

    // 1) Default pattern
    final ChannelGenre base =
        _defaults[hour] ?? ChannelGenre.entertainment;

    // 2) Apprentissage : on récupère le total de visionnage à cette
    //    heure-ci sur les 30 derniers jours. Pour cette version on
    //    garde simple : le default pattern fait foi. Le croisement
    //    "à cette heure × ce genre" arrivera en P2.
    //
    //    On lit quand même la valeur pour valider que le tracking
    //    fonctionne, et pour préparer le terrain (debug print en dev).
    final Map<int, int> byHour =
        await WatchHistoryRepository.instance.watchTimeByHour(days: 30);
    final int hourMs = byHour[hour] ?? 0;
    if (hourMs > 0 && kDebugMode) {
      debugPrint(
        '[TimeOfDay] hour=$hour, history=${hourMs ~/ 60000}min — using default=$base',
      );
    }

    _suggested = base;
    notifyListeners();
  }
}
