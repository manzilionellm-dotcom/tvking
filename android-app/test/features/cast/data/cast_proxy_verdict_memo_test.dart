// =========================================================
//  cast_proxy_verdict_memo_test.dart — Mémo du verdict /cast-proxy
// =========================================================
//  Fluidité 2026-07-10 : le fournisseur IPTV refuse les IP datacenter
//  du Worker de façon STABLE (upstream 403/456/458 sur 9 casts), mais
//  l'app re-signait et re-vérifiait le proxy À CHAQUE zap (~0,5-3 s +
//  un 502 martelé). Le mémo retient le verdict par hôte du portail :
//    - « bloqué »  → TTL 10 min (zap direct au relais téléphone) ;
//    - « délivre » → TTL 2 min  (on signe mais on saute le GET).
//  À l'expiration, cachedBlocked renvoie null → re-vérification réelle.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';

void main() {
  group('CastProxyVerdictMemo', () {
    test('verdict « bloqué » retenu 10 min, puis expiré (re-test réel)', () {
      DateTime now = DateTime(2026, 7, 10, 12);
      final CastProxyVerdictMemo memo =
          CastProxyVerdictMemo(clock: () => now);

      expect(memo.cachedBlocked('portal.example'), isNull,
          reason: 'hôte jamais vu → vérification réelle requise');

      memo.remember('portal.example', blocked: true);
      expect(memo.cachedBlocked('portal.example'), isTrue);

      now = now.add(CastProxyVerdictMemo.kBlockedTtl -
          const Duration(seconds: 1));
      expect(memo.cachedBlocked('portal.example'), isTrue,
          reason: 'toujours dans le TTL « bloqué »');

      now = now.add(const Duration(seconds: 2));
      expect(memo.cachedBlocked('portal.example'), isNull,
          reason: 'TTL dépassé → un fournisseur qui débloque le '
              'datacenter doit être re-détecté');
    });

    test('verdict « délivre » expire plus vite (2 min)', () {
      DateTime now = DateTime(2026, 7, 10, 12);
      final CastProxyVerdictMemo memo =
          CastProxyVerdictMemo(clock: () => now);

      memo.remember('portal.example', blocked: false);
      expect(memo.cachedBlocked('portal.example'), isFalse);

      now = now.add(CastProxyVerdictMemo.kDeliversTtl -
          const Duration(seconds: 1));
      expect(memo.cachedBlocked('portal.example'), isFalse);

      now = now.add(const Duration(seconds: 2));
      expect(memo.cachedBlocked('portal.example'), isNull,
          reason: 'un proxy qui se met à être bloqué doit être '
              're-détecté vite (écran noir sinon)');
    });

    test('un nouveau verdict écrase l\'ancien (re-test après TTL)', () {
      DateTime now = DateTime(2026, 7, 10, 12);
      final CastProxyVerdictMemo memo =
          CastProxyVerdictMemo(clock: () => now);

      memo.remember('portal.example', blocked: true);
      expect(memo.cachedBlocked('portal.example'), isTrue);

      // Le fournisseur débloque le datacenter : le re-test le voit.
      memo.remember('portal.example', blocked: false);
      expect(memo.cachedBlocked('portal.example'), isFalse);
    });

    test('les hôtes sont indépendants, l\'hôte vide est ignoré', () {
      DateTime now = DateTime(2026, 7, 10, 12);
      final CastProxyVerdictMemo memo =
          CastProxyVerdictMemo(clock: () => now);

      memo.remember('a.example', blocked: true);
      expect(memo.cachedBlocked('a.example'), isTrue);
      expect(memo.cachedBlocked('b.example'), isNull,
          reason: 'le verdict d\'un portail ne déteint pas sur un autre');

      memo.remember('', blocked: true);
      expect(memo.cachedBlocked(''), isNull,
          reason: 'hôte imparsable → jamais mémorisé');
    });
  });
}
