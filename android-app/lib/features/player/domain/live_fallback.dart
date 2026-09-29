// =========================================================
//  live_fallback.dart — Secours du DIRECT (chaîne qui ne démarre pas)
// =========================================================
//  Cas réel chez les revendeurs : le serveur du fournisseur continue de
//  servir le Cinéma (films / séries) mais le DIRECT ne répond plus, ou plus
//  dans un format donné. Au lieu de laisser le client devant la roue de
//  chargement, le lecteur essaie, dans l'ordre :
//
//   1. l'adresse d'origine de la chaîne ;
//   2. les AUTRES FORMATS du même serveur Xtream, qui passent souvent par
//      un autre chemin côté serveur :
//        …/live/user/pass/123.ts    (MPEG-TS, le plus courant)
//        …/live/user/pass/123.m3u8  (HLS)
//        …/user/pass/123            (ancien chemin Xtream, sans « live »)
//   3. la MÊME CHAÎNE dans une AUTRE SOURCE du client (Zuno fusionne les
//      sources actives) ou dans une autre qualité (« TF1 HD » ↔ « TF1 FHD »).
//
//  Ce n'est PAS un contournement : on n'utilise que des adresses auxquelles
//  le client a déjà droit (ses propres sources). Si le fournisseur coupe
//  réellement l'accès au direct, aucun format ne répond et l'écran d'erreur
//  habituel s'affiche.
//
//  Modèle PUR (aucun widget) → testé dans test/features/player/.
// =========================================================
import '../../channels/domain/channel.dart';

abstract final class LiveFallback {
  /// Nombre maximal de copies de la chaîne prises dans d'autres sources.
  static const int maxBackups = 4;

  /// `http(s)://hôte[:port]` + (`/live`)? + `/user/pass/123` + (`.ts|.m3u8`)?
  /// Le numéro de flux doit être NUMÉRIQUE et il faut EXACTEMENT 3 segments
  /// après l'hôte (ou 4 avec « live ») : les films (`/movie/…`) et séries
  /// (`/series/…`) ne correspondent jamais.
  static final RegExp _rxXtream = RegExp(
    r'^(https?://[^/?#]+)(?:/live)?/([^/?#]+)/([^/?#]+)/(\d+)(?:\.(ts|m3u8))?$',
    caseSensitive: false,
  );

  /// Formats essayés, dans l'ordre par défaut.
  static const List<_Variant> _variants = <_Variant>[
    _Variant.ts,
    _Variant.hls,
    _Variant.legacy,
  ];

  /// Mémoire de SESSION (remise à zéro au redémarrage de l'app) : pour
  /// chaque serveur, le format qui a marché. Les chaînes suivantes du même
  /// serveur s'ouvrent directement dans ce format (zapping rapide).
  static final Map<String, _Variant> _hostVariant = <String, _Variant>{};

  /// Adresse à ouvrir EN PREMIER pour [url] : l'adresse d'origine, ou le
  /// format qui a déjà marché sur ce serveur pendant cette session.
  static String preferred(String url) {
    final RegExpMatch? m = _rxXtream.firstMatch(url.trim());
    if (m == null) return url;
    final _Variant? v = _hostVariant[m.group(1)!.toLowerCase()];
    return v == null ? url : _build(m, v);
  }

  /// Toutes les adresses à essayer pour [current], dans l'ordre, SANS
  /// doublon. La 1re est toujours [preferred] (l'adresse ouverte au départ).
  /// [all] = toutes les chaînes connues (sources fusionnées) ; on y cherche
  /// la même chaîne ailleurs.
  static List<String> candidates(Channel current, Iterable<Channel> all) {
    final List<String> out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    final String original = current.streamUrl.trim();
    add(preferred(original));
    add(original);
    for (final String v in formatVariants(original)) {
      add(v);
    }
    for (final String b in backups(current, all)) {
      add(b);
    }
    return out;
  }

