// =========================================================
//  block_reason_account_scope_test.dart — deux lignes, deux verdicts
// =========================================================
//  Journal terrain du 20/08, 20:32:32.403 → .755 : la box portait DEUX
//  comptes Xtream — l'un ACTIF (expire 18/09), l'autre EXPIRÉ (01/08).
//  Trois contrôles de compte entremêlés en 400 ms, et la boîte noire
//  (singleton) gardait le DERNIER écrit : « Expired ». Conséquence :
//  _abortIfLineDead (relais) lisait ce verdict GLOBAL et pouvait couper
//  les reconnexions d'un flux appartenant au compte ACTIF, avec le
//  message « abonnement expiré » — faux, et un appel au support garanti.
//
//  Ces tests verrouillent le correctif : les signaux de NIVEAU COMPTE
//  (banni / expiré / compteur active-max) ne s'appliquent qu'aux flux du
//  compte contrôlé (même hôte + même utilisateur) ; les signaux de
//  SESSION (458 vu par le relais, écran noir placeholder) s'appliquent
//  toujours, car ils viennent du flux lui-même.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  late StreamDiagnostics d;
  setUp(() {
    d = StreamDiagnostics.instance;
    // Session neuve : remet à zéro placeholder, HTTP et état de compte
    // (recordXtreamAccount sans argument efface AUSSI l'identité).
    d.beginSession(url: 'http://ligne-a.tv/live/1.ts', userAgent: 'test');
    d.recordXtreamAccount();
  });

  test('le compte EXPIRÉ d\'une AUTRE ligne ne condamne pas le flux de la '
      'ligne active (hôtes différents)', () {
    d.recordXtreamAccount(
      status: 'Expired',
      serverHost: 'ligne-b.tv',
      username: 'userB',
    );
    expect(
      d.blockReasonForUrl('http://ligne-a.tv/userA/passA/1924346.ts'),
      StreamBlockReason.none,
      reason: 'le flux joue sur ligne-a.tv : le « Expired » contrôlé sur '
          'ligne-b.tv ne le concerne pas (c\'était la coupure à tort du 20/08)',
    );
  });

  test('le compte EXPIRÉ s\'applique bien à SES PROPRES flux', () {
    d.recordXtreamAccount(
      status: 'Expired',
      serverHost: 'ligne-b.tv',
      username: 'userB',
    );
    expect(
      d.blockReasonForUrl('http://ligne-b.tv/userB/passB/42.ts'),
      StreamBlockReason.expired,
    );
  });

  test('même hôte mais UTILISATEUR différent = autre ligne : le verdict '
      'compte ne s\'applique pas', () {
    d.recordXtreamAccount(
      status: 'Expired',
      serverHost: 'panel.tv',
      username: 'expire01',
    );
    expect(
      d.blockReasonForUrl('http://panel.tv/live/actif02/pass/7.ts'),
      StreamBlockReason.none,
    );
    expect(
      d.blockReasonForUrl('http://panel.tv/live/expire01/pass/7.ts'),
      StreamBlockReason.expired,
    );
  });

  test('identité INCONNUE (ancien appelant) → comportement historique : '
      'le verdict compte s\'applique à tout flux', () {
    d.recordXtreamAccount(status: 'Expired');
    expect(
      d.blockReasonForUrl('http://nimporte.tv/u/p/1.ts'),
      StreamBlockReason.expired,
    );
  });

  test('le 458 est un signal de SESSION : il s\'applique même si le compte '
      'contrôlé est celui d\'une autre ligne', () {
    d.recordXtreamAccount(
      status: 'Active',
      serverHost: 'ligne-b.tv',
      username: 'userB',
    );
    d.recordHttp(status: 458);
    expect(
      d.blockReasonForUrl('http://ligne-a.tv/userA/passA/1.ts'),
      StreamBlockReason.maxConnections,
    );
  });

  test('l\'écran noir placeholder reste un signal de session lui aussi', () {
    d.recordXtreamAccount(
      status: 'Expired',
      serverHost: 'ligne-b.tv',
      username: 'userB',
    );
    d.recordUpstreamPlaceholder('http://ligne-a.tv/black.ts');
    expect(
      d.blockReasonForUrl('http://ligne-a.tv/userA/passA/1.ts'),
      StreamBlockReason.providerBlocked,
      reason: 'pas de faux « expiré » : le compte expiré est celui d\'une '
          'autre ligne, mais l\'écran noir, lui, est bien servi sur CE flux',
    );
  });

  test('blockReason (global, sans URL) garde son comportement historique', () {
    d.recordXtreamAccount(
      status: 'Expired',
      serverHost: 'ligne-b.tv',
      username: 'userB',
    );
    expect(d.blockReason, StreamBlockReason.expired);
  });
}
