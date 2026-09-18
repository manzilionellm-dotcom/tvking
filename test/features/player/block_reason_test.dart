// =========================================================
//  block_reason_test.dart — ne JAMAIS accuser à tort la ligne du client
// =========================================================
//  Photo client du 18/08/2026 : « Ton abonnement a expiré le 18/09/2026 »,
//  soit UN MOIS avant la date annoncée. La ligne était parfaitement valide :
//  le fournisseur servait un écran noir (placeholder), et le repli rangeait
//  ce cas dans « expiré » — l'écran formatait alors la date d'expiration,
//  future, comme si elle était passée.
//
//  Un client qui a payé et à qui l'app dit « tu as expiré » appelle le
//  support. Ces tests verrouillent la distinction.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  late StreamDiagnostics d;
  setUp(() {
    d = StreamDiagnostics.instance;
    // Session neuve : remet à zéro placeholder, HTTP et état de compte.
    d.beginSession(url: 'http://exemple.tv/live/1.ts', userAgent: 'test');
    d.recordXtreamAccount();
  });

  test('écran noir du fournisseur ≠ abonnement expiré', () {
    d.recordUpstreamPlaceholder('http://exemple.tv/black.ts');
    expect(d.blockReason, StreamBlockReason.providerBlocked);
  });

  test('une date d’expiration FUTURE ne déclenche pas « expiré »', () {
    d.recordXtreamAccount(
      status: 'Active',
      expDate: DateTime.now().add(const Duration(days: 31)),
    );
    expect(d.blockReason, isNot(StreamBlockReason.expired));
  });

  test('une date d’expiration PASSÉE déclenche bien « expiré »', () {
    d.recordXtreamAccount(
      status: 'Active',
      expDate: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(d.blockReason, StreamBlockReason.expired);
  });

  test('un compte banni prime sur tout le reste', () {
    d.recordUpstreamPlaceholder('http://exemple.tv/black.ts');
    d.recordXtreamAccount(status: 'Banned');
    expect(d.blockReason, StreamBlockReason.banned);
  });

  test('la limite de connexions prime sur l’écran noir', () {
    d.recordUpstreamPlaceholder('http://exemple.tv/black.ts');
    d.recordHttp(status: 458);
    expect(d.blockReason, StreamBlockReason.maxConnections);
  });
}
