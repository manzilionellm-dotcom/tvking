import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel_genre.dart';

/// Les contrôles d'accès et le classement affiché doivent prendre la même
/// décision à partir des libellés réellement fournis, sans analyser la vidéo.
void expectAdultLabel(String name, String category, bool expected) {
  expect(
    ChannelClassifier.isAdult(name, category),
    expected,
    reason: 'nom=$name ; catégorie=$category',
  );
  expect(
    ChannelClassifier.classifyGenre(name, category) == ChannelGenre.adult,
    expected,
    reason: 'le genre affiché doit suivre la même règle adulte',
  );
}

void main() {
  group('repères adultes explicites dans le nom ou la catégorie', () {
    for (final String marker in <String>[
      '🔞',
      '🔞\uFE0F',
      '18+',
      '+18',
      '18 +',
      '+ 18',
      '18  +',
      '+  18',
      '18\u00A0+',
      '+\u00A018',
      '18\u202F+',
      '+\u202F18',
      '18\t+',
      '+\t18',
    ]) {
      test('reconnaît le repère « $marker »', () {
        expectAdultLabel('Signal [$marker] HD', 'Films', true);
        expectAdultLabel('Signal HD', 'Films [$marker]', true);
      });
    }

    test(
      'le symbole peut être collé au titre et prime sur les autres genres',
      () {
        expectAdultLabel('Découvertes🔞HD', 'Documentaires', true);
        expectAdultLabel('Kids sport', '🔞Premium', true);
      },
    );

    test('conserve les mots-clés adultes déjà reconnus', () {
      for (final String marker in <String>[
        'XXX',
        'ADULT',
        'Adultes',
        'X-RATED',
        'Érotique',
        'Dorcel',
      ]) {
        expectAdultLabel('Signal $marker', 'Films', true);
        expectAdultLabel('Signal', marker, true);
      }
    });
  });

  group('nombres et libellés ordinaires', () {
    for (final String label in <String>[
      '2018',
      '2018+',
      '2018 +',
      '+2018',
      '+ 2018',
      '218+',
      '+180',
      '18 minutes',
      '18minutes',
      'Canal 18',
      'Chaîne18',
      'Canal18HD',
      '18 chaînes',
      'Canal+18',
      'Canal+ 18',
      'Film 2018',
    ]) {
      test('ne transforme pas « $label » en contenu adulte', () {
        expectAdultLabel(label, 'Films', false);
        expectAdultLabel('Signal', label, false);
      });
    }

    test('ne concatène pas deux champs pour inventer un repère', () {
      expectAdultLabel('Canal 18', '+', false);
      expectAdultLabel('Signal +', '18', false);
    });

    test('conserve les autres genres et leur priorité', () {
      const Map<String, ChannelGenre> examples = <String, ChannelGenre>{
        'Kids sport': ChannelGenre.kids,
        'Football 18': ChannelGenre.sports,
        'News 2018': ChannelGenre.news,
        'Cinéma 2018': ChannelGenre.movies,
        'Séries 18': ChannelGenre.series,
        'Musique 18': ChannelGenre.music,
        'Documentaire 18 minutes': ChannelGenre.documentary,
        'Divertissement 18': ChannelGenre.entertainment,
        'UK 18': ChannelGenre.international,
        'Canal 18': ChannelGenre.other,
      };
      for (final MapEntry<String, ChannelGenre> example in examples.entries) {
        expectAdultLabel(example.key, '', false);
        expect(
          ChannelClassifier.classifyGenre(example.key, ''),
          example.value,
          reason: 'le changement adulte ne doit pas reclasser les autres',
        );
      }
    });
  });
}
