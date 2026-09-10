// =========================================================
//  main_windows.dart — Point d'entrée The Few sur WINDOWS (PC)
// =========================================================
//  App SŒUR des versions mobile et TV : MÊME backend, MÊME panel (licence,
//  activation, sources poussées). On réutilise l'UI « 10-foot » de la TV
//  (features/tv/) car elle est pensée pleine page, navigable au CLAVIER
//  (flèches = D-pad, Entrée = OK, Échap = Retour) → parfaite pour un PC /
//  mini-PC branché à un écran ou une TV.
//
//  CE QUI CHANGE par rapport à la TV (Android) :
//    1) STOCKAGE : Windows n'a pas de SQLite système. On initialise le moteur
//       SQLite « FFI » (sqflite_common_ffi) AVANT toute ouverture de base, puis
//       on branche `databaseFactory` dessus → tout le code de base existant
//       (PlaylistDatabase…) fonctionne tel quel.
//    2) LECTURE VIDÉO : le lecteur natif Media3/ExoPlayer est Android-uniquement.
//       Sur PC, c'est media_kit (libmpv) qui lira les flux (étape 2 — câblage
//       du lecteur desktop, à tester sur une vraie machine Windows).
//    3) On N'APPELLE PAS les briques 100 % Android (BootGuard natif anti-boucle,
//       notifications/alarmes, enregistrement par relais) : elles s'appuient sur
//       des canaux natifs absents sur PC. Le filet d'erreurs global (runGuarded)
//       reste partagé → l'app ne se ferme jamais toute seule.
//
//  Build : `flutter build windows --release --target=lib/main_windows.dart`
//  (un workflow CI dédié compile et publie un .zip téléchargeable).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app/app_platform.dart';
import 'core/app/foreground_sync.dart';
import 'core/app/guarded_main.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'core/privacy/privacy_shield.dart';
import 'core/realtime/realtime_sync_service.dart';
import 'features/channels/domain/channel.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/recordings/data/recording_scheduler.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'core/profiles/remote_profiles_repository.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/player/data/player_settings.dart';
import 'features/security/data/parental_controls.dart';
import 'features/sports/data/live_scores_service.dart';
import 'features/sports/data/sports_repository.dart';
import 'features/stats/data/watch_stats_service.dart';
import 'features/tv/core/tv_home_template.dart';
import 'features/tv/data/display_settings.dart';
import 'features/tv/data/place_repository.dart';
import 'features/vod/data/playback_position_repository.dart';
import 'features/vod/data/vod_download_service.dart';
import 'features/tv/presentation/player/desktop_fullscreen.dart';
import 'features/tv/presentation/player/desktop_player_screen.dart';
import 'features/tv/presentation/tv_app.dart';
import 'features/tv/presentation/tv_player_screen.dart';

// Le filet d'erreurs global (« l'app ne se ferme JAMAIS toute seule ») est
// MUTUALISÉ avec le mobile et la TV via runGuarded.
void main() => runGuarded(_bootstrap);

