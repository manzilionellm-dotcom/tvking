// =========================================================
//  audio_frames.dart — Découpage des trames audio élémentaires
// =========================================================
//  POURQUOI : le Default Media Receiver (CC1AD845) transmuxe le
//  MPEG-TS avec mux.js, qui ne sait ré-emballer que l'AAC (ADTS) et
//  le MP3. Un TS avec de l'AC-3/E-AC-3 meurt en « idle » sur un vrai
//  Chromecast (confirmé terrain 2026-07-16) et le sauvetage TV-directe
//  est interdit sur récepteur web (CORS). La seule issue : servir du
//  fMP4 — Shaka le lit NATIVEMENT (sans mux.js) et l'AC-3/E-AC-3
//  passe en passthrough HDMI. Pour construire ce fMP4, il faut
//  découper le flux audio élémentaire en TRAMES individuelles (une
//  trame = un sample MP4) et en extraire les paramètres des boîtes
//  de configuration (dac3 / dec3 / esds).
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
//  Références : ETSI TS 102 366 (AC-3/E-AC-3, annexe F pour dac3 et
//  dec3), ISO 14496-3 (AudioSpecificConfig AAC), ADTS.
// =========================================================

import 'dart:typed_data';

/// Une trame audio élémentaire complète (un sample fMP4).
class AudioFrame {
  AudioFrame({
    required this.bytes,
    required this.sampleCount,
    required this.sampleRate,
  });

  final Uint8List bytes;

  /// Nombre d'échantillons PCM que représente la trame (durée du
  /// sample MP4, en timescale = sampleRate). AC-3 : 1536 constant ;
  /// E-AC-3 : numblks × 256 ; AAC : 1024.
  final int sampleCount;

  final int sampleRate;
}

/// Paramètres codec extraits de la première trame — de quoi remplir
/// la boîte de configuration du sample entry fMP4 ('dac3', 'dec3' ou
/// 'esds') et l'attribut CODECS d'une playlist HLS.
class AudioCodecConfig {
  AudioCodecConfig({
    required this.codec,
    required this.sampleRate,
    required this.channelCount,
    required this.codecConfigBytes,
    required this.rfc6381,
  });

  /// 'ac3' | 'eac3' | 'aac' (mêmes étiquettes que TsHlsSegmenter).
  final String codec;
  final int sampleRate;
  final int channelCount;

  /// Contenu (payload) de la boîte de configuration : dac3 pour AC-3,
  /// dec3 pour E-AC-3, AudioSpecificConfig (2 octets) pour AAC.
  final Uint8List codecConfigBytes;

  /// Étiquette RFC 6381 pour CODECS= ('ac-3', 'ec-3', 'mp4a.40.2').
  final String rfc6381;
}

/// Résultat d'un découpage : les trames complètes + le reliquat
/// d'octets (trame coupée en fin de buffer, à re-préfixer au prochain
/// appel par l'appelant s'il streame — au niveau segment le reliquat
/// est simplement ignoré, le segment suivant re-synchronise).
class AudioSplitResult {
  AudioSplitResult({
    required this.frames,
    required this.config,
    required this.rest,
  });

  final List<AudioFrame> frames;
  final AudioCodecConfig? config;
  final Uint8List rest;
}

/// Lecteur de bits MSB-first — les en-têtes AC-3/E-AC-3 ne tombent
/// pas sur des frontières d'octets.
class _BitReader {
  _BitReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0; // en bits

  int read(int n) {
    int v = 0;
    for (int i = 0; i < n; i++) {
      final int byte = _bytes[_pos >> 3];
      v = (v << 1) | ((byte >> (7 - (_pos & 7))) & 1);
      _pos++;
    }
    return v;
  }

  void skip(int n) => _pos += n;
}

/// Fréquences d'échantillonnage AC-3 (fscod).
const List<int> _kAc3SampleRates = <int>[48000, 44100, 32000];

/// Table des tailles de trame AC-3 en MOTS (16 bits) pour 44,1 kHz —
/// ETSI TS 102 366 table 4.13 (colonne du milieu). Les colonnes 48 et
/// 32 kHz s'en déduisent (voir [_ac3FrameSizeWords]).
const List<int> _kAc3FrameSize44 = <int>[
  69, 70, 87, 88, 104, 105, 121, 122, 139, 140, 174, 175, 208, 209, 243, 244,
  278, 279, 348, 349, 417, 418, 487, 488, 557, 558, 696, 697, 835, 836, 975,
  976, 1114, 1115, 1253, 1254, 1393, 1394,
];

/// Débits nominaux AC-3 (kbit/s) par bit_rate_code = frmsizecod >> 1.
const List<int> _kAc3BitrateKbps = <int>[
  32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448,
  512, 576, 640,
];

