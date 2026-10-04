// =========================================================
//  panel_board_test.dart — Les cartes du panel : décisions pures
// =========================================================
//  Aucune adresse de flux réelle, aucun réseau : on teste ce que
//  l'accueil a le droit de montrer, et dans quel ordre.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/panel_board/domain/panel_board.dart';

Channel _ch(String id, String name, {bool live = true}) => Channel(
      id: id,
      name: name,
      category: 'Test',
      streamUrl: 'http://flux.example.invalid/$id',
      isLive: live,
    );

Map<String, Object?> _item(
  String id, {
  String image = 'https://img.example.invalid/$_png',
  Object? extra,
}) =>
    <String, Object?>{
      'id': id,
      'image': image,
      if (extra is Map) ...extra.cast<String, Object?>(),
    };

const String _png = 'b.png';

void main() {
  group('favori du jour : retrouver la chaîne par son nom', () {
    final List<Channel> list = <Channel>[
      _ch('1', 'TF1 HD'),
      _ch('2', 'TF1 +1'),
      _ch('3', 'France 2'),
      _ch('4', 'Télé Monte-Carlo'),
      _ch('5', 'TF1', live: false),
      _ch('6', 'TF1'),
    ];

    test('nom replié identique, le direct d\'abord', () {
      expect(matchChannelByName('tf1', list)?.id, '6');
      expect(matchChannelByName('TELE MONTE CARLO', list)?.id, '4');
      expect(matchChannelByName('télé monte carlo', list)?.id, '4');
    });

    test('sinon la première en direct qui commence par le nom + espace', () {
      final List<Channel> short = <Channel>[_ch('1', 'TF1 HD'), _ch('2', 'TF1 +1')];
      expect(matchChannelByName('tf1', short)?.id, '1');
    });

    test('inconnu ou vide : rien', () {
      expect(matchChannelByName('Canal+', list), isNull);
      expect(matchChannelByName('', list), isNull);
      expect(matchChannelByName('tf1', const <Channel>[]), isNull);
    });

    test('la VOD du même nom ne gagne que s\'il n\'y a pas de direct', () {
      expect(matchChannelByName('tf1', <Channel>[_ch('5', 'TF1', live: false)])?.id, '5');
    });

    test('grosse liste : même réponse hors fil UI', () async {
      final List<Channel> big = <Channel>[
        for (int i = 0; i < kNameMatchInlineMax + 50; i++) _ch('c$i', 'Chaîne $i'),
        _ch('bein', 'beIN Sports 1'),
      ];
      final Channel? found = await findChannelByName('bein sports 1', big);
      expect(found?.id, 'bein');
      expect(await findChannelByName('rien', big), isNull);
    });
  });

  group('bannières : lecture du contrat', () {
    test('https obligatoire, id obligatoire, libellé par défaut', () {
      expect(PromoBanner.fromJson(_item('a'))?.label, kPromoDefaultLabel);
      expect(PromoBanner.fromJson(_item('a', image: 'http://x.example/b.png')), isNull);
      expect(PromoBanner.fromJson(_item('', )), isNull);
      expect(PromoBanner.fromJson(<String, Object?>{'id': 'a'}), isNull);
      expect(PromoBanner.fromJson('texte'), isNull);
    });

    test('champs optionnels, bornés, lien https seulement', () {
      final PromoBanner b = PromoBanner.fromJson(_item('a', extra: <String, Object?>{
        'title': 'Coupe du monde',
        'subtitle': 'Tous les matchs',
        'label': 'Sponsorisé',
        'cta': 'Voir',
        'channel': 'beIN Sports 1',
        'url': 'http://pas-sur.example/',
        'from': 1000,
        'until': '2000',
        'kids': true,
      }))!;
      expect(b.title, 'Coupe du monde');
      expect(b.label, 'Sponsorisé');
      expect(b.channel, 'beIN Sports 1');
      expect(b.url, '', reason: 'un lien http en clair est ignoré');
      expect(b.fromMs, 1000);
      expect(b.untilMs, 2000);
      expect(b.kids, isTrue);
      expect(b.hasAction, isTrue);
      expect(PromoBanner.fromJson(_item('b'))!.hasAction, isFalse);
    });

    test('{items:[…]} ou […], doublons gardés une fois, liste bornée', () {
      final List<Object?> many = <Object?>[
        for (int i = 0; i < kPromoMaxItems + 5; i++) _item('b$i'),
      ];
      expect(parsePromoBanners(<String, Object?>{'items': many}), hasLength(kPromoMaxItems));
      expect(parsePromoBanners(many), hasLength(kPromoMaxItems));
      expect(parsePromoBanners(<Object?>[_item('x'), _item('x'), 'bruit']), hasLength(1));
      expect(parsePromoBanners(null), isEmpty);
      expect(parsePromoBanners(<String, Object?>{'items': 'non'}), isEmpty);
    });
  });

  group('bannières : ce qu\'on a le droit de montrer', () {
    final List<PromoBanner> all = <PromoBanner>[
      PromoBanner.fromJson(_item('tout'))!,
      PromoBanner.fromJson(_item('demain', extra: <String, Object?>{'from': 5000}))!,
      PromoBanner.fromJson(_item('fini', extra: <String, Object?>{'until': 1000}))!,
      PromoBanner.fromJson(_item('enfants', extra: <String, Object?>{'kids': true}))!,
    ];

    test('fenêtre de diffusion', () {
      final List<PromoBanner> now = eligiblePromos(
        banners: all,
        nowMs: 2000,
        kidsMode: false,
        shownToday: const <String, int>{},
        dismissed: const <String>{},
      );
      expect(now.map((PromoBanner b) => b.id), <String>['tout', 'enfants']);
    });

    test('mode enfants : seulement les bannières marquées kids', () {
      final List<PromoBanner> kids = eligiblePromos(
        banners: all,
        nowMs: 2000,
        kidsMode: true,
        shownToday: const <String, int>{},
        dismissed: const <String>{},
      );
      expect(kids.map((PromoBanner b) => b.id), <String>['enfants']);
    });

    test('fermée ou plafond du jour atteint : absente', () {
      final List<PromoBanner> left = eligiblePromos(
        banners: all,
        nowMs: 2000,
        kidsMode: false,
        shownToday: <String, int>{'tout': kPromoMaxPerDay},
        dismissed: <String>{'enfants'},
      );
      expect(left, isEmpty);
      final List<PromoBanner> one = eligiblePromos(
        banners: all,
        nowMs: 2000,
        kidsMode: false,
        shownToday: <String, int>{'tout': kPromoMaxPerDay - 1},
        dismissed: const <String>{},
      );
      expect(one.first.id, 'tout');
    });

    test('rotation stable, liste vide = rien', () {
      final List<PromoBanner> two = <PromoBanner>[all[0], all[3]];
      expect(rotatePromo(two, 0)!.id, 'tout');
      expect(rotatePromo(two, 1)!.id, 'enfants');
      expect(rotatePromo(two, 2)!.id, 'tout');
      expect(rotatePromo(two, -1)!.id, 'enfants');
      expect(rotatePromo(const <PromoBanner>[], 3), isNull);
    });
  });

  group('une seule carte en tête de l\'accueil', () {
    test('l\'émission suivie passe devant tout, puis l\'annonce', () {
      expect(
        pickHeaderCard(hasShow: true, hasNotice: true, hasPromo: true, hasFeatured: true, tick: 0),
        HeaderCard.show,
      );
      expect(
        pickHeaderCard(hasShow: false, hasNotice: true, hasPromo: true, hasFeatured: true, tick: 0),
        HeaderCard.notice,
      );
    });

    test('bannière et favori alternent d\'un tic à l\'autre', () {
      expect(
        pickHeaderCard(hasShow: false, hasNotice: false, hasPromo: true, hasFeatured: true, tick: 0),
        HeaderCard.promo,
      );
      expect(
        pickHeaderCard(hasShow: false, hasNotice: false, hasPromo: true, hasFeatured: true, tick: 1),
        HeaderCard.featured,
      );
      expect(
        pickHeaderCard(hasShow: false, hasNotice: false, hasPromo: false, hasFeatured: true, tick: 0),
        HeaderCard.featured,
      );
      expect(
        pickHeaderCard(hasShow: false, hasNotice: false, hasPromo: true, hasFeatured: false, tick: 1),
        HeaderCard.promo,
      );
      expect(
        pickHeaderCard(hasShow: false, hasNotice: false, hasPromo: false, hasFeatured: false, tick: 7),
        HeaderCard.none,
      );
    });
  });

  test('clé du jour et annonce promo en mode enfants', () {
    expect(promoDayKey(DateTime(2026, 10, 4, 23, 59)), '2026-10-04');
    expect(promoDayKey(DateTime(2026, 1, 9)), '2026-01-09');
    expect(noticeAllowed(kind: 'promo', kidsMode: true), isFalse);
    expect(noticeAllowed(kind: 'promo', kidsMode: false), isTrue);
    expect(noticeAllowed(kind: 'maintenance', kidsMode: true), isTrue);
    expect(kPromoDismissFor, const Duration(days: 7));
  });
}
