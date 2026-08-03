// =========================================================
//  demo_mode_test.dart — Le mode démo, et ses garde-fous
// =========================================================
//  Demande du client : « si quelqu'un vient et n'a pas encore mis son
//  M3U, il doit y avoir une option mode démo. Ça doit avoir des vidéos,
//  une, deux, trois… même dans le cinéma. »
//
//  Ce que ces tests protègent — et ce n'est pas cosmétique. Ces écrans
//  servent aussi de captures pour la fiche Google Play, qui a DÉJÀ été
//  bloquée une fois. Une seule chaîne mal nommée, un seul lien de
//  fournisseur qui se glisse ici, et c'est un refus.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/demo/data/demo_mode.dart';

void main() {
  // Les clips vivent maintenant SUR l'appareil : sans chemins extraits,
  // le bouquet est vide par construction. On injecte des chemins
  // factices pour voir le catalogue complet, sans toucher au disque.
  DemoMode.debugFakeClipPaths();
  final List<Channel> bouquet = DemoMode.demoChannels;

  group('le bouquet couvre tout le parcours', () {
    test('du direct ET du cinéma, six chaînes au moins', () {
      final List<Channel> live =
          bouquet.where((Channel c) => c.isLive).toList();
      final List<Channel> vod =
          bouquet.where((Channel c) => !c.isLive).toList();

      expect(live.length, greaterThanOrEqualTo(6),
          reason:
              'le client a demandé « une, deux, trois, quatre, cinq, six »');
      expect(vod, isNotEmpty,
          reason: '« même dans le cinéma, tu mets des démonstrations »');
    });

    test('des guides dans le cinéma, pas seulement des films', () {
      final Iterable<Channel> guides =
          bouquet.where((Channel c) => c.id.startsWith('demo-tuto-'));
      expect(guides.length, greaterThanOrEqualTo(3),
          reason: 'ce sont eux qui montrent comment l\'app fonctionne');
    });

    test('chaque identifiant est préfixé « demo- »', () {
      for (final Channel c in bouquet) {
        expect(c.id, startsWith('demo-'),
            reason: 'impossible de confondre avec une chaîne réelle');
      }
    });

    test('aucun doublon d\'identifiant', () {
      final Set<String> ids = bouquet.map((Channel c) => c.id).toSet();
      expect(ids.length, bouquet.length);
    });
  });

  // ---------------------------------------------------------
  //  LES DEUX RÈGLES QUI PROTÈGENT LA FICHE PLAY STORE
  // ---------------------------------------------------------
  group('rien de réel ne doit entrer ici', () {
    test('aucun nom de chaîne ou de bouquet réel', () {
      // Motif de refus n°1 des lecteurs IPTV sur les stores. La liste
      // ci-dessous n'est pas exhaustive — elle attrape les noms qui ont
      // déjà circulé dans les captures de ce projet.
      const List<String> interdits = <String>[
        'dazn',
        'bein',
        'canal',
        'sky',
        'netflix',
        'disney',
        'rmc',
        'espn',
        'hbo',
        'prime',
        'eurosport',
        'bbc',
        'tf1',
        'm6',
      ];
      for (final Channel c in bouquet) {
        final String n = c.name.toLowerCase();
        for (final String mot in interdits) {
          expect(n.contains(mot), isFalse,
              reason: '« ${c.name} » contient « $mot » — refus garanti');
        }
      }
    });

    test('tout s\'appelle « Démo » ou « Guide »', () {
      for (final Channel c in bouquet) {
        final bool ok = c.name.startsWith('Démo') || c.name.startsWith('Guide');
        expect(ok, isTrue, reason: '« ${c.name} » n\'annonce pas la démo');
      }
    });

    test('aucun lien de fournisseur ne peut se glisser ici', () {
      // Motif de refus lourd sur les stores : diffuser le serveur d'un
      // fournisseur depuis une app publique. Le bouquet étant 100 %
      // local, la porte est fermée — ce test vérifie qu'elle le reste.
      for (final Channel c in bouquet) {
        expect(c.streamUrl.contains('://'), isFalse,
            reason: '« ${c.name} » porte une URL');
      }
    });
  });

  // ---------------------------------------------------------
  //  PLUS AUCUNE URL — la leçon de la journée du 3 août 2026
  // ---------------------------------------------------------
  //  Le bouquet a été noir une journée entière. On a accusé le lien,
  //  puis l'hébergeur, puis le codec. La vraie cause était que l'app ne
  //  négociait AUCUN TLS (cf. doh_resolver.dart) — ce bouquet était son
  //  seul consommateur HTTPS, et c'est lui qui a fait sortir la panne.
  //  En chemin, un hébergeur s'est mis à répondre 403.
  //
  //  Conclusion : le mode démo se déclenche DEVANT un client, il n'a
  //  pas droit à l'erreur, et il ne dépend donc plus de personne. Les
  //  clips sont fabriqués et embarqués.
  //
  //  Ce test est le gardien de cette décision. Le jour où quelqu'un
  //  voudra « alléger l'APK en mettant les clips sur un serveur », il
  //  le verra tomber, et il lira pourquoi.
  group('le bouquet ne dépend de personne', () {
    test('aucune URL : QUE des fichiers locaux', () {
      for (final Channel c in bouquet) {
        expect(c.streamUrl.startsWith('http'), isFalse,
            reason: '« ${c.name} » repasse par le réseau — on reperd la '
                'seule garantie qui compte : une démo qui marche toujours');
        expect(c.streamUrl, startsWith('/'),
            reason: 'un chemin relatif ne serait pas lisible par le lecteur');
      }
    });

    test('chaque clip a son propre fichier', () {
      // Deux entrées qui pointent le même fichier, c'est un catalogue
      // qui a l'air riche et qui montre six fois la même chose.
      final Set<String> fichiers =
          bouquet.map((Channel c) => c.streamUrl).toSet();
      expect(fichiers.length, bouquet.length);
    });
  });

  group('le guide « Comment ça marche »', () {
    test('cinq étapes numérotées, dans l\'ordre', () {
      expect(DemoMode.lessons.length, 5);
      for (int i = 0; i < DemoMode.lessons.length; i++) {
        expect(DemoMode.lessons[i].step, i + 1);
        expect(DemoMode.lessons[i].title, isNotEmpty);
        expect(DemoMode.lessons[i].body.length, greaterThan(40));
      }
    });

    test('il dit que l\'app ne fournit aucune chaîne', () {
      // C'est LA phrase qui protège de la requalification en
      // distributeur de contenu. Elle doit rester quelque part.
      final String tout = DemoMode.lessons
          .map((DemoLesson l) => l.body)
          .join(' ')
          .toLowerCase();
      expect(tout, contains('ne fournit aucune chaîne'));
    });

    test('il explique la sortie de la démo', () {
      final String tout = DemoMode.lessons
          .map((DemoLesson l) => l.body)
          .join(' ')
          .toLowerCase();
      expect(tout, contains('quitte le mode démo'));
    });
  });
}
