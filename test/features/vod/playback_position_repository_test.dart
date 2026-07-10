// =========================================================
//  playback_position_repository_test.dart — Reprise de lecture (VOD)
// =========================================================
//  Verrouille les RÈGLES MÉTIER de la reprise « Reprendre à 42:15 » :
//    • < 60 s            → rien n'est sauvegardé (zapping d'essai) ;
//    • > 95 % de la durée → TERMINÉ (l'entrée est supprimée) ;
//    • éviction bornée    → jamais plus de 100 entrées, les plus ANCIENNES
//      sautent d'abord (anti-bloat prefs / anti-OOM) ;
//    • ordre              → entries du plus récent au plus ancien (l'ordre
//      exact de la rangée « Continuer à regarder ») ;
//    • persistance        → un load() après redémarrage retrouve tout.
//  SharedPreferences est mocké (aucun disque) — logique pure, test rapide.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/vod/data/playback_position_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final PlaybackPositionRepository repo = PlaybackPositionRepository.instance;

  // Horloge de test déterministe (l'ordre/l'éviction dépendent d'updatedAt).
  final DateTime t0 = DateTime(2026, 1, 1, 20, 0, 0);

  /// Raccourci : mémorise [position] (en secondes) pour [key], sur un film
  /// de [durationMin] minutes (90 par défaut), à l'instant t0 + [atOffsetS].
  Future<void> rec(
    String key,
    int positionS, {
    int durationMin = 90,
    int atOffsetS = 0,
  }) {
    return repo.record(
      key: key,
      position: Duration(seconds: positionS),
      duration: Duration(minutes: durationMin),
      name: 'Film $key',
      streamUrl: 'http://example.com/$key.mp4',
      posterUrl: null,
      at: t0.add(Duration(seconds: atOffsetS)),
    );
  }

  setUp(() async {
    // Base vierge + singleton remis à neuf à chaque test (sinon l'état
    // fuirait d'un cas à l'autre).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo.resetForTest();
    await repo.load();
  });

  group('Seuil bas (60 s) — zapping d\'essai', () {
    test('position < 60 s → rien n\'est sauvegardé', () async {
      await rec('vod-1', 59);
      expect(repo.positionFor('vod-1'), isNull);
      expect(repo.entries, isEmpty);
    });

    test('position ≥ 60 s → sauvegardée', () async {
      await rec('vod-1', 60);
      expect(repo.positionFor('vod-1'), const Duration(seconds: 60));
      expect(repo.entries, hasLength(1));
    });

    test('revoir 30 s n\'efface PAS un vrai point de reprise', () async {
      // L'utilisateur s'était arrêté à 42:15, puis relance le film et zappe
      // au bout de 30 s : le point de reprise doit survivre.
      await rec('vod-1', 42 * 60 + 15);
      await rec('vod-1', 30, atOffsetS: 100);
      expect(repo.positionFor('vod-1'),
          const Duration(minutes: 42, seconds: 15));
    });
  });

  group('Seuil haut (95 %) — contenu terminé', () {
    test('position > 95 % → considéré TERMINÉ, entrée supprimée', () async {
      await rec('vod-1', 40 * 60); // vrai point de reprise d'abord
      expect(repo.positionFor('vod-1'), isNotNull);
      // 90 min = 5400 s ; 95 % = 5130 s → 5200 s est « fini ».
      await rec('vod-1', 5200, atOffsetS: 10);
      expect(repo.positionFor('vod-1'), isNull);
      expect(repo.entries, isEmpty);
    });

    test('position juste SOUS 95 % → toujours reprise', () async {
      await rec('vod-1', 5100); // 5100 < 5130 (95 % de 90 min)
      expect(repo.positionFor('vod-1'), const Duration(seconds: 5100));
    });

    test('durée inconnue (0) → rien n\'est sauvegardé', () async {
      await rec('vod-1', 600, durationMin: 0);
      expect(repo.entries, isEmpty);
    });
  });

  group('markFinished', () {
    test('supprime l\'entrée', () async {
      await rec('vod-1', 600);
      await repo.markFinished('vod-1');
      expect(repo.positionFor('vod-1'), isNull);
      expect(repo.entries, isEmpty);
    });

    test('sur une clé inconnue → sans effet ni erreur', () async {
      await rec('vod-1', 600);
      await repo.markFinished('vod-inconnu');
      expect(repo.entries, hasLength(1));
    });
  });

  group('Ordre et éviction', () {
    test('entries : du plus récent au plus ancien', () async {
      await rec('vod-a', 600, atOffsetS: 0);
      await rec('vod-b', 600, atOffsetS: 10);
      await rec('vod-c', 600, atOffsetS: 5);
      expect(
        repo.entries.map((PlaybackPosition e) => e.key).toList(),
        <String>['vod-b', 'vod-c', 'vod-a'],
      );
    });

    test('re-regarder un contenu le remonte en tête', () async {
      await rec('vod-a', 600, atOffsetS: 0);
      await rec('vod-b', 600, atOffsetS: 10);
      await rec('vod-a', 1200, atOffsetS: 20); // a re-regardé plus tard
      expect(repo.entries.first.key, 'vod-a');
      expect(repo.positionFor('vod-a'), const Duration(seconds: 1200));
      expect(repo.entries, hasLength(2)); // pas de doublon
    });

    test('plafond 100 entrées : les plus ANCIENNES sont évincées', () async {
      for (int i = 0; i < 105; i++) {
        await rec('vod-$i', 600, atOffsetS: i);
      }
      expect(repo.entries, hasLength(100));
      // Les 5 plus anciennes (vod-0 … vod-4) ont sauté.
      expect(repo.positionFor('vod-0'), isNull);
      expect(repo.positionFor('vod-4'), isNull);
      expect(repo.positionFor('vod-5'), isNotNull);
      // La plus récente est bien en tête.
      expect(repo.entries.first.key, 'vod-104');
    });
  });

  group('Progression et métadonnées', () {
    test('progressFor : fraction déjà vue (barre sous l\'affiche)', () async {
      await rec('vod-1', 2700); // 2700 / 5400 = 50 %
      expect(repo.progressFor('vod-1'), closeTo(0.5, 0.001));
      expect(repo.progressFor('vod-inconnu'), isNull);
    });

    test('les métadonnées de relance sont conservées', () async {
      await repo.record(
        key: 'ep-42',
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 45),
        name: 'Ma Série — S1 E3 · Pilote',
        streamUrl: 'http://example.com/ep-42.mkv',
        posterUrl: 'http://example.com/poster.jpg',
        isEpisode: true,
        at: t0,
      );
      final PlaybackPosition e = repo.entryFor('ep-42')!;
      expect(e.name, 'Ma Série — S1 E3 · Pilote');
      expect(e.streamUrl, 'http://example.com/ep-42.mkv');
      expect(e.posterUrl, 'http://example.com/poster.jpg');
      expect(e.isEpisode, isTrue);
    });
  });

  group('Persistance', () {
    test('load() après « redémarrage » retrouve positions et ordre', () async {
      await rec('vod-a', 600, atOffsetS: 0);
      await rec('vod-b', 1200, atOffsetS: 10);
      // Simule un redémarrage : mémoire vidée, mêmes prefs sur « disque ».
      repo.resetForTest();
      expect(repo.entries, isEmpty);
      await repo.load();
      expect(repo.entries, hasLength(2));
      expect(repo.entries.first.key, 'vod-b');
      expect(repo.positionFor('vod-a'), const Duration(seconds: 600));
    });

    test('une entrée corrompue est ignorée sans casser le reste', () async {
      await rec('vod-a', 600);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> raw =
          List<String>.from(prefs.getStringList('tv_playback_positions')!);
      raw.add('{pas du json'); // corruption volontaire
      await prefs.setStringList('tv_playback_positions', raw);
      repo.resetForTest();
      await repo.load();
      expect(repo.entries, hasLength(1));
      expect(repo.positionFor('vod-a'), const Duration(seconds: 600));
    });
  });
}
