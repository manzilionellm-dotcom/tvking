// =========================================================
//  lab_source_activation_test.dart — LABO DU MAÎTRE
// =========================================================
//  Régression : ajouter une source au Labo du Maître cassait l'app sur la
//  box maître. Le worker ajoute les sources labo EN FIN du tableau
//  `sources` ; l'app les importe dans l'ordre et chaque import appelle
//  setActivePlaylist → la DERNIÈRE gagnait, donc toujours le labo. La box
//  basculait sur le serveur de test et l'abonnement réel disparaissait de
//  l'accueil (getAllChannels ne rend que la playlist active).
//
//  Règle vérifiée ici : une source labo n'est activée QUE si elle est
//  seule (box maître sans abonnement — c'est le cas où coller un M3U au
//  labo doit suffire à alimenter la box).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

Map<String, dynamic> _src(String label, {String? origin}) => <String, dynamic>{
      'type': 'xtream',
      'label': label,
      'server_url': 'http://$label.example',
      'username': 'u',
      'password': 'p',
      if (origin != null) 'origin': origin,
    };

void main() {
  group('RemoteSourceRepository.shouldActivate', () {
    test('la source labo ne vole PAS l’écran à l’abonnement réel', () {
      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[
        _src('abonnement'),
        _src('ttt', origin: 'lab'),
      ];

      expect(RemoteSourceRepository.shouldActivate(all[0], all), isTrue,
          reason: 'l’abonnement réel reste la playlist active');
      expect(RemoteSourceRepository.shouldActivate(all[1], all), isFalse,
          reason: 'la source labo s’importe mais ne prend pas la main');
    });

    test('seule, la source labo alimente bien la box maître', () {
      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[
        _src('ttt', origin: 'lab'),
      ];

      expect(RemoteSourceRepository.shouldActivate(all[0], all), isTrue,
          reason: 'sans abonnement, coller un M3U au labo doit suffire');
    });

    test('plusieurs sources labo, aucun abonnement : la dernière gagne', () {
      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[
        _src('labo1', origin: 'lab'),
        _src('labo2', origin: 'lab'),
      ];

      // Aucune n'est bridée : le comportement historique (la dernière
      // importée devient active) s'applique entre sources labo.
      expect(RemoteSourceRepository.shouldActivate(all[0], all), isTrue);
      expect(RemoteSourceRepository.shouldActivate(all[1], all), isTrue);
    });

    test('box normale (aucune source labo) : comportement inchangé', () {
      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[
        _src('source1'),
        _src('source2'),
        _src('source3'),
      ];

      for (final Map<String, dynamic> s in all) {
        expect(RemoteSourceRepository.shouldActivate(s, all), isTrue,
            reason: 'le TRIO du panel garde sa règle « la dernière gagne »');
      }
    });
  });
}