int? _ac3FrameSizeWords(int fscod, int frmsizecod) {
  if (frmsizecod >= _kAc3FrameSize44.length) return null;
  switch (fscod) {
    case 0: // 48 kHz : frmsizecod/2 → débit, taille = débit × 2
      return _kAc3BitrateKbps[frmsizecod >> 1] * 2;
    case 1: // 44,1 kHz : table dédiée (tailles impaires)
      return _kAc3FrameSize44[frmsizecod];
    case 2: // 32 kHz : taille = débit × 3
      return _kAc3BitrateKbps[frmsizecod >> 1] * 3;
  }
  return null;
}

/// Canaux par acmod (sans le LFE).
const List<int> _kAc3Channels = <int>[2, 1, 2, 3, 3, 4, 4, 5];

/// Découpe un flux élémentaire AC-3 **ou** E-AC-3 en trames. Le choix
/// AC-3/E-AC-3 se fait au bsid de chaque trame (≤ 8 : AC-3, 11-16 :
/// E-AC-3) — certains flux DVB mélangent les deux étiquettes.
AudioSplitResult splitAc3Frames(Uint8List es) {
  final List<AudioFrame> frames = <AudioFrame>[];
  AudioCodecConfig? config;
  int i = 0;
  while (i + 8 <= es.length) {
    // Syncword 0x0B77 : re-synchronisation octet par octet (les PES
    // audio peuvent charrier du stuffing ou une trame tronquée).
    if (es[i] != 0x0B || es[i + 1] != 0x77) {
      i++;
      continue;
    }
    final int bsid = es[i + 5] >> 3;
    if (bsid <= 10) {
      // ---- AC-3 (bsid ≤ 8, on tolère jusqu'à 10 par compat) ----
      final int fscod = es[i + 4] >> 6;
      final int frmsizecod = es[i + 4] & 0x3F;
      if (fscod == 3) {
        i++; // fscod réservé : faux positif de sync
        continue;
      }
      final int? words = _ac3FrameSizeWords(fscod, frmsizecod);
      if (words == null) {
        i++;
        continue;
      }
      final int size = words * 2;
      if (i + size > es.length) break; // trame incomplète → reliquat
      final Uint8List frame = Uint8List.sublistView(es, i, i + size);
      final int rate = _kAc3SampleRates[fscod];
      frames.add(AudioFrame(bytes: frame, sampleCount: 1536, sampleRate: rate));
      config ??= _ac3Config(frame, fscod, frmsizecod, bsid, rate);
      i += size;
    } else if (bsid >= 11 && bsid <= 16) {
      // ---- E-AC-3 ----
      final _BitReader br = _BitReader(Uint8List.sublistView(es, i + 2));
      final int strmtyp = br.read(2);
      br.skip(3); // substreamid
      final int frmsiz = br.read(11);
      final int fscod = br.read(2);
      int numblkscod;
      int rate;
      if (fscod == 3) {
        final int fscod2 = br.read(2);
        if (fscod2 == 3) {
          i++; // réservé : faux positif
          continue;
        }
        rate = _kAc3SampleRates[fscod2] ~/ 2;
        numblkscod = 3; // fscod==3 → toujours 6 blocs
      } else {
        rate = _kAc3SampleRates[fscod];
        numblkscod = br.read(2);
      }
      final int acmod = br.read(3);
      final int lfeon = br.read(1);
      final int size = (frmsiz + 1) * 2;
      if (i + size > es.length) break;
      final Uint8List frame = Uint8List.sublistView(es, i, i + size);
      final int numblks = const <int>[1, 2, 3, 6][numblkscod];
      frames.add(AudioFrame(
        bytes: frame,
        sampleCount: numblks * 256,
        sampleRate: rate,
      ));
      // Seul le flux INDÉPENDANT (strmtyp 0/2) configure la piste —
      // les substreams dépendants (strmtyp 1) enrichissent le même
      // sample, hors périmètre v1.
      if (config == null && strmtyp != 1) {
        config = _eac3Config(
          frameBytes: size,
          fscod: fscod,
          acmod: acmod,
          lfeon: lfeon,
          bsid: bsid,
          rate: rate,
          numblks: numblks,
        );
      }
      i += size;
    } else {
      i++; // bsid inconnu : faux positif de sync
    }
  }
  return AudioSplitResult(
    frames: frames,
    config: config,
    rest: Uint8List.sublistView(es, i > es.length ? es.length : i),
  );
}

