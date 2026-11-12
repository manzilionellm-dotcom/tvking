// =========================================================
//  replay_choice.dart — Peut-on revoir CE programme ?
// =========================================================
//  Une seule règle pour le guide TV : un programme se revoit seulement si
//    1. il est TERMINÉ ;
//    2. la chaîne DÉCLARE un catch-up (tv_archive Xtream, attribut
//       catchup / catchup-source du M3U) — on ne propose pas un bouton
//       qui a peu de chances de marcher ;
//    3. il est encore dans la fenêtre annoncée par le fournisseur
//       (catchupDays), quand elle est connue ;
//    4. on sait fabriquer son adresse (CatchupUrlBuilder).
//  Sinon : pas de bouton « Replay », la ligne garde son rôle d'avant.
// =========================================================
import '../../channels/domain/channel.dart';
import '../data/catchup_url_builder.dart';
import 'epg_program.dart';

abstract final class ReplayChoice {
  /// Vrai si la source annonce un catch-up pour cette chaîne.
  static bool declared(Channel channel) =>
      channel.catchupSupported ||
      (channel.catchupSource != null && channel.catchupSource!.isNotEmpty);

  /// Adresse pour revoir [program] depuis le début, ou null s'il ne se
  /// revoit pas (voir les 4 conditions en tête de fichier).
  static String? urlFor(Channel channel, EpgProgram program, DateTime now) {
    final int nowMs = now.millisecondsSinceEpoch;
    if (program.stopTime > nowMs) return null; // en cours ou à venir
    if (!declared(channel)) return null;
    final int? days = channel.catchupDays;
    if (days != null && days > 0) {
      final int oldest = nowMs - days * Duration.millisecondsPerDay;
      if (program.startTime < oldest) return null; // archive expirée
    }
    final String? url =
        CatchupUrlBuilder.build(channel: channel, program: program);
    return (url == null || url.isEmpty) ? null : url;
  }
}
