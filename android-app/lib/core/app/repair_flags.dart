// =========================================================
//  repair_flags.dart — Interrupteurs de REPLI des correctifs de l'audit
// =========================================================
//  Chaque correctif de comportement de l'audit de production (octobre
//  2026) garde un interrupteur qui RÉTABLIT l'ancien comportement. Tous
//  sont FAUX par défaut : le nouveau comportement s'applique, et une
//  préférence absente ou illisible reste fausse.
//
//  Aucun écran ne les affiche : on les pose à la main (adb, ou un futur
//  réglage) si un correctif devait être désarmé sur une box. Le nom de
//  chaque clé dit ce que « vrai » rétablit.
//
//  Chargé une fois au démarrage (main_tv.dart), après la boîte noire :
//  les quelques lignes écrites avant le chargement suivent les défauts.
// =========================================================

import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class RepairFlags {
  /// Vrai = copie de la dernière image à l'ancienne (gardée même noire,
  /// retirée seulement au signal « première image »). Faux = copie noire
  /// rejetée (PixelCopy d'une surface vidéo rend souvent du noir) et copie
  /// retirée dès qu'une trame est rendue après son affichage. Correctif de
  /// l'écran noir « le son continue » après une coupure.
  static const String legacyHoldFrameKey = 'zuno.player.hold_frame_legacy';
  static bool legacyHoldFrame = false;
  /// Vrai = la boîte noire écrit les lignes TELLES QUELLES (ancien
  /// comportement). Faux = chaque ligne est expurgée à l'écriture
  /// (adresses de flux, identifiants, mots de passe) : le journal sur la
  /// box ne contient plus de secret, pas seulement la copie envoyée.
  static const String blackBoxRawKey = 'zuno.blackbox.raw';
  static bool blackBoxRaw = false;

  /// Vrai = un `fsync` disque à CHAQUE ligne du journal, sur le fil UI
  /// (ancien comportement). Faux = les lignes d'information sont écrites
  /// tout de suite (elles survivent à une mort du processus) et le
  /// `fsync` est regroupé au plus une fois par seconde ; les lignes
  /// d'avertissement et d'erreur gardent le `fsync` immédiat.
  static const String blackBoxFsyncAllKey = 'zuno.blackbox.fsync_all';
  static bool blackBoxFsyncAll = false;

  /// Vrai = l'écran Direct relance la re-vérification lente de la source
  /// (téléchargement + ré-import complet possible) même quand le lecteur
  /// plein écran est ouvert (ancien comportement). Faux = on attend que
  /// le lecteur soit fermé.
  static const String syncDuringPlaybackKey = 'zuno.sync.during_playback';
  static bool syncDuringPlayback = false;

  /// Vrai = le guide (XMLTV) n'est PAS re-téléchargé quand une liste M3U
  /// est actualisée (ancien comportement : le guide ne vivait que 48 h
  /// après l'ajout de la source). Faux = chaque actualisation de liste
  /// relance aussi le guide de cette liste.
  static const String epgRefreshOffKey = 'zuno.epg.refresh_off';
  static bool epgRefreshOff = false;

  /// Vrai = le guide XMLTV est téléchargé et décodé sur le fil UI (ancien
  /// comportement : la box saccadait pendant l'import). Faux = dans un
  /// isolate, les rangées arrivent par lots.
  static const String epgInlineParseKey = 'zuno.epg.inline_parse';
  static bool epgInlineParse = false;

  /// Vrai = chaque ouverture de chaîne écrit l'historique tout de suite
  /// (ancien : 20 chaînes survolées = 20 entrées « Reprendre »). Faux =
  /// après 20 s avec une image, ou en quittant le lecteur sur la chaîne.
  static const String historyOnOpenKey = 'zuno.history.on_open';
  static bool historyOnOpen = false;

  /// Vrai = la MAC s'affiche avec « MK: » devant (ancien affichage).
  /// Faux = le client voit « AD:A6:98:70:6A » ; l'identifiant interne
  /// (serveur, QR, appels réseau) garde toujours « MK: ».
  static const String macShowPrefixKey = 'zuno.mac.show_prefix';
  static bool macShowPrefix = false;

  /// Vrai = mise à jour à l'ancienne : un seul manifeste (release clients),
  /// 3 minutes maximum pour tout le téléchargement, pas de vérification de
  /// l'autorisation « applications inconnues » avant l'installateur.
  /// Faux = box de test : release de test ET clients, le plus récent des
  /// deux ; abandon après 45 s sans données ou 20 min ; si l'autorisation
  /// manque, l'écran Android pour la donner s'ouvre.
  static const String updateLegacyKey = 'zuno.update.legacy';
  static bool updateLegacy = false;

  /// Vrai = pas de WebSocket vers le panel. La box garde l'attente
  /// longue, puis la lecture courte (ancien rythme). Faux = on ouvre
  /// le WebSocket et on ne retombe sur l'attente longue que s'il
  /// ne tient pas. Défaut faux : le repli est coupé.
  static const String realtimeLegacyKey = 'zuno.channel.legacy';
  static bool realtimeLegacy = false;

  /// Vrai = pas de pastille « Mise à jour… » pendant le chargement d'une
  /// liste envoyée par le panel (ancien comportement : écran immobile).
  /// La durée de chargement reste notée dans la boîte noire.
  static const String syncPillOffKey = 'zuno.sync.pill_off';
  static bool syncPillOff = false;

  static Future<void> load() async {
    bool raw = false;
    bool fsyncAll = false;
    bool syncPlayback = false;
    bool epgOff = false;
    bool holdLegacy = false;
    bool epgInline = false;
    bool histOpen = false;
    bool macPrefix = false;
    bool updLegacy = false;
    bool channelLegacy = false;
    bool pillOff = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      raw = prefs.getBool(blackBoxRawKey) ?? false;
      fsyncAll = prefs.getBool(blackBoxFsyncAllKey) ?? false;
      syncPlayback = prefs.getBool(syncDuringPlaybackKey) ?? false;
      epgOff = prefs.getBool(epgRefreshOffKey) ?? false;
      holdLegacy = prefs.getBool(legacyHoldFrameKey) ?? false;
      epgInline = prefs.getBool(epgInlineParseKey) ?? false;
      histOpen = prefs.getBool(historyOnOpenKey) ?? false;
      macPrefix = prefs.getBool(macShowPrefixKey) ?? false;
      updLegacy = prefs.getBool(updateLegacyKey) ?? false;
      channelLegacy = prefs.getBool(realtimeLegacyKey) ?? false;
      pillOff = prefs.getBool(syncPillOffKey) ?? false;
    } catch (_) {
      raw = false;
      fsyncAll = false;
      syncPlayback = false;
      epgOff = false;
      holdLegacy = false;
      epgInline = false;
      histOpen = false;
      macPrefix = false;
      updLegacy = false;
      channelLegacy = false;
      pillOff = false;
    }
    syncPillOff = pillOff;
    macShowPrefix = macPrefix;
    updateLegacy = updLegacy;
    realtimeLegacy = channelLegacy;
    blackBoxRaw = raw;
    blackBoxFsyncAll = fsyncAll;
    syncDuringPlayback = syncPlayback;
    epgRefreshOff = epgOff;
    legacyHoldFrame = holdLegacy;
    epgInlineParse = epgInline;
    historyOnOpen = histOpen;
    // Le lecteur natif reçoit le réglage avec les autres (avant l'URL).
    NativeVideoController.legacyHoldFrame = holdLegacy;
    NativeVideoController.pushAudioDiagFlags();
  }

  /// Remise aux défauts (tests).
  static void debugReset() {
    blackBoxRaw = false;
    blackBoxFsyncAll = false;
    syncDuringPlayback = false;
    epgRefreshOff = false;
    legacyHoldFrame = false;
    epgInlineParse = false;
    historyOnOpen = false;
    macShowPrefix = false;
    updateLegacy = false;
    realtimeLegacy = false;
    syncPillOff = false;
    NativeVideoController.legacyHoldFrame = false;
  }
}
