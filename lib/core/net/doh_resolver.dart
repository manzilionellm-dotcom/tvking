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

  /// TTL court du CACHE NÉGATIF : un hôte qui ne résout nulle part (mort ou
  /// bloqué partout) coûtait ~14 s à CHAQUE tentative (DNS système 4 s + 2
  /// fournisseurs DoH × 5 s). On mémorise l'échec brièvement pour que les
  /// re-tentatives rapprochées (zapping, retry du lecteur) répondent
  /// instantanément — assez court pour re-tester vite quand le réseau revient.
  static const Duration _negativeTtl = Duration(seconds: 45);

  /// PLAFOND du cache (anti-OOM) : les panels à domaine WILDCARD génèrent des
  /// sous-domaines à la volée → sans borne, une longue session de zapping
  /// ferait grossir la map indéfiniment (contribution au kill mémoire natif
  /// sur box ≤ 1 Go). 256 entrées ≈ quelques dizaines de Ko, largement assez
  /// pour tous les hôtes vivants d'une session.
  static const int _kCacheCap = 256;

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  /// Injectable pour les tests : exécute la requête DoH et renvoie le
  /// corps JSON brut (ou lève). En production : requête HTTPS réelle
  /// vers l'IP du fournisseur. Signature volontairement à 3 arguments (le
  /// type d'enregistrement A/AAAA n'intéresse pas les stubs de test).
  @visibleForTesting
  Future<String> Function(String providerIp, String providerHost, String name)?
      httpGetOverride;

  /// Vide le cache (tests / changement de réseau).
  void clearCache() => _cache.clear();

  /// Résout [host] en adresses IP via DoH. Renvoie une liste vide si
  /// aucun fournisseur ne répond. Résultat mis en cache selon le TTL.
  Future<List<InternetAddress>> resolve(String host) async {
    final _CacheEntry? cached = _cache[host];
    if (cached != null && cached.isFresh) return cached.addresses;

    for (final ({String ip, String host}) p in _providers) {
      // A (IPv4) d'abord — compatibilité maximale des panels — puis AAAA
      // (IPv6) SI le fournisseur RÉPOND mais sans enregistrement A : sur les
      // réseaux mobiles IPv6-only (fréquents chez certains opérateurs), un
      // domaine sans A n'était JAMAIS résolu → « ça ne marche pas » persistant.
      // En revanche, si le fournisseur ÉCHOUE (réseau/timeout), il est mort :
      // on bascule directement au fournisseur suivant plutôt que de re-taper
      // le même en AAAA (inutile et coûteux).
      for (final String type in const <String>['A', 'AAAA']) {
        try {
          final Future<String> Function() call = httpGetOverride != null
              ? () => httpGetOverride!(p.ip, p.host, host)
              : () => _realDohGet(p.ip, p.host, host, type);
          final String body =
              await call().timeout(const Duration(seconds: 5));
          final (List<InternetAddress> addrs, Duration ttl) =
              _parseDohJson(body);
          if (addrs.isNotEmpty) {
            _cachePut(host, _CacheEntry(addrs, DateTime.now().add(ttl)));
            if (kDebugMode) {
              debugPrint('[DoH] $host → ${addrs.map((InternetAddress a) => a.address).join(', ')} '
                  '(via ${p.host}, $type)');
            }
            return addrs;
          }
          // Réponse VIDE (pas d'exception) : le fournisseur marche mais ce
          // type manque → on tente le type suivant sur CE fournisseur.
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[DoH] ${p.host} ($type) KO pour $host : $e');
          }
          // Échec dur du fournisseur : inutile d'insister en AAAA, on passe
          // au fournisseur suivant.
          break;
        }
      }
    }
    // CACHE NÉGATIF : mémorise l'échec complet (TTL court) pour que les
    // re-tentatives immédiates ne re-paient pas toute la cascade de timeouts.
    _cachePut(
      host,
      _CacheEntry(
          const <InternetAddress>[], DateTime.now().add(_negativeTtl)),
    );
    return const <InternetAddress>[];
  }

  /// Insère en respectant le plafond : purge d'abord les entrées périmées,
  /// puis éviction FIFO (les plus anciennes insérées) si on déborde encore.
  void _cachePut(String host, _CacheEntry entry) {
    if (_cache.length >= _kCacheCap) {
      _cache.removeWhere((_, _CacheEntry e) => !e.isFresh);
      while (_cache.length >= _kCacheCap) {
        _cache.remove(_cache.keys.first);
      }
    }
    _cache[host] = entry;
  }

  /// Requête DoH JSON réelle. Client DÉDIÉ (pas de connectionFactory —
  /// sinon récursion) qui se connecte à l'IP du fournisseur : aucune
  /// résolution système requise.
  ///
  /// SÉCURITÉ (correctif d'audit) : le certificat TLS du fournisseur est
  /// validé NORMALEMENT (chaîne + nom). Les certificats de 1.1.1.1 et
  /// 8.8.8.8 contiennent leurs IPs en SAN → la validation par défaut passe.
  /// L'ancien `badCertificateCallback => true` permettait à un attaquant
  /// on-path de se faire passer pour le résolveur et d'empoisonner la
  /// réponse DNS (l'app se connectait ensuite au serveur pirate en HTTP
  /// clair, identifiants Xtream dans l'URL). Si un réseau intercepte le TLS,
  /// la requête échoue proprement et on retombe sur le DNS système —
  /// accessibilité préservée, authenticité jamais sacrifiée.
  Future<String> _realDohGet(
    String providerIp,
    String providerHost,
    String name, [
    String type = 'A',
  ]) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final Uri uri = Uri.parse(
          'https://$providerIp/dns-query?name=${Uri.encodeQueryComponent(name)}&type=$type');
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
      // 1 = A (IPv4), 28 = AAAA (IPv6) — les deux sont exploitables.
      if (a['type'] != 1 && a['type'] != 28) continue;
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
    if (sys.isNotEmpty) return Socket.startConnect(sys.first, port);
  } catch (_) {
    // blocage / échec → on tente le DoH
  }

  // 2) DoH : l'app résout elle-même, l'opérateur ne peut pas filtrer.
  final List<InternetAddress> doh = await DohResolver.instance.resolve(host);
  if (doh.isNotEmpty) return Socket.startConnect(doh.first, port);

  // 3) Dernier recours : laisser la connexion échouer avec l'erreur
  //    système native (message clair pour l'utilisateur).
  return Socket.startConnect(host, port);
}
