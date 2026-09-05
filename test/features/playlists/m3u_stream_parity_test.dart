// =========================================================
//  m3u_stream_parity_test.dart — Les deux chemins d'import
//  produisent EXACTEMENT la même chose
// =========================================================
//  POURQUOI CE TEST EXISTE (05/09/2026).
//
//  Il y a désormais deux façons d'importer une playlist :
//
//   • M3uParser.parse(String)        — le chemin historique
//   • M3uParser.parseStream(octets)  — le chemin du MILLION
//
//  Mesuré sur un vrai M3U d'un million d'entrées (204 Mo) :
//  480 Mo de pic mémoire pour l'ancien, 1 Mo pour le nouveau.
//
//  LE RISQUE QUE CE TEST COUVRE. Deux implémentations d'un même
//  parseur DIVERGENT. Pas tout de suite : au premier attribut ajouté,
//  au premier cas tordu corrigé d'un seul côté. Et la divergence est
//  SILENCIEUSE — l'import marche, il produit simplement des chaînes
//  différentes selon le chemin emprunté. Le client voit une catégorie
//  qui change de nom, un logo qui disparaît, un film classé en direct.
//
//  Ce test compare les deux sorties CHAMP PAR CHAMP sur les cas
//  tordus du monde réel. S'ils divergent, il le dit tout de suite.
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

/// Résumé d'une chaîne, tous champs qui comptent. On compare des
/// chaînes de caractères : le message d'échec montre alors CE QUI
/// diffère, au lieu d'un « Channel != Channel » illisible.
String empreinte(Channel c) => <String>[
      c.id,
      c.name,
      c.category,
      c.streamUrl,
      c.logoUrl ?? '-',
      c.isLive ? 'live' : 'vod',
      c.catchupSupported ? 'catchup' : '-',
      '${c.catchupDays ?? '-'}',
      c.catchupSource ?? '-',
    ].join('|');

Future<List<Channel>> viaFlux(String contenu, {int playlistId = 7}) async {
  final List<Channel> out = <Channel>[];
  final Stream<List<int>> octets = Stream<List<int>>.fromIterable(
    // On découpe en petits blocs EXPRÈS : dans la vraie vie les octets
    // arrivent par paquets réseau, et une ligne est souvent coupée en
    // deux. Un parseur qui ne testerait qu'un bloc unique raterait ce
    // cas — qui est le plus fréquent de tous.
    _blocs(utf8.encode(contenu), 64),
  );
  await for (final List<Channel> lot
      in M3uParser.parseStream(octets, playlistId: playlistId)) {
    out.addAll(lot);
  }
  return out;
}

Iterable<List<int>> _blocs(List<int> data, int taille) sync* {
  for (int i = 0; i < data.length; i += taille) {
    yield data.sublist(i, i + taille > data.length ? data.length : i + taille);
  }
}

