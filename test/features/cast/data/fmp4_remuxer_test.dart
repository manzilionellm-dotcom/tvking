// =========================================================
//  fmp4_remuxer_test.dart — Ré-emballage TS → fMP4 (AC-3 Chromecast)
// =========================================================
//  Le fMP4 est la seule issue pour l'AC-3/E-AC-3 sur les VRAIS
//  Chromecast : mux.js (récepteur web, chemin TS) ne ré-emballe que
//  l'AAC/MP3, et la TV-directe y est interdite (CORS). On vérifie ici
//  sur des flux TS SYNTHÉTIQUES COMPLETS (PAT + PMT + PES vidéo H.264
//  datés + PES audio AC-3/ADTS, fragmentés sur plusieurs paquets) :
//    - le découpage des trames audio et l'extraction des paramètres
//      dac3/esds ;
//    - la conversion Annex B → AVCC et la lecture du SPS ;
//    - le démux PES (PTS/DTS, PES borné/non borné, à cheval sur deux
//      segments) ;
//    - la structure fMP4 produite (ftyp/moov/moof/mdat, tfdt,
//      data_offset des trun → les octets du mdat sont EXACTEMENT les
//      samples annoncés) ;
//    - la continuité entre segments (séquence, horloges, init unique).
// =========================================================

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/fmp4/audio_frames.dart';
import 'package:tv_king/features/cast/data/fmp4/fmp4_remuxer.dart';
import 'package:tv_king/features/cast/data/fmp4/h264_annexb.dart';
import 'package:tv_king/features/cast/data/fmp4/ts_es_extractor.dart';

// ---------------------------------------------------------
//  Outillage : écriture bit à bit (SPS synthétique mais VALIDE)
// ---------------------------------------------------------

class _BitWriter {
  final List<int> _bytes = <int>[];
  int _cur = 0;
  int _nbits = 0;

  void bit(int b) {
    _cur = (_cur << 1) | (b & 1);
    _nbits++;
    if (_nbits == 8) {
      _bytes.add(_cur);
      _cur = 0;
      _nbits = 0;
    }
  }

  void bits(int v, int n) {
    for (int i = n - 1; i >= 0; i--) {
      bit((v >> i) & 1);
    }
  }

  /// Exp-Golomb non signé.
  void ue(int v) {
    final int code = v + 1;
    final int len = code.bitLength;
    for (int i = 0; i < len - 1; i++) {
      bit(0);
    }
    bits(code, len);
  }

  /// rbsp_trailing_bits : stop bit + alignement.
  Uint8List finishRbsp() {
    bit(1);
    while (_nbits != 0) {
      bit(0);
    }
    return Uint8List.fromList(_bytes);
  }
}

/// SPS H.264 Baseline VALIDE annonçant 640×360 (40×23 macroblocs,
/// rognage bas de 8 pixels). Le parseur du module doit retrouver ces
/// dimensions — c'est le test du lecteur Exp-Golomb.
Uint8List buildSps() {
  final _BitWriter w = _BitWriter();
  w.bits(66, 8); // profile_idc Baseline
  w.bits(0, 8); // constraint flags
  w.bits(30, 8); // level_idc 3.0
  w.ue(0); // seq_parameter_set_id
  w.ue(0); // log2_max_frame_num_minus4
  w.ue(0); // pic_order_cnt_type
  w.ue(0); // log2_max_pic_order_cnt_lsb_minus4
  w.ue(1); // max_num_ref_frames
  w.bit(0); // gaps_in_frame_num_value_allowed
  w.ue(39); // pic_width_in_mbs_minus1 → 640
  w.ue(22); // pic_height_in_map_units_minus1 → 368
  w.bit(1); // frame_mbs_only_flag
  w.bit(1); // direct_8x8_inference
  w.bit(1); // frame_cropping_flag
  w.ue(0); // crop_left
  w.ue(0); // crop_right
  w.ue(0); // crop_top
  w.ue(4); // crop_bottom → 368 − 8 = 360
  final Uint8List rbsp = w.finishRbsp();
  return Uint8List.fromList(<int>[0x67, ...rbsp]); // nal_ref_idc 3, type 7
}

final Uint8List kPps = Uint8List.fromList(<int>[0x68, 0xCE, 0x3C, 0x80]);

/// Unité d'accès Annex B : [SPS+PPS+]IDR ou non-IDR, avec un corps
/// reconnaissable (marqueur) pour vérifier les octets du mdat.
Uint8List buildAccessUnit({required bool idr, required int marker}) {
  final BytesBuilder b = BytesBuilder();
  if (idr) {
    b.add(<int>[0, 0, 0, 1]);
    b.add(buildSps());
    b.add(<int>[0, 0, 0, 1]);
    b.add(kPps);
  }
  b.add(<int>[0, 0, 1]); // start code 3 octets (les deux formes existent)
  b.add(<int>[idr ? 0x65 : 0x41, 0x88, marker & 0xFF, 0x42, 0x99]);
  return b.takeBytes();
}

