// =========================================================
//  xtream_account_info_test.dart — Parsing user_info (player_api.php)
// =========================================================
//  Le protocole Xtream n'est pas normalisé : selon le panel, les
//  nombres arrivent en int OU en String, `exp_date` est un epoch en
//  secondes (String), parfois null/vide pour « illimité ». Le parseur
//  doit digérer tout ça sans jamais lancer.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

void main() {
  group('XtreamClient.parseAccountInfo', () {
    test('panel « tout en String » (le plus courant)', () {
      final XtreamAccountInfo info =
          XtreamClient.parseAccountInfo(<String, dynamic>{
        'status': 'Active',
        'exp_date': '1789999999',
        'max_connections': '1',
        'active_cons': '0',
      });
      expect(info.status, 'Active');
      expect(
        info.expDate,
        DateTime.fromMillisecondsSinceEpoch(1789999999 * 1000),
      );
      expect(info.maxConnections, 1);
      expect(info.activeCons, 0);
    });

    test('panel « tout en int »', () {
      final XtreamAccountInfo info =
          XtreamClient.parseAccountInfo(<String, dynamic>{
        'status': 'Expired',
        'exp_date': 1600000000,
        'max_connections': 3,
        'active_cons': 2,
      });
      expect(info.status, 'Expired');
      expect(
        info.expDate,
        DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000),
      );
      expect(info.maxConnections, 3);
      expect(info.activeCons, 2);
    });

    test('exp_date null / "null" / vide → pas de date (compte illimité)',
        () {
      for (final Object? v in <Object?>[null, 'null', '']) {
        final XtreamAccountInfo info =
            XtreamClient.parseAccountInfo(<String, dynamic>{
          'status': 'Active',
          'exp_date': v,
        });
        expect(info.expDate, isNull, reason: 'exp_date=$v');
      }
    });

    test('champs absents → tout null, aucune exception', () {
      final XtreamAccountInfo info =
          XtreamClient.parseAccountInfo(<String, dynamic>{});
      expect(info.status, isNull);
      expect(info.expDate, isNull);
      expect(info.maxConnections, isNull);
      expect(info.activeCons, isNull);
    });
  });
}
