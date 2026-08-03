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

    test('aucun lien de fournisseur : que des flux de test publics', () {
      // Les seuls hôtes autorisés sont ceux qui publient des flux POUR
      // être testés. Un hôte de panel IPTV ici, et on diffuserait le
      // serveur d'un fournisseur dans une app publique.
      const List<String> hotesPermis = <String>[
        'devstreaming-cdn.apple.com', // flux de référence Apple HLS
        'test-streams.mux.dev', // échantillons mux.dev
        'bitdash-a.akamaihd.net', // Sintel (Blender, licence libre)
        'demo.unified-streaming.com', // Tears of Steel (idem)
      ];
      for (final Channel c in bouquet) {
        // Le clip embarqué n'a pas d'hôte : il est SUR l'appareil. C'est
        // justement son intérêt — voir plus bas.
        if (!c.streamUrl.startsWith('http')) continue;
        final String host = Uri.parse(c.streamUrl).host;
        expect(hotesPermis, contains(host),
            reason: '« ${c.name} » pointe vers $host');
        expect(c.streamUrl, startsWith('https://'),
            reason: 'un flux de démo en clair passerait mal partout');
      }
    });
  });

  // ---------------------------------------------------------
  //  LES HÔTES ET LES CHEMINS — ce que l'écran noir nous a appris
  // ---------------------------------------------------------
  //  Le bouquet a été noir pendant une journée entière. On a accusé
  //  successivement le lien, l'hébergeur, puis le codec. La vraie cause
  //  était que l'app ne négociait AUCUN TLS (cf. doh_resolver.dart) :
  //  ce bouquet était son seul consommateur HTTPS, et c'est lui qui a
  //  fait sortir la panne.
  //
  //  Les tests ci-dessous gardent chacun une trace de ces impasses,
  //  pour qu'on n'y revienne pas par distraction.
  group('les hôtes et les chemins de la démo', () {
    // Le clip du client, embarqué dans l'APK. C'est la SEULE entrée du
    // bouquet qui ne dépende ni du réseau, ni d'un CDN, ni d'une
    // playlist : si même celle-là reste noire, le problème n'est pas
    // dehors. Le jour où quelqu'un la « déplacera sur un serveur pour
    // alléger l'APK », il faudra qu'il voie ce test tomber d'abord.
    test('le clip embarqué reste LOCAL, jamais une URL', () {
      final Iterable<Channel> clip =
          bouquet.where((Channel c) => c.id.startsWith('demo-clip-'));
      for (final Channel c in clip) {
        expect(c.streamUrl.startsWith('http'), isFalse,
            reason: '« ${c.name} » repasse par le réseau — on perd le seul '
                'élément de démo qui ne peut pas tomber en panne');
      }
    });

    test('le direct est en HLS — le format des vraies chaînes', () {
      final Iterable<Channel> live = bouquet.where((Channel c) => c.isLive);
      for (final Channel c in live) {
        expect(Uri.parse(c.streamUrl).path, endsWith('.m3u8'),
            reason: '« ${c.name} » n\'exerce pas le chemin HLS');
      }
    });

    // L'exemple « advanced » d'Apple mêle des variantes HEVC et Dolby
    // Vision au H.264. On l'a cru coupable de l'écran noir — à tort,
    // c'était le TLS. On le garde interdit quand même : une seule
    // famille de codecs, c'est une variable de moins le jour où
    // quelque chose ira encore de travers. Les formes `_ts` et `_fmp4`
    // partagent le même jeu de variantes, d'où le motif commun.
    test('pas d\'exemple Apple « advanced » : HEVC / Dolby Vision', () {
      for (final Channel c in bouquet) {
        expect(c.streamUrl.contains('img_bipbop_adv_example'), isFalse,
            reason: '« ${c.name} » revient sur le flux à variantes HEVC/DV '
                '— celui qui donnait un écran noir malgré des octets reçus');
      }
    });

    // L'hôte des MP4 (`commondatastorage.googleapis.com`) répond
    // 403 Forbidden — constaté par mpv dans la boîte noire du client, et
    // sans rapport avec le TLS puisque mpv fait son propre HTTPS. Un
    // hôte mort n'a rien à faire dans une démo qu'on montre à un client.
    test('plus aucun lien vers le dépôt Google qui renvoie 403', () {
      for (final Channel c in bouquet) {
        expect(c.streamUrl.contains('commondatastorage.googleapis.com'),
            isFalse,
            reason: '« ${c.name} » revient sur un hôte dont on a la trace '
                'qu\'il refuse les requêtes');
      }
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