AudioCodecConfig _ac3Config(
  Uint8List frame,
  int fscod,
  int frmsizecod,
  int bsid,
  int rate,
) {
  // BSI après le syncinfo (2 sync + 2 CRC + 1 fscod/frmsizecod) :
  // bsid(5) bsmod(3) acmod(3) [cmixlev(2)] [surmixlev(2)] [dsurmod(2)]
  // lfeon(1) — les champs optionnels dépendent d'acmod.
  final _BitReader br = _BitReader(Uint8List.sublistView(frame, 5));
  br.skip(5); // bsid (déjà lu)
  final int bsmod = br.read(3);
  final int acmod = br.read(3);
  if ((acmod & 0x1) != 0 && acmod != 0x1) br.skip(2); // cmixlev
  if ((acmod & 0x4) != 0) br.skip(2); // surmixlev
  if (acmod == 0x2) br.skip(2); // dsurmod
  final int lfeon = br.read(1);

  // dac3 (ETSI TS 102 366 annexe F.4) : fscod(2) bsid(5) bsmod(3)
  // acmod(3) lfeon(1) bit_rate_code(5) reserved(5) = 24 bits.
  final int bitRateCode = frmsizecod >> 1;
  final int v = (fscod << 22) |
      (bsid << 17) |
      (bsmod << 14) |
      (acmod << 11) |
      (lfeon << 10) |
      (bitRateCode << 5);
  return AudioCodecConfig(
    codec: 'ac3',
    sampleRate: rate,
    channelCount: _kAc3Channels[acmod] + lfeon,
    codecConfigBytes:
        Uint8List.fromList(<int>[(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]),
    rfc6381: 'ac-3',
  );
}

AudioCodecConfig _eac3Config({
  required int frameBytes,
  required int fscod,
  required int acmod,
  required int lfeon,
  required int bsid,
  required int rate,
  required int numblks,
}) {
  // dec3 (ETSI TS 102 366 annexe F.6) : data_rate(13) num_ind_sub(3)
  // puis par flux indépendant : fscod(2) bsid(5) reserved(1) asvc(1)
  // bsmod(3) acmod(3) lfeon(1) reserved(3) num_dep_sub(4) +
  // chan_loc(9) si dépendants, sinon reserved(1).
  final int dataRateKbps =
      (frameBytes * 8 * rate / (numblks * 256) / 1000).ceil();
  final int word0 = (dataRateKbps << 3); // num_ind_sub = 0 (= 1 flux)
  final int word1 = (fscod << 14) |
      (bsid << 9) |
      // reserved(1)=0, asvc(1)=0, bsmod(3)=0
      (acmod << 1) |
      lfeon;
  // num_dep_sub(4)=0 + reserved(1)=0 → dernier octet 0x00.
  return AudioCodecConfig(
    codec: 'eac3',
    sampleRate: rate,
    channelCount: _kAc3Channels[acmod] + lfeon,
    codecConfigBytes: Uint8List.fromList(<int>[
      (word0 >> 8) & 0xFF,
      word0 & 0xFF,
      (word1 >> 8) & 0xFF,
      word1 & 0xFF,
      0x00,
    ]),
    rfc6381: 'ec-3',
  );
}

/// Fréquences ADTS (sampling_frequency_index).
const List<int> _kAdtsRates = <int>[
  96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000,
  11025, 8000, 7350,
];

/// Découpe un flux ADTS (AAC) en trames BRUTES (en-tête ADTS retiré :
/// le fMP4 transporte de l'AAC nu, la config vit dans l'esds).
AudioSplitResult splitAdtsFrames(Uint8List es) {
  final List<AudioFrame> frames = <AudioFrame>[];
  AudioCodecConfig? config;
  int i = 0;
  while (i + 7 <= es.length) {
    if (es[i] != 0xFF || (es[i + 1] & 0xF0) != 0xF0) {
      i++;
      continue;
    }
    final bool crcAbsent = (es[i + 1] & 0x01) != 0;
    final int profile = es[i + 2] >> 6; // objectType - 1
    final int freqIdx = (es[i + 2] >> 2) & 0x0F;
    final int chanCfg = ((es[i + 2] & 0x01) << 2) | (es[i + 3] >> 6);
    final int frameLen =
        ((es[i + 3] & 0x03) << 11) | (es[i + 4] << 3) | (es[i + 5] >> 5);
    if (freqIdx >= _kAdtsRates.length || frameLen < 7) {
      i++;
      continue;
    }
    if (i + frameLen > es.length) break;
    final int headerLen = crcAbsent ? 7 : 9;
    if (frameLen <= headerLen) {
      i++;
      continue;
    }
    final int rate = _kAdtsRates[freqIdx];
    frames.add(AudioFrame(
      bytes: Uint8List.sublistView(es, i + headerLen, i + frameLen),
      sampleCount: 1024,
      sampleRate: rate,
    ));
    // AudioSpecificConfig 2 octets : objectType(5) freqIdx(4)
    // chanCfg(4) + GASpecificConfig(3 bits à 0).
    final int objectType = profile + 1;
    final int asc =
        (objectType << 11) | (freqIdx << 7) | (chanCfg << 3);
    config ??= AudioCodecConfig(
      codec: 'aac',
      sampleRate: rate,
      channelCount: chanCfg == 7 ? 8 : chanCfg,
      codecConfigBytes:
          Uint8List.fromList(<int>[(asc >> 8) & 0xFF, asc & 0xFF]),
      rfc6381: 'mp4a.40.$objectType',
    );
    i += frameLen;
  }
  return AudioSplitResult(
    frames: frames,
    config: config,
    rest: Uint8List.sublistView(es, i > es.length ? es.length : i),
  );
}
