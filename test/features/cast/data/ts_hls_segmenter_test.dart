// =========================================================
//  ts_hls_segmenter_test.dart — Découpe TS → segments HLS finis
// =========================================================
//  Le repli Chromecast « local_hls_relay » dépend entièrement de
//  cette découpe (diag SHIELD 2026-07-09 : l'ancienne playlist à
//  segment infini échouait 8/8). On vérifie sur un flux TS
//  SYNTHÉTIQUE (PAT + PMT + PES vidéo avec RAI/PCR) que :
//    - la découpe tombe sur les images-clés, autour de la durée cible
//    - chaque segment commence par PAT puis PMT (décodable seul)
//    - le codec est lu dans la PMT
//    - un flux SANS random_access_indicator est quand même découpé
//    - la resynchronisation avale les octets parasites
// =========================================================

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/ts_hls_segmenter.dart';

const int kPmtPid = 0x1000; // 4096
const int kVideoPid = 0x100; // 256

/// Paquet TS de 188 octets. Le padding se fait par le champ
/// d'adaptation (stuffing 0xFF), comme un vrai multiplexeur.
Uint8List tsPacket({
  required int pid,
  bool pusi = false,
  int cc = 0,
  bool rai = false,
  double? pcrSec,
  List<int> payload = const <int>[],
}) {
  final Uint8List p = Uint8List(188);
  p[0] = 0x47;
  p[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
  p[2] = pid & 0xFF;
  final int payloadLen = payload.length;
  // Adaptation field TOUJOURS présent (afc=3) : il porte RAI/PCR et
  // sert de bourrage pour amener le paquet à 188 octets.
  final int afLen = 183 - payloadLen; // longueur APRÈS l'octet af_length
  assert(afLen >= 1, 'payload trop grande pour un paquet');
  p[3] = 0x30 | (cc & 0x0F);
  p[4] = afLen;
  int flags = 0;
  if (rai) flags |= 0x40;
  if (pcrSec != null) flags |= 0x10;
  p[5] = flags;
  int off = 6;
  if (pcrSec != null) {
    final int base = (pcrSec * 90000).round();
    p[6] = (base >> 25) & 0xFF;
    p[7] = (base >> 17) & 0xFF;
    p[8] = (base >> 9) & 0xFF;
    p[9] = (base >> 1) & 0xFF;
    p[10] = ((base & 1) << 7) | 0x7E; // bits réservés
    p[11] = 0;
    off = 12;
  }
  for (int i = off; i < 4 + 1 + afLen; i++) {
    p[i] = 0xFF; // stuffing
  }
  p.setRange(4 + 1 + afLen, 188, payload);
  return p;
}

Uint8List patPacket({int cc = 0}) {
  final List<int> section = <int>[
    0x00, // pointer_field
    0x00, // table_id PAT
    0xB0, 13, // section_syntax + length (5 + 4 + CRC 4)
    0x00, 0x01, // transport_stream_id
    0xC1, // version/current_next
    0x00, 0x00, // section/last_section
    0x00, 0x01, // program_number 1
    0xE0 | ((kPmtPid >> 8) & 0x1F), kPmtPid & 0xFF,
    0xDE, 0xAD, 0xBE, 0xEF, // CRC (non vérifié par le segmenteur)
  ];
  return tsPacket(pid: 0, pusi: true, cc: cc, payload: section);
}

Uint8List pmtPacket({int cc = 0, int streamType = 0x1B, int? audioType = 0x0F}) {
  final int audioCount = audioType != null ? 1 : 0;
  final List<int> section = <int>[
    0x00, // pointer_field
    0x02, // table_id PMT
    0xB0, 13 + 5 + 5 * audioCount, // 9 + 5/flux + CRC 4
    0x00, 0x01, // program_number
    0xC1,
    0x00, 0x00,
    0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF, // PCR PID
    0xF0, 0x00, // program_info_length 0
    streamType,
    0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF,
    0xF0, 0x00, // ES_info_length 0
    if (audioType != null) ...<int>[
      audioType,
      0xE0 | (((kVideoPid + 1) >> 8) & 0x1F), (kVideoPid + 1) & 0xFF,
      0xF0, 0x00,
    ],
    0xDE, 0xAD, 0xBE, 0xEF,
  ];
  return tsPacket(pid: kPmtPid, pusi: true, cc: cc, payload: section);
}

/// [seconds] de flux à 25 « images »/s : chaque image = 1 paquet PUSI
/// (PCR) + 2 paquets de continuation. Image-clé toutes les [gopSec] s.
/// PAT/PMT ré-émis chaque seconde (comme un vrai mux).
List<int> syntheticStream({
  required double seconds,
  double gopSec = 1.0,
  bool withRai = true,
  double startPcr = 10.0,
  int streamType = 0x1B,
}) {
  final BytesBuilder b = BytesBuilder();
  int cc = 0;
  final int frames = (seconds * 25).round();
  for (int f = 0; f < frames; f++) {
    final double t = startPcr + f / 25.0;
    if (f % 25 == 0) {
      b
        ..add(patPacket(cc: cc))
        ..add(pmtPacket(cc: cc, streamType: streamType));
    }
    final bool key = withRai && (f % (gopSec * 25).round() == 0);
    b.add(tsPacket(
      pid: kVideoPid,
      pusi: true,
      cc: cc++,
      rai: key,
      pcrSec: t,
      payload: <int>[0x00, 0x00, 0x01, 0xE0, 0x00, 0x00],
    ));
    b.add(tsPacket(pid: kVideoPid, cc: cc++, payload: <int>[1, 2, 3]));
    b.add(tsPacket(pid: kVideoPid, cc: cc++, payload: <int>[4, 5, 6]));
  }
  return b.takeBytes();
}

int pidOfPacket(Uint8List seg, int index) {
  final int off = index * 188;
  return ((seg[off + 1] & 0x1F) << 8) | seg[off + 2];
}

void main() {
  group('TsHlsSegmenter — flux nominal (RAI + PCR)', () {
    test('découpe ~3 s alignée keyframes, PAT/PMT en tête de segment', () {
      final TsHlsSegmenter seg = TsHlsSegmenter();
      final List<TsSegment> out =
          seg.ingest(syntheticStream(seconds: 14.0));
      // 14 s de flux, GOP 1 s, cible 3 s → au moins 3 segments finis.
      expect(out.length, greaterThanOrEqualTo(3));
      for (final TsSegment s in out) {
        expect(s.bytes.length % 188, 0, reason: 'alignement paquets');
        // Décodable indépendamment : PAT (pid 0) puis PMT.
        expect(pidOfPacket(s.bytes, 0), 0);
        expect(pidOfPacket(s.bytes, 1), kPmtPid);
        // 3e paquet = début PES vidéo avec image-clé (RAI).
        expect(pidOfPacket(s.bytes, 2), kVideoPid);
        final int afFlags = s.bytes[2 * 188 + 5];
        expect(afFlags & 0x40, isNot(0), reason: 'segment démarre keyframe');
        // Durée honnête, proche de la cible (GOP 1 s → 3.0 exact).
        expect(s.durationSec, inInclusiveRange(2.5, 4.5));
      }
      expect(seg.videoCodec, 'h264');
      expect(seg.audioCodec, 'aac',
          reason: 'piste audio AAC annoncée dans la PMT synthétique');
    });

    test('codec HEVC lu dans la PMT', () {
      final TsHlsSegmenter seg = TsHlsSegmenter();
      seg.ingest(syntheticStream(seconds: 4.0, streamType: 0x24));
      expect(seg.videoCodec, 'hevc');
    });

    test('flush publie le reliquat en fin de connexion', () {
      final TsHlsSegmenter seg = TsHlsSegmenter();
      final List<TsSegment> out = seg.ingest(syntheticStream(seconds: 2.0));
      expect(out, isEmpty, reason: '2 s < cible 3 s : rien de fini');
      final TsSegment? tail = seg.flush();
      expect(tail, isNotNull);
      expect(tail!.durationSec, inInclusiveRange(0.5, 3.0));
    });

    test('ingestion par petits chunks non alignés = même résultat', () {
      final List<int> stream = syntheticStream(seconds: 8.0);
      final TsHlsSegmenter seg = TsHlsSegmenter();
      final List<TsSegment> out = <TsSegment>[];
      for (int i = 0; i < stream.length; i += 1000) {
        out.addAll(seg.ingest(stream.sublist(
            i, i + 1000 > stream.length ? stream.length : i + 1000)));
      }
      expect(out.length, greaterThanOrEqualTo(1));
      expect(out.first.bytes.length % 188, 0);
    });

    test('resynchronisation après octets parasites', () {
      final TsHlsSegmenter seg = TsHlsSegmenter();
      final BytesBuilder b = BytesBuilder()
        ..add(List<int>.filled(97, 0x42)) // bruit avant le 1er sync
        ..add(syntheticStream(seconds: 8.0));
      final List<TsSegment> out = seg.ingest(b.takeBytes());
      expect(out.length, greaterThanOrEqualTo(1));
      expect(seg.videoCodec, 'h264');
    });
  });

  group('TsHlsSegmenter — flux sans random_access_indicator', () {
    test('démarre et découpe quand même (repli sans keyframe)', () {
      // Horloge injectée : le give-up RAI (8 s) est piloté par le test.
      DateTime now = DateTime(2026, 7, 9, 12);
      final TsHlsSegmenter seg = TsHlsSegmenter(clock: () => now);
      final List<TsSegment> out = <TsSegment>[];
      // 1re passe : le segmenteur observe qu'aucun RAI n'arrive.
      out.addAll(seg.ingest(syntheticStream(seconds: 4.0, withRai: false)));
      now = now.add(const Duration(seconds: 9)); // > give-up 8 s
      out.addAll(seg.ingest(syntheticStream(
          seconds: 8.0, withRai: false, startPcr: 14.0)));
      expect(out.length, greaterThanOrEqualTo(1),
          reason: 'découpe au fil des PES même sans RAI');
      for (final TsSegment s in out) {
        expect(pidOfPacket(s.bytes, 0), 0);
        expect(pidOfPacket(s.bytes, 1), kPmtPid);
      }
    });
  });

  group('TsHlsSegmenter — robustesse horloge', () {
    test('saut de PCR (discontinuité serveur) ne produit pas de durée folle',
        () {
      final TsHlsSegmenter seg = TsHlsSegmenter();
      final List<TsSegment> out = <TsSegment>[
        ...seg.ingest(syntheticStream(seconds: 2.0, startPcr: 10.0)),
        // L'horloge upstream saute de 10 000 s (redémarrage encodeur).
        ...seg.ingest(syntheticStream(seconds: 6.0, startPcr: 10000.0)),
      ];
      expect(out, isNotEmpty);
      for (final TsSegment s in out) {
        expect(s.durationSec, lessThanOrEqualTo(30.0));
      }
    });
  });
}
