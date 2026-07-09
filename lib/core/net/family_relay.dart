// =========================================================
//  family_relay.dart — FLUX MUTUALISÉ (option famille)
// =========================================================
//  PROBLÈME MÉTIER : l'option famille partage UNE ligne Xtream sur
//  plusieurs appareils. Or le fournisseur limite le nombre de connexions
//  SIMULTANÉES (souvent 1). Si 5 appareils tapent directement le
//  fournisseur, ça fait 5 connexions → saturé.
//
//  SOLUTION : un relais central (server/cast-remux) tire le flux UNE fois
//  par chaîne et le redistribue à tous les spectateurs de cette chaîne.
//  Le fournisseur voit alors 1 connexion PAR CHAÎNE regardée (pas par
//  appareil). Les appareils d'une famille en « flux mutualisé » lisent
//  donc leurs chaînes via ce relais au lieu du fournisseur.
//
//  ⚠️ Limite physique (honnête) : la mutualisation ne collapse QUE les
//  spectateurs d'une MÊME chaîne. 5 personnes sur 5 chaînes différentes =
//  5 flux (contenus différents — impossible à réduire). 5 personnes sur
//  la même chaîne = 1 flux.
//
//  Ce singleton porte la base du relais (livrée par le panel via
//  /api/device-net, champ `relay`, appliquée à l'appareil quand l'admin a
//  coché « flux mutualisé »). Vide = OFF → lecture directe (inchangé).
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

class FamilyRelay {
  FamilyRelay._();
  static final FamilyRelay instance = FamilyRelay._();

  /// Base HTTPS du relais central (ex. 'https://relais.mon-infra.net').
  /// Vide = flux mutualisé désactivé pour cet appareil.
  String _base = '';

  /// Notifie les lecteurs ouverts d'un changement (re-router au prochain zap).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get isActive => _base.isNotEmpty;
  String get base => _base;

  bool update(String base) {
    final String b = base.trim().replaceAll(RegExp(r'/+$'), '');
    if (b == _base) return false;
    _base = b;
    revision.value++;
    if (kDebugMode) {
      debugPrint('[FamilyRelay] ${_base.isEmpty ? "OFF (direct)" : _base}');
    }
    return true;
  }

  void clear() => update('');

  /// Réécrit une URL de flux LIVE vers le relais mutualisé. Renvoie l'URL
  /// d'origine si le relais est OFF, si l'URL est vide, ou si ce n'est pas
  /// un flux live pris en charge (VOD/replay restent directs).
  ///
  /// Forme produite : `<base>/live/<b64url(url)>/master.m3u8` — exactement
  /// la route servie par server/cast-remux (mutualisation par b64url de
  /// l'upstream : deux spectateurs de la même chaîne → même clé → 1 ffmpeg).
  String wrapLive(String url) {
    if (_base.isEmpty || url.isEmpty) return url;
    // On ne mutualise QUE le live (le VOD/replay n'a pas d'enjeu de
    // connexions simultanées et n'est pas servi par le remux live).
    if (!_looksLive(url)) return url;
    // Déjà passé par le relais (idempotent) → ne pas ré-emballer.
    if (url.startsWith(_base)) return url;
    final String b64 =
        base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return '$_base/live/$b64/master.m3u8';
  }

  /// Heuristique « c'est du live » : les URLs Xtream live sont de la forme
  /// `…/live/user/pass/id.ts|m3u8` ou `…/user/pass/id.ts` (sans /movie/ ni
  /// /series/). On mutualise le .ts et le .m3u8 live ; on laisse le VOD.
  bool _looksLive(String url) {
    final String u = url.toLowerCase();
    if (u.contains('/movie/') || u.contains('/series/')) return false;
    return u.contains('/live/') ||
        u.endsWith('.ts') ||
        u.contains('.ts?') ||
        // live HLS Xtream (…/id.m3u8) hors VOD (déjà exclu ci-dessus).
        u.contains('.m3u8');
  }
}
