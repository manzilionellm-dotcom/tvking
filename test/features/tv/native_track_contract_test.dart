// =========================================================
//  native_track_contract_test.dart — Contrat pistes natif ⇄ Dart
// =========================================================
//  Le lecteur TV natif (ExoPlayer, NativeVideoView.kt) remonte ses
//  pistes audio/sous-titres via l'événement MethodChannel `tracks` :
//  [{label, language, selected}]. La feuille « Pistes & format »
//  du lecteur TV s'appuie dessus. Ces tests verrouillent le contrat
//  côté Dart : champs présents, valeurs manquantes tolérées (un
//  flux IPTV ne déclare pas toujours label ni langue), entrées
//  malformées ignorées sans crash.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  test('parseTracks lit label + language + selected', () {
    final List<TrackInfo> tracks = NativeVideoController.parseTracks(<Object>[
      <Object?, Object?>{
        'label': 'VF',
        'language': 'fra',
        'selected': true,
      },
      <Object?, Object?>{
        'label': 'VO',
        'language': 'eng',
        'selected': false,
      },
    ]);
    expect(tracks, hasLength(2));
    expect(tracks.first.label, 'VF');
    expect(tracks.first.language, 'fra');
    expect(tracks.first.selected, isTrue);
    expect(tracks.last.language, 'eng');
    expect(tracks.last.selected, isFalse);
  });

  test('valeurs manquantes tolérées (flux IPTV sans métadonnées)', () {
    final List<TrackInfo> tracks = NativeVideoController.parseTracks(<Object>[
      <Object?, Object?>{'label': 'Piste 1'}, // ni langue ni selected
    ]);
    expect(tracks.single.label, 'Piste 1');
    expect(tracks.single.language, '',
        reason: 'langue absente → chaîne vide, jamais null');
    expect(tracks.single.selected, isFalse);
  });

  test('payload malformé → liste vide, jamais de crash', () {
    expect(NativeVideoController.parseTracks(null), isEmpty);
    expect(NativeVideoController.parseTracks('oops'), isEmpty);
    expect(NativeVideoController.parseTracks(<Object>['pas une map']),
        isEmpty);
  });
}
