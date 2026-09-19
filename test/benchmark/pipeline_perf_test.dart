// =========================================================
//  pipeline_perf_test.dart — Banc de la CHAÎNE DE DONNÉES (charge box)
// =========================================================
//  « Fais un benchmark exhaustif » (propriétaire, 19/09/2026).
//
//  CE QUE CE FICHIER MESURE : le coût, en millisecondes et en Mo, des
//  deux traitements qui précèdent TOUTE lecture — lire une liste M3U et
//  lire un guide XMLTV. C'est ce qu'une box fait au premier lancement
//  et à chaque synchronisation, et c'est là que les box à 1 Go
//  s'étouffent quand un fournisseur envoie 60 000 chaînes.
//
//  CE QU'IL NE MESURE PAS : la vidéo, le réseau, le décodage. Ça se
//  mesure sur une box, par la Boîte noire (banc_essai.dart), pas ici.
//
//  RÈGLE (même que smart_search_perf_test.dart) : on publie le chiffre
//  BRUT + la machine. Une CI est 5 à 15× plus rapide qu'une box à 30 € ;
//  le seuil appliqué ici est donc le budget box divisé par 10.
//  Le propriétaire juge lui-même.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/epg_import_stats.dart';
import 'package:tv_king/features/epg/data/xmltv_parser.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

/// Budget BOX : 60 000 chaînes doivent être lues en moins de 6 s (le
/// client attend devant l'écran « Import »). Divisé par 10 pour la CI.
const int kCiBudgetM3uMs = 600;

/// Budget BOX : 100 000 programmes (≈ 2 000 chaînes × 48 h) en moins de
/// 20 s de synchronisation silencieuse. Divisé par 10 pour la CI.
const int kCiBudgetXmltvMs = 2000;

String _machine() => <String>[
      Platform.localHostname,
      Platform.operatingSystem,
      Platform.numberOfProcessors.toString() + ' cœurs',
    ].join(' · ');

/// Une liste M3U réaliste : tvg-id, logo, groupe, noms variés, URLs
/// Xtream — c'est la forme que 95 % des fournisseurs envoient.
String _m3u(int n) {
  final StringBuffer b = StringBuffer('#EXTM3U\n');
  const List<String> groupes = <String>[
    'FRANCE', 'SPORT', 'BEIN SPORTS', 'CINEMA', 'ENFANTS', 'ARABE',
    'UK', 'USA', 'DOCUMENTAIRE', 'MUSIQUE',
  ];
  for (int i = 0; i < n; i++) {
    final String g = groupes[i % groupes.length];
    b.write('#EXTINF:-1 tvg-id="chan$i.fr" tvg-name="Chaine $i HD" '
        'tvg-logo="http://logos.example.com/$i.png" group-title="$g",'
        '${i % 7 == 0 ? 'beIN SPORTS ${i % 9 + 1} FHD' : 'Chaine $i HD'}\n');
    b.write('http://srv.example.com:8080/user/pass/$i.ts\n');
  }
  return b.toString();
}

/// Un XMLTV réaliste : [chaines] chaînes, un programme toutes les 30 min
/// sur 48 h dans la fenêtre gardée, titres + descriptions.
String _xmltv({required int chaines, required int slotsParChaine}) {
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  final DateTime base = DateTime.now().toUtc();
  String fmt(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}00 +0000';
  for (int c = 0; c < chaines; c++) {
    b.write('<channel id="chan$c.fr"><display-name>Chaine $c</display-name>'
        '</channel>');
  }
  for (int c = 0; c < chaines; c++) {
    for (int s = 0; s < slotsParChaine; s++) {
      final DateTime start = base.add(Duration(minutes: 30 * s));
      final DateTime stop = start.add(const Duration(minutes: 30));
      b.write('<programme start="${fmt(start)}" stop="${fmt(stop)}" '
          'channel="chan$c.fr"><title lang="fr">Emission $s</title>'
          '<desc lang="fr">Description un peu longue du programme $s '
          'de la chaine $c, comme en envoient les fournisseurs.</desc>'
          '<category lang="fr">Divertissement</category></programme>');
    }
  }
  b.write('</tv>');
  return b.toString();
}

Stream<List<int>> _parMorceaux(List<int> bytes, {int size = 64 * 1024}) async* {
  for (int i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  test('M3U 60 000 chaînes : ms, chaînes/s, Mo — chiffre brut + machine', () {
    final String contenu = _m3u(60000);
    final int poidsMo = utf8.encode(contenu).length ~/ (1024 * 1024);
    // Échauffement (JIT) puis mesure.
    M3uParser.parse(contenu, playlistId: 1, maxChannels: 100000);
    final Stopwatch sw = Stopwatch()..start();
    final M3uParseResult r =
        M3uParser.parse(contenu, playlistId: 1, maxChannels: 100000);
    sw.stop();
    final int ms = sw.elapsedMilliseconds;
    final int parSeconde = ms == 0 ? 0 : (r.channels.length * 1000 ~/ ms);
    // (Pas de mesure RSS ici : le ramasse-miettes rend un delta de RSS
    //  entre deux instants aussi souvent négatif que positif — un chiffre
    //  qu'on ne peut pas lire n'a pas sa place dans un banc.)
    // ignore: avoid_print
    print('[BANC M3U] ${r.channels.length} chaînes ($poidsMo Mo) en $ms ms '
        '→ $parSeconde chaînes/s · ${_machine()}');
    expect(r.channels.length, 60000);
    expect(ms, lessThan(kCiBudgetM3uMs),
        reason: 'au-delà de $kCiBudgetM3uMs ms en CI (≈ 6 s sur box), '
            'l\'écran Import devient une attente visible');
  });

  test('XMLTV 100 000 programmes : ms, programmes/s — chiffre brut + machine',
      () async {
    // 2 000 chaînes × 50 créneaux de 30 min ≈ 25 h dans la fenêtre 48 h.
    final List<int> bytes =
        utf8.encode(_xmltv(chaines: 2000, slotsParChaine: 50));
    final int poidsMo = bytes.length ~/ (1024 * 1024);
    int n = 0;
    final Stopwatch sw = Stopwatch()..start();
    final EpgParseStats stats = await XmltvParser.parse(
      _parMorceaux(bytes),
      onProgram: (EpgProgram p) async {
        n++;
      },
    );
    sw.stop();
    final int ms = sw.elapsedMilliseconds;
    final int parSeconde = ms == 0 ? 0 : (n * 1000 ~/ ms);
    // ignore: avoid_print
    print('[BANC XMLTV] $n programmes ($poidsMo Mo, ${stats.emitted} émis) '
        'en $ms ms → $parSeconde programmes/s · ${_machine()}');
    expect(n, 100000);
    expect(ms, lessThan(kCiBudgetXmltvMs),
        reason: 'au-delà de $kCiBudgetXmltvMs ms en CI (≈ 20 s sur box), '
            'la synchronisation EPG chevauche la lecture');
  });
}
