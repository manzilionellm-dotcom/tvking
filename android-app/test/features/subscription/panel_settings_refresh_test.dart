import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/branding/brand_config.dart';
import 'package:tv_king/features/theme/data/remote_theme_repository.dart';
import 'package:tv_king/features/pricing/data/pricing_repository.dart';
import 'package:tv_king/features/simple_home/data/home_layout_repository.dart';
import 'package:tv_king/features/country_home/data/featured_repository.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';
import 'package:tv_king/features/feedback/data/feedback_repository.dart';
import 'package:tv_king/features/playlists/data/default_servers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  final Map<String, Future<void> Function()> readers = <String, Future<void> Function()>{
    'thème': () => RemoteThemeRepository.fetchAndApply(strict: true),
    'tarifs': () => PricingRepository.fetch(strict: true),
    'accueil': () => HomeLayoutRepository.instance.refresh(strict: true),
    'vedette': () => FeaturedRepository.instance.refresh(strict: true),
    'publicité': () async { await StartupAdRepository.instance.fetch(strict: true); },
    'avis': () => FeedbackRepository.instance.reload(strict: true),
    'serveurs': () async { await DefaultServersApi.fetch(forceRefresh: true, strict: true); },
  };
  for (final entry in readers.entries) {
    test('${entry.key} : une panne HTTP ou un JSON invalide ne vaut pas application', () async {
      for (final response in <http.Response>[http.Response('indisponible',503),http.Response('[]',200)]) {
        await expectLater(http.runWithClient(entry.value, () => MockClient((_) async => response)), throwsA(isA<StateError>()));
      }
    });
  }
  test('les valeurs distantes remplacent les réglages courants sans redémarrage', () async {
    final data = <String, Object>{
      '/api/theme': <String, Object>{'appName':'Nom du panel','accent':'#884422'},
      '/api/pricing': <String, Object>{'currency':'€','yearly':'7','lifetime':'15','trialDays':0,'promoEnabled':false},
      '/api/home-layout': <String, Object>{'items':<Object>[<String,Object>{'key':'recent','position':0,'enabled':true,'ribbon':'Nouveau','featured':false}]},
      '/api/featured': <String, Object>{'name':'Chaîne locale','note':'À voir'},
      '/api/ad': <String, Object>{'enabled':false,'url':'','skip':9,'freq':'daily'},
      '/api/feedback-prompt': <String, Object>{'enabled':true,'message':'Votre avis'},
      '/api/servers': <String, Object>{'servers':<Object>[<String,Object>{'id':'fixture','label':'Fixture','url':'https://example.invalid'}]},
    };
    await http.runWithClient(() async {
      for (final reader in readers.values) { await reader(); }
    }, () => MockClient((request) async => http.Response.bytes(utf8.encode(jsonEncode(data[request.url.path])), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    expect(BrandConfig.instance.appName,'Nom du panel');
    expect(PricingRepository.current.yearly,'7');
    expect(HomeLayoutRepository.instance.config('recent')?.ribbon,'Nouveau');
    expect(FeaturedRepository.instance.note,'À voir');
    expect(StartupAdRepository.instance.config.skip,9);
    expect(FeedbackRepository.instance.message,'Votre avis');
    expect((await DefaultServersApi.fetch()).single.id,'fixture');
  });
}
