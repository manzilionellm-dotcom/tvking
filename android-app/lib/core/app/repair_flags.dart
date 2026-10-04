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

  static Future<void> load() async {
    bool raw = false;
    bool fsyncAll = false;
    bool syncPlayback = false;
    bool epgOff = false;
    bool holdLegacy = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      raw = prefs.getBool(blackBoxRawKey) ?? false;
      fsyncAll = prefs.getBool(blackBoxFsyncAllKey) ?? false;
      syncPlayback = prefs.getBool(syncDuringPlaybackKey) ?? false;
      epgOff = prefs.getBool(epgRefreshOffKey) ?? false;
      holdLegacy = prefs.getBool(legacyHoldFrameKey) ?? false;
    } catch (_) {
      raw = false;
      fsyncAll = false;
      syncPlayback = false;
      epgOff = false;
      holdLegacy = false;
    }
    blackBoxRaw = raw;
    blackBoxFsyncAll = fsyncAll;
    syncDuringPlayback = syncPlayback;
    epgRefreshOff = epgOff;
    legacyHoldFrame = holdLegacy;
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
    NativeVideoController.legacyHoldFrame = false;
  }
}
