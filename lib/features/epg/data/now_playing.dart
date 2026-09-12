// =========================================================
//  now_playing.dart — « qu'est-ce qui passe sur cette chaîne ? »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (12/09/2026), photo de sa recherche à l'appui :
//  il tape « cana », les chaînes remontent bien — Canal Play 04, Canal
//  Play 06, Prime: Canal J — mais chaque vignette ne porte QUE son logo et
//  son nom. « Les informations ne viennent pas. »
//
//  ---------------------------------------------------------
//  POURQUOI ELLES NE VENAIENT PAS
//  ---------------------------------------------------------
//  L'application a DEUX sources de guide, et la recherche n'en consultait
//  aucune :
//
//   1. LE XMLTV IMPORTÉ (base locale). Complet quand il marche, gratuit et
//      instantané. Mais chez ce client il ne couvre qu'une douzaine de
//      chaînes sur neuf cents — mesuré, et affiché dans la Boîte noire.
//      Le XMLTV du panel nomme les chaînes « TF1.fr » quand les nôtres
//      s'appellent « xtream-1234 » ; sans correspondance, rien ne matche.
//
//   2. L'EPG COURTE DU PANEL (`get_short_epg`), qui répond chaîne par
//      chaîne, par identifiant de flux — donc SANS dépendre de cette
//      correspondance. Elle existait déjà (short_epg_service.dart) et ne
//      servait qu'à UN écran : l'aperçu de la liste des chaînes.
//
//  Autrement dit : le repli qui aurait sauvé la recherche était écrit,
//  testé, en production — et branché à un seul endroit. Encore une
//  fonctionnalité qui existe et dont le câblage manque.
//
//  ---------------------------------------------------------
//  L'ORDRE DES DEUX SOURCES EST LA DÉCISION
//  ---------------------------------------------------------
//  La base locale D'ABORD, toujours : zéro réseau, réponse immédiate, et
//  elle a déjà son cache de 60 secondes. Le panel seulement si elle ne
//  sait pas. L'inverse ferait payer un aller-retour réseau à des chaînes
//  dont on connaît déjà le programme — sur une box, à trois mètres, ça se
//  voit.
//
//  Et l'absence de réponse n'est jamais une erreur : une chaîne sans
//  guide affiche simplement son nom, comme avant. On n'écrit pas
//  « indisponible » sous chaque vignette — ce serait transformer un
//  manque discret en défaut criant.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../domain/epg_program.dart';
import 'epg_repository.dart';
import 'short_epg_service.dart';

class NowPlaying {
  NowPlaying._();

  /// Ce qui passe MAINTENANT sur [channel], ou `null` si aucune des deux
  /// sources ne le sait.
  ///
  /// BEST-EFFORT : ni exception, ni attente visible. Un écran qui liste des
  /// chaînes ne doit pas ralentir parce qu'un guide manque.
  static Future<EpgProgram?> pour(Channel channel, {DateTime? now}) async {
    try {
      // 1. La base locale (gratuite, instantanée, déjà mise en cache).
      final EpgProgram? local =
          await EpgRepository.instance.currentProgram(channel.id);
      if (local != null) return local;
      // 2. Le panel, chaîne par chaîne. Son propre cache — positif ET
      //    négatif — fait qu'une chaîne sans guide n'est demandée qu'une
      //    fois toutes les dix minutes, même si la vignette se reconstruit
      //    à chaque lettre tapée.
      final List<EpgProgram> courts =
          await ShortEpgService.instance.upcomingFor(channel);
      return enCours(courts, now ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Ce qui est à l'antenne à [now] dans une liste de programmes. PURE.
  ///
  /// `get_short_epg` renvoie « l'en-cours et les suivants », mais rien ne
  /// garantit l'ordre ni que le premier ait commencé : selon le panel, la
  /// liste peut démarrer au programme SUIVANT (l'en-cours étant déjà
  /// filtré), ou contenir des créneaux qui se chevauchent. Prendre
  /// aveuglément le premier élément annoncerait donc au client une
  /// émission qui n'a pas commencé — exactement le genre de petit
  /// mensonge qui fait douter de tout le reste de l'écran.
  ///
  /// On exige donc que le créneau CONTIENNE l'instant : début ≤ now < fin.
  @visibleForTesting
  static EpgProgram? enCours(List<EpgProgram> programmes, DateTime now) {
    for (final EpgProgram p in programmes) {
      final DateTime debut = p.startDateTime;
      final DateTime fin = p.stopDateTime;
      if (!debut.isAfter(now) && fin.isAfter(now)) return p;
    }
    return null;
  }
}
