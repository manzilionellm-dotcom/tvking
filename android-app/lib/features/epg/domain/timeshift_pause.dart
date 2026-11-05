// =========================================================
//  timeshift_pause.dart — Pause du direct, si le fournisseur suit
// =========================================================
//  Le lecteur TV ne garde PAS les images déjà jouées (tampon
//  arrière à 0) et ne prépare au plus que 45 s d'avance. En
//  dessous de ce délai, Pause puis Lecture reprend le MÊME flux :
//  une seule connexion, rien à reconstruire.
//
//  Au-delà, le direct a glissé. On n'invente pas une archive :
//  on réutilise [CatchupUrlBuilder]. S'il ne sait pas fabriquer
//  d'adresse (chaîne sans catch-up, et pas un flux Xtream), on
//  reste sur Lecture. On n'ouvre jamais un second lecteur pour
//  « précharger » la chaîne d'à côté : beaucoup de fournisseurs
//  refusent la chaîne dès qu'une deuxième connexion arrive, et
//  une box d'entrée de gamme n'a pas deux décodeurs.
// =========================================================

import '../../channels/domain/channel.dart';
import '../data/catchup_url_builder.dart';
import 'epg_program.dart';

abstract final class TimeshiftPause {
  /// Fenêtre déjà couverte par le tampon du lecteur (cf. le
  /// commentaire du lecteur natif : max 45 s, arrière à 0).
  static const Duration sameStreamHold = Duration(seconds: 45);

  /// Vrai si [CatchupUrlBuilder] sait fabriquer une adresse pour
  /// cette chaîne. On jette l'adresse : elle peut contenir les
  /// identifiants du flux, on ne l'écrit nulle part.
  static bool supports(Channel channel) {
    if (channel.streamUrl.trim().isEmpty) return false;
    final DateTime start = DateTime.utc(2020, 1, 1, 12);
    final String? url = CatchupUrlBuilder.build(
      channel: channel,
      program: EpgProgram(
        channelId: channel.id,
        startTime: start.millisecondsSinceEpoch,
        stopTime: start.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        title: '',
      ),
    );
    return url != null && url.isNotEmpty;
  }

  /// Adresse à ouvrir pour reprendre à l'instant de la pause.
  /// `null` : rester sur le flux déjà ouvert (Lecture simple).
  static String? resumeUrl({
    required Channel channel,
    required DateTime pausedAt,
    required DateTime resumedAt,
    required bool live,
    required bool alreadyTimeshift,
  }) {
    if (!live || alreadyTimeshift) return null;
    if (!resumedAt.isAfter(pausedAt)) return null;
    if (resumedAt.difference(pausedAt) < sameStreamHold) return null;
    // Le timeshift Xtream est à la minute. On aligne le début
    // sur la minute de la pause, pas sur une seconde inventée.
    final DateTime start = DateTime(
      pausedAt.year,
      pausedAt.month,
      pausedAt.day,
      pausedAt.hour,
      pausedAt.minute,
    );
    return CatchupUrlBuilder.build(
      channel: channel,
      program: EpgProgram(
        channelId: channel.id,
        startTime: start.millisecondsSinceEpoch,
        stopTime: resumedAt.millisecondsSinceEpoch,
        title: '',
      ),
    );
  }
}
