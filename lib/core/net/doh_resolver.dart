// =========================================================
//  doh_resolver.dart — Résolution DNS chiffrée (DNS-over-HTTPS)
// =========================================================
//  CAUSE RACINE terrain (2026-07-08) : des panels IPTV utilisent un
//  domaine WILDCARD (ex. *.801802.com sur Cloudflare) — n'importe quel
//  sous-domaine généré à la volée résout vers le CDN. Ces domaines
//  EXISTENT (ils ont une IP), mais beaucoup d'opérateurs FR bloquent la
//  résolution DNS des domaines IPTV (« Failed host lookup … No address
//  associated with hostname »). Résultat : la source ne charge pas,
//  alors qu'IBO/Smarters la lisent.
//
//  Ce résolveur contourne le DNS de l'opérateur : il interroge
//  directement Cloudflare (1.1.1.1) et Google (8.8.8.8) en DNS-over-
//  HTTPS — une requête HTTPS que l'opérateur ne peut ni voir ni
//  filtrer. On tape les résolveurs PAR IP (pas par nom) pour ne
//  dépendre d'AUCUNE résolution DNS système au démarrage.
//
//  Installé sur les clients HTTP qui parlent aux panels via
//  `installDohResolution` : le DNS système est tenté EN PREMIER (rapide,
//  marche sur la majorité des réseaux) ; le DoH ne prend le relais que
//  lorsqu'il échoue. Périmètre STRICT : serveurs IPTV tiers uniquement,
//  jamais notre backend.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Une entrée de cache : les adresses résolues et leur péremption.
class _CacheEntry {
  _CacheEntry(this.addresses, this.expiresAt);
  final List<InternetAddress> addresses;
  final DateTime expiresAt;
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

/// Résolveur DNS-over-HTTPS avec cache, repli entre fournisseurs, et
/// repli final sur le DNS système. Sans état partagé nécessaire hors du
/// cache — une instance singleton suffit.
class DohResolver {
  DohResolver._();
  static final DohResolver instance = DohResolver._();

  /// Point d'accès DoH JSON, désigné PAR IP pour ne dépendre d'aucune
  /// résolution système. `host` = le SNI/Host à présenter (le certificat
  /// de ces IPs le couvre).
  static const List<({String ip, String host})> _providers =
      <({String ip, String host})>[
    (ip: '1.1.1.1', host: 'cloudflare-dns.com'), // Cloudflare
    (ip: '8.8.8.8', host: 'dns.google'), //          Google
  ];

  static const Duration _minTtl = Duration(seconds: 60);
  static const Duration _maxTtl = Duration(hours: 6);

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  /// Injectable pour les tests : exécute la requête DoH et renvoie le
  /// corps JSON brut (ou lève). En production : requête HTTPS réelle
  /// vers l'IP du fournisseur.
  @visibleForTesting
  Future<String> Function(String providerIp, String providerHost,
      String name)? httpGetOverride;

  /// Vide le cache (tests / changement de réseau).
  void clearCache() => _cache.clear();

