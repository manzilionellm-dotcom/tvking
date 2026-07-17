// =========================================================
//  epg_alias_short_epg_test.dart — Pont EPG Xtream + EPG courte
// =========================================================
//  Bug terrain (capture client 2026-07-17, « Programme non disponible »
//  sous l'aperçu En direct) : le XMLTV du panel identifie ses chaînes
//  par `epg_channel_id` (« TF1.fr ») alors que les chaînes Xtream de
//  l'app s'appellent `xtream-<stream_id>` → AUCUN programme importé ne
//  matchait jamais une chaîne (la boîte noire montrait import_ok avec
//  count=0 et known élevé). Ces tests verrouillent :
//    1. la COLLECTE des alias pendant l'import (`epgChannelAliases`) ;
//    2. la FUSION du filtre parseur (jamais d'élargissement sauvage) ;
//    3. le REMAP d'une ligne programme vers l'id de sa chaîne ;
//    4. le parsing pur de `get_short_epg` (repli de l'aperçu).
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

MockClient _server() {
  return MockClient((http.Request req) async {
    final String action = req.url.queryParameters['action'] ?? '';
    Object body;
    switch (action) {
      case 'get_live_categories':
        body = <Object>[
          <String, Object>{'category_id': '7', 'category_name': 'Généraliste'},
        ];
      case 'get_live_streams':
        body = <Object>[
          <String, Object>{
            'stream_id': 42,
            'name': 'TF1 RAW',
            'category_id': '7',
            'epg_channel_id': 'TF1.fr',
          },
          <String, Object>{
            'stream_id': 43,
            'name': 'Sans EPG',
            'category_id': '7',
            // pas d'epg_channel_id → aucun alias attendu
          },
          <String, Object>{
            'stream_id': 44,
            'name': 'EPG vide',
            'category_id': '7',
            'epg_channel_id': '  ', // blancs seulement → ignoré
          },
        ];
      default:
        body = <String, Object?>{
          'user_info': <String, Object>{'auth': 1, 'status': 'Active'},
        };
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

void main() {
  group('collecte des alias EPG pendant l\'import Xtream', () {
    test('epg_channel_id → xtream-<stream_id> ; vides/absents ignorés',
        () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _server(),
      );
      final List<Channel> channels = await c.fetchLiveChannels(playlistId: 1);
      expect(channels, hasLength(3));
      expect(c.epgChannelAliases, <String, String>{'TF1.fr': 'xtream-42'});
    });
  });

  group('EpgRepository.mergeKnownWithAliases', () {
    test('ajoute les ids EPG des seules chaînes du filtre', () {
      final Set<String>? merged = EpgRepository.mergeKnownWithAliases(
        <String>{'xtream-42', 'm3u-tvg-id'},
        <String, String>{
          'TF1.fr': 'xtream-42', // chaîne connue → alias accepté
          'M6.fr': 'xtream-99', // chaîne HORS filtre → refusé
        },
      );
      expect(merged, <String>{'xtream-42', 'm3u-tvg-id', 'TF1.fr'});
    });

    test('sans filtre (null) → reste null ; sans alias → filtre inchangé', () {
      expect(
        EpgRepository.mergeKnownWithAliases(
            null, <String, String>{'TF1.fr': 'xtream-42'}),
        isNull,
      );
      final Set<String> known = <String>{'a'};
      expect(
        EpgRepository.mergeKnownWithAliases(known, <String, String>{}),
        same(known),
      );
    });
  });

  group('EpgRepository.remapProgramRow', () {
    test('alias → id de chaîne ; id canonique → inchangé', () {
      final Map<String, String> aliases = <String, String>{
        'TF1.fr': 'xtream-42',
      };
      final Map<String, Object?> aliased = <String, Object?>{
        'channel_id': 'TF1.fr',
        'title': 'JT 20h',
      };
      final Map<String, Object?> canonical = <String, Object?>{
        'channel_id': 'm3u-tvg-id',
        'title': 'Météo',
      };
      expect(EpgRepository.remapProgramRow(aliased, aliases)['channel_id'],
          'xtream-42');
      // La ligne d'origine n'est pas mutée (copie défensive).
      expect(aliased['channel_id'], 'TF1.fr');
      expect(EpgRepository.remapProgramRow(canonical, aliases),
          same(canonical));
    });
  });

  group('parseShortEpgListings (get_short_epg — parsing pur)', () {
    String b64(String s) => base64Encode(utf8.encode(s));

    test('titres/descriptions base64, timestamps String → programmes triés',
        () {
      final Map<String, Object?> payload = <String, Object?>{
        'epg_listings': <Object>[
          <String, Object?>{
            // Volontairement APRÈS l'autre pour vérifier le tri.
            'title': b64('Le Film du soir'),
            'description': b64('Un classique.'),
            'start_timestamp': '1752762600',
            'stop_timestamp': '1752769800',
          },
          <String, Object?>{
            'title': b64('JT 20h'),
            'description': '',
            'start_timestamp': '1752760800',
            'stop_timestamp': '1752762600',
          },
        ],
      };
      final List<EpgProgram> out =
          XtreamClient.parseShortEpgListings(payload, 'xtream-42');
      expect(out, hasLength(2));
      expect(out.first.title, 'JT 20h');
      expect(out.first.channelId, 'xtream-42');
      expect(out.first.startTime, 1752760800 * 1000);
      expect(out.first.description, isNull); // description vide → null
      expect(out.last.title, 'Le Film du soir');
      expect(out.last.description, 'Un classique.');
    });

    test('titre en CLAIR (panel sans base64) conservé tel quel', () {
      final List<EpgProgram> out = XtreamClient.parseShortEpgListings(
        <String, Object?>{
          'epg_listings': <Object>[
            <String, Object?>{
              'title': 'Journal télévisé', // espace+accent : pas du base64
              'start_timestamp': 1752760800,
              'stop_timestamp': 1752762600,
            },
          ],
        },
        'xtream-42',
      );
      expect(out.single.title, 'Journal télévisé');
    });

    test('entrées invalides ignorées une à une, jamais d\'exception', () {
      final List<EpgProgram> out = XtreamClient.parseShortEpgListings(
        <String, Object?>{
          'epg_listings': <Object?>[
            'pas un objet',
            <String, Object?>{'title': b64('Sans horaires')},
            <String, Object?>{
              // stop <= start → rejeté
              'title': b64('Horaires inversés'),
              'start_timestamp': 1752762600,
              'stop_timestamp': 1752762600,
            },
            <String, Object?>{
              // titre vide après décodage → rejeté
              'title': '',
              'start_timestamp': 1752760800,
              'stop_timestamp': 1752762600,
            },
            <String, Object?>{
              'title': b64('Le seul valide'),
              'start_timestamp': 1752760800,
              'stop_timestamp': 1752762600,
            },
          ],
        },
        'xtream-42',
      );
      expect(out.single.title, 'Le seul valide');
    });

    test('réponses hors contrat (Map sans listings, null, String) → []', () {
      expect(XtreamClient.parseShortEpgListings(
          <String, Object?>{'error': 'x'}, 'xtream-42'), isEmpty);
      expect(XtreamClient.parseShortEpgListings(null, 'xtream-42'), isEmpty);
      expect(XtreamClient.parseShortEpgListings('HTML', 'xtream-42'), isEmpty);
    });
  });
}