Future<void> _bootstrap() async {
  // Un seul produit pour l'instant : The Few.
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // Le heartbeat enverra platform='windows' (le panel pourra distinguer PC
  // des box TV et des téléphones ). AppPlatform.isTv reste à false : l'UI
  // TV s'affiche quand même (on l'instancie explicitement via TvApp ci-dessous).
  AppPlatform.isWindows = true;

  // ====================================================================
  //  SQLite DESKTOP : on initialise le moteur FFI et on le pose comme fabrique
  //  GLOBALE de bases AVANT toute ouverture. Dès lors, `openDatabase(...)` du
  //  code existant (PlaylistDatabase) passe par le SQLite embarqué Windows.
  // ====================================================================
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Moteur de lecture desktop (libmpv) : initialisation, puis on INJECTE le
  // lecteur media_kit comme lecteur plein écran de l'app (le défaut natif
  // Android est ainsi remplacé sur PC, sans toucher au code partagé).
  MediaKit.ensureInitialized();
  registerTvPlayer((List<Channel> channels, int startIndex) =>
      DesktopPlayerScreen(channels: channels, startIndex: startIndex));

  // Le canal vers la FENÊTRE native, pour le plein écran du lecteur.
  //
  // Sans cet appel, le bouton et la touche F11 tomberaient dans le vide,
  // sans erreur ni message — la panne dont on conclut « le bouton ne
  // marche pas » alors que le bouton va très bien. Même famille de défaut
  // que les onze briques de l'audit ci-dessous : la fonction existe, c'est
  // son démarrage qui manque. Bloquant mais quasi instantané (un simple
  // enregistrement de canal, aucune E/S).
  await DesktopFullscreen.preparer();

  // Langue de l'app : choix mémorisé (ou « Système »). Bloquant et rapide pour
  // que le 1er rendu soit déjà dans la bonne langue.
  await LocaleRepository.instance.initialize();

  // ====================================================================
  //  PARITÉ AVEC LA BOX — les briques que le PC oubliait de démarrer
  // ====================================================================
  //  AUDIT DU 10/09/2026, après une série de « l'app Windows n'a pas… ».
  //  À chaque fois, la fonction EXISTAIT : c'est son démarrage qui
  //  manquait ici. Treize briques que `main_tv.dart` allume et que ce
  //  fichier ignorait. On les compare désormais explicitement.
  //
  //  BLOQUANT ET RAPIDE, comme sur la box : le modèle d'accueil doit être
  //  connu AVANT le premier rendu, sinon l'écran s'affiche dans une
  //  disposition puis saute dans une autre.
  await TvHomeTemplateRepository.instance.initialize();

  //  LE PLUS GRAVE DES TREIZE : le CONTRÔLE PARENTAL.
  //
  //  Sans ce `load()`, le mode Enfants reste sur sa valeur par défaut —
  //  DÉSACTIVÉ — quoi que le parent ait réglé. Il l'active, ferme l'app,
  //  la rouvre : la protection a disparu. Et l'app ne s'abonnait jamais
  //  aux profils, donc un profil marqué « enfant » (y compris re-marqué
  //  depuis le panel) ne filtrait plus rien.
  //
  //  Une protection qui s'oublie au redémarrage est pire qu'une
  //  protection absente : le parent, lui, croit qu'elle est là.
  unawaited(ParentalControls.instance.load());

  //  Réglages d'AFFICHAGE (marge d'écran + taille du texte) : `TvApp` les
  //  lit à chaque rendu. Jamais chargés ici, donc le PC ignorait purement
  //  et simplement ce que le client avait réglé.
  unawaited(DisplaySettings.instance.load());

  //  Réglages du LECTEUR (tampon, ratio, pistes préférées…).
  unawaited(PlayerSettings.instance.load());

  //  « Derniers vus » : la rangée d'accueil restait vide sur PC.
  unawaited(RecentlyWatchedRepository.instance.initialize());

  //  Statistiques de visionnage (temps d'écran, top chaînes — local).
  unawaited(WatchStatsService.instance.start());

  //  Sport : catalogue et scores en direct, comme sur la box.
  unawaited(SportsRepository.instance.initialize());
  LiveScoresService.instance.startSentinel();

  //  Ville (météo de l'accueil) et profils distants poussés par le panel.
  unawaited(PlaceRepository.instance.initialize());
  unawaited(RemoteProfilesRepository.instance.syncSelf());

  //  DEUX BRIQUES VOLONTAIREMENT LAISSÉES DE CÔTÉ, et ce n'est pas un
  //  oubli : `NotificationService` et `MatchAlertsService` reposent sur
  //  les notifications et les alarmes ANDROID, qui n'existent pas sur PC.
  //  Les brancher ici ferait au mieux rien, au pire échouer le démarrage.
  //  Les alertes de match sur PC demandent une autre implémentation.

  // --- Briques PARTAGÉES avec mobile/TV (non bloquantes) ---
  // 1) Identité stable (MAC) : sur PC, le canal natif Android est absent →
  //    DeviceIdentity bascule TOUT SEUL sur une MAC locale stable (try/catch
  //    interne). Le panel reconnaît donc aussi le poste Windows.
  unawaited(DeviceIdentity.instance.preload());
  // 2) Licence/abonnement : heartbeat + statut depuis le MÊME worker (HTTP,
  //    100 % multiplateforme).
  unawaited(SubscriptionState.instance.initialize().then((_) {
    SubscriptionState.instance.syncWithBackend();
  }));
  // 3) Thème distant piloté par le panel (couleur/nom).
  unawaited(RemoteThemeRepository.fetchAndApply());

  // 4) Chaînes : on charge la base locale AVANT le 1er rendu (cache SQLite via
  //    FFI), avec un garde-fou de 6 s pour ne jamais bloquer le démarrage.
  await PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});

  // 5) Favoris : préchargés pour que le cœur reflète le bon état dès l'ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  // 5-bis) TÉLÉCHARGEMENTS HORS-LIGNE (Cinéma & Séries).
  //
  //  SIGNALÉ PAR LE PROPRIÉTAIRE (10/09/2026) : « côté cinéma et séries,
  //  l'option téléchargement / regarder hors ligne doit être
  //  fonctionnelle ».
  //
  //  IL AVAIT RAISON, ET CE N'ÉTAIT NI LE SERVICE NI LES ÉCRANS. Les deux
  //  existent et marchent : le service de téléchargement, la fiche film,
  //  la fiche série, l'écran « Mes téléchargements ». Ce qui manquait,
  //  c'est CETTE LIGNE. Le téléphone et la box appellent `load()` au
  //  démarrage ; le PC ne l'appelait pas.
  //
  //  Conséquence : la liste des films déjà téléchargés restait vide au
  //  lancement, et les reprises de téléchargement interrompus ne
  //  repartaient jamais. L'écran s'affichait, simplement il ne connaissait
  //  rien. Un client PC pouvait télécharger un film, fermer l'app, et ne
  //  plus jamais le retrouver.
  //
  //  C'est le même défaut que la langue, la synchro au réveil et la
  //  proposition de mise à jour : une brique partagée que les entrées
  //  mobile et TV branchent, et que l'entrée Windows a oubliée.
  unawaited(VodDownloadService.instance.load());

  // 5-ter) REPRISE DE LECTURE (« Reprendre à 42:15 ») : mêmes positions
  //  sauvegardées que sur mobile et TV. Sans ça, un film commencé sur le
  //  PC repart toujours du début, alors que la donnée existe.
  unawaited(PlaybackPositionRepository.instance.load());

  // 6) Enregistrements programmés : sur PC il n'y a pas d'alarme native,
  //    c'est le tick Dart du planificateur qui capte à l'heure (tant que
  //    l'app tourne). recoverOrphans avant, comme sur mobile/TV.
  unawaited(
    RecordingRepository.instance
        .initialize()
        .then((_) => RecordingRepository.instance.recoverOrphans())
        .then((_) => RecordingScheduler.instance.start()),
  );

  runApp(const TvApp());

  // IMPORT DISTANT (source poussée par le panel) EN ARRIÈRE-PLAN, après le 1er
  // rendu : c'est l'étape la plus gourmande (fetch + parse). Best-effort, ne
  // throw jamais.
  unawaited(RemoteSourceRepository.sync());

  // Re-synchro PÉRIODIQUE (60 s) tant que l'app tourne : une source ajoutée/
  // poussée par le revendeur APRÈS l'ouverture de l'app reste sinon invisible
  // jusqu'au redémarrage. Léger (un GET JSON), n'ajoute que ce qui manque.
  //
  // 60 s et non 5 min depuis le 09/09/2026 : les ORDRES du panel — dont
  // « retirer cette liste » — voyagent dans cette réponse, donc ce minuteur
  // EST le délai que voit le client. Même cadence que la box et le mobile.
  Timer.periodic(const Duration(minutes: 1), (_) {
    RemoteSourceRepository.sync();
  });

  // Et au retour au premier plan : sur PC on réduit la fenêtre pendant des
  // heures, exactement comme une box s'endort. Même garde-fou anti-rafale.
  ForegroundSync.instance.start();

  // TEMPS RÉEL (WebSocket) : les actions du panel arrivent en < 1 s quand
  // le poste est en ligne — les polls ci-dessus restent le filet de
  // sécurité. `dart:io` est disponible sur Windows ; le try/catch est une
  // ceinture supplémentaire (le service, lui, ne throw jamais).
  try {
    // Mode Bouclier : réglages (HTTPS préféré, télémétrie minimale). Sur PC
    // la détection VPN n'existe pas : le coupe-circuit y est sans effet.
    unawaited(PrivacyShield.instance.load());
    unawaited(RealtimeSyncService.instance.start(platform: 'windows'));
  } catch (e) {
    debugPrint('[main_windows] realtime start: $e');
  }
}
