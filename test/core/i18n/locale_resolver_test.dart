// Test — LA RÈGLE DE LANGUE, partagée par la TV, le PC et le téléphone.
//
// Signalé par le propriétaire : « l'app Windows ne traduit pas les
// langues automatiquement ». Le scénario 3 ci-dessous EST ce bug ; il
// échoue avec l'ancienne logique (« ne regarder que la première langue
// du système ») et passe avec la nouvelle.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/i18n/locale_resolver.dart';

void main() {
  // Les 8 langues réellement livrées, dans l'ordre du projet.
  const List<Locale> livrees = <Locale>[
    Locale('fr'), Locale('en'), Locale('es'), Locale('sv'),
    Locale('da'), Locale('nb'), Locale('ar'), Locale('sw'),
  ];

  group('resolveAppLocale', () {
    test('le choix explicite de l\'utilisateur passe avant tout', () {
      // Même si le système réclame l'espagnol : Réglages a dit suédois.
      expect(
        resolveAppLocale(
          forced: const Locale('sv'),
          preferred: const <Locale>[Locale('es', 'ES')],
          supported: livrees,
        ),
        const Locale('sv'),
      );
    });

    test('sans choix explicite, on suit la langue du système', () {
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[Locale('es', 'MX')],
          supported: livrees,
        ),
        const Locale('es'),
      );
    });

    // ================= LE DÉFAUT PC, REJOUÉ =================
    test('une langue système inconnue n\'écrase plus la suivante, '
        'qui est connue', () {
      // LE CŒUR DU CORRECTIF. Un PC déclare une LISTE de langues ; une
      // box Android n'en déclare qu'une. L'ancien code ne lisait que la
      // première : ici il aurait vu le polonais, qu'on ne traduit pas,
      // et serait tombé sur l'anglais — en ignorant le français, pourtant
      // demandé juste après et parfaitement disponible.
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[Locale('pl', 'PL'), Locale('fr', 'FR')],
          supported: livrees,
        ),
        const Locale('fr'),
      );
    });

    test('on descend aussi loin qu\'il faut dans la liste', () {
      // Trois langues non traduites avant la bonne : on ne s'arrête pas
      // en chemin.
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[
            Locale('pl'), Locale('ja'), Locale('ko'), Locale('sw', 'KE'),
          ],
          supported: livrees,
        ),
        const Locale('sw'),
      );
    });

    test('l\'ordre du système est respecté : la 1re langue connue gagne',
        () {
      // On ne parcourt pas la liste pour prendre n'importe laquelle : la
      // préférence de l'utilisateur reste l'ordre du système.
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[Locale('es', 'ES'), Locale('fr', 'FR')],
          supported: livrees,
        ),
        const Locale('es'),
      );
    });

    test('aucune langue système connue → anglais, JAMAIS l\'arabe', () {
      // Régression historique : la liste générée commence par l'arabe, et
      // un repli naïf mettait « tout le monde en arabe ».
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[Locale('pl'), Locale('ja')],
          supported: livrees,
        ),
        const Locale('en'),
      );
    });

    test('même repli partout : écran et notifications ne peuvent plus '
        'diverger', () {
      // Avant, l'écran repliait sur l'anglais et les textes hors widgets
      // sur le français. Un seul appel = une seule réponse possible.
      const List<Locale> systeme = <Locale>[Locale('ja')];
      final Locale ecran = resolveAppLocale(
          forced: null, preferred: systeme, supported: livrees);
      final Locale notifications = resolveAppLocale(
          forced: null, preferred: systeme, supported: livrees);
      expect(ecran, notifications);
    });

    test('une correspondance exacte (langue + pays) bat la langue seule',
        () {
      const List<Locale> avecPays = <Locale>[
        Locale('pt'), Locale('pt', 'BR'), Locale('en'),
      ];
      expect(
        resolveAppLocale(
          forced: null,
          preferred: const <Locale>[Locale('pt', 'BR')],
          supported: avecPays,
        ),
        const Locale('pt', 'BR'),
      );
    });

    test('un choix enregistré par une ancienne version, langue retirée '
        'depuis, ne bloque pas l\'app', () {
      // `forced` pointe une langue qu'on ne livre plus : on ne la rend
      // pas telle quelle (l'app afficherait des clés brutes), on
      // retombe sur la règle normale.
      expect(
        resolveAppLocale(
          forced: const Locale('it'),
          preferred: const <Locale>[Locale('es')],
          supported: livrees,
        ),
        const Locale('es'),
      );
    });

    test('liste supportée vide → repli, sans exception', () {
      expect(
        resolveAppLocale(
          forced: const Locale('fr'),
          preferred: const <Locale>[Locale('fr')],
          supported: const <Locale>[],
        ),
        kFallbackLocale,
      );
    });

    test('système sans aucune langue → repli anglais', () {
      expect(
        resolveAppLocale(
          forced: null, preferred: const <Locale>[], supported: livrees),
        const Locale('en'),
      );
    });
  });
}