  /// Résout [host] en adresses IP via DoH. Renvoie une liste vide si
  /// aucun fournisseur ne répond. Résultat mis en cache selon le TTL.
  Future<List<InternetAddress>> resolve(String host) async {
    final _CacheEntry? cached = _cache[host];
    if (cached != null && cached.isFresh) return cached.addresses;

    for (final ({String ip, String host}) p in _providers) {
      try {
        final String body = await (httpGetOverride ?? _realDohGet)(
          p.ip,
          p.host,
          host,
        ).timeout(const Duration(seconds: 5));
        final (List<InternetAddress> addrs, Duration ttl) =
            _parseDohJson(body);
        if (addrs.isNotEmpty) {
          _cache[host] = _CacheEntry(addrs, DateTime.now().add(ttl));
          if (kDebugMode) {
            debugPrint('[DoH] $host → ${addrs.map((InternetAddress a) => a.address).join(', ')} '
                '(via ${p.host})');
          }
          return addrs;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[DoH] ${p.host} KO pour $host : $e');
        // fournisseur suivant
      }
    }
    return const <InternetAddress>[];
  }

  /// Requête DoH JSON réelle. Client DÉDIÉ (pas de connectionFactory —
  /// sinon récursion) qui se connecte à l'IP du fournisseur : aucune
  /// résolution système requise. On tolère les certificats interceptés
  /// (réseaux hostiles) — l'objectif est l'accessibilité, et la réponse
  /// est de toute façon revalidée en tentant la connexion réelle.
  Future<String> _realDohGet(
    String providerIp,
    String providerHost,
    String name,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    try {
      final Uri uri = Uri.parse(
          'https://$providerIp/dns-query?name=${Uri.encodeQueryComponent(name)}&type=A');
      final HttpClientRequest req = await client.getUrl(uri);
      // Présente le bon nom d'hôte (Host header ; le SNI part sur l'IP,
      // le certificat de 1.1.1.1 / 8.8.8.8 couvre ces noms).
      req.headers.set(HttpHeaders.hostHeader, providerHost);
      req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('DoH HTTP ${resp.statusCode}');
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  /// Parse une réponse DoH JSON (format Cloudflare/Google) : extrait les
  /// enregistrements A (type 1) et le TTL minimum (borné).
  static (List<InternetAddress>, Duration) _parseDohJson(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return (const <InternetAddress>[], _minTtl);
    }
    final Object? answer = decoded['Answer'];
    if (answer is! List) return (const <InternetAddress>[], _minTtl);
    final List<InternetAddress> addrs = <InternetAddress>[];
    int minTtl = _maxTtl.inSeconds;
    for (final Object? a in answer) {
      if (a is! Map) continue;
      if (a['type'] != 1) continue; // 1 = A (IPv4)
      final Object? data = a['data'];
      if (data is! String) continue;
      final InternetAddress? ip = InternetAddress.tryParse(data.trim());
      if (ip == null) continue;
      addrs.add(ip);
      final Object? ttl = a['TTL'];
      if (ttl is int && ttl < minTtl) minTtl = ttl;
    }
    Duration ttl = Duration(seconds: minTtl);
    if (ttl < _minTtl) ttl = _minTtl;
    if (ttl > _maxTtl) ttl = _maxTtl;
    return (addrs, ttl);
  }
}

/// Résout [host] en UNE adresse IP pour une lecture média DIRECTE (mpv),
/// qui ne passe PAS par un [HttpClient] Dart et ignore donc
/// [installDohResolution]. DNS système d'abord (rapide, exact pour les
/// CDN locaux) ; DoH en repli quand l'opérateur bloque le domaine IPTV.
/// Renvoie null si rien ne résout (l'appelant laisse alors mpv tenter le
/// nom brut). Une IP littérale est renvoyée telle quelle. On préfère
/// l'IPv4 (compatibilité maximale des panels).
Future<InternetAddress?> resolveHostForMedia(String host) async {
  final InternetAddress? literal = InternetAddress.tryParse(host);
  if (literal != null) return literal;
  // 1) DNS système (budget court : sur réseau bloquant, échoue vite).
  try {
    final List<InternetAddress> sys = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 3));
    for (final InternetAddress a in sys) {
      if (a.type == InternetAddressType.IPv4) return a;
    }
    if (sys.isNotEmpty) return sys.first;
  } catch (_) {
    // blocage / échec → DoH
  }
  // 2) DoH : l'app résout elle-même, l'opérateur ne peut pas filtrer.
  final List<InternetAddress> doh = await DohResolver.instance.resolve(host);
  return doh.isNotEmpty ? doh.first : null;
}

/// Installe la résolution DoH sur [client] : le DNS système est tenté
/// d'abord ; en cas d'échec (blocage opérateur), le domaine est résolu
/// en DoH et la connexion part directement sur l'IP obtenue — le
/// [HttpClient] conserve le nom d'hôte d'origine pour l'en-tête Host et
/// le SNI TLS. À réserver aux clients qui parlent aux panels IPTV.
void installDohResolution(HttpClient client) {
  client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
    // Connexions via proxy : laissées telles quelles (on ne résout que
    // l'hôte final quand il n'y a pas de proxy).
    if (proxyHost != null) {
      return Socket.startConnect(proxyHost, proxyPort ?? 0);
    }
    final int port =
        uri.port != 0 ? uri.port : (uri.isScheme('https') ? 443 : 80);
    return _connectResolving(uri.host, port);
  };
}

/// DNS système d'abord (rapide, marche partout) ; DoH en repli quand il
/// échoue (domaine bloqué par l'opérateur). Renvoie un ConnectionTask
/// vers la première adresse utilisable.
Future<ConnectionTask<Socket>> _connectResolving(String host, int port) async {
  // Déjà une IP littérale : rien à résoudre.
  final InternetAddress? literal = InternetAddress.tryParse(host);
  if (literal != null) return Socket.startConnect(literal, port);

  // 1) DNS système (avec un budget court : sur un réseau qui bloque, il
  //    échoue vite avec « Failed host lookup »).
  try {
    final List<InternetAddress> sys =
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
    if (sys.isNotEmpty) return Socket.startConnect(preferIpv4(sys), port);
  } catch (_) {
    // blocage / échec → on tente le DoH
  }

  // 2) DoH : l'app résout elle-même, l'opérateur ne peut pas filtrer.
  final List<InternetAddress> doh = await DohResolver.instance.resolve(host);
  if (doh.isNotEmpty) return Socket.startConnect(preferIpv4(doh), port);

  // 3) Dernier recours : laisser la connexion échouer avec l'erreur
  //    système native (message clair pour l'utilisateur).
  return Socket.startConnect(host, port);
}

/// Choisit une adresse IPv4 EN PRIORITÉ dans [addrs], sinon la première.
///
/// CAUSE RACINE terrain (log box 2026-07-19) : le DNS système renvoie
/// souvent l'IPv6 en tête (`sys.first`). Or de nombreuses box (Android TV
/// bon marché, certains FAI) ont une IPv6 CASSÉE ou très lente → la
/// connexion au flux stalle puis est annulée
/// (« SocketException: Connection attempt cancelled, … IPv6 … ») → le relais
/// reconnecte en boucle → buffering / gel. On aligne le relais sur le
/// résolveur média (qui préfère déjà l'IPv4 « compatibilité maximale des
/// panels »). Une box en IPv4-only n'est pas affectée ; une chaîne servie
/// UNIQUEMENT en IPv6 (quasi inexistant en IPTV) retombe sur la 1re adresse.
InternetAddress preferIpv4(List<InternetAddress> addrs) {
  for (final InternetAddress a in addrs) {
    if (a.type == InternetAddressType.IPv4) return a;
  }
  return addrs.first;
}
