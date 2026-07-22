// =========================================================
//  notification_service.dart — Rappels de programmes (EPG)
// =========================================================
//  Levier de rétention n°1 : ramener l'utilisateur au bon moment
//  (« ton émission commence dans 5 min »).
//
//  Choix techniques :
//    - flutter_local_notifications : 100 % local, pas de serveur, pas
//      de compte. Suffit pour les rappels posés depuis le guide EPG.
//    - Mode INEXACT (AndroidScheduleMode.inexactAllowWhileIdle) : on
//      évite la permission « alarmes exactes » (SCHEDULE_EXACT_ALARM)
//      qui complique l'installation. Un rappel à ±1 min près convient
//      parfaitement pour « 5 min avant le début ».
//    - On programme à l'instant ABSOLU du programme moins le délai. Le
//      `startTime` d'un EpgProgram est déjà un timestamp epoch (UTC), donc
//      on planifie avec une TZDateTime en UTC : pas besoin de détecter
//      le fuseau de l'appareil (le moment absolu est le même partout).
//
//  Tout est best-effort et encapsulé dans des try/catch : si les
//  notifications échouent (permission refusée, OS exotique…), l'app
//  continue normalement.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/subscription/data/subscription_backend.dart';
import '../../features/subscription/data/subscription_state.dart';
import '../i18n/l10n_now.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  // Canal Android dédié aux rappels (obligatoire depuis Android 8).
  // Les LIBELLÉS (nom + description, visibles dans les réglages Android)
  // sont lus via `l10nNow` À CHAQUE création de canal / émission : ils
  // suivent donc la langue active au moment de l'appel.
  static const String _channelId = 'epg_reminders';
  static String get _channelName => l10nNow.notifChannelRemindersName;
  static String get _channelDesc => l10nNow.notifChannelRemindersDesc;

  // Canal "général" : annonces de l'admin + dispo des mises à jour.
  static const String _generalChannelId = 'general_news';
  static String get _generalChannelName => l10nNow.notifChannelGeneralName;
  static String get _generalChannelDesc => l10nNow.notifChannelGeneralDesc;

  // -------------------------------------------------------------------
  //  Préférences utilisateur (3 interrupteurs côté Réglages)
  // -------------------------------------------------------------------
  //  Par défaut TOUT est activé (opt-out) : la valeur de rétention est
  //  maximale et l'utilisateur peut couper ce qu'il ne veut pas.
  static const String prefReminders = 'notif.reminders.enabled';
  static const String prefAnnouncements = 'notif.announcements.enabled';
  static const String prefAppUpdates = 'notif.appupdates.enabled';

  /// Lit un interrupteur (défaut = activé).
  Future<bool> isEnabled(String key, {bool def = true}) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getBool(key) ?? def;
    } catch (_) {
      return def;
    }
  }

  /// Écrit un interrupteur. Si on ACTIVE, on s'assure que le plugin est
  /// prêt et on (re)demande la permission système — sinon l'utilisateur
  /// activerait un réglage qui ne notifie jamais.
  Future<void> setEnabled(String key, bool value) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {}
    if (value) {
      await init();
      await requestPermission();
    }
  }

  /// Initialise le plugin + les fuseaux horaires. Idempotent.
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();

      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings settings =
          InitializationSettings(android: androidInit);
      await _plugin.initialize(settings);

      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      // Canal "général" volontairement DOUX : importance "default" (pas de
      // pop-up plein écran intrusif), pas de vibration. L'annonce arrive
      // comme une info gentille dans le volet, pas comme une alarme.
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _generalChannelId,
          _generalChannelName,
          description: _generalChannelDesc,
          importance: Importance.defaultImportance,
          enableVibration: false,
        ),
      );

      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] init: $e');
    }
  }

  /// Demande la permission de notifier (Android 13+). Renvoie `true`
  /// si accordée (ou si la version d'Android n'exige pas de demande).
  Future<bool> requestPermission() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final bool? granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// ID stable d'un rappel pour un (channel, début) donné → permet de
  /// l'annuler et d'éviter les doublons si on re-tape le même programme.
  int _idFor(String channelId, int startMs) =>
      (channelId.hashCode ^ startMs) & 0x7fffffff;

  /// Programme un rappel `leadMinutes` avant le début du programme.
  /// Renvoie `false` si le créneau est déjà trop proche/passé.
  Future<bool> scheduleProgramReminder({
    required String channelId,
    required String channelName,
    required String title,
    required int startMs,
    int leadMinutes = 5,
  }) async {
    await init();
    if (!_ready) return false;
    // Interrupteur Réglages : si l'utilisateur a coupé les rappels, on
    // ne programme rien (et tv_guide affichera son message d'échec).
    if (!await isEnabled(prefReminders)) return false;
    await requestPermission();

    final int fireMs = startMs - leadMinutes * 60 * 1000;
    // Trop tard pour un rappel utile.
    if (fireMs <= DateTime.now().millisecondsSinceEpoch + 1000) return false;

    final tz.TZDateTime when =
        tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, fireMs);

    final DateTime startLocal = DateTime.fromMillisecondsSinceEpoch(startMs);
    final String hhmm =
        '${startLocal.hour.toString().padLeft(2, '0')}:'
        '${startLocal.minute.toString().padLeft(2, '0')}';

    try {
      await _plugin.zonedSchedule(
        _idFor(channelId, startMs),
        title,
        l10nNow.notifBodyStartsAt(hhmm, channelName),
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Requis par la version résolue du plugin (iOS only ; Android
        // l'ignore). On planifie à un instant absolu.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] schedule: $e');
      return false;
    }
  }

  /// Annule un rappel précédemment posé pour ce programme.
  Future<void> cancelProgramReminder(String channelId, int startMs) async {
    await _safeCancel(_idFor(channelId, startMs));
  }

  /// Annulation BLINDÉE d'une notification. `cancel()` déclenche en interne
  /// `loadScheduledNotifications` (relecture Gson des notifs programmées) : sur
  /// une build minifiée sans la bonne règle R8, OU quand l'ancien fichier de
  /// notifications (sérialisé par une version antérieure) n'est plus relisible
  /// après mise à jour, le plugin lève un PlatformException « Missing type
  /// parameter ». Non rattrapé, il remontait jusqu'au filet global (crash
  /// « majeur » de la boîte noire, déclenché typiquement à l'envoi/réception
  /// d'un test → reprogrammation des rappels). On l'avale ici : au pire un
  /// rappel n'est pas annulé, jamais un crash.
  Future<void> _safeCancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] cancel($id): $e');
    }
  }

  // ===================================================================
  //  Notification IMMÉDIATE (canal général) — annonces & mises à jour
  // ===================================================================

  /// Affiche tout de suite une notification dans le canal "général".
  /// Best-effort : silencieux si le plugin/permission n'est pas dispo.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    if (!_ready) return;
    await requestPermission();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _generalChannelId,
            _generalChannelName,
            channelDescription: _generalChannelDesc,
            // Doux : pas de heads-up agressif, pas de vibration. Le texte
            // long s'affiche proprement quand on déroule la notif.
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            enableVibration: false,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] show: $e');
    }
  }

  /// Notifie qu'une mise à jour de l'app est dispo (en plus de la
  /// fenêtre affichée au démarrage). Gardé par l'interrupteur Réglages.
  /// Anti-spam : on ne re-notifie pas pour une build déjà signalée
  /// (clé `notif.update.lastTs`).
  Future<void> notifyAppUpdate({
    required int latestTs,
    String? versionLabel,
  }) async {
    try {
      if (latestTs <= 0) return;
      if (!await isEnabled(prefAppUpdates)) return;
      final SharedPreferences p = await SharedPreferences.getInstance();
      final int last = p.getInt('notif.update.lastTs') ?? 0;
      if (latestTs <= last) return;
      await showNow(
        id: 990001,
        title: l10nNow.updateAvailableTitle,
        body: versionLabel == null || versionLabel.isEmpty
            ? l10nNow.notifBodyUpdateReady
            : l10nNow.notifBodyUpdateVersion(versionLabel),
      );
      await p.setInt('notif.update.lastTs', latestTs);
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] update: $e');
    }
  }

  /// Vérifie s'il y a une annonce de l'admin à montrer (au démarrage).
  /// Le backend renvoie `{ id, title, body, url }` ; on ne notifie que si
  /// l'`id` est plus récent que la dernière annonce déjà vue. Gardé par
  /// l'interrupteur Réglages. 100 % best-effort.
  Future<void> checkAnnouncement() async {
    try {
      if (!await isEnabled(prefAnnouncements)) return;
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/announcement'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;
      final int id = (decoded['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) return;
      final String title = decoded['title']?.toString() ?? '';
      final String body = decoded['body']?.toString() ?? '';
      if (title.isEmpty && body.isEmpty) return;

      final SharedPreferences p = await SharedPreferences.getInstance();
      final int lastSeen = p.getInt('notif.announce.lastSeen') ?? 0;
      if (id <= lastSeen) return;

      await showNow(
        id: 980000 + (id & 0xffff),
        title: title.isEmpty ? l10nNow.notifTitleNews : title,
        body: body,
      );
      await p.setInt('notif.announce.lastSeen', id);
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] announcement: $e');
    }
  }

  // ===================================================================
  //  RÉ-ENGAGEMENT — le SEUL canal qui ramène un utilisateur HORS de l'app
  // ===================================================================
  //  100 % local (aucun push serveur). Reprogrammé à CHAQUE ouverture :
  //  le fait d'ouvrir l'app « repousse » le rappel de dormance → un
  //  utilisateur assidu ne le voit jamais. Fréquence plafonnée, respect
  //  du même interrupteur que les rappels EPG, ton bienveillant (jamais
  //  culpabilisant). C'est la moitié « faire revenir » de la rétention,
  //  jusqu'ici absente.

  static const int _idDormant = 900001; // « on ne t'a pas vu »
  static const int _idTonight = 900002; // nudge quotidien du soir
  static const int _idTrialEnd = 900003; // « ton accès se termine bientôt »

  // Plus `const` : le nom/description du canal sont désormais LOCALISÉS
  // (getters l10nNow, non constants).
  NotificationDetails get _generalDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          _generalChannelId,
          _generalChannelName,
          channelDescription: _generalChannelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          enableVibration: false,
        ),
      );

  Future<void> _scheduleAt(
    int id,
    tz.TZDateTime when,
    String title,
    String body, {
    DateTimeComponents? repeat,
  }) async {
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _generalDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeat,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Notif] reengage: $e');
    }
  }

  /// À appeler à chaque arrivée sur l'accueil. Reprogramme les nudges de
  /// retour (dormance, soirée, fin d'accès). Respecte l'interrupteur
  /// « rappels » des Réglages. Best-effort / silencieux si permission KO.
  Future<void> scheduleReEngagement() async {
    await init();
    if (!_ready) return;
    if (!await isEnabled(prefReminders)) return;
    await requestPermission();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    // 1) « On ne t'a pas vu depuis 3 jours » — annulé/repoussé à chaque
    //    ouverture, donc invisible pour qui revient avant l'échéance.
    await _safeCancel(_idDormant);
    await _scheduleAt(
      _idDormant,
      now.add(const Duration(days: 3)),
      'Tes chaînes t\'attendent',
      'On ne t\'a pas vu depuis quelques jours — on reprend là où tu t\'étais arrêté ?',
    );

    // 2) Nudge quotidien léger à 20 h (« ce soir sur 7 MOTION »), répété.
    await _safeCancel(_idTonight);
    tz.TZDateTime tonight =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    if (tonight.isBefore(now)) tonight = tonight.add(const Duration(days: 1));
    await _scheduleAt(
      _idTonight,
      tonight,
      'Ce soir sur 7 MOTION',
      'Tes chaînes en direct t\'attendent.',
      repeat: DateTimeComponents.time,
    );

    // 3) « Ton accès se termine bientôt » — LE rappel de conversion qui
    //    manquait (avant, l'alerte n'était qu'une bannière in-app d'un
    //    écran que le mobile ne montre même pas → churn silencieux).
    //    Planifié la veille de l'expiration, à 19 h.
    await _safeCancel(_idTrialEnd);
    final int? days = SubscriptionState.instance.daysUntilExpiry;
    final SubscriptionStatus st = SubscriptionState.instance.status;
    final bool relevant = st == SubscriptionStatus.trialActive ||
        st == SubscriptionStatus.paid;
    if (relevant && days != null && days >= 1 && days <= 30) {
      final tz.TZDateTime day = now.add(Duration(days: days - 1));
      final tz.TZDateTime at =
          tz.TZDateTime(tz.local, day.year, day.month, day.day, 19);
      await _scheduleAt(
        _idTrialEnd,
        at,
        'Ton accès se termine bientôt',
        'Garde tes chaînes sans coupure — prolonge en un geste.',
      );
    }
  }
}
