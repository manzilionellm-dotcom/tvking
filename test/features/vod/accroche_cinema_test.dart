// =========================================================
//  accroche_cinema_test.dart — Top 10 et sagas, sur de vrais noms
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (21/09/2026) : « des choses qui rendent
//  accro ». Deux règles verrouillées ici : on ne classe JAMAIS au hasard
//  (pas de note = pas de Top 10), et une saga ne se fabrique pas avec
//  « Blade Runner 2049 » ou « Apollo 13 ».
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/domain/accroche_cinema.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';

VodMovie film(String name, {String? rating, int? added}) => VodMovie(
      id: name,
      name: name,
      category: 'Films',
      streamUrl: '',
      containerExt: 'mp4',
      rating: rating,
      addedEpoch: added,
    );

void main() {
  group('noteDe — la note du catalogue, telle qu\'elle est écrite', () {
    test('formats acceptés', () {
      expect(noteDe(film('a', rating: '7.4')), 7.4);
      expect(noteDe(film('b', rating: '7,4')), 7.4);
      expect(noteDe(film('c', rating: '8/10')), 8);
    });

    test('inconnu, zéro ou absurde → null (on ne classe pas là-dessus)', () {
      expect(noteDe(film('a')), isNull);
      expect(noteDe(film('b', rating: '0')), isNull);
      expect(noteDe(film('c', rating: 'N/A')), isNull);
      expect(noteDe(film('d', rating: '57')), isNull);
    });
  });

  group('top10 — les mieux notés, les plus récents devant à note égale', () {
    test('classement et départage', () {
      final List<VodMovie> r = top10(<VodMovie>[
        film('moyen', rating: '6.1'),
        film('bon ancien', rating: '8.5', added: 100),
        film('bon récent', rating: '8.5', added: 200),
        film('sans note'),
        film('excellent', rating: '9.2'),
      ]);
      expect(r.map((VodMovie m) => m.name).toList(),
          <String>['excellent', 'bon récent', 'bon ancien', 'moyen']);
    });

    test('dix au plus, zéro si rien n\'est noté', () {
      expect(
          top10(<VodMovie>[
            for (int i = 0; i < 25; i++) film('f$i', rating: '${5 + i % 5}')
          ]).length,
          10);
      expect(top10(<VodMovie>[film('a'), film('b')]), isEmpty);
    });
  });

  group('episodeDeSaga — reconnaître un numéro, et seulement un numéro', () {
    test('les écritures des fournisseurs', () {
      expect(episodeDeSaga('Rocky 2'), (base: 'Rocky', numero: 2));
      expect(episodeDeSaga('Rocky II'), (base: 'Rocky', numero: 2));
      expect(episodeDeSaga('Fast & Furious 7'),
          (base: 'Fast & Furious', numero: 7));
      expect(episodeDeSaga('Harry Potter 3 - Le prisonnier d\'Azkaban'),
          (base: 'Harry Potter', numero: 3));
      expect(episodeDeSaga('Rocky 4 (1985)'), (base: 'Rocky', numero: 4));
      expect(episodeDeSaga('John Wick: Chapter 4'),
          (base: 'John Wick', numero: 4));
      expect(episodeDeSaga('Scream VI'), (base: 'Scream', numero: 6));
    });

    test('ce qui n\'est PAS un épisode', () {
      expect(episodeDeSaga('Blade Runner 2049'), isNull);
      expect(episodeDeSaga('2012'), isNull);
      expect(episodeDeSaga('Inception'), isNull);
      expect(episodeDeSaga(''), isNull);
    });
  });

  group('sagas — au moins trois films, rangés, le premier rattaché', () {
    test('Rocky, en vrac dans le catalogue', () {
      final List<Saga> s = sagas(<VodMovie>[
        film('Rocky IV'),
        film('Inception'),
        film('Rocky'),
        film('Rocky II'),
        film('Apollo 13'),
        film('Rocky III'),
        film('Blade Runner 2049'),
      ]);
      expect(s, hasLength(1));
      expect(s.single.titre, 'Rocky');
      expect(s.single.films.map((VodMovie m) => m.name).toList(),
          <String>['Rocky', 'Rocky II', 'Rocky III', 'Rocky IV']);
    });

    test('deux films ne font pas une saga ; la plus longue passe devant', () {
      final List<Saga> s = sagas(<VodMovie>[
        film('Taken 2'),
        film('Taken 3'),
        film('Saw 2'),
        film('Saw 3'),
        film('Saw 4'),
        film('Saw 5'),
        film('Fast & Furious 5'),
        film('Fast & Furious 6'),
        film('Fast & Furious 7'),
      ]);
      expect(s.map((Saga x) => x.titre).toList(),
          <String>['Saw', 'Fast & Furious']);
    });

    test('le doublon HD du fournisseur ne compte pas deux fois', () {
      final List<Saga> s = sagas(<VodMovie>[
        film('Saw 2'),
        film('Saw 2'),
        film('Saw 3'),
        film('Saw 4'),
      ]);
      expect(s.single.films, hasLength(3));
    });
  });
}