void main() {
  group('parse et parseStream sont d’accord', () {
    // Chaque cas est un piège réel rencontré dans des playlists du
    // marché. Le nom du cas dit ce qui est testé.
    const Map<String, String> cas = <String, String>{
      'M3U_PLUS complet': '''
#EXTM3U
#EXTINF:-1 tvg-id="tf1.fr" tvg-name="TF1" tvg-logo="http://x/tf1.png" group-title="FRANCE",TF1 FHD
http://serveur.tv:8080/u/p/1.ts
#EXTINF:-1 tvg-id="m6.fr" tvg-logo="http://x/m6.png" group-title="FRANCE",M6
http://serveur.tv:8080/u/p/2.ts
''',
      'sans en-tête #EXTM3U': '''
#EXTINF:-1 group-title="SPORT",Canal Sport
http://serveur.tv:8080/u/p/3.ts
''',
      'URLs nues (M3U simple)': '''
#EXTM3U
http://serveur.tv:8080/u/p/10.ts
http://serveur.tv:8080/u/p/11.ts
''',
      '#EXTGRP sur ligne séparée': '''
#EXTM3U
#EXTGRP:DOCUMENTAIRES
http://serveur.tv:8080/u/p/20.ts
''',
      'directives à ignorer': '''
#EXTM3U
#EXTVLCOPT:network-caching=1000
#KODIPROP:inputstream=ffmpeg
#EXTINF:-1 group-title="TEST",Chaine A
http://serveur.tv:8080/u/p/30.ts
''',
      'nom vide → repli': '''
#EXTM3U
#EXTINF:-1 group-title="X",
http://serveur.tv:8080/u/p/40.ts
''',
      'film VOD (.mkv)': '''
#EXTM3U
#EXTINF:-1 group-title="VOD | ACTION",Le Film
http://serveur.tv:8080/movie/u/p/50.mkv
''',
      'catchup + rattrapage': '''
#EXTM3U
#EXTINF:-1 catchup="default" catchup-days="7" catchup-source="http://x/{start}" group-title="FR",Rattrapage
http://serveur.tv:8080/u/p/60.ts
''',
      'lignes vides et espaces': '''
#EXTM3U

#EXTINF:-1 group-title="A",Un

http://serveur.tv:8080/u/p/70.ts

''',
      'ligne de bruit (pas une URL)': '''
#EXTM3U
#EXTINF:-1 group-title="A",Un
ceci n est pas une url
#EXTINF:-1 group-title="A",Deux
http://serveur.tv:8080/u/p/80.ts
''',
      'sauts de ligne Windows': '#EXTM3U\r\n'
          '#EXTINF:-1 group-title="FR",Windows\r\n'
          'http://serveur.tv:8080/u/p/90.ts\r\n',
    };

    for (final MapEntry<String, String> e in cas.entries) {
      test(e.key, () async {
        final List<Channel> direct =
            M3uParser.parse(e.value, playlistId: 7).channels;
        final List<Channel> flux = await viaFlux(e.value);
        expect(flux.map(empreinte).toList(), direct.map(empreinte).toList(),
            reason: 'les deux chemins d\'import divergent sur « ${e.key} »');
      });
    }
  });

  test('le plafond mémoire est respecté par les DEUX chemins', () async {
    final StringBuffer b = StringBuffer('#EXTM3U\n');
    for (int i = 0; i < 50; i++) {
      b.writeln('#EXTINF:-1 group-title="G",Chaine $i');
      b.writeln('http://serveur.tv:8080/u/p/$i.ts');
    }
    final String contenu = b.toString();

    final List<Channel> direct =
        M3uParser.parse(contenu, playlistId: 1, maxChannels: 10).channels;
    expect(direct.length, 10);

    final List<Channel> flux = <Channel>[];
    await for (final List<Channel> lot in M3uParser.parseStream(
      Stream<List<int>>.fromIterable(_blocs(utf8.encode(contenu), 128)),
      playlistId: 1,
      maxChannels: 10,
    )) {
      flux.addAll(lot);
    }
    // Le plafond protège les petites box : sans lui, une source géante
    // fait planter l'app en boucle, ce dont on ne se relève pas.
    expect(flux.length, 10);
    expect(flux.map(empreinte).toList(), direct.map(empreinte).toList());
  });

  test('les paquets sont bien découpés et rien ne se perd', () async {
    final StringBuffer b = StringBuffer('#EXTM3U\n');
    for (int i = 0; i < 250; i++) {
      b.writeln('#EXTINF:-1 group-title="G",Chaine $i');
      b.writeln('http://serveur.tv:8080/u/p/$i.ts');
    }
    final List<int> tailles = <int>[];
    int total = 0;
    await for (final List<Channel> lot in M3uParser.parseStream(
      Stream<List<int>>.fromIterable(_blocs(utf8.encode(b.toString()), 512)),
      playlistId: 1,
      tailleLot: 100,
    )) {
      tailles.add(lot.length);
      total += lot.length;
    }
    // 250 chaînes en lots de 100 → 100, 100, 50. Le dernier lot PARTIEL
    // doit sortir : l'oublier ferait perdre les dernières chaînes de
    // toute playlist dont le total n'est pas un multiple du lot.
    expect(tailles, <int>[100, 100, 50]);
    expect(total, 250);
  });
}
