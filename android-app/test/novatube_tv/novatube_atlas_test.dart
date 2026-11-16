// =========================================================
//  Activation Atlas NovaTube : identité, traduction du statut, client HTTP.
// =========================================================
//  Les valeurs de référence (MK, MAC brute) ont été calculées avec Node à
//  partir de la formule du serveur (novatube4k.js) : la box et le panel
//  affichent forcément le même code. Le client est testé avec un faux
//  serveur HTTP (aucun réseau). Le test contre le VRAI Worker local est
//  atlas_local_integration_test.dart.
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

const int _day = 24 * 60 * 60 * 1000;

Map<String, dynamic> _state({
  String status = 'active',
  String kind = 'trial',
  int? expiresIn = 10 * _day,
  bool sourcesOk = false,
  int? rev,
  String plan = 'trial10',
}) {
  const int now = 1800000000000;
  final bool open = status == 'active';
  return <String, dynamic>{
    'ok': true,
    'app_id': 'app_novatube4k',
    'mac': 'MK:F8:CA:83:78:18',
    'status': status,
    'active': open,
    'playback_allowed': open,
    'access_kind': open ? kind : 'none',
    'plan': plan,
    'expires_at': expiresIn == null ? null : now + expiresIn,
    'server_now': now,
    'sources': <Object?>[],
    'sources_ok': sourcesOk,
    'source_rev': rev,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identité (même formule que le serveur)', () {
    test('code MK du serveur pour une MAC brute connue', () async {
      expect(await NovatubeIdentity.atlasMacFor('0123456789AB'), 'MK:F8:CA:83:78:18');
      expect(await NovatubeIdentity.atlasMacFor('0123456789ab'), 'MK:F8:CA:83:78:18');
    });

    test('MAC brute dérivée de la graine Android', () async {
      expect(await NovatubeIdentity.rawFromSeed('abcdef0123456789'), 'BFE64C01681D');
    });

    test('identité créée une fois puis gardée (mise à jour sans perte)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NovatubeIdentity.seedProvider = () async => 'abcdef0123456789';
      NovatubeIdentity.instance.resetForTesting();
      final String raw = await NovatubeIdentity.instance.rawMac;
      final String key = await NovatubeIdentity.instance.deviceKey;
      expect(raw, 'BFE64C01681D');
      expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(await NovatubeIdentity.instance.mac,
          await NovatubeIdentity.atlasMacFor(raw));
      // « Redémarrage » : on relit les préférences, rien ne change, même si
      // la graine Android n'est plus lisible.
      NovatubeIdentity.seedProvider = () async => '';
      NovatubeIdentity.instance.resetForTesting();
      expect(await NovatubeIdentity.instance.rawMac, raw);
      expect(await NovatubeIdentity.instance.deviceKey, key);
    });
  });

  group('traduction du statut serveur', () {
    test('essai actif : 10 jours, ni payé ni en attente', () {
      final RemoteSubscriptionStatus s = NovatubeAtlas.mapState(_state());
      expect(s.exists, isTrue);
      expect(s.paid, isFalse);
      expect(s.pending, isFalse);
      expect(s.expired, isFalse);
      expect(s.daysLeft, 10);
      expect(s.trialUntil, 1800000000000 + 10 * _day);
    });

    test('licence payée avec échéance, puis à vie', () {
      final RemoteSubscriptionStatus paid =
          NovatubeAtlas.mapState(_state(kind: 'paid', plan: 'yearly', expiresIn: 365 * _day));
      expect(paid.paid, isTrue);
      expect(paid.paidUntil, 1800000000000 + 365 * _day);
      final RemoteSubscriptionStatus life =
          NovatubeAtlas.mapState(_state(kind: 'paid', plan: 'yearly', expiresIn: null));
      expect(life.paid, isTrue);
      expect(life.plan, 'lifetime');
    });

    test('expirée, suspendue, désactivée, bannie : jamais « en attente »', () {
      expect(NovatubeAtlas.mapState(_state(status: 'expired')).expired, isTrue);
      expect(NovatubeAtlas.mapState(_state(status: 'frozen')).frozen, isTrue);
      expect(NovatubeAtlas.mapState(_state(status: 'disabled')).frozen, isTrue);
      expect(NovatubeAtlas.mapState(_state(status: 'banned')).banned, isTrue);
      for (final String st in <String>['expired', 'frozen', 'disabled', 'banned']) {
        expect(NovatubeAtlas.mapState(_state(status: st)).pending, isFalse, reason: st);
        expect(NovatubeAtlas.mapState(_state(status: st)).paid, isFalse, reason: st);
      }
    });

    test('fiche inactive (jamais activée) = en attente, sans accès', () {
      final RemoteSubscriptionStatus s = NovatubeAtlas.mapState(_state(status: 'inactive'));
      expect(s.pending, isTrue);
      expect(s.paid, isFalse);
      expect(s.trialUntil, 0);
    });

    test('révision des listes seulement si le serveur les a vraiment servies', () {
      expect(NovatubeAtlas.mapState(_state(sourcesOk: true, rev: 7)).sourceRev, 7);
      expect(NovatubeAtlas.mapState(_state(sourcesOk: false, rev: 7)).sourceRev, isNull);
    });
  });

  group('client HTTP (faux serveur, aucun réseau)', () {
    late List<http.Request> seen;
    late List<http.Response Function(http.Request)> replies;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NovatubeIdentity.seedProvider = () async => 'abcdef0123456789';
      NovatubeIdentity.instance.resetForTesting();
      NovatubeAtlas.instance.resetForTesting();
      NovatubeAtlas.baseUrl = 'https://atlas.test';
      seen = <http.Request>[];
      replies = <http.Response Function(http.Request)>[];
      NovatubeAtlas.clientFactory = () => MockClient((http.Request r) async {
            seen.add(r);
            return replies.removeAt(0)(r);
          });
    });

    http.Response okState(http.Request _) =>
        http.Response(jsonEncode(_state(sourcesOk: true, rev: 3)), 200);

    test('register au premier appel, puis state ; clé et MAC brute envoyées', () async {
      replies.addAll(<http.Response Function(http.Request)>[okState, okState]);
      final RemoteStatusRead a = await NovatubeAtlas.instance.readStatus();
      final RemoteStatusRead b = await NovatubeAtlas.instance.readStatus();
      expect(a.reached, isTrue);
      expect(b.reached, isTrue);
      expect(seen[0].url.path, '/api/novatube4k/register');
      expect(seen[1].url.path, '/api/novatube4k/state');
      expect(seen[0].headers['X-Device-Key'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(jsonDecode(seen[0].body), <String, dynamic>{'raw_mac': 'BFE64C01681D'});
      expect(NovatubeAtlas.instance.servedSources,
          <String, dynamic>{'sources': <Object?>[], 'rev': 3});
    });

    test('clé refusée sur une fiche existante → code de réassociation', () async {
      replies.add((_) => http.Response(
          jsonEncode(<String, dynamic>{
            'ok': false,
            'error': 'device_key_conflict',
            'recovery': <String, dynamic>{'status': 'pending', 'code': '482913'},
          }),
          409));
      final RemoteStatusRead r = await NovatubeAtlas.instance.readStatus();
      expect(r.reached, isTrue);
      expect(r.status.pending, isTrue);
      expect(NovatubeAtlas.instance.recoveryCode.value, '482913');
    });

    test('fiche supprimée (401 sur state) → nouvelle inscription au tour suivant', () async {
      replies.addAll(<http.Response Function(http.Request)>[
        okState,
        (_) => http.Response('{"ok":false,"error":"device_auth_required"}', 401),
        okState,
      ]);
      await NovatubeAtlas.instance.readStatus();
      final RemoteStatusRead lost = await NovatubeAtlas.instance.readStatus();
      expect(lost.reached, isFalse);
      await NovatubeAtlas.instance.readStatus();
      expect(seen.map((http.Request r) => r.url.path).toList(), <String>[
        '/api/novatube4k/register',
        '/api/novatube4k/state',
        '/api/novatube4k/register',
      ]);
    });

    test('panne réseau : « hors ligne », les listes locales sont gardées', () async {
      replies.add((_) => throw http.ClientException('réseau coupé'));
      final RemoteStatusRead r = await NovatubeAtlas.instance.readStatus();
      expect(r.reached, isFalse);
      expect(NovatubeAtlas.instance.servedSources, isNull);
    });

    test('accusé de réception des listes', () async {
      replies.add((_) => http.Response('{"ok":true,"result":"config_saved"}', 200));
      expect(await NovatubeAtlas.instance.ack(3), isTrue);
      final Map<String, dynamic> body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(seen.single.url.path, '/api/novatube4k/ack');
      expect(body['source_rev'], 3);
      expect(body['applied'], isTrue);
    });

    test(
      kNovatubeTv
          ? 'édition NovaTube : heartbeat et statut passent par /api/novatube4k'
          : 'Zuno : heartbeat inchangé (aucun appel NovaTube)',
      () async {
        if (!kNovatubeTv) {
          // Zuno ne touche jamais au client NovaTube.
          expect(seen, isEmpty);
          return;
        }
        replies.addAll(<http.Response Function(http.Request)>[okState, okState]);
        await SubscriptionBackend.heartbeat('MK:00:00:00:00:00');
        await SubscriptionBackend.getStatus('MK:00:00:00:00:00');
        expect(seen.every((http.Request r) => r.url.path.startsWith('/api/novatube4k/')),
            isTrue);
      },
    );
  });
}
