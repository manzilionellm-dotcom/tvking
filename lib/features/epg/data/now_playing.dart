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
    final ({EpgProgram? now, EpgProgram? next}) pair =
        await maintenantEtEnsuite(channel, now: now);
    return pair.now;
  }

  /// En-cours ET suivant, même ordre de sources que [pour].
  ///
  /// POURQUOI CETTE PAIRE. MiniEpgNowNext et le bandeau du guide D
  /// ont besoin des DEUX lignes. Deux appels [pour] + nextProgram
  /// doubleraient le court-circuit panel (et risqueraient deux
  /// allers-retours). Une seule lecture locale, un seul
  /// `upcomingFor` (déjà coalescé / TTL 10 min).
  ///
  /// PAS 900 get_short_epg au scroll : ShortEpgService cache
  /// positif+négatif et fusionne les demandes en vol. L'UI doit
  /// encore débouncer (MiniEpgNowNext.debounce) pour ne demander
  /// que la chaîne où le focus SE POSE.
  static Future<({EpgProgram? now, EpgProgram? next})> maintenantEtEnsuite(
    Channel channel, {
    DateTime? now,
  }) async {
    try {
      final DateTime instant = now ?? DateTime.now();
      // 1. Base locale (gratuite, cache 60 s).
      final EpgProgram? localNow =
          await EpgRepository.instance.currentProgram(channel.id);
      if (localNow != null) {
        final EpgProgram? localNext =
            await EpgRepository.instance.nextProgram(channel.id);
        return (now: localNow, next: localNext);
      }
      // 2. Panel, UNE chaîne, cache 10 min.
      final List<EpgProgram> courts =
          await ShortEpgService.instance.upcomingFor(channel);
      final EpgProgram? en = enCours(courts, instant);
      return (now: en, next: suivant(courts, instant, enCours: en));
    } catch (_) {
      return (now: null, next: null);
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

  /// Premier programme qui COMMENCE à ou après la fin de l'en-cours
  /// (ou après [now] s'il n'y a pas d'en-cours). PURE.
  @visibleForTesting
  static EpgProgram? suivant(
    List<EpgProgram> programmes,
    DateTime now, {
    EpgProgram? enCours,
  }) {
    final int after = enCours?.stopTime ?? now.millisecondsSinceEpoch;
    EpgProgram? best;
    for (final EpgProgram p in programmes) {
      if (p.startTime < after) continue;
      if (best == null || p.startTime < best.startTime) best = p;
    }
    return best;
  }
}
