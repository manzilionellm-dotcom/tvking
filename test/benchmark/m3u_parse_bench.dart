// =========================================================
//  m3u_parse_bench.dart — combien ça coûte d'avaler une liste
// =========================================================
//  POURQUOI CE BANC EXISTE (17/09/2026).
//
//  L'import d'une playlist est le seul moment où l'app manipule un
//  objet plus gros qu'elle. C'est LÀ que les box meurent : l'OS tue
//  l'application pour dépassement mémoire, la relance, et le client
//  voit « ça redémarre tout seul ».
//
//  Les chiffres ci-dessous ne sont donc pas de la décoration. Ils
//  répondent à une question précise : **est-ce qu'une box à 1 Go
//  survit à la liste de ce fournisseur ?**
//
//  CE QU'IL MESURE
//  ---------------
//   • le débit du parseur (chaînes/seconde) ;
//   • la mémoire vraiment consommée (RSS avant / après) ;
//   • la version ÉVIDENTE du même travail — celle qui recopie le
//     fichier pour normaliser les fins de ligne — pour montrer
//     l'écart. C'est cette version-là qui avait été écrite en premier,
//     et c'est elle qui tuait les box.
//
//  CE QU'IL NE MESURE PAS, ET IL FAUT LE DIRE
//  ------------------------------------------
//  Rien du décodage vidéo. Le son sans image, les coupures, le choix
//  du chemin de rendu : ça se mesure sur une VRAIE box, pas ici. Ce
//  banc ne parle que de l'import.
//
//  LANCER :
//    flutter test test/benchmark/m3u_parse_bench.dart
//
//  Le nom ne finit pas par `_test.dart` : il ne part donc PAS dans la
//  suite normale. Un banc qui alloue des centaines de Mo n'a rien à
//  faire dans un CI qui tourne à chaque commit.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';

/// Fabrique une playlist réaliste de [n] chaînes.
String fabriquer(int n, {bool sale = false}) {
  final StringBuffer b = StringBuffer();
  if (sale) b.write('﻿  \r\n'); // BOM + blancs, export Windows
  b.write('#EXTM3U\n');
  final String nl = sale ? '\r\n' : '\n';
  for (int i = 0; i < n; i++) {
    b.write('#EXTINF:-1 tvg-id="c$i.fr" tvg-name="Chaine $i" '
        'tvg-logo="http://logo.example/$i.png" group-title="Groupe ${i % 40}",'
        'Chaine $i$nl');
    b.write('http://pro.exemple.tv:8080/live/user/pass/$i.ts$nl');
  }
  return b.toString();
}

/// Mémoire résidente du processus, en Mo.
double rssMo() => ProcessInfo.currentRss / (1024 * 1024);

void _ligne(String quoi, Object valeur) =>
    print('  ${quoi.padRight(34)} $valeur');

