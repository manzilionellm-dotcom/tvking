// =========================================================
//  main_tv.dart — Point d'entrée DeFew TV (Android TV / Fire TV)
// =========================================================
//  App SŒUR de la version mobile : MÊME backend, MÊME panel (licence,
//  activation, sources poussées, « regarde », annonces, thème). Seule
//  l'UI change → 10-foot, navigation D-pad (cf. features/tv/).
//
//  Build : `flutter build apk --release --target=lib/main_tv.dart`
//  (un workflow CI dédié + manifest Leanback viendront ensuite).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app/app_platform.dart';
import 'core/app/boot_guard.dart';
import 'core/backend/backend_hosts.dart';
import 'core/app/device_memory.dart';
import 'core/app/guarded_main.dart';
import 'core/app/safe_mode_app.dart';
import 'core/crash/crash_reporting.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'features/tv/core/tv_developer_mode.dart';
import 'features/tv/core/tv_home_template.dart';
import 'features/tv/core/tv_memory_guard.dart';
import 'core/notifications/notification_service.dart';
import 'core/privacy/privacy_shield.dart';
import 'core/realtime/realtime_sync_service.dart';
import 'core/profiles/profiles_repository.dart';
import 'core/profiles/remote_profiles_repository.dart';
import 'core/theme/accent_controller.dart';
import 'core/tv/screen_awake.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/device/data/device_identity.dart';
import 'features/player/data/player_settings.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/playlists/data/source_content_watch.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/recordings/data/recording_scheduler.dart';
import 'features/security/data/parental_controls.dart';
import 'features/sports/data/sports_repository.dart';
import 'features/stats/data/watch_stats_service.dart';
import 'features/tv/data/place_repository.dart';
import 'features/vod/data/playback_position_repository.dart';
import 'features/vod/data/vod_download_service.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/data/display_settings.dart';
import 'features/tv/presentation/tv_app.dart';

// =========================================================
//  Point d'entrée TV — le filet d'erreurs global (« l'app ne se ferme
//  JAMAIS toute seule ») est désormais MUTUALISÉ avec le mobile dans
//  core/app/guarded_main.dart (`runGuarded`). Avant, ce filet était
//  dupliqué ici ; on le partage maintenant pour garantir un comportement
//  IDENTIQUE sur tous les flavors (mobile, Privé, TV).
// =========================================================
void main() => runGuarded(_bootstrap);

