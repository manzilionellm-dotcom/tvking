import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/ads/domain/campaign_creative.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';

void main() {
  final Map<String, dynamic> recipe = <String, dynamic>{
    'version': 1,
    'template': 'prism',
    'palette': 'ice',
    'image_url': '',
    'badge': 'Nouveau',
    'motion': 'gentle',
    'duration_seconds': 8,
  };
  test('modèle valide et ancien message restent lisibles', () {
    expect(CampaignCreative.parse(recipe)?.durationSeconds, 8);
    final Map<String, dynamic> legacy = <String, dynamic>{
      'id': 1,
      'title': 'Découvrir',
      'body': 'Le programme',
      'created_at': 1,
    };
    expect(Announcement.fromJson(legacy)?.creative, isNull);
    expect(
      Announcement.fromJson(<String, dynamic>{...legacy, 'creative': recipe})
          ?.creative
          ?.template,
      'prism',
    );
    expect(
      Announcement.fromJson(<String, dynamic>{
        ...legacy,
        'creative': <String, dynamic>{...recipe, 'version': 99},
      })?.title,
      'Découvrir',
    );
  });
  test('aucun mouvement illimité ni URL de script', () {
    for (final Map<String, dynamic> changes in <Map<String, dynamic>>[
      <String, dynamic>{'duration_seconds': 999},
      <String, dynamic>{'motion': 'loop'},
      <String, dynamic>{'template': 'html'},
      <String, dynamic>{'image_url': 'javascript:alert(1)'},
      <String, dynamic>{'image_url': 'https://secret@image.invalid/a.png'},
    ])
      expect(
        CampaignCreative.parse(<String, dynamic>{...recipe, ...changes}),
        isNull,
      );
  });
}
