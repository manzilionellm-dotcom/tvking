// =========================================================
//  privacy_shield_test.dart — Mode Bouclier : la règle, pas l'UI
// =========================================================
//  Ce que ces tests verrouillent :
//    1. bouclier éteint = aucun effet (lecture toujours autorisée, URL
//       inchangée, télémétrie normale) ;
//    2. coupe-circuit : sans VPN → lecture réseau refusée, fichier local
//       toujours autorisé, VPN revenu → autorisé ;
//    3. HTTPS préféré : sondé UNE fois par serveur, mémorisé, jamais sur
//       l'URL du flux (la sonde reçoit la racine du serveur) ;
//    4. télémétrie minimale n'est active QUE si le bouclier l'est ;
//    5. la persistance survit à un rechargement.
//  Les sondes natives sont remplacées par des fakes : aucun réseau, aucun
//  canal natif — les tests tournent en CI sans Android.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/privacy/privacy_shield.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PrivacyShield shield;
  late bool fakeVpn;
  late List<Uri> httpsProbed;
  late bool fakeHttps;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    shield = PrivacyShield.instance;
    shield.resetForTest();
    fakeVpn = false;
    fakeHttps = true;
    httpsProbed = <Uri>[];
    shield.vpnProbe = () async => fakeVpn;
    shield.httpsProbe = (Uri root) async {
      httpsProbed.add(root);
      return fakeHttps;
    };
    await shield.load();
  });

  tearDown(() => shield.resetForTest());

  test('bouclier éteint : aucun effet', () async {
    expect(shield.enabled, isFalse);
    expect(shield.blocksNetworkPlayback, isFalse);
    expect(shield.minimalTelemetryActive, isFalse);
    expect(await shield.allowsPlayback('http://panel.example/live/u/p/1.ts'),
        isTrue);
    expect(await shield.preferredUrl('http://panel.example/live/u/p/1.ts'),
        'http://panel.example/live/u/p/1.ts');
    expect(httpsProbed, isEmpty);
  });

  test('coupe-circuit : sans VPN la lecture réseau est refusée', () async {
    await shield.setEnabled(true);
    fakeVpn = false;
    final bool allowed =
        await shield.allowsPlayback('http://panel.example/live/u/p/1.ts');
    // Hors Android, la détection n'existe pas : le coupe-circuit ne doit
    // JAMAIS bloquer sur un « je ne sais pas ».
    if (Platform.isAndroid) {
      expect(allowed, isFalse);
      expect(shield.blocksNetworkPlayback, isTrue);
    } else {
      expect(allowed, isTrue);
      expect(shield.blocksNetworkPlayback, isFalse);
      expect(shield.vpnDetectionSupported, isFalse);
    }
  });

  test('coupe-circuit : un fichier local passe toujours', () async {
    await shield.setEnabled(true);
    fakeVpn = false;
    expect(await shield.allowsPlayback('/data/user/0/app/films/x.mp4'),
        isTrue);
    expect(await shield.allowsPlayback('file:///sdcard/x.mkv'), isTrue);
  });

  test('coupe-circuit : la sonde est rafraîchie et le VPN revenu débloque',
      () async {
    await shield.setEnabled(true);
    fakeVpn = true;
    expect(await shield.refreshVpnStatus(), isTrue);
    expect(shield.vpnActive, isTrue);
    expect(shield.blocksNetworkPlayback, isFalse);
    fakeVpn = false;
    expect(await shield.refreshVpnStatus(), isFalse);
    expect(shield.vpnActive, isFalse);
  });

  test('coupe-circuit désarmé : l\'état VPN ne bloque plus rien', () async {
    await shield.setEnabled(true);
    await shield.setRequireVpn(false);
    fakeVpn = false;
    expect(shield.blocksNetworkPlayback, isFalse);
    expect(await shield.allowsPlayback('http://panel.example/x.ts'), isTrue);
  });

  test('HTTPS préféré : sondé une fois par serveur, sur la racine, mémorisé',
      () async {
    await shield.setEnabled(true);
    fakeHttps = true;
    const String a = 'http://panel.example:8080/live/user/pass/12.ts';
    const String b = 'http://panel.example:8080/live/user/pass/13.ts';
    expect(await shield.preferredUrl(a),
        'https://panel.example:8080/live/user/pass/12.ts');
    expect(await shield.preferredUrl(b),
        'https://panel.example:8080/live/user/pass/13.ts');
    // Une seule sonde pour les deux chaînes du même serveur…
    expect(httpsProbed, hasLength(1));
    // …et jamais sur l'URL du flux : racine, sans identifiants.
    expect(httpsProbed.single.toString(), 'https://panel.example:8080/');
    expect(shield.httpsMemoryForTest, <String, bool>{
      'panel.example:8080': true,
    });
  });

  test('HTTPS préféré : un serveur sans TLS garde son URL http', () async {
    await shield.setEnabled(true);
    fakeHttps = false;
    const String a = 'http://plain.example/live/u/p/1.ts';
    expect(await shield.preferredUrl(a), a);
    expect(await shield.preferredUrl(a), a);
    expect(httpsProbed, hasLength(1));
  });

  test('HTTPS préféré : déjà https, local ou non-http → inchangé', () async {
    await shield.setEnabled(true);
    expect(await shield.preferredUrl('https://x.example/a.m3u8'),
        'https://x.example/a.m3u8');
    expect(await shield.preferredUrl('/films/a.mp4'), '/films/a.mp4');
    expect(await shield.preferredUrl('rtsp://cam.example/1'),
        'rtsp://cam.example/1');
    expect(httpsProbed, isEmpty);
  });

  test('HTTPS préféré désactivé : aucune sonde', () async {
    await shield.setEnabled(true);
    await shield.setPreferHttps(false);
    const String a = 'http://panel.example/live/u/p/1.ts';
    expect(await shield.preferredUrl(a), a);
    expect(httpsProbed, isEmpty);
  });

  test('télémétrie minimale : seulement avec le bouclier', () async {
    expect(shield.minimalTelemetryActive, isFalse);
    await shield.setMinimalTelemetry(true);
    expect(shield.minimalTelemetryActive, isFalse);
    await shield.setEnabled(true);
    expect(shield.minimalTelemetryActive, isTrue);
    await shield.setMinimalTelemetry(false);
    expect(shield.minimalTelemetryActive, isFalse);
  });

  test('persistance : réglages et mémoire HTTPS survivent au rechargement',
      () async {
    await shield.setEnabled(true);
    await shield.setRequireVpn(false);
    await shield.setPreferHttps(true);
    await shield.setMinimalTelemetry(false);
    fakeHttps = true;
    await shield.preferredUrl('http://panel.example/live/u/p/1.ts');

    // Nouvelle « session » : même prefs, instance réinitialisée.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, Object> kept = <String, Object>{
      for (final String k in prefs.getKeys()) k: prefs.get(k)!,
    };
    shield.resetForTest();
    SharedPreferences.setMockInitialValues(kept);
    shield.httpsProbe = (Uri root) async {
      httpsProbed.add(root);
      return false; // ne doit PAS être appelée : verdict mémorisé
    };
    httpsProbed.clear();
    await shield.load();

    expect(shield.enabled, isTrue);
    expect(shield.requireVpn, isFalse);
    expect(shield.preferHttps, isTrue);
    expect(shield.minimalTelemetry, isFalse);
    expect(await shield.preferredUrl('http://panel.example/live/u/p/2.ts'),
        'https://panel.example/live/u/p/2.ts');
    expect(httpsProbed, isEmpty);
  });
}
