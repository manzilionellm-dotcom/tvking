// =========================================================
//  playback_failure_log.dart — Journal DURABLE des échecs de lecture
// =========================================================
//  Quand le lecteur TV déclare un échec DÉFINITIF (reconnexions épuisées,
//  chaîne bloquée par le fournisseur, erreur fatale ExoPlayer), on grave ici
//  une entrée que la Boîte noire des Réglages saura relire des mois plus
//  tard : QUELLE chaîne, QUAND, avec QUEL code d'erreur stable, et le
//  verdict humain calculé au moment des faits.
//
//  VIE PRIVÉE : on ne stocke JAMAIS l'URL complète du flux (elle contient
//  les identifiants Xtream) — uniquement l'HÔTE (ex. "iptv.example.com"),
//  suffisant pour le diagnostic (même règle que probe.dns_failure du
//  StreamProbe).
//
//  CONTRAT DE SCHÉMA — CONÇU POUR DIX ANS SANS Y RETOUCHER :
//    • Chaque entrée porte `"v": 1` (version de schéma).
//    • AJOUTER des champs = OK (les vieux lecteurs les ignorent).
//    • RENOMMER ou SUPPRIMER un champ = INTERDIT (casserait les entrées
//      déjà gravées sur les box du parc).
//    • Lecture TOLÉRANTE : champ inconnu → ignoré ; champ manquant →
//      valeur par défaut ; entrée illisible (JSON cassé, mauvais type) →
//      SAUTÉE sans crash. La boîte noire ne plante JAMAIS l'avion.
//
//  STOCKAGE : SharedPreferences (liste JSON), comme les autres journaux
//  bornés de l'app (PlaybackPositionRepository, RecentVod…). Pourquoi PAS
//  le fichier JSONL de BlackBox ? Sa ROTATION (1 Mo, 2 générations) est
//  faite pour un flux d'événements dense : nos 50 échecs seraient noyés
//  puis PERDUS à la rotation. Ici : BORNÉ à 50 entrées (éviction des plus
//  anciennes, ~15 Ko max — négligeable même sur une box 1 Go), durable tant
//  que l'app est installée. Chaque écriture est AUSSI reflétée dans la
//  BlackBox (domain 'player', event 'playback_failure') pour apparaître
//  dans le journal de vol et son analyse par signatures.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/observability/black_box.dart';

/// Une entrée du journal des échecs de lecture. IMMUABLE, schéma v1.
@immutable
class PlaybackFailureEntry {
  const PlaybackFailureEntry({
    this.v = schemaVersion,
    required this.timestamp,
    required this.channelName,
    required this.streamHost,
    this.errorCodeName,
    this.errorCode,
    this.cause,
    this.uaTriedCount = 0,
    this.uaAdopted,
    this.verdict = '',
  });

  /// Version du schéma d'écriture (cf. contrat en tête de fichier).
  static const int schemaVersion = 1;

  /// Version de schéma LUE (une entrée future v2 reste affichable : les
  /// champs v1 sont garantis présents à vie par le contrat).
  final int v;

  /// Quand l'échec a été déclaré (heure locale de la box).
  final DateTime timestamp;

  /// Nom lisible de la chaîne (« beIN Sports 1 »).
  final String channelName;

  /// HÔTE du flux uniquement — jamais l'URL complète (identifiants !).
  final String streamHost;

  /// Constante Media3 STABLE (ex. "ERROR_CODE_IO_BAD_HTTP_STATUS").
  final String? errorCodeName;

  /// Équivalent numérique du code Media3 (ex. 2004).
  final int? errorCode;

  /// Message de la cause racine (contexte humain — jamais utilisé pour
  /// matcher, cf. failure_explainer.dart).
  final String? cause;

  /// Nombre de signatures de lecteur (User-Agent) testées par le
  /// diagnostic multi-UA (0 = pas de sonde tentée).
  final int uaTriedCount;

  /// Signature retenue si une a fonctionné (null = aucune).
  final String? uaAdopted;

  /// Verdict humain calculé AU MOMENT DES FAITS (failure_explainer) —
  /// gravé pour rester lisible même si la table évolue.
  final String verdict;

  /// Sérialisation v1. NE JAMAIS renommer/supprimer une clé (contrat).
  Map<String, Object?> toMap() => <String, Object?>{
        'v': v,
        'ts': timestamp.toIso8601String(),
        'channel': channelName,
        'host': streamHost,
        if (errorCodeName != null) 'codeName': errorCodeName,
        if (errorCode != null) 'code': errorCode,
        if (cause != null) 'cause': cause,
        'uaTried': uaTriedCount,
        if (uaAdopted != null) 'uaAdopted': uaAdopted,
        'verdict': verdict,
      };

