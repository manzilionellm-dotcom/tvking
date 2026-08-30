// =========================================================
//  track_format_test.dart — Lire le format audio d'une piste
// =========================================================
//  Ce fichier existe à cause d'un signalement qu'on ne pouvait PAS
//  diagnostiquer : « le son n'est pas HD, on dirait une vieille cassette
//  radio ».
//
//  Deux causes très différentes s'entendent exactement pareil :
//    • la SOURCE est pauvre — MP2 96 kb/s en 32 kHz, très courant sur un
//      flux IPTV live. Aucun code ne peut réparer ça ;
//    • le LECTEUR choisit mal — mauvaise piste, downmix inutile.
//
//  L'application ne remontait que le nom et la langue de la piste. On ne
//  pouvait donc que deviner. Ces tests verrouillent la lecture du format
//  réel, et surtout le fait qu'une valeur INCONNUE ne s'affiche jamais.
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  group('Nom du codec', () {
    test('les codecs courants ont un nom lisible par un client', () {
      const Map<String, String> attendus = <String, String>{
        'audio/mp4a-latm': 'AAC',
        'audio/ac3': 'Dolby Digital',
        'audio/eac3': 'Dolby Digital+',
        'audio/mpeg-L2': 'MP2',
        'audio/mpeg': 'MP3',
      };
      attendus.forEach((String mime, String nom) {
        expect(TrackInfo(label: '', selected: false, codec: mime).codecLabel,
            nom,
            reason: mime);
      });
    });

    test('un codec inconnu montre son sous-type plutôt que rien', () {
      // « eac3-atmos » reste plus parlant qu'une case vide.
      expect(
        const TrackInfo(label: '', selected: false, codec: 'audio/eac3-atmos')
            .codecLabel,
        'eac3-atmos',
      );
    });
  });

  group('Résumé de format', () {
    test('une piste complète se lit d\'un coup d\'œil', () {
      const TrackInfo t = TrackInfo(
        label: 'VF', selected: true, codec: 'audio/ac3',
        sampleRate: 48000, channels: 6, bitrate: 384000,
      );
      expect(t.formatLabel, 'Dolby Digital · 48 kHz · 5.1 · 384 kb/s');
    });

    test('LE POINT CLÉ : une valeur inconnue est OMISE, pas affichée', () {
      // Un live MPEG-TS ne déclare presque jamais son débit. Écrire
      // « -1 kb/s » à l'écran serait pire que ne rien écrire.
      const TrackInfo t = TrackInfo(
        label: '', selected: false, codec: 'audio/mp4a-latm',
        sampleRate: 48000, channels: 2, bitrate: -1,
      );
      expect(t.formatLabel, 'AAC · 48 kHz · Stéréo');
      expect(t.formatLabel.contains('-1'), isFalse);
    });

    test('une piste sans aucune information rend une chaîne VIDE', () {
      // L'appelant doit alors afficher le libellé seul. Sans ça, on
      // collerait « Français ·  » avec un séparateur orphelin.
      expect(const TrackInfo(label: 'VF', selected: false).formatLabel,
          isEmpty);
    });

    test('une fréquence non ronde reste lisible', () {
      const TrackInfo t = TrackInfo(
        label: '', selected: false, codec: 'audio/mpeg', sampleRate: 44100,
      );
      expect(t.formatLabel, 'MP3 · 44.1 kHz');
    });
  });

  group('Détection d\'une piste pauvre', () {
    test('LE CAS DU SIGNALEMENT : 32 kHz = son de vieille radio', () {
      // C'est ce chiffre-là qui explique l'effet : au-dessus de 16 kHz
      // il n'y a plus rien, et la voix devient sourde.
      const TrackInfo t = TrackInfo(
        label: '', selected: false, codec: 'audio/mpeg-L2',
        sampleRate: 32000, channels: 2, bitrate: 96000,
      );
      expect(t.isLowQuality, isTrue);
    });

    test('mono = pauvre, quelle que soit la fréquence', () {
      const TrackInfo t = TrackInfo(
        label: '', selected: false, sampleRate: 48000, channels: 1,
      );
      expect(t.isLowQuality, isTrue);
    });

    test('un débit famélique en stéréo est signalé', () {
      const TrackInfo t = TrackInfo(
        label: '', selected: false, sampleRate: 48000, channels: 2,
        bitrate: 64000,
      );
      expect(t.isLowQuality, isTrue);
    });

    test('ON NE CRIE PAS AU LOUP : 48 kHz stéréo correct passe', () {
      // Si l'avertissement s'affichait sur des pistes normales, il ne
      // voudrait plus rien dire et on cesserait de le lire.
      const TrackInfo t = TrackInfo(
        label: '', selected: false, codec: 'audio/mp4a-latm',
        sampleRate: 48000, channels: 2, bitrate: 128000,
      );
      expect(t.isLowQuality, isFalse);
    });

    test('le 5.1 à gros débit passe évidemment', () {
      const TrackInfo t = TrackInfo(
        label: '', selected: false, codec: 'audio/eac3',
        sampleRate: 48000, channels: 6, bitrate: 640000,
      );
      expect(t.isLowQuality, isFalse);
    });

    test('une piste SANS information n\'est PAS declaree pauvre', () {
      // L'ignorance n'est pas un defaut. Afficher un avertissement parce
      // qu'on ne sait rien serait mentir au client.
      expect(const TrackInfo(label: 'VF', selected: false).isLowQuality,
          isFalse);
    });
  });
}
