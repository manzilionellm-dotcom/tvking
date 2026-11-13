// =========================================================
//  user_agent_probe_test.dart — Diagnostic multi-signature
// =========================================================
//  « La chaîne marche sur IBO mais pas chez nous » : beaucoup de
//  fournisseurs IPTV whitelistent la signature d'un lecteur connu (VLC,
//  ExoPlayer/IBO, Smarters…) et servent une page vide/erreur aux autres,
//  sans jamais renvoyer une vraie erreur réseau. `StreamProbe.probeUserAgents`
//  teste plusieurs signatures et `UserAgentProbeResult` en tire la décision
//  (bascule silencieuse, ou message réseau honnête). Ces tests verrouillent
//  la logique de décision SANS réseau réel (StreamProbeResult construits à
//  la main), cf. dns_failure_classifier_test.dart pour le même style.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';

StreamProbeResult _ok({String? mime}) {
  return StreamProbeResult(
    originalUrl: 'http://example.com/live/u/p/1.ts',
    finalUrl: 'http://example.com/live/u/p/1.ts',
    success: true,
    mime: mime,
  );
}

StreamProbeResult _fail(String reason) {
  return StreamProbeResult(
    originalUrl: 'http://example.com/live/u/p/1.ts',
    finalUrl: 'http://example.com/live/u/p/1.ts',
    success: false,
    errorReason: reason,
  );
}

StreamProbeResult _authFail() {
  return const StreamProbeResult(
    originalUrl: 'http://example.com/live/u/p/1.ts',
    finalUrl: 'http://example.com/live/u/p/1.ts',
    success: false,
    requiresAuth: true,
    errorCode: 403,
    errorReason: 'Authentification requise — token expiré ?',
  );
}

void main() {
  group('UserAgentProbeResult', () {
    test('la 1re signature qui répond un vrai média est adoptée', () {
      final Map<String, StreamProbeResult> attempts = <String, StreamProbeResult>{
        'VLC/3.0.18': _fail('Le serveur ne répond pas — réessaie'),
        'ExoPlayerLib/2.19.1': _ok(mime: 'video/mp2t'),
      };
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: 'ExoPlayerLib/2.19.1',
        attempts: attempts,
      );
      expect(r.workingUserAgent, 'ExoPlayerLib/2.19.1');
      expect(r.isLikelyNetworkBlocked, isFalse);
    });

    test(
        'signature actuelle déjà fonctionnelle → workingUserAgent == la '
        'même (rien à changer)', () {
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: 'VLC/3.0.18',
        attempts: <String, StreamProbeResult>{'VLC/3.0.18': _ok()},
      );
      expect(r.workingUserAgent, 'VLC/3.0.18');
    });

    test(
        'toutes les signatures échouent avec des raisons RÉSEAU '
        '(DNS/timeout) → isLikelyNetworkBlocked', () {
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{
          'VLC/3.0.18': _fail('Connexion impossible (No address associated '
              'with hostname)'),
          'ExoPlayerLib/2.19.1': _fail('Le serveur ne répond pas — réessaie'),
          'okhttp/4.12.0': _fail('Connexion impossible (réseau)'),
        },
      );
      expect(r.workingUserAgent, isNull);
      expect(r.isLikelyNetworkBlocked, isTrue);
    });

    test(
        'échec par AUTH (403) sur toutes les signatures → PAS un blocage '
        'réseau (changer de signature ne réglera rien, mais ce n\'est pas '
        'un souci FAI/DNS non plus)', () {
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{
          'VLC/3.0.18': _authFail(),
          'ExoPlayerLib/2.19.1': _authFail(),
        },
      );
      expect(r.workingUserAgent, isNull);
      expect(r.isLikelyNetworkBlocked, isFalse);
    });

    test(
        'mélange échec réseau + échec auth → PAS "likely network blocked" '
        '(pas UNANIME)', () {
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{
          'VLC/3.0.18': _fail('Connexion impossible (réseau)'),
          'ExoPlayerLib/2.19.1': _authFail(),
        },
      );
      expect(r.isLikelyNetworkBlocked, isFalse);
    });

    test('aucune tentative (attempts vide) → isLikelyNetworkBlocked faux', () {
      const UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{},
      );
      expect(r.isLikelyNetworkBlocked, isFalse);
    });

    test(
        'une signature réussit MAIS avec un MIME html (page placeholder) → '
        'ne compte PAS comme un vrai média', () {
      // Ce cas est couvert par StreamProbe.probeUserAgents (qui filtre via
      // _looksLikeRealMedia avant de déclarer une signature "working") : ici
      // on vérifie juste que si le CALLER construit lui-même un résultat où
      // aucune signature n'a été retenue malgré un success=true (mime html),
      // isLikelyNetworkBlocked reste faux (ce n'est pas un blocage réseau,
      // le serveur a bien répondu — juste pas avec le flux attendu).
      final UserAgentProbeResult r = UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{
          'VLC/3.0.18': _ok(mime: 'text/html'),
        },
      );
      expect(r.isLikelyNetworkBlocked, isFalse);
    });
  });
}