// ---------------------------------------------------------
//  Outillage : trames audio synthétiques
// ---------------------------------------------------------

/// Trame AC-3 valide : 48 kHz (fscod 0), 384 kbit/s (frmsizecod 28,
/// soit 1536 octets), stéréo (acmod 2), bsid 8. Corps rempli de
/// [fill] pour tracer les octets dans le mdat.
Uint8List buildAc3Frame({int fill = 0xAA}) {
  final Uint8List f = Uint8List(1536);
  f.fillRange(0, f.length, fill);
  f[0] = 0x0B;
  f[1] = 0x77;
  f[2] = 0x00; // crc1
  f[3] = 0x00;
  f[4] = (0 << 6) | 28; // fscod 0 (48 kHz) | frmsizecod 28 (384 kbit/s)
  f[5] = (8 << 3) | 0; // bsid 8 | bsmod 0
  // acmod 2 (stéréo) → dsurmod(2) présent puis lfeon(1) = 0.
  f[6] = 2 << 5;
  return f;
}

/// Trame ADTS AAC-LC 48 kHz stéréo, payload [payloadLen] octets.
Uint8List buildAdtsFrame({int payloadLen = 64, int fill = 0x55}) {
  final int frameLen = 7 + payloadLen;
  final Uint8List f = Uint8List(frameLen);
  f.fillRange(7, frameLen, fill);
  f[0] = 0xFF;
  f[1] = 0xF1; // MPEG-4, sans CRC
  f[2] = (1 << 6) | (3 << 2); // profile AAC-LC (1) | freq index 3 (48 kHz)
  f[3] = (2 << 6) | ((frameLen >> 11) & 0x03); // 2 canaux
  f[4] = (frameLen >> 3) & 0xFF;
  f[5] = ((frameLen & 0x07) << 5) | 0x1F;
  f[6] = 0xFC;
  return f;
}

// ---------------------------------------------------------
//  Outillage : multiplexeur TS minimal (PES → paquets 188)
// ---------------------------------------------------------

const int kPmtPid = 0x1000;
const int kVideoPid = 0x100;
const int kAudioPid = 0x101;

