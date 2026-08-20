// =========================================================
//  line_occupancy_probe_test.dart — le verdict « qui tient la ligne ? »
// =========================================================
//  Terrain 20/08 : « 1/1 » persistant alors que l'app ferme tout en ms.
//  La sonde lit les compteurs réels du compte pendant que CETTE TV n'a
//  aucune connexion, et tranche : libérée (linger du panel) vs occupée
//  en continu (autre appareil). Ces tests verrouillent les deux verdicts,
//  avec un faux XtreamClient (aucun réseau).
// =========================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/line_occupancy_probe.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

/// Faux client : renvoie les compteurs d'une file scriptée, sans réseau.
class _FakeXtreamClient extends XtreamClient {
  _FakeXtreamClient(this._script)
      : super(
          serverUrl: 'http://fake.invalid',
          username: 'u',
          password: 'p',
        );
  final List<XtreamAccountInfo> _script;
  int _i = 0;

  @override
  Future<XtreamAccountInfo> fetchAccountInfo() async {
    final XtreamAccountInfo info =
        _script[_i < _script.length ? _i : _script.length - 1];
    _i++;
    return info;
  }
}

void main() {
  const Duration fast = Duration(milliseconds: 1);

  test('libérée : active_cons tombe à 0 → outcome.freed avec le délai', () async {
    final _FakeXtreamClient client = _FakeXtreamClient(<XtreamAccountInfo>[
      const XtreamAccountInfo(status: 'Active', maxConnections: 1, activeCons: 1),
      const XtreamAccountInfo(status: 'Active', maxConnections: 1, activeCons: 1),
      const XtreamAccountInfo(status: 'Active', maxConnections: 1, activeCons: 0),
    ]);
    final LineProbeReport r = await LineOccupancyProbe.run(
      client: client,
      total: const Duration(seconds: 10),
      interval: fast,
    );
    expect(r.outcome, LineProbeOutcome.freed);
    expect(r.freedAfter, isNotNull);
    expect(r.lastActive, 0);
  });

  test('occupée en continu → outcome.neverFreed', () async {
    final _FakeXtreamClient client = _FakeXtreamClient(<XtreamAccountInfo>[
      const XtreamAccountInfo(status: 'Active', maxConnections: 1, activeCons: 1),
    ]);
    final LineProbeReport r = await LineOccupancyProbe.run(
      client: client,
      total: const Duration(milliseconds: 6),
      interval: fast,
    );
    expect(r.outcome, LineProbeOutcome.neverFreed);
    expect(r.lastActive, 1);
  });

  test('panel sans active_cons → outcome.apiUnavailable', () async {
    final _FakeXtreamClient client = _FakeXtreamClient(<XtreamAccountInfo>[
      const XtreamAccountInfo(status: 'Active', maxConnections: 1),
    ]);
    final LineProbeReport r = await LineOccupancyProbe.run(
      client: client,
      total: const Duration(seconds: 10),
      interval: fast,
    );
    expect(r.outcome, LineProbeOutcome.apiUnavailable);
  });

  test('annulation → apiUnavailable sans boucler', () async {
    final _FakeXtreamClient client = _FakeXtreamClient(<XtreamAccountInfo>[
      const XtreamAccountInfo(status: 'Active', maxConnections: 1, activeCons: 1),
    ]);
    final LineProbeReport r = await LineOccupancyProbe.run(
      client: client,
      total: const Duration(minutes: 3),
      interval: fast,
      isCancelled: () => true,
    );
    expect(r.outcome, LineProbeOutcome.apiUnavailable);
  });
}
