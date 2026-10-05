// =========================================================
//  panel_visibility_test.dart — Interrupteur allumé / éteint du panel
// =========================================================
//  Adresses factices. On teste la décision pure : quoi masquer,
//  quoi réafficher, quoi laisser au choix du client.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

Map<String, dynamic> _x(String user, {bool? enabled}) => <String, dynamic>{
      'type': 'xtream',
      'server_url': 'http://srv.example.invalid:8080/',
      'username': user,
      'password': 'p',
      if (enabled != null) 'enabled': enabled,
    };

const String _fpA = 'xtream|http://srv.example.invalid:8080|a';

void main() {
  test('le panel éteint une liste : la box la masque, une seule fois', () {
    final PanelVisibilityPlan p1 = planPanelVisibility(
      served: <Map<String, dynamic>>[_x('a', enabled: false), _x('b')],
      applied: const <String, bool>{},
    );
    expect(p1.apply, <String, bool>{_fpA: false});
    expect(p1.nextApplied, <String, bool>{_fpA: false});

    // Tour suivant, rien n'a changé : on ne retouche rien.
    final PanelVisibilityPlan p2 = planPanelVisibility(
      served: <Map<String, dynamic>>[_x('a', enabled: false), _x('b')],
      applied: p1.nextApplied,
    );
    expect(p2.apply, isEmpty);
  });

  test('le panel rallume : la box réaffiche, puis oublie', () {
    final PanelVisibilityPlan p = planPanelVisibility(
      served: <Map<String, dynamic>>[_x('a', enabled: true)],
      applied: const <String, bool>{_fpA: false},
    );
    expect(p.apply, <String, bool>{_fpA: true});
    expect(p.nextApplied, isEmpty);
  });

  test('champ absent = allumée, mais une liste masquée par le CLIENT reste masquée', () {
    final PanelVisibilityPlan p = planPanelVisibility(
      served: <Map<String, dynamic>>[_x('a')],
      applied: const <String, bool>{},
    );
    expect(p.apply, isEmpty, reason: 'le panel ne l\'a jamais éteinte : choix du client respecté');
  });

  test('liste plus envoyée : oubliée (son effacement est géré ailleurs)', () {
    final PanelVisibilityPlan p = planPanelVisibility(
      served: const <Map<String, dynamic>>[],
      applied: const <String, bool>{_fpA: false},
    );
    expect(p.apply, isEmpty);
    expect(p.nextApplied, isEmpty);
  });

  test('élément illisible ignoré', () {
    final PanelVisibilityPlan p = planPanelVisibility(
      served: <Map<String, dynamic>>[<String, dynamic>{'type': 'm3u'}, <String, dynamic>{}],
      applied: const <String, bool>{},
    );
    expect(p.apply, isEmpty);
  });
}