Future<void> _bootstrap() async {
  // Flavor explicite (un seul produit pour l'instant : The Few).
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // ImageCache : sur TV, TvMemoryGuard est la SOURCE UNIQUE des plafonds
  // (posé AVANT tout await → le tuner générique de guarded_main s'efface,
  // fin de la course « dernier arrivé gagne »).
  imageCacheOwnedByFlavor = true;

  // DISJONCTEUR anti-boucle de redémarrage : si la TV s'est relancée
  // plusieurs fois de suite (crash natif type mémoire en ré-important une
  // grosse source), on passe en MODE SANS ÉCHEC et on saute le ré-import
  // distant plus bas → la boucle est cassée. Voir core/app/boot_guard.dart.
  await BootGuard.instance.beginBoot();

  // Cette app est la version TÉLÉVISION → le heartbeat enverra
  // platform='tv' et le panel l'affichera comme (vs mobile).
  AppPlatform.isTv = true;

  // GARDE-MÉMOIRE TV (anti-fermeture) : AVANT la branche mode sans échec —
  // c'est justement après des crashs mémoire qu'il sert le plus. Non
  // bloquant : la détection « petite box » se termine en arrière-plan.
  unawaited(TvMemoryGuard.instance.install());

  // ====================================================================
  //  MODE SANS ÉCHEC (disjoncteur) — boucle de crash détectée par BootGuard.
  //  On n'initialise RIEN de risqué (pas de mpv, pas de repos lourds, AUCUN
  //  import distant) : on ouvre un écran de RÉCUPÉRATION ciblé selon l'endroit
  //  du dernier crash (rendu vs mémoire/import), puis on s'arrête là. C'est ce
  //  qui CASSE la boucle « ouvre/ferme » au lieu de refaire l'action qui tue.
  // ====================================================================
  if (BootGuard.instance.isInSafeMode) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Langue chargée pour que l'écran de récup s'affiche dans la bonne langue.
    await LocaleRepository.instance.initialize();
    runApp(SafeModeApp(failedPhase: BootGuard.instance.lastFailedPhase));
    return; // on ne va PAS plus loin (rien de risqué).
  }
  // Boot normal : on note le jalon « moteur prêt » (avant tout import).
  await BootGuard.instance.markPhase(BootPhase.flutterUp);

  // ANTI-OOM TV (confirmé par logcat: lowmemorykiller / signal 9) : on N'INITIE
  // PLUS le moteur mpv (media_kit) sur la TV. La TV joue EXCLUSIVEMENT via
  // ExoPlayer (packages/native_video_player) — cf. tv_player_screen.dart. mpv
  // n'y était JAMAIS utilisé : l'initialiser ne faisait que charger libmpv +
  // ses codecs en mémoire pour rien, aggravant la pression mémoire au démarrage
  // sur des box à RAM limitée (SHIELD incluse). Aucune fonctionnalité TV perdue.

  // La TV est TOUJOURS en paysage : on verrouille (pas de portrait).
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  //  L'ÉCRAN NE DOIT JAMAIS S'ENDORMIR (signalé le 28/08 : veille au bout
  //  de 15 min). L'app TV ne posait AUCUN verrou d'écran — le seul du
  //  projet vit dans le lecteur MOBILE, un chemin que la TV n'emprunte
  //  jamais. La box appliquait donc son délai d'inactivité système, et
  //  regarder la télévision c'est justement ne pas toucher à la
  //  télécommande pendant plus de 15 minutes.
  //
  //  Posé ICI, avant le premier rendu, et pour TOUTE l'application : le
  //  client lit aussi le guide et les synopsis, et un écran qui
  //  s'éteint pendant qu'on lit se vit comme une panne de l'app.
  //  Le verrou suit le cycle de vie (relâché en arrière-plan) — voir
  //  core/tv/screen_awake.dart.
  await ScreenAwake.instance.install();

  // Langue de l'app : on charge le choix mémorisé (ou « Système » =>
  // l'app suit la langue de la TV). BLOQUANT et rapide : garantit que le
  // 1er rendu est déjà dans la bonne langue (pas de flash en français).
  await LocaleRepository.instance.initialize();

  // Thème d'accent (couleur choisie OU mode immersif « une couleur par
  // jour ») : BLOQUANT et rapide, pour que le 1er rendu TV soit déjà à la
  // bonne couleur (pas de flash). Partagé avec le mobile via AccentController.
  await AccentController.instance.initialize();

  // Mode Développeur (caché) AVANT le template : hors de ce mode, l'app
  // force le Modèle D — le drapeau doit donc être connu au 1er rendu.
  await TvDeveloperMode.instance.initialize();

  // Template d'accueil choisi (Classique / Grandes tuiles) : BLOQUANT et
  // rapide, pour que le 1er rendu affiche la bonne disposition sans flash.
  await TvHomeTemplateRepository.instance.initialize();

  // --- Briques PARTAGÉES avec le mobile (non bloquant) ---
  // 0) FAILOVER backend : si le domaine maison était KO au dernier
  //    lancement, on repart directement sur l'adresse de secours
  //    mémorisée (retour auto au domaine maison au 1er heartbeat OK).
  await BackendHosts.loadPreferred();
  // 1) Identité stable (MAC) → le panel reconnaît l'appareil TV.
  unawaited(DeviceIdentity.instance.preload());
  // 2) Licence/abonnement : heartbeat + statut depuis le MÊME worker.
  //    ROBUSTESSE (box allumée en continu) : avant, UNE seule tentative au
  //    boot — si le serveur avait un creux à cet instant, la box restait
  //    « inconnue » des semaines et la tolérance hors-ligne s'égrenait en
  //    silence. Désormais : RETENTATIVES au boot (2/10/30 min tant que le
  //    serveur n'a pas répondu) + re-synchro PÉRIODIQUE (6 h) qui fait
  //    glisser la fenêtre de tolérance (kOfflineGraceDays) et propage les
  //    actions du panel (activation, gel…) sans redémarrer l'app.
  unawaited(SubscriptionState.instance.initialize().then((_) async {
    await SubscriptionState.instance.syncWithBackend();
    for (final int minutes in <int>[2, 10, 30]) {
      if (SubscriptionState.instance.remote.exists) break;
      await Future<void>.delayed(Duration(minutes: minutes));
      if (SubscriptionState.instance.remote.exists) break;
      await SubscriptionState.instance.syncWithBackend();
    }
  }));
  Timer.periodic(const Duration(hours: 6), (_) {
    SubscriptionState.instance.syncWithBackend();
  });

  // 2b) SOURCES POUSSÉES PAR LE PANEL : re-synchro PÉRIODIQUE courte (5 min),
  //     tant que l'app tourne. AVANT ce correctif, `RemoteSourceRepository.
  //     sync()` n'était appelé QU'UNE FOIS au boot (plus bas) → une source
  //     ajoutée/poussée par le revendeur APRÈS l'ouverture de l'app restait
  //     invisible tant que le client ne redémarrait pas — pas « fluide et
  //     instantané ». Léger : un seul GET JSON ; n'ajoute que ce qui manque
  //     (dédup existante), ne touche jamais aux sources déjà chargées.
  Timer.periodic(const Duration(minutes: 5), (_) {
    if (!BootGuard.instance.safeMode) RemoteSourceRepository.sync();
  });

  // 2b-bis) CONTENU du panel (bug terrain « la Belgique est toujours là ») :
  //     le sync ci-dessus n'AJOUTE que les sources manquantes — il ne voit
  //     JAMAIS qu'un bouquet a été retiré/ajouté DANS une source existante.
  //     SourceContentWatch sonde les catégories du panel toutes les 60 s
  //     (une requête JSON minuscule) et, si elles ont changé, rejoue le
  //     MÊME refresh que le bouton manuel → la box se met à jour toute
  //     seule, sans aucune action du client.
  if (!BootGuard.instance.safeMode) SourceContentWatch.instance.start();

  // 2c) GUIDE TV (EPG) : re-synchro PÉRIODIQUE (12 h) + une passe différée au
  //     boot (10 min, le temps que l'import de chaînes soit passé). AVANT ce
  //     correctif, l'EPG n'était téléchargé qu'à l'AJOUT de la source ; comme
  //     le guide ne conserve que ~48 h de programmes (anti-OOM), une box
  //     allumée en continu se retrouvait avec un guide VIDE au bout de ~2
  //     jours. Léger : IDs de chaînes seulement + import XMLTV en flux ;
  //     silencieux et optionnel (aucun impact si la source n'a pas d'EPG).
  Timer(const Duration(minutes: 10), () {
    if (!BootGuard.instance.safeMode) {
      unawaited(PlaylistRepository.instance.resyncEpgAll());
    }
  });
  Timer.periodic(const Duration(hours: 12), (_) {
    if (!BootGuard.instance.safeMode) {
      unawaited(PlaylistRepository.instance.resyncEpgAll());
    }
  });

  // 2d) TEMPS RÉEL (WebSocket) : les actions du panel (activation, gel,
  //     source poussée, message…) arrivent en < 1 s quand la box est en
  //     ligne — les polls ci-dessus RESTENT le filet de sécurité.
  //     Fire-and-forget : le service ne throw jamais, se reconnecte tout
  //     seul (backoff) et ne retarde JAMAIS le démarrage.
  unawaited(RealtimeSyncService.instance.start(platform: 'tv'));

  // 3) Thème distant piloté par le panel (couleur/nom).
  unawaited(RemoteThemeRepository.fetchAndApply());

  // 4) Chaînes : on charge la base locale AVANT le 1er rendu, puis on
  //    synchronise la source poussée par le panel EN ARRIÈRE-PLAN.
  //
  //    POURQUOI bloquant ici : au redémarrage, les chaînes sont DÉJÀ en cache
  //    (SQLite). Si on attend leur chargement avant `runApp`, l'app ouvre
  //    DIRECTEMENT sur les chaînes — fini l'écran « Recherche de tes chaînes… »
  //    qui s'affichait à chaque démarrage le temps que le cache se charge.
  //    Timeout de sécurité : si la base est lente, on n'empêche JAMAIS l'app
  //    de démarrer (au pire, le cache arrivera via le stream juste après).
  await PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});
  //    La source distante se (re)synchronise plus bas, APRÈS runApp, et de façon
  //    JALONNÉE (importStart → importDone → markBootSucceeded) : c'est l'étape la
  //    plus gourmande (fetch + parse de toute la source), suspect n°1 du crash
  //    mémoire. En mode sans échec on n'arrive jamais ici (return plus haut).

  // PLAFOND CHAÎNES ADAPTÉ À LA RAM : on lit la classe mémoire AVANT l'import
  // pour que le plafond de chaînes en RAM soit exact (petite box ⇒ plafond bas).
  await DeviceMemory.ensureLoaded();

  // 5) Enregistrements : on initialise la base et on finalise les
  //    enregistrements « fantômes » (l'app a pu être tuée par l'OS en plein
  //    enregistrement). recoverOrphans est idempotent (no-op s'il n'y a rien).
  //    Puis le PLANIFICATEUR (enregistrements programmés depuis le guide) :
  //    il relit ce que le natif a capté pendant que la box dormait, crée les
  //    fiches manquantes et tient son tick de 30 s. Après recoverOrphans,
  //    sinon une capture natif encore en cours serait finalisée à tort.
  unawaited(
    RecordingRepository.instance
        .initialize()
        .then((_) => RecordingRepository.instance.recoverOrphans())
        .then((_) => RecordingScheduler.instance.start()),
  );

  // 6) Favoris : on précharge l'ensemble des chaînes favorites pour que le
  // cœur du lecteur affiche le bon état dès la 1re ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  // 7) Notifications (alarmes « ton équipe joue bientôt ») : init du plugin +
  //    fuseaux horaires + canal Android. Idempotent, best-effort.
  unawaited(NotificationService.instance.init());

  // 8) Contrôle parental : on charge l'état du Mode Enfants pour que le 1er
  //    rendu du Direct masque déjà l'Adulte si le parent l'a activé.
  unawaited(ParentalControls.instance.load());

  // 8z) TÉLÉCHARGEMENTS HORS-LIGNE : recharge la liste des films téléchargés
  //     (et l'état des reprises). Lecture SharedPreferences, non bloquant.
  unawaited(VodDownloadService.instance.load());

  // 8z-bis) REPRISE DE LECTURE (« Reprendre à 42:15 ») : recharge les
  //     positions VOD sauvegardées pour que la rangée « Continuer à
  //     regarder » et les barres de progression soient chaudes dès le 1er
  //     rendu. Lecture SharedPreferences, non bloquant.
  unawaited(PlaybackPositionRepository.instance.load());

  // 8a) STATISTIQUES PERSONNELLES : échantillonneur 1 min qui lit NowPlaying
  //     (déjà alimenté par le lecteur pour le panel). Local à la box, par
  //     profil, zéro réseau, zéro contact lecteur. Cf. watch_stats_service.
  unawaited(WatchStatsService.instance.start());

  // 8b) SPORT : charge les équipes favorites dès le boot → les matchs de
  //     « ton équipe » sont récupérés et les ALARMES « joue bientôt »
  //     programmées MÊME si le client n'ouvre jamais l'onglet Sport, et le
  //     bandeau « Grand Match » de l'accueil est chaud dès le 1er rendu.
  //     Léger : aucune requête si aucune équipe favorite.
  unawaited(SportsRepository.instance.initialize());

  // Réglages d'affichage (overscan / grand texte). Best-effort, non bloquant.
  // Défauts = comportement inchangé, donc aucun risque au 1er rendu.
  unawaited(DisplaySettings.instance.load());

  // Mode Bouclier (vie privée) : réglages + état VPN. Non bloquant ; sans
  // réglage mémorisé, le bouclier est éteint et n'a aucun effet.
  unawaited(PrivacyShield.instance.load());

  // Signature de lecteur (User-Agent) persistée : si le diagnostic multi-UA
  // (cf. tv_player_screen.dart _declareChannelBlocked) a déjà trouvé la
  // signature qui débloque le fournisseur du client, elle doit survivre à un
  // redémarrage de l'app — sans ce load(), PlayerSettings ne lirait jamais
  // la valeur sauvegardée et reviendrait au défaut VLC à chaque lancement.
  unawaited(PlayerSettings.instance.load());

  // Ville météo choisie par l'utilisateur (pas de GPS sur TV). Si une ville a
  // été mémorisée, la météo de l'accueil devient EXACTE ; sinon détection auto
  // par IP (comportement inchangé). Lecture SharedPreferences, non bloquant.
  unawaited(PlaceRepository.instance.initialize());

  // Profils famille : chargés AVANT le 1er rendu (lecture SharedPreferences
  // quasi instantanée). BLOQUANT car TvGate décide du PREMIER écran avec eux :
  // « Qui regarde ? » doit s'afficher AVANT l'accueil (comme Netflix), jamais
  // remplacer un accueil déjà affiché quand le chargement finit en retard.
  // Timeout de sécurité : ne bloque jamais le démarrage si prefs est lent.
  await ProfilesRepository.instance
      .load()
      .timeout(const Duration(seconds: 2), onTimeout: () {});

  // Profils PILOTÉS PAR LE PANEL : le propriétaire colle UNE source M3U et
  // le serveur génère les cinq profils de la famille (papa, maman, trois
  // enfants), chacun avec son PIN et ses règles. On les récupère ici.
  //
  // NON BLOQUANT, volontairement : le `load()` juste au-dessus a déjà mis
  // en cache les profils de la dernière synchro. Attendre le réseau ferait
  // patienter la box devant un écran vide pour, dans 99 % des cas, la même
  // liste. Si le serveur répond après le 1er rendu, `applyRemote` notifie
  // et l'écran « Qui regarde ? » se met à jour tout seul.
  unawaited(RemoteProfilesRepository.instance.syncSelf());
  // Même cadence que la source poussée (5 min) : c'est le FILET quand le
  // temps réel ne passe pas (box derrière un réseau qui coupe le
  // WebSocket). Désactiver un profil à distance doit finir par prendre
  // effet même sans socket.
  Timer.periodic(const Duration(minutes: 5), (_) {
    if (!BootGuard.instance.safeMode) {
      unawaited(RemoteProfilesRepository.instance.syncSelf());
    }
  });

  // 9) Historique multi-box : on initialise l'historique local PUIS on le
  //    restaure depuis le serveur si la box est neuve (l'historique « suit »
  //    le client d'une box à l'autre). Best-effort, n'écrase jamais le local.
  unawaited(
    RecentlyWatchedRepository.instance.initialize().then((_) {
      if (!BootGuard.instance.safeMode) RemoteSourceRepository.syncHistory();
    }),
  );

  CrashReporting.instance.recordMemoryBreadcrumb('boot.beforeRunApp');
  runApp(const TvApp());

  // Jalon « 1er frame rendu » : l'UI s'est affichée au moins une fois.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    BootGuard.instance.markPhase(BootPhase.firstFrame);
    CrashReporting.instance.recordMemoryBreadcrumb('boot.firstFrame');
  });

  // ====================================================================
  //  IMPORT DISTANT = étape risquée → JALONNÉE. À sa FIN (succès ou rien à
  //  importer), on déclare le boot RÉUSSI : c'est le SEUL reset du compteur
  //  anti-boucle (plus de reset par timer). Si un crash natif survient PENDANT
  //  l'import (même à 60 s), on n'atteint jamais markBootSucceeded → le
  //  compteur reste incrémenté → au 3e essai, BootGuard ouvre le mode sans
  //  échec. C'est exactement ce que l'ancien reset-par-timer empêchait.
  //
  //  RÉCUPÉRATION : si l'utilisateur a choisi « démarrer sans réimporter » dans
  //  l'écran mode sans échec, on SAUTE l'auto-import ce boot-ci (one-shot).
  // ====================================================================
  final bool skipAutoImport = await BootGuard.instance.consumeSkipAutoImport();
  if (skipAutoImport) {
    debugPrint('[main_tv] auto-import SAUTÉ (choix de récupération). '
        'L\'app ouvre sur le cache ; sync manuelle possible.');
    await BootGuard.instance.markBootSucceeded();
  } else {
    await BootGuard.instance.markPhase(BootPhase.importStart);
    CrashReporting.instance.recordMemoryBreadcrumb('import.start');
    // RemoteSourceRepository.sync ne throw jamais (renvoie un résultat) ; on
    // marque donc le succès du boot dès qu'il a terminé, quel que soit le
    // résultat (chargé / rien d'assigné / réseau KO) — l'app, elle, a démarré
    // sans crasher, c'est ça « un boot réussi ».
    unawaited(RemoteSourceRepository.sync().then((_) async {
      CrashReporting.instance.recordMemoryBreadcrumb('import.done');
      await BootGuard.instance.markPhase(BootPhase.importDone);
      await BootGuard.instance.markBootSucceeded();
    }));
  }
}
