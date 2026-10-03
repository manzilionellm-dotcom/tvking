// =========================================================
//  audio_sources_test.dart — Qui survit au zap et au Home
// =========================================================
//  Pas de flux, pas de son. On rejoue les ouvertures que les
//  écrans déclarent, et on lit la ligne de la fiche.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/audio_sources.dart';

void main() {
  setUp(AudioSources.debugReset);

  test('la politique lue dans les écrans ne coupe pas l\'aperçu ni le téléphone', () {
    expect(AudioSources.codeStopsOnHome[AudioSources.apercu], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.telephone], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.pub], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.temoin], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.enregistrementTel], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.sonde], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.voix], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.serviceFond], isFalse);
    expect(AudioSources.codeStopsOnHome[AudioSources.pleinEcran], isTrue);
    expect(AudioSources.codeStopsOnHome[AudioSources.film], isTrue);
    expect(AudioSources.codeStopsOnHome[AudioSources.enregistrementTv], isTrue);
  });

  test('50 zaps du plein écran laissent une seule source avec du son', () {
    final int screen = AudioSources.acquire(AudioSources.pleinEcran);
    AudioSources.setPresence(screen, AudioPresence.sound);
    for (int i = 0; i < 50; i++) {
      AudioSources.markZap();
    }
    final String row = AudioSources.line();
    expect(row.contains('plein écran 1 (son)'), isTrue, reason: row);
    expect(row.contains('Sons en même temps : 1'), isTrue, reason: row);
    expect(row.contains('plusieurs sons'), isFalse, reason: row);
    expect(row.contains('Au dernier zap (n°50) : 1 avec du son (plein écran)'), isTrue, reason: row);
    expect(row.contains('http'), isFalse, reason: row);
  });

  test('Home depuis la grille : l\'aperçu a encore du son, le plein écran coupé n\'en a plus', () {
    final int preview = AudioSources.acquire(AudioSources.apercu);
    AudioSources.setPresence(preview, AudioPresence.sound);
    final int screen = AudioSources.acquire(AudioSources.pleinEcran);
    AudioSources.setPresence(screen, AudioPresence.sound);
    // Le plein écran, lui, appelle suspend : son coupé, objet gardé.
    AudioSources.setPresence(screen, AudioPresence.open);
    AudioSources.markHome();
    expect(AudioSources.lastHome, <String>['aperçu']);
    final String row = AudioSources.line();
    expect(row.contains('Au dernier Home : aperçu avait encore du son.'), isTrue, reason: row);
    expect(row.contains('plein écran 1 (ouvert, son coupé)'), isTrue, reason: row);
    expect(row.contains('aperçu 1 (son)'), isTrue, reason: row);
  });

  test('Home depuis le téléphone : le lecteur mpv n\'est pas coupé par le code', () {
    final int phone = AudioSources.acquire(AudioSources.telephone);
    AudioSources.setPresence(phone, AudioPresence.sound);
    AudioSources.markHome();
    expect(AudioSources.lastHome, <String>['téléphone']);
    expect(AudioSources.line().contains('téléphone 1 (son)'), isTrue);
  });

  test('pause du plein écran (réglage de repli) garde la piste au Home', () {
    final int screen = AudioSources.acquire(AudioSources.pleinEcran);
    AudioSources.setPresence(screen, AudioPresence.held);
    AudioSources.markHome();
    expect(AudioSources.lastHome, <String>['plein écran']);
    expect(
      AudioSources.line().contains('plein écran 1 (piste gardée)'),
      isTrue,
    );
  });

  test('aperçu + plein écran en son = plusieurs sons', () {
    AudioSources.setPresence(
      AudioSources.acquire(AudioSources.apercu),
      AudioPresence.sound,
    );
    AudioSources.setPresence(
      AudioSources.acquire(AudioSources.pleinEcran),
      AudioPresence.sound,
    );
    final String row = AudioSources.line();
    expect(row.contains('Sons en même temps : 2'), isTrue, reason: row);
    expect(row.contains('⚠ plusieurs sons'), isTrue, reason: row);
    expect(row.contains('plein écran'), isTrue, reason: row);
    expect(row.contains('aperçu'), isTrue, reason: row);
  });

  test('le témoin laissé ouvert à côté du plein écran se voit', () {
    AudioSources.onPlayerEvent(1, AudioSources.pleinEcran, 'open');
    AudioSources.onPlayerEvent(1, AudioSources.pleinEcran, 'audible');
    AudioSources.onPlayerEvent(2, AudioSources.temoin, 'open');
    AudioSources.onPlayerEvent(2, AudioSources.temoin, 'audible');
    expect(AudioSources.line().contains('⚠ plusieurs sons'), isTrue);
    AudioSources.onPlayerEvent(2, AudioSources.temoin, 'close');
    final String row = AudioSources.line();
    expect(row.contains('son témoin 0'), isTrue, reason: row);
    expect(row.contains('plusieurs sons'), isFalse, reason: row);
  });

  test('la pub encore ouverte quand le téléphone démarre fait deux sons', () {
    final int ad = AudioSources.acquire(AudioSources.pub);
    AudioSources.setPresence(ad, AudioPresence.sound);
    final int phone = AudioSources.acquire(AudioSources.telephone);
    AudioSources.setPresence(phone, AudioPresence.sound);
    expect(AudioSources.line().contains('Sons en même temps : 2'), isTrue);
    AudioSources.release(ad);
    expect(AudioSources.line().contains('pub 0'), isTrue);
    expect(AudioSources.line().contains('téléphone 1 (son)'), isTrue);
    AudioSources.release(phone);
    AudioSources.release(phone);
    expect(AudioSources.line().contains('téléphone 0'), isTrue);
  });

  test('le service de fond est un verrou, pas un second son', () {
    final int phone = AudioSources.acquire(AudioSources.telephone);
    AudioSources.setPresence(phone, AudioPresence.sound);
    final int lock = AudioSources.acquire(AudioSources.serviceFond);
    AudioSources.setPresence(lock, AudioPresence.lock);
    final String row = AudioSources.line();
    expect(row.contains('service de fond 1 (verrou, pas de son)'), isTrue, reason: row);
    expect(row.contains('Sons en même temps : 1'), isTrue, reason: row);
    AudioSources.markHome();
    expect(AudioSources.lastHome, <String>['téléphone']);
  });

  test('le micro encore ouvert au Home est nommé', () {
    final int mic = AudioSources.acquire(AudioSources.voix);
    AudioSources.setPresence(mic, AudioPresence.mic);
    AudioSources.markHome();
    expect(AudioSources.lastHome, <String>['voix']);
    expect(AudioSources.line().contains('voix 1 (micro)'), isTrue);
  });

  test('la fiche de chaîne reçoit la ligne, un journal non', () {
    AudioSources.setPresence(
      AudioSources.acquire(AudioSources.pleinEcran),
      AudioPresence.sound,
    );
    const String sheet = 'reçu : AAC-LC 48 kHz · décodé par : FFmpeg\nCodec : AAC-LC';
    final String attached = AudioSources.attach(sheet);
    expect(attached.startsWith(sheet), isTrue);
    expect(attached.contains('Sources :'), isTrue);
    expect(AudioSources.attach(attached).split('Sources :').length, 2);
    expect(AudioSources.attach('Zap : n°3'), 'Zap : n°3');
    expect(AudioSources.attach('Focus audio : obtenu.'), 'Focus audio : obtenu.');
    expect(attached.contains('http'), isFalse);
  });

  test('un silence de passage ne compte plus comme du son', () {
    AudioSources.onPlayerEvent(-1, AudioSources.apercu, 'open');
    AudioSources.onPlayerEvent(-1, AudioSources.apercu, 'audible');
    AudioSources.onPlayerEvent(-2, AudioSources.pleinEcran, 'open');
    AudioSources.onPlayerEvent(-2, AudioSources.pleinEcran, 'zap');
    AudioSources.onPlayerEvent(-1, AudioSources.apercu, 'silent');
    AudioSources.onPlayerEvent(-2, AudioSources.pleinEcran, 'audible');
    final String row = AudioSources.line();
    expect(row.contains('Sons en même temps : 1'), isTrue, reason: row);
    expect(row.contains('aperçu 1 (ouvert, son coupé)'), isTrue, reason: row);
  });
}