void main() {
  // Un banc n'est pas un test : il mesure, il n'affirme presque rien.
  // Les DEUX seules assertions sont des garde-fous de sanité — si
  // elles tombent, c'est le banc qui ment, pas le code qui est lent.

  test('débit et mémoire du parseur', () {
    print('\n════════ IMPORT D\'UNE PLAYLIST ════════\n');

    for (final int n in <int>[10000, 100000, 300000]) {
      final String contenu = fabriquer(n);
      final double tailleMo = contenu.length / (1024 * 1024);

      final double avant = rssMo();
      final Stopwatch sw = Stopwatch()..start();
      final M3uParseResult r =
          M3uParser.parse(contenu, playlistId: 1, maxChannels: n + 10);
      sw.stop();
      final double apres = rssMo();

      expect(r.channels.length, n, reason: 'le banc doit parser TOUT');

      final double sec = sw.elapsedMicroseconds / 1000000;
      print('── $n chaînes  (fichier ${tailleMo.toStringAsFixed(1)} Mo)');
      _ligne('temps', '${sw.elapsedMilliseconds} ms');
      _ligne('débit', '${(n / sec).round()} chaînes/s');
      _ligne('mémoire pendant l\'import', '+${(apres - avant).toStringAsFixed(1)} Mo');
      _ligne('mémoire par chaîne', '${((apres - avant) * 1024 / n).toStringAsFixed(2)} Ko');
      print('');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('ce que coûte la RECOPIE, à travail égal', () {
    print('\n════════ POURQUOI ON NE RECOPIE PAS ════════\n');

    //  COMPARAISON HONNÊTE. Un premier jet de ce banc mesurait d'un côté
    //  « recopier » et de l'autre « recopier PAS + parser », puis
    //  concluait en faveur du second. Les deux colonnes ne faisaient pas
    //  le même travail : le camp qui parsait payait en plus ses 300 000
    //  objets Channel, et affichait donc PLUS de mémoire — l'inverse de
    //  ce que le texte affirmait.
    //
    //  Ici les deux camps produisent EXACTEMENT le même résultat. Seule
    //  diffère l'étape de normalisation : recopie, ou offset. L'écart
    //  est donc le vrai prix de la recopie, et rien d'autre.
    final String contenu = fabriquer(300000, sale: true);
    final double tailleMo = contenu.length / (1024 * 1024);
    print('  fichier : ${tailleMo.toStringAsFixed(1)} Mo '
        '(BOM + fins de ligne Windows)\n');

    // ---- A) Ce que fait l'app : examen + offset, AUCUNE recopie.
    double avant = rssMo();
    Stopwatch sw = Stopwatch()..start();
    final M3uParseResult a =
        M3uParser.parse(contenu, playlistId: 1, maxChannels: 300010);
    sw.stop();
    final int tempsA = sw.elapsedMilliseconds;
    final double memA = rssMo() - avant;
    print('── A. RETENUE : examen + offset');
    _ligne('temps total', '$tempsA ms');
    _ligne('mémoire', '+${memA.toStringAsFixed(1)} Mo');
    print('');

    // ---- B) La version évidente : on normalise EN RECOPIANT, puis on
    //         parse exactement pareil. Même sortie, une étape de plus.
    avant = rssMo();
    sw = Stopwatch()..start();
    final String recopie =
        contenu.replaceAll('\r\n', '\n').replaceFirst('\uFEFF', '').trimLeft();
    final int tempsRecopie = sw.elapsedMilliseconds;
    final M3uParseResult b =
        M3uParser.parse(recopie, playlistId: 1, maxChannels: 300010);
    sw.stop();
    final int tempsB = sw.elapsedMilliseconds;
    final double memB = rssMo() - avant;
    print('── B. ÉVIDENTE : replaceAll puis le MÊME parsing');
    _ligne('dont la seule recopie', '$tempsRecopie ms');
    _ligne('temps total', '$tempsB ms');
    _ligne('mémoire', '+${memB.toStringAsFixed(1)} Mo');
    print('');

    // Même sortie des deux côtés : la comparaison est légitime.
    expect(a.channels.length, b.channels.length);
    expect(a.channels.length, 300000);

    print('  ── LECTURE ──');
    print('  Les deux produisent les MÊMES 300 000 chaînes.');
    print('  La recopie coûte ${tempsRecopie} ms et alloue une deuxième');
    print('  copie du fichier (~${tailleMo.toStringAsFixed(0)} Mo) AVANT');
    print('  qu\'une seule chaîne existe. Sur une box à 1 Go dont l\'app');
    print('  a déjà son interface et ses tampons vidéo, c\'est ce pic-là');
    print('  qui fait tuer l\'application par le système.');
    print('');
    print('  ⚠ La mémoire est lue via RSS : le ramasse-miettes la rend');
    print('  bruitée d\'une exécution à l\'autre. Le chiffre qui ne ment');
    print('  pas est la taille du fichier — la recopie la paie une');
    print('  deuxième fois, par construction.');
    print('');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