Uint8List _tsPacket({
  required int pid,
  required bool pusi,
  required int cc,
  required List<int> payload,
}) {
  assert(payload.length <= 184);
  final Uint8List p = Uint8List(188);
  p[0] = 0x47;
  p[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
  p[2] = pid & 0xFF;
  if (payload.length == 184) {
    p[3] = 0x10 | (cc & 0x0F); // payload seul
    p.setRange(4, 188, payload);
  } else {
    // Bourrage par champ d'adaptation (comme un vrai multiplexeur).
    p[3] = 0x30 | (cc & 0x0F);
    final int afLen = 183 - payload.length;
    p[4] = afLen;
    if (afLen > 0) p[5] = 0x00;
    for (int i = 6; i < 5 + afLen; i++) {
      p[i] = 0xFF;
    }
    p.setRange(5 + afLen, 188, payload);
  }
  return p;
}

/// En-tête PES + payload, découpés en paquets TS de 188 octets.
List<Uint8List> pesToTs({
  required int pid,
  required int streamId,
  required List<int> es,
  int? pts90k,
  int? dts90k,
  required int ccStart,
  bool bounded = false,
}) {
  final List<int> header = <int>[0x00, 0x00, 0x01, streamId];
  final List<int> optional = <int>[];
  int flags = 0;
  if (pts90k != null) {
    flags |= 0x80;
    optional.addAll(_timestamp(pts90k, dts90k != null ? 0x3 : 0x2));
    if (dts90k != null) {
      flags |= 0x40;
      optional.addAll(_timestamp(dts90k, 0x1));
    }
  }
  final int pesLen = bounded ? 3 + optional.length + es.length : 0;
  header.addAll(<int>[(pesLen >> 8) & 0xFF, pesLen & 0xFF]);
  header.addAll(<int>[0x80, flags, optional.length]);
  header.addAll(optional);
  header.addAll(es);

  final List<Uint8List> out = <Uint8List>[];
  int cc = ccStart;
  for (int off = 0; off < header.length; off += 184) {
    final int end = (off + 184 > header.length) ? header.length : off + 184;
    out.add(_tsPacket(
      pid: pid,
      pusi: off == 0,
      cc: cc++,
      payload: header.sublist(off, end),
    ));
  }
  return out;
}

List<int> _timestamp(int ts, int prefix) {
  return <int>[
    (prefix << 4) | (((ts >> 30) & 0x07) << 1) | 1,
    (ts >> 22) & 0xFF,
    (((ts >> 15) & 0x7F) << 1) | 1,
    (ts >> 7) & 0xFF,
    ((ts & 0x7F) << 1) | 1,
  ];
}

Uint8List _patPacket() {
  final List<int> section = <int>[
    0x00, 0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00,
    0x00, 0x01, 0xE0 | ((kPmtPid >> 8) & 0x1F), kPmtPid & 0xFF,
    0xDE, 0xAD, 0xBE, 0xEF,
  ];
  return _tsPacket(pid: 0, pusi: true, cc: 0, payload: section);
}

/// PMT : vidéo H.264 + audio [audioStreamType] (défaut AC-3 ATSC
/// 0x81). [dvbDescriptorTag] simule la variante DVB : stream_type
/// 0x06 + descripteur (0x6A = AC-3).
Uint8List _pmtPacket({int audioStreamType = 0x81, int? dvbDescriptorTag}) {
  final int esInfoLen = dvbDescriptorTag != null ? 2 : 0;
  final List<int> section = <int>[
    0x00, 0x02, 0xB0, 13 + 5 + 5 + esInfoLen, 0x00, 0x01, 0xC1, 0x00, 0x00,
    0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF,
    0xF0, 0x00,
    0x1B, // H.264
    0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF,
    0xF0, 0x00,
    dvbDescriptorTag != null ? 0x06 : audioStreamType,
    0xE0 | ((kAudioPid >> 8) & 0x1F), kAudioPid & 0xFF,
    0xF0, esInfoLen,
    if (dvbDescriptorTag != null) ...<int>[dvbDescriptorTag, 0x00],
    0xDE, 0xAD, 0xBE, 0xEF,
  ];
  return _tsPacket(pid: kPmtPid, pusi: true, cc: 0, payload: section);
}

/// Un segment TS complet, comme le produirait TsHlsSegmenter : PAT +
/// PMT en tête, puis [frames] images à 25 i/s (PTS = DTS + 3600 pour
/// exercer le CTS), audio AC-3 intercalé.
Uint8List buildTsSegment({
  required int frames,
  required int firstDts90k,
  bool firstIsIdr = true,
  List<List<int>> audioPes = const <List<int>>[],
  List<int?> audioPts = const <int?>[],
  int audioStreamType = 0x81,
  int? dvbDescriptorTag,
}) {
  final BytesBuilder b = BytesBuilder();
  b.add(_patPacket());
  b.add(_pmtPacket(
    audioStreamType: audioStreamType,
    dvbDescriptorTag: dvbDescriptorTag,
  ));
  int ccV = 0;
  int ccA = 0;
  for (int f = 0; f < frames; f++) {
    final int dts = firstDts90k + f * 3600;
    for (final Uint8List p in pesToTs(
      pid: kVideoPid,
      streamId: 0xE0,
      es: buildAccessUnit(idr: f == 0 && firstIsIdr, marker: f),
      pts90k: dts + 3600,
      dts90k: dts,
      ccStart: ccV,
    )) {
      b.add(p);
      ccV++;
    }
    // Audio réparti au fil des images.
    if (f < audioPes.length) {
      for (final Uint8List p in pesToTs(
        pid: kAudioPid,
        streamId: 0xBD,
        es: audioPes[f],
        pts90k: f < audioPts.length ? audioPts[f] : null,
        ccStart: ccA,
        bounded: true,
      )) {
        b.add(p);
        ccA++;
      }
    }
  }
  return b.takeBytes();
}

// ---------------------------------------------------------
//  Outillage : mini-parseur de boîtes MP4
// ---------------------------------------------------------

class _Box {
  _Box(this.type, this.offset, this.size, this.payload);
  final String type;
  final int offset; // offset absolu dans le buffer d'origine
  final int size;
  final Uint8List payload;
}

List<_Box> parseBoxes(Uint8List buf, {int base = 0}) {
  final List<_Box> out = <_Box>[];
  int off = 0;
  while (off + 8 <= buf.length) {
    final int size = (buf[off] << 24) |
        (buf[off + 1] << 16) |
        (buf[off + 2] << 8) |
        buf[off + 3];
    final String type = String.fromCharCodes(buf, off + 4, off + 8);
    if (size < 8 || off + size > buf.length) break;
    out.add(_Box(type, base + off,
        size, Uint8List.sublistView(buf, off + 8, off + size)));
    off += size;
  }
  return out;
}

_Box boxOf(List<_Box> boxes, String type) =>
    boxes.firstWhere((_Box b) => b.type == type,
        orElse: () => fail('boîte $type introuvable dans '
            '${boxes.map((_Box b) => b.type).toList()}'));

int u32(Uint8List b, int off) =>
    (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

int u64(Uint8List b, int off) => (u32(b, off) << 32) | u32(b, off + 4);

void main() {
  group('audio_frames — découpage AC-3', () {
    test('trames complètes découpées, reliquat rendu, config dac3 exacte',
        () {
      final BytesBuilder es = BytesBuilder()
        ..add(buildAc3Frame(fill: 0x01))
        ..add(buildAc3Frame(fill: 0x02))
        ..add(buildAc3Frame(fill: 0x03).sublist(0, 700)); // tronquée
      final AudioSplitResult r = splitAc3Frames(es.takeBytes());
      expect(r.frames.length, 2);
      expect(r.frames[0].sampleCount, 1536);
      expect(r.frames[0].sampleRate, 48000);
      expect(r.rest.length, 700, reason: 'trame incomplète = reliquat');
      expect(r.config, isNotNull);
      expect(r.config!.codec, 'ac3');
      expect(r.config!.rfc6381, 'ac-3');
      expect(r.config!.channelCount, 2);
      // dac3 : fscod 0, bsid 8, bsmod 0, acmod 2, lfeon 0, brc 14.
      expect(r.config!.codecConfigBytes, <int>[0x10, 0x11, 0xC0]);
    });

    test('bruit avant le syncword : re-synchronisation', () {
      final BytesBuilder es = BytesBuilder()
        ..add(<int>[0x00, 0x0B, 0x12, 0x77]) // faux départs
        ..add(buildAc3Frame());
      final AudioSplitResult r = splitAc3Frames(es.takeBytes());
      expect(r.frames.length, 1);
    });
  });

  group('audio_frames — découpage ADTS (AAC)', () {
    test('en-tête retiré, config esds (ASC) exacte', () {
      final BytesBuilder es = BytesBuilder()
        ..add(buildAdtsFrame(payloadLen: 64, fill: 0x11))
        ..add(buildAdtsFrame(payloadLen: 32, fill: 0x22));
      final AudioSplitResult r = splitAdtsFrames(es.takeBytes());
      expect(r.frames.length, 2);
      expect(r.frames[0].bytes.length, 64, reason: 'ADTS retiré');
      expect(r.frames[0].bytes[0], 0x11);
      expect(r.frames[0].sampleCount, 1024);
      expect(r.config!.codec, 'aac');
      expect(r.config!.rfc6381, 'mp4a.40.2');
      expect(r.config!.channelCount, 2);
      // ASC : objectType 2, freqIdx 3 (48 kHz), chanCfg 2 → 0x11 0x90.
      expect(r.config!.codecConfigBytes, <int>[0x11, 0x90]);
    });
  });

  group('h264_annexb', () {
    test('découpe NAL (start codes 3 et 4 octets) et AVCC', () {
      final Uint8List au = buildAccessUnit(idr: true, marker: 7);
      final List<Uint8List> nals = splitAnnexBNals(au);
      expect(nals.length, 3, reason: 'SPS + PPS + slice IDR');
      expect(nalType(nals[0]), kNalSps);
      expect(nalType(nals[1]), kNalPps);
      expect(nalType(nals[2]), kNalIdr);
      final Uint8List avcc = nalsToAvcc(nals);
      // Chaque NAL préfixée par sa longueur : la relecture retombe
      // exactement sur les mêmes octets.
      int off = 0;
      for (final Uint8List nal in nals) {
        final int len = u32(avcc, off);
        expect(len, nal.length);
        expect(avcc.sublist(off + 4, off + 4 + len), nal);
        off += 4 + len;
      }
      expect(off, avcc.length);
    });

    test('dimensions lues dans le SPS (Exp-Golomb + rognage)', () {
      final ({int width, int height})? dims = parseSpsDimensions(buildSps());
      expect(dims, isNotNull);
      expect(dims!.width, 640);
      expect(dims.height, 360);
    });

    test('étiquette RFC 6381', () {
      expect(avc1CodecString(buildSps()), 'avc1.42001e');
    });

    test('SPS tronqué → null (pas d\'exception)', () {
      expect(parseSpsDimensions(Uint8List.fromList(<int>[0x67, 66])), isNull);
    });
  });

  group('ts_es_extractor — démux PES', () {
    test('PTS/DTS relus, PES vidéo non borné clos en fin de segment', () {
      final Uint8List ts = buildTsSegment(frames: 3, firstDts90k: 900000);
      final TsEsExtraction ex = TsEsExtractor().extract(ts);
      expect(ex.videoCodec, 'h264');
      expect(ex.audioCodec, 'ac3');
      expect(ex.videoUnits.length, 3);
      expect(ex.videoUnits[0].dts90k, 900000);
      expect(ex.videoUnits[0].pts90k, 903600);
      expect(ex.videoUnits[2].dts90k, 900000 + 2 * 3600);
      // La payload relue est EXACTEMENT l'unité d'accès mise en PES.
      expect(ex.videoUnits[1].bytes,
          buildAccessUnit(idr: false, marker: 1));
    });

    test(
        'PES audio BORNÉ : émis dès sa longueur déclarée atteinte, '
        'stuffing TS coupé', () {
      final Uint8List frame = buildAc3Frame();
      final Uint8List ts = buildTsSegment(
        frames: 2,
        firstDts90k: 90000,
        audioPes: <List<int>>[frame],
        audioPts: <int?>[90000],
      );
      final TsEsExtraction ex = TsEsExtractor().extract(ts);
      // La longueur PES fait foi : l'audio du segment reste dans SON
      // segment (l'init fMP4 connaît la piste dès le 1er segment).
      expect(ex.audioUnits.length, 1);
      expect(ex.audioUnits[0].bytes, frame,
          reason: 'payload exacte, stuffing exclu');
      expect(ex.audioUnits[0].pts90k, 90000);
    });

    test('PES audio À CHEVAL sur deux segments : ZÉRO trame perdue', () {
      // Le segmenteur coupe sur un début de PES VIDÉO : un PES audio
      // commencé avant la coupe finit dans le segment suivant. On
      // reconstruit ce cas à la main : la trame A est répartie sur
      // 9 paquets TS, seul le premier est dans le segment 1.
      final Uint8List frameA = buildAc3Frame(fill: 0x0A);
      final List<Uint8List> audioPackets = pesToTs(
        pid: kAudioPid,
        streamId: 0xBD,
        es: frameA,
        pts90k: 90000,
        ccStart: 0,
        bounded: true,
      );
      expect(audioPackets.length, greaterThan(2));

      final BytesBuilder seg1 = BytesBuilder()
        ..add(_patPacket())
        ..add(_pmtPacket());
      for (final Uint8List p in pesToTs(
        pid: kVideoPid,
        streamId: 0xE0,
        es: buildAccessUnit(idr: true, marker: 0),
        pts90k: 93600,
        dts90k: 90000,
        ccStart: 0,
      )) {
        seg1.add(p);
      }
      seg1.add(audioPackets.first); // PES audio COMMENCÉ…

      final BytesBuilder seg2 = BytesBuilder()
        ..add(_patPacket())
        ..add(_pmtPacket());
      for (final Uint8List p in audioPackets.skip(1)) {
        seg2.add(p); // …TERMINÉ dans le segment suivant.
      }
      for (final Uint8List p in pesToTs(
        pid: kVideoPid,
        streamId: 0xE0,
        es: buildAccessUnit(idr: false, marker: 1),
        pts90k: 97200,
        dts90k: 93600,
        ccStart: 8,
      )) {
        seg2.add(p);
      }

      final TsEsExtractor x = TsEsExtractor();
      final TsEsExtraction ex1 = x.extract(seg1.takeBytes());
      expect(ex1.audioUnits, isEmpty, reason: 'PES A encore ouvert');
      final TsEsExtraction ex2 = x.extract(seg2.takeBytes());
      expect(ex2.audioUnits.length, 1);
      expect(ex2.audioUnits[0].bytes, frameA,
          reason: 'trame complète malgré la frontière');
      expect(ex2.audioUnits[0].pts90k, 90000);
    });

    test('dropPending (discontinuité) : le PES en cours est jeté', () {
      final Uint8List frameA = buildAc3Frame(fill: 0x0A);
      final List<Uint8List> audioPackets = pesToTs(
        pid: kAudioPid,
        streamId: 0xBD,
        es: frameA,
        pts90k: 90000,
        ccStart: 0,
        bounded: true,
      );
      final BytesBuilder seg1 = BytesBuilder()
        ..add(_patPacket())
        ..add(_pmtPacket())
        ..add(audioPackets.first);
      final BytesBuilder seg2 = BytesBuilder();
      for (final Uint8List p in audioPackets.skip(1)) {
        seg2.add(p);
      }
      final TsEsExtractor x = TsEsExtractor();
      x.extract(seg1.takeBytes());
      x.dropPending();
      final TsEsExtraction ex2 = x.extract(seg2.takeBytes());
      expect(ex2.audioUnits, isEmpty,
          reason: 'les octets de l\'ancienne ligne de temps sont jetés');
    });
  });

  group('Fmp4Remuxer — bout en bout', () {
    test('init (ftyp/moov, avcC, dac3) + média (moof/mdat) cohérents', () {
      final Uint8List ts = buildTsSegment(
        frames: 4,
        firstDts90k: 900000,
        audioPes: <List<int>>[buildAc3Frame(fill: 0x77)],
        audioPts: <int?>[900000],
      );
      // Deux segments : le PES audio de seg1 est livré avec seg2.
      final Uint8List ts2 = buildTsSegment(
        frames: 2,
        firstDts90k: 900000 + 4 * 3600,
        firstIsIdr: false,
        audioPes: <List<int>>[buildAc3Frame(fill: 0x78)],
        audioPts: <int?>[914400],
      );
      final Fmp4Remuxer mux = Fmp4Remuxer();
      final Fmp4RemuxResult? r1 = mux.remux(ts);
      expect(r1, isNotNull);
      expect(r1!.init, isNotNull, reason: '1er segment → init générée');
      expect(r1.init!.codecs, 'avc1.42001e,ac-3');
      expect(r1.droppedAudioCodec, isNull);

      // ---- Structure de l'init ----
      final List<_Box> initBoxes = parseBoxes(r1.init!.bytes);
      expect(initBoxes.map((_Box b) => b.type), <String>['ftyp', 'moov']);
      final List<_Box> moov = parseBoxes(boxOf(initBoxes, 'moov').payload);
      expect(moov.where((_Box b) => b.type == 'trak').length, 2);
      expect(boxOf(moov, 'mvex'), isNotNull);
      // avcC : SPS/PPS embarqués tels quels.
      final Uint8List moovBytes = boxOf(initBoxes, 'moov').payload;
      final String moovStr = String.fromCharCodes(moovBytes);
      expect(moovStr.contains('avcC'), isTrue);
      expect(moovStr.contains('dac3'), isTrue);

      // ---- Structure du segment média ----
      final List<_Box> media = parseBoxes(r1.media.bytes);
      expect(media.map((_Box b) => b.type), <String>['moof', 'mdat']);
      final _Box moof = boxOf(media, 'moof');
      final List<_Box> moofKids = parseBoxes(moof.payload, base: 8);
      final _Box mfhd = boxOf(moofKids, 'mfhd');
      expect(u32(mfhd.payload, 4), 1, reason: 'sequence_number = 1');
      final List<_Box> trafs =
          moofKids.where((_Box b) => b.type == 'traf').toList();
      expect(trafs.length, 2, reason: 'vidéo + audio');

      // traf vidéo : tfdt = premier DTS (900000), trun cohérent.
      final List<_Box> vTraf = parseBoxes(trafs[0].payload,
          base: trafs[0].offset + 8);
      final _Box vTfdt = boxOf(vTraf, 'tfdt');
      expect(vTfdt.payload[0], 1, reason: 'tfdt version 1 (64 bits)');
      expect(u64(vTfdt.payload, 4), 900000);
      final _Box vTrun = boxOf(vTraf, 'trun');
      final int vCount = u32(vTrun.payload, 4);
      expect(vCount, 4);
      final int vDataOffset = u32(vTrun.payload, 8);
      // data_offset relatif au début du moof → 1er sample vidéo.
      final Uint8List all = r1.media.bytes;
      final int base = vDataOffset; // moof commence à 0
      final Uint8List firstSample = Uint8List.sublistView(
          all, base, base + u32(vTrun.payload, 12 + 4));
      // Le 1er sample est l'AVCC de l'AU 0 (SPS+PPS+IDR).
      final Uint8List expectedAvcc =
          nalsToAvcc(splitAnnexBNals(buildAccessUnit(idr: true, marker: 0)));
      expect(firstSample, expectedAvcc,
          reason: 'les octets du mdat sont exactement les samples annoncés');
      // Durées : 3600 ticks (25 i/s) partout ; keyframe sur le 1er.
      expect(u32(vTrun.payload, 12), 3600);
      final int firstFlags = u32(vTrun.payload, 12 + 8);
      expect(firstFlags, 0x02000000, reason: 'IDR = sync sample');
      final int secondFlags = u32(vTrun.payload, 12 + 16 + 8);
      expect(secondFlags, 0x01010000, reason: 'non-IDR = non-sync');
      // CTS : PTS − DTS = 3600 sur toutes les images.
      expect(u32(vTrun.payload, 12 + 12), 3600);

      // Audio du segment 1 : une trame AC-3, tfdt = PTS converti en
      // ticks 48 kHz (900000 × 48000 / 90000), et les octets du mdat
      // sont EXACTEMENT la trame.
      final List<_Box> aTraf1 = parseBoxes(trafs[1].payload);
      final _Box aTfdt1 = boxOf(aTraf1, 'tfdt');
      expect(u64(aTfdt1.payload, 4), 900000 * 48000 ~/ 90000);
      final _Box aTrun1 = boxOf(aTraf1, 'trun');
      expect(u32(aTrun1.payload, 4), 1, reason: 'une trame AC-3');
      expect(u32(aTrun1.payload, 12), 1536, reason: 'durée = 1536 ticks');
      final int aDataOffset = u32(aTrun1.payload, 8);
      final Uint8List audioBytes = Uint8List.sublistView(
          all, aDataOffset, aDataOffset + u32(aTrun1.payload, 12 + 4));
      expect(audioBytes, buildAc3Frame(fill: 0x77));
      // Durée EXTINF honnête : 4 images à 25 i/s.
      expect(r1.media.durationSec, closeTo(4 / 25.0, 0.001));

      // ---- Segment 2 : continuité ----
      final Fmp4RemuxResult? r2 = mux.remux(ts2);
      expect(r2, isNotNull);
      expect(r2!.init, isNull, reason: 'config inchangée → pas de ré-init');
      final List<_Box> media2 = parseBoxes(r2.media.bytes);
      final List<_Box> moof2Kids =
          parseBoxes(boxOf(media2, 'moof').payload, base: 8);
      expect(u32(boxOf(moof2Kids, 'mfhd').payload, 4), 2);
      final List<_Box> trafs2 =
          moof2Kids.where((_Box b) => b.type == 'traf').toList();
      expect(trafs2.length, 2);
      // tfdt vidéo du segment 2 = DTS réel (continuité d'horloge).
      final _Box vTfdt2 = boxOf(parseBoxes(trafs2[0].payload), 'tfdt');
      expect(u64(vTfdt2.payload, 4), 900000 + 4 * 3600);
      // tfdt audio du segment 2 = PTS de SA trame (914400 × 48/90).
      final _Box aTfdt2 = boxOf(parseBoxes(trafs2[1].payload), 'tfdt');
      expect(u64(aTfdt2.payload, 4), 914400 * 48000 ~/ 90000);
      // Durée EXTINF honnête : 2 images à 25 i/s.
      expect(r2.media.durationSec, closeTo(2 / 25.0, 0.001));
    });

    test('audio DVB (stream_type 0x06 + descripteur 0x6A) → ac-3 aussi',
        () {
      final Uint8List ts = buildTsSegment(
        frames: 2,
        firstDts90k: 90000,
        dvbDescriptorTag: 0x6A,
        audioPes: <List<int>>[buildAc3Frame()],
        audioPts: <int?>[90000],
      );
      final Fmp4RemuxResult? r = Fmp4Remuxer().remux(ts);
      expect(r, isNotNull);
      expect(r!.init!.codecs, 'avc1.42001e,ac-3');
    });

    test('audio MP2 (non transportable v1) → fMP4 vidéo seule + signal',
        () {
      final Uint8List ts = buildTsSegment(
        frames: 2,
        firstDts90k: 90000,
        audioStreamType: 0x03, // MPEG-1 layer II
        audioPes: <List<int>>[
          <int>[0xFF, 0xFD, 0x00, 0x00, 1, 2, 3],
        ],
        audioPts: <int?>[90000],
      );
      final Fmp4RemuxResult? r = Fmp4Remuxer().remux(ts);
      expect(r, isNotNull);
      expect(r!.init!.codecs, 'avc1.42001e', reason: 'pas de piste audio');
      expect(r.droppedAudioCodec, 'mp2',
          reason: 'l\'appelant journalise le WARN boîte noire');
    });

    test('discontinuité : horloges ré-ancrées, pas de ré-init inutile', () {
      final Fmp4Remuxer mux = Fmp4Remuxer();
      final Fmp4RemuxResult? r1 = mux.remux(buildTsSegment(
        frames: 3,
        firstDts90k: 90000,
      ));
      expect(r1, isNotNull);
      // Splice : l'horloge repart très en arrière (nouvelle timeline).
      final Fmp4RemuxResult? r2 = mux.remux(
        buildTsSegment(frames: 3, firstDts90k: 4500),
        discontinuity: true,
      );
      expect(r2, isNotNull);
      expect(r2!.init, isNull, reason: 'mêmes SPS/PPS → même init');
      final List<_Box> kids =
          parseBoxes(boxOf(parseBoxes(r2.media.bytes), 'moof').payload);
      final _Box traf = kids.firstWhere((_Box b) => b.type == 'traf');
      final _Box tfdt = boxOf(parseBoxes(traf.payload), 'tfdt');
      expect(u64(tfdt.payload, 4), 4500,
          reason: 'ré-ancrage : le tfdt suit la nouvelle horloge');
    });

    test('wrap 33 bits du PTS/DTS : tfdt reste monotone (64 bits)', () {
      const int nearWrap = (1 << 33) - 2 * 3600; // 2 images avant le wrap
      final Fmp4Remuxer mux = Fmp4Remuxer();
      final Fmp4RemuxResult? r1 = mux.remux(buildTsSegment(
        frames: 2,
        firstDts90k: nearWrap,
      ));
      expect(r1, isNotNull);
      // Le segment suivant est APRÈS le wrap : DTS bruts minuscules.
      final Fmp4RemuxResult? r2 = mux.remux(buildTsSegment(
        frames: 2,
        firstDts90k: 0,
        firstIsIdr: false,
      ));
      expect(r2, isNotNull);
      final List<_Box> kids =
          parseBoxes(boxOf(parseBoxes(r2!.media.bytes), 'moof').payload);
      final _Box traf = kids.firstWhere((_Box b) => b.type == 'traf');
      final _Box tfdt = boxOf(parseBoxes(traf.payload), 'tfdt');
      expect(u64(tfdt.payload, 4), 1 << 33,
          reason: 'horloge déroulée : 0 brut = 2^33 monotone');
    });

    test(
        'trame AC-3 coupée entre deux segments (mux non aligné) : '
        'reportée, pas perdue', () {
      final Uint8List frameA = buildAc3Frame(fill: 0x0C);
      final Uint8List frameB = buildAc3Frame(fill: 0x0D);
      // Segment 1 : un PES audio borné dont la payload s'arrête EN
      // PLEIN MILIEU de la trame A (multiplexeur non aligné).
      final Uint8List seg1 = buildTsSegment(
        frames: 2,
        firstDts90k: 90000,
        audioPes: <List<int>>[frameA.sublist(0, 1000)],
        audioPts: <int?>[90000],
      );
      // Segment 2 : la suite de la trame A + la trame B.
      final Uint8List seg2 = buildTsSegment(
        frames: 2,
        firstDts90k: 97200,
        firstIsIdr: false,
        audioPes: <List<int>>[
          <int>[...frameA.sublist(1000), ...frameB],
        ],
        audioPts: <int?>[92880],
      );
      final Fmp4Remuxer mux = Fmp4Remuxer();
      final Fmp4RemuxResult? r1 = mux.remux(seg1);
      expect(r1, isNotNull, reason: 'vidéo seule en attendant l\'audio');
      final Fmp4RemuxResult? r2 = mux.remux(seg2);
      expect(r2, isNotNull);
      // Les DEUX trames sont là : A recomposée du reliquat + B.
      final List<_Box> kids =
          parseBoxes(boxOf(parseBoxes(r2!.media.bytes), 'moof').payload);
      final List<_Box> trafs =
          kids.where((_Box b) => b.type == 'traf').toList();
      expect(trafs.length, 2);
      final _Box aTrun = boxOf(parseBoxes(trafs[1].payload), 'trun');
      expect(u32(aTrun.payload, 4), 2, reason: 'trames A et B');
      final int off = u32(aTrun.payload, 8);
      final Uint8List bytes = Uint8List.sublistView(
          r2.media.bytes, off, off + 2 * 1536);
      expect(bytes.sublist(0, 1536), frameA);
      expect(bytes.sublist(1536), frameB);
    });

    test('vidéo HEVC → refus propre (le TS reste la voie)', () {
      final BytesBuilder b = BytesBuilder();
      b.add(_patPacket());
      // PMT HEVC (0x24) + audio AC-3.
      final List<int> section = <int>[
        0x00, 0x02, 0xB0, 18, 0x00, 0x01, 0xC1, 0x00, 0x00,
        0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF,
        0xF0, 0x00,
        0x24,
        0xE0 | ((kVideoPid >> 8) & 0x1F), kVideoPid & 0xFF,
        0xF0, 0x00,
        0xDE, 0xAD, 0xBE, 0xEF,
      ];
      b.add(_tsPacket(pid: kPmtPid, pusi: true, cc: 0, payload: section));
      for (final Uint8List p in pesToTs(
        pid: kVideoPid,
        streamId: 0xE0,
        es: buildAccessUnit(idr: true, marker: 0),
        pts90k: 93600,
        dts90k: 90000,
        ccStart: 0,
      )) {
        b.add(p);
      }
      expect(Fmp4Remuxer().remux(b.takeBytes()), isNull);
    });
  });
}