  /// Lecture TOLÉRANTE : `null` si l'entrée est illisible (l'appelant la
  /// SAUTE) ; champ manquant/mauvais type → valeur par défaut ; champ
  /// inconnu (écrit par une version future) → ignoré. Aucune exception ne
  /// sort d'ici.
  static PlaybackFailureEntry? tryParse(Object? raw) {
    try {
      if (raw is! Map) return null;
      final Map<Object?, Object?> m = raw;
      String str(Object? o, [String fallback = '']) =>
          o is String ? o : fallback;
      int? asInt(Object? o) =>
          o is int ? o : (o is num ? o.toInt() : null);
      final DateTime ts =
          DateTime.tryParse(str(m['ts'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return PlaybackFailureEntry(
        v: asInt(m['v']) ?? schemaVersion,
        timestamp: ts,
        channelName: str(m['channel']),
        streamHost: str(m['host']),
        errorCodeName: m['codeName'] is String ? m['codeName']! as String : null,
        errorCode: asInt(m['code']),
        cause: m['cause'] is String ? m['cause']! as String : null,
        uaTriedCount: asInt(m['uaTried']) ?? 0,
        uaAdopted: m['uaAdopted'] is String ? m['uaAdopted']! as String : null,
        verdict: str(m['verdict']),
      );
    } on Object {
      return null; // entrée illisible → sautée, jamais de crash
    }
  }
}

/// Journal borné des échecs de lecture. Singleton, chargement paresseux
/// (`ensureLoaded`) : AUCUN branchement nécessaire dans main_tv — le premier
/// écran/lecteur qui s'en sert le réveille.
class PlaybackFailureLog extends ChangeNotifier {
  PlaybackFailureLog._();
  static final PlaybackFailureLog instance = PlaybackFailureLog._();

  /// Plafond d'entrées conservées (éviction des plus anciennes). 50 échecs
  /// ≈ 15 Ko de prefs : négligeable même sur une box 1 Go (anti-OOM).
  static const int kMaxEntries = 50;

  /// Clé prefs versionnée : si un jour le CONTENANT (pas le schéma d'entrée)
  /// devait changer, on lirait l'ancienne clé en migration douce.
  static const String _kPrefsKey = 'playback_failure_log.v1';

  List<PlaybackFailureEntry> _entries = <PlaybackFailureEntry>[];
  bool _loaded = false;

  /// Entrées du plus RÉCENT au plus ancien (ordre d'affichage).
  List<PlaybackFailureEntry> get entries =>
      _entries.reversed.toList(growable: false);

  /// Charge le journal depuis le disque (une fois). Best-effort : disque ou
  /// JSON KO → journal vide, l'app continue.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final List<PlaybackFailureEntry> loaded = <PlaybackFailureEntry>[];
      for (final Object? item in decoded) {
        final PlaybackFailureEntry? e = PlaybackFailureEntry.tryParse(item);
        if (e != null) loaded.add(e); // illisible → sautée (contrat)
      }
      // Borne aussi en LECTURE : si une vieille version a laissé plus de 50
      // entrées, on ne garde que les plus récentes (fin de liste).
      _entries = loaded.length <= kMaxEntries
          ? loaded
          : loaded.sublist(loaded.length - kMaxEntries);
    } on Object {
      _entries = <PlaybackFailureEntry>[]; // fail-open
    }
  }

  /// Grave un échec. JAMAIS bloquant pour l'appelant, JAMAIS d'exception :
  /// un journal qui plante le lecteur serait pire que le problème qu'il
  /// documente.
  Future<void> record(PlaybackFailureEntry entry) async {
    try {
      await ensureLoaded();
      _entries.add(entry);
      if (_entries.length > kMaxEntries) {
        _entries.removeRange(0, _entries.length - kMaxEntries);
      }
      // Reflet dans la boîte de vol (analyse par signatures + post-mortem).
      // No-op silencieux si la BlackBox n'est pas initialisée (tests).
      BlackBox.instance.record(
        domain: 'player',
        event: 'playback_failure',
        level: 'warn',
        ctx: entry.toMap(),
      );
      notifyListeners();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kPrefsKey,
        jsonEncode(_entries
            .map((PlaybackFailureEntry e) => e.toMap())
            .toList(growable: false)),
      );
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[PlaybackFailureLog] record ignoré: $e');
    }
  }

  /// Vide le journal (bouton éventuel / tests).
  Future<void> clear() async {
    try {
      _entries = <PlaybackFailureEntry>[];
      _loaded = true;
      notifyListeners();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefsKey);
    } on Object {
      // best effort
    }
  }

  /// Réarme le singleton entre deux tests (prefs mockées différentes).
  @visibleForTesting
  void resetForTest() {
    _entries = <PlaybackFailureEntry>[];
    _loaded = false;
  }
}