  /// Les autres formats Xtream de [url] (vide si ce n'est pas une adresse
  /// de direct Xtream reconnue).
  static List<String> formatVariants(String url) {
    final RegExpMatch? m = _rxXtream.firstMatch(url.trim());
    if (m == null) return const <String>[];
    return <String>[
      for (final _Variant v in _variants) _build(m, v),
    ].where((String u) => u != url.trim()).toList();
  }

  /// La même chaîne dans une autre source / une autre qualité : même nom
  /// « nettoyé » (sans HD/FHD/4K, préfixes pays…), adresse différente.
  /// Les autres SERVEURS passent en premier (le serveur courant est
  /// peut-être celui qui ne répond pas).
  static List<String> backups(Channel current, Iterable<Channel> all) {
    final String key = matchKey(current.name);
    if (key.length < 2) return const <String>[];
    final String url = current.streamUrl.trim();
    final String host = _host(url);
    final List<String> otherHost = <String>[];
    final List<String> sameHost = <String>[];
    for (final Channel c in all) {
      if (!c.isLive || c.id == current.id) continue;
      final String u = c.streamUrl.trim();
      if (u.isEmpty || u == url) continue;
      if (matchKey(c.name) != key) continue;
      final List<String> bucket = _host(u) == host ? sameHost : otherHost;
      if (!bucket.contains(u)) bucket.add(u);
      if (otherHost.length >= maxBackups) break;
    }
    return <String>[...otherHost, ...sameHost].take(maxBackups).toList();
  }

  /// À appeler quand une adresse de secours a VRAIMENT joué : si c'était un
  /// autre format du même serveur, on le retient pour la session.
  static void remember(String original, String working) {
    final RegExpMatch? a = _rxXtream.firstMatch(original.trim());
    final RegExpMatch? b = _rxXtream.firstMatch(working.trim());
    if (a == null || b == null) return;
    final String host = a.group(1)!.toLowerCase();
    if (b.group(1)!.toLowerCase() != host) return; // autre serveur : rien
    for (final _Variant v in _variants) {
      if (_build(a, v) == working.trim()) {
        _hostVariant[host] = v;
        return;
      }
    }
  }

  /// Oublie les formats retenus (tests).
  static void resetMemory() => _hostVariant.clear();

  // ---- Nom de chaîne comparable ----

  static final RegExp _rxPrefix = RegExp(r'^\s*[\[(|]?[a-z]{2}[\])|:]\s*', caseSensitive: false);
  static final RegExp _rxQuality = RegExp(
    r'\b(uhd|fhd|hd|sd|4k|8k|hevc|h265|h\.265|h264|1080p?|720p?|2160p?|50fps|60fps|backup|raw)\b',
    caseSensitive: false,
  );
  static final RegExp _rxNonAlnum = RegExp(r'[^a-z0-9À-ɏЀ-ӿ؀-ۿ]+');

  /// « FR: TF1 FHD » → « tf1 » ; « |UK| Sky Sports 1 HD » → « skysports1 ».
  static String matchKey(String name) {
    String s = name.toLowerCase().trim();
    s = s.replaceFirst(_rxPrefix, '');
    s = s.replaceAll(_rxQuality, ' ');
    return s.replaceAll(_rxNonAlnum, '');
  }

  // ---- internes ----

  static String _host(String url) {
    final int i = url.indexOf('://');
    if (i < 0) return '';
    final int end = url.indexOf('/', i + 3);
    return (end < 0 ? url.substring(i + 3) : url.substring(i + 3, end)).toLowerCase();
  }

  static String _build(RegExpMatch m, _Variant v) {
    final String base = m.group(1)!;
    final String user = m.group(2)!;
    final String pass = m.group(3)!;
    final String id = m.group(4)!;
    switch (v) {
      case _Variant.ts:
        return '$base/live/$user/$pass/$id.ts';
      case _Variant.hls:
        return '$base/live/$user/$pass/$id.m3u8';
      case _Variant.legacy:
        return '$base/$user/$pass/$id';
    }
  }
}

enum _Variant { ts, hls, legacy }
