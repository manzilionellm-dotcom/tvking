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

  /// Vrai = la box ignore l'interrupteur allumé / éteint du panel (ancien
  /// comportement : une liste envoyée est toujours visible). Faux = une
  /// liste éteinte dans le panel est masquée, rallumée elle revient.
  static const String panelVisibilityOffKey = 'zuno.panel.visibility_off';
  static bool panelVisibilityOff = false;

  /// Vrai = un ordre « source » reçu par l'attente longue attend le retour
  /// à l'accueil avant d'importer la liste (ancien comportement : la liste
  /// envoyée depuis le panel n'arrivait pas tant que le client regardait
  /// une chaîne). Faux = l'ordre du panel importe tout de suite, comme
  /// sur le chemin WebSocket.
  static const String sourceOrderWaitsIdleKey = 'zuno.source.order_waits_idle';
  static bool sourceOrderWaitsIdle = false;

  /// Vrai = la passe automatique (2 min après l'ouverture, puis toutes les
  /// 6 h) retélécharge TOUTES les listes synchronisées il y a plus de
  /// 2 minutes (ancien comportement : « Mise à jour… » pendant de longues
  /// minutes à chaque ouverture, 3 listes retéléchargées d'un coup).
  /// Faux = elle ne retélécharge que les listes synchronisées il y a plus
  /// de 6 h. Le bouton Redémarrer garde la passe complète.
  static const String autoRefreshFullKey = 'zuno.refresh.auto_full';
  static bool autoRefreshFull = false;

  /// Vrai = les chaînes d'une NOUVELLE liste n'apparaissent qu'à la fin de
  /// l'insertion (ancien comportement). Faux = sur une box encore sans
  /// chaîne, le premier lot (1 000 chaînes) est affiché dès qu'il est en
  /// base, le reste suit : le client voit sa liste arriver à la seconde.
  /// Une box qui a déjà des chaînes n'est pas concernée (relire toute la
  /// base pendant un import faisait planter les box à 1 Go, audit P1-3).
  static const String importFirstBatchOffKey = 'zuno.import.first_batch_off';
  static bool importFirstBatchOff = false;

  /// Vrai = après une liste chargée sur ordre du panel, la box attend le
  /// prochain heartbeat régulier (jusqu'à 60 s, ou le prochain démarrage)
  /// pour remonter son inventaire (ancien comportement). Faux = elle
  /// l'envoie tout de suite : le panel affiche « Liste sur la TV après
  /// N s » (bouton Envoi instantané) dès que l'import est fini.
  static const String heartbeatAfterImportOffKey = 'zuno.heartbeat.after_import_off';
  static bool heartbeatAfterImportOff = false;

  /// Vrai = la pastille « Mise à jour… » s'affiche sur l'accueil pendant un
  /// import (comportement des builds #154 à #157). Faux (défaut depuis le
  /// 05/10/2026, demande du propriétaire : « je ne veux plus voir le bouton
  /// mise à jour sur la télévision ») = rien à l'écran, l'import se fait en
  /// silence ; la mesure reste dans la boîte noire.
  static const String updatingPillShownKey = 'zuno.sync.pill_show';
  static bool updatingPillShown = false;

  /// Vrai = l'APK vérifié attend que le client ouvre Réglages → Mise à
  /// jour (ancien comportement). Faux = dès que l'APK est téléchargé et
  /// vérifié, la box ouvre elle-même l'installateur Android quand elle
  /// est à l'accueil (une seule confirmation système « Installer », que
  /// Android exige pour toute app hors Play Store), une fois par version.
  static const String autoInstallOffKey = 'zuno.update.auto_install_off';
  static bool autoInstallOff = false;

  /// Vrai = téléchargement M3U à l'ancienne : 90 s pour les en-têtes et
  /// 90 s pour tout le corps (mesuré le 05/10/2026 : « refusée après
  /// 90,0 s » sur un fournisseur lent derrière Cloudflare). Faux = 120 s
  /// pour la première réponse, puis on continue tant que des octets
  /// arrivent (60 s de silence maximum, 10 min au total).
  static const String m3uTimeoutLegacyKey = 'zuno.m3u.timeout_legacy';
  static bool m3uTimeoutLegacy = false;

  /// Vrai = un lien « get.php?username=…&password=… » envoyé par le panel
  /// est téléchargé comme un fichier M3U complet (ancien comportement :
  /// des dizaines de Mo, parfois plus de 90 s à générer). Faux = il est
  /// lu par l'API Xtream du même serveur (chaînes TV seules, JSON léger,
  /// quelques secondes), comme le font les grandes applications ; si
  /// l'API refuse, repli automatique sur le fichier M3U.
  static const String m3uLinkAsM3uKey = 'zuno.source.m3u_link_as_m3u';
  static bool m3uLinkAsM3u = false;

  /// Vrai = à chaque tour, la box réessaie TOUTES les listes du panel dans
  /// l'ordre du serveur, même celles qui viennent d'être refusées (ancien
  /// comportement : une liste au mot de passe faux bloquait la bonne
  /// pendant des heures). Faux = une liste refusée attend 5, 15, 45 min,
  /// 2 h puis 6 h, et passe après les listes saines ; un ordre du panel
  /// remet tout le monde en course.
  static const String sourceRetryAlwaysKey = 'zuno.source.retry_always';
  static bool sourceRetryAlways = false;

  /// Vrai = ancien comportement : si la ligne d'une liste a disparu de la
  /// base pendant le téléchargement de ses chaînes, l'écriture échoue
  /// (« FOREIGN KEY constraint failed », mesuré les 5 et 6 octobre 2026 après
  /// 145 s puis 131 s de téléchargement) et tout est perdu. Faux = la box
  /// le constate juste avant d'écrire, le note dans la boîte noire avec la
  /// durée, remet la ligne et termine l'import.
  static const String importReinsertOffKey = 'zuno.import.reinsert_off';
  static bool importReinsertOff = false;

  /// Vrai = ancien comportement : la passe « nouvelles chaînes » (2 min
  /// après l'ouverture, puis toutes les 6 h) re-télécharge aussi une liste
  /// dont l'ajout est encore en cours (jamais synchronisée) : deux
  /// téléchargements de la même liste en même temps sur une box 1 Go.
  /// Faux = une liste jamais synchronisée est laissée à son import.
  static const String refreshPendingLegacyKey = 'zuno.refresh.pending_legacy';
  static bool refreshPendingLegacy = false;

  /// Vrai = la box ignore la remise à neuf demandée depuis le panel
  /// (`reset_at` du statut). Faux = elle efface listes, chaînes, favoris,
  /// historique et guide, puis relit ses listes (bouton « Réinitialiser la
  /// box », 06/10/2026).
  static const String remoteResetOffKey = 'zuno.reset.off';
  static bool remoteResetOff = false;

  /// Vrai = un build de test vérifie une nouvelle version toutes les 30 min
  /// comme un build client. Faux = toutes les 60 s (mesuré le 06/10/2026 :
  /// « la mise à jour met 3 à 5 minutes à arriver »). Sans effet sur les
  /// builds clients, qui gardent 30 min + l'ordre « force_update » du panel.
  static const String testUpdatePollLegacyKey = 'zuno.update.test_poll_legacy';
  static bool testUpdatePollLegacy = false;

  /// Vrai = ancien ordre : les listes que le panel ne sert plus sont
  /// effacées AVANT d'importer les nouvelles (« effacer l'ancienne puis
  /// espérer »). Faux = on importe d'abord, on efface ensuite ; et si
  /// toutes les nouvelles listes sont refusées, l'ancienne reste à l'écran
  /// jusqu'au tour suivant (dernière configuration qui marchait).
  static const String sourceDropFirstLegacyKey = 'zuno.source.drop_first_legacy';
  static bool sourceDropFirstLegacy = false;

  /// Vrai = la box n'envoie aucun accusé d'ordre (ancien comportement :
  /// le serveur ne savait pas si un ordre avait été reçu ou appliqué).
  /// Faux = accusé RECEIVED dès la réception, puis APPLIED ou FAILED avec
  /// le résultat réel et la révision de listes appliquée.
  static const String orderAckOffKey = 'zuno.ack.off';
  static bool orderAckOff = false;

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
    bool visOff = false;
    bool orderIdle = false;
    bool autoFull = false;
    bool firstBatchOff = false;
    bool hbOff = false;
    bool pillShow = false;
    bool autoInstOff = false;
    bool m3uLegacy = false;
    bool linkAsM3u = false;
    bool retryAlways = false;
    bool reinsertOff = false;
    bool pendingLegacy = false;
    bool resetOff = false;
    bool testPollLegacy = false;
    bool dropFirst = false;
    bool ackOff = false;
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
      visOff = prefs.getBool(panelVisibilityOffKey) ?? false;
      orderIdle = prefs.getBool(sourceOrderWaitsIdleKey) ?? false;
      autoFull = prefs.getBool(autoRefreshFullKey) ?? false;
      firstBatchOff = prefs.getBool(importFirstBatchOffKey) ?? false;
      hbOff = prefs.getBool(heartbeatAfterImportOffKey) ?? false;
      pillShow = prefs.getBool(updatingPillShownKey) ?? false;
      autoInstOff = prefs.getBool(autoInstallOffKey) ?? false;
      m3uLegacy = prefs.getBool(m3uTimeoutLegacyKey) ?? false;
      linkAsM3u = prefs.getBool(m3uLinkAsM3uKey) ?? false;
      retryAlways = prefs.getBool(sourceRetryAlwaysKey) ?? false;
      reinsertOff = prefs.getBool(importReinsertOffKey) ?? false;
      pendingLegacy = prefs.getBool(refreshPendingLegacyKey) ?? false;
      resetOff = prefs.getBool(remoteResetOffKey) ?? false;
      testPollLegacy = prefs.getBool(testUpdatePollLegacyKey) ?? false;
      dropFirst = prefs.getBool(sourceDropFirstLegacyKey) ?? false;
      ackOff = prefs.getBool(orderAckOffKey) ?? false;
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
      visOff = false;
      orderIdle = false;
      autoFull = false;
      firstBatchOff = false;
      hbOff = false;
      pillShow = false;
      autoInstOff = false;
      m3uLegacy = false;
      linkAsM3u = false;
      retryAlways = false;
      reinsertOff = false;
      pendingLegacy = false;
      resetOff = false;
      testPollLegacy = false;
      dropFirst = false;
      ackOff = false;
    }
    orderAckOff = ackOff;
    sourceDropFirstLegacy = dropFirst;
    remoteResetOff = resetOff;
    testUpdatePollLegacy = testPollLegacy;
    importReinsertOff = reinsertOff;
    refreshPendingLegacy = pendingLegacy;
    sourceRetryAlways = retryAlways;
    m3uLinkAsM3u = linkAsM3u;
    m3uTimeoutLegacy = m3uLegacy;
    updatingPillShown = pillShow;
    autoInstallOff = autoInstOff;
    heartbeatAfterImportOff = hbOff;
    autoRefreshFull = autoFull;
    importFirstBatchOff = firstBatchOff;
    sourceOrderWaitsIdle = orderIdle;
    panelVisibilityOff = visOff;
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
    panelVisibilityOff = false;
    sourceOrderWaitsIdle = false;
    autoRefreshFull = false;
    importFirstBatchOff = false;
    heartbeatAfterImportOff = false;
    updatingPillShown = false;
    autoInstallOff = false;
    m3uTimeoutLegacy = false;
    m3uLinkAsM3u = false;
    sourceRetryAlways = false;
    importReinsertOff = false;
    refreshPendingLegacy = false;
    remoteResetOff = false;
    testUpdatePollLegacy = false;
    sourceDropFirstLegacy = false;
    orderAckOff = false;
    NativeVideoController.legacyHoldFrame = false;
  }
}
