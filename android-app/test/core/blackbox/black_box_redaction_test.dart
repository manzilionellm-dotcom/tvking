// =========================================================
//  Le journal qui part au panel ne contient ni lien de flux,
//  ni mot de passe, ni identifiant. Les lignes [SON] restent.
//  Mêmes phrases que cloudflare/blackbox.test.mjs.
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/blackbox/black_box_redaction.dart';
import 'package:tv_king/core/blackbox/black_box_upload_flag.dart';

const String _son =
    '03/10 18:26:01 I [SON] [TF1] reçu : HE-AAC 48 kHz 2 voies 128 kb/s · '
    'décodé par : box (c2.android.aac.decoder) · sortie : PCM 16 bits 48 kHz '
    '2 voies passthrough';

const String _fixture = '$_son\n'
    '03/10 18:26:02 I [ACTION] Ajout liste Xtream exemple.test (utilisateur COMPTE)\n'
    '03/10 18:26:03 E [SOURCE] echec http://COMPTE:JETON@exemple.test:8080/get.php?username=COMPTE&password=JETON\n'
    '03/10 18:26:04 I [SOURCE] chemin /live/COMPTE/JETON/1.ts\n'
    '03/10 18:26:05 W [SOURCE] recu password=JETON username=COMPTE\n'
    '03/10 18:26:06 I [SOURCE] note COMPTE@exemple.test\n';

void main() {
  test('une ligne [SON] n\'est pas modifiée', () {
    final String out = redactBlackBox(_son);
    expect(out, _son);
    expect(out.contains('[SON]'), isTrue);
    expect(out.contains('passthrough'), isTrue);
    expect(out.contains('HE-AAC'), isTrue);
    expect(out.contains('48 kHz'), isTrue);
  });

  test('lien, mot de passe et identifiant sont masqués', () {
    final String? out = prepareBlackBoxUpload(_fixture, enabled: true);
    expect(out, isNotNull);
    expect(out!.contains('JETON'), isFalse);
    expect(out.contains('COMPTE'), isFalse);
    expect(out.contains('http://'), isFalse);
    expect(out.contains('password=JETON'), isFalse);
    expect(out.contains('[lien]'), isTrue);
    expect(out.contains('[masqué]'), isTrue);
    expect(out.contains('[identifiant]'), isTrue);
    expect(out.contains('[SON]'), isTrue);
    expect(out.contains('passthrough'), isTrue);
  });

  test('un deuxième passage ne change plus rien', () {
    final String once = redactBlackBox(_fixture);
    expect(redactBlackBox(once), once);
  });

  test('interrupteur coupé : rien n\'est préparé', () {
    expect(prepareBlackBoxUpload(_fixture, enabled: false), isNull);
    expect(prepareBlackBoxUpload('   \n', enabled: true), isNull);
  });

  test('la clé SharedPreferences est celle de l\'interrupteur', () {
    expect(blackBoxUploadFlag.key, 'zuno.flag.blackbox_upload');
    // Avant toute lecture disque : allumé, comme les autres fonctions.
    expect(blackBoxUploadFlag.value, isTrue);
  });

  test('on ne garde que la fin, sous la limite', () {
    final String son = 'I [SON] ligne recente intacte';
    final String raw = '${'A' * 80000}\n$son';
    final String? out = prepareBlackBoxUpload(
      raw,
      enabled: true,
      maxBytes: 200,
    );
    expect(out, isNotNull);
    expect(out!.endsWith(son), isTrue);
    expect(utf8.encode(out).length <= 200, isTrue);
    expect(out.startsWith('A' * 200), isFalse);
  });

  test('la limite par défaut tient sur un gros journal', () {
    final String? out = prepareBlackBoxUpload(
      '${'B' * 200000}\n$_son',
      enabled: true,
    );
    expect(out, isNotNull);
    expect(utf8.encode(out!).length <= kBlackBoxUploadMaxBytes, isTrue);
    expect(kBlackBoxUploadMaxBytes, 32 * 1024);
    expect(out.contains('[SON]'), isTrue);
    expect(out.contains('HE-AAC'), isTrue);
  });
}
