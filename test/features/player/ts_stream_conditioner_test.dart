// =========================================================
//  ts_stream_conditioner_test.dart — Hygiène du flux TS relayé
// =========================================================
//  Vérifie octet par octet les trois briques de résilience du relais :
//    1. TsSyncAligner : après une reconnexion en plein milieu de paquet,
//       le décodeur ne reçoit JAMAIS un demi-paquet — on jette jusqu'au
//       premier point de synchronisation fiable (3 × 0x47 espacés de 188).
//    2. TsRingBuffer : la mémoire glissante rend un instantané qui
//       commence toujours sur une frontière de paquet, même après
//       éviction d'un nombre d'octets non multiple de 188.
//    3. IngestRateMeter : le débit mesuré correspond aux octets réellement
//       reçus dans la fenêtre (horodatages injectés, zéro sleep).
// =========================================================

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/ts_stream_conditioner.dart';

/// Fabrique [count] paquets TS valides (0x47 + 187 octets de charge utile
/// pseudo-aléatoire SANS 0x47, pour que seul le vrai octet de synchro
/// puisse accrocher l'aligneur).
Uint8List tsPackets(int count, {int seed = 1}) {
  final Uint8List out = Uint8List(count * kTsPacketSize);
  int v = seed;
  for (int p = 0; p < count; p++) {
    out[p * kTsPacketSize] = kTsSyncByte;
    for (int i = 1; i < kTsPacketSize; i++) {
      v = (v * 1103515245 + 12345) & 0x7fffffff;
      int b = v & 0xff;
      if (b == kTsSyncByte) b = 0x48; // jamais de faux 0x47
      out[p * kTsPacketSize + i] = b;
    }
  }
  return out;
}

void main() {
  group('TsSyncAligner', () {
    test('flux déjà aligné : tout passe, rien de jeté', () {
      final TsSyncAligner aligner = TsSyncAligner();
      final Uint8List stream = tsPackets(5);
      final List<int> out = aligner.feed(stream);
      expect(out, stream);
      expect(aligner.isLocked, isTrue);
      expect(aligner.discardedBytes, 0);
    });

    test('reconnexion en milieu de paquet : le demi-paquet est jeté', () {
      final TsSyncAligner aligner = TsSyncAligner();
      final Uint8List stream = tsPackets(5);
      // Le serveur repart 100 octets APRÈS une frontière de paquet.
      final Uint8List cut = Uint8List.sublistView(stream, 100);
      final List<int> out = aligner.feed(cut);
      // On doit retomber pile sur le paquet n°2 (premier complet visible).
      expect(out.length, 4 * kTsPacketSize);
      expect(out[0], kTsSyncByte);
      expect(aligner.discardedBytes, kTsPacketSize - 100);
      expect(out, Uint8List.sublistView(stream, kTsPacketSize));
    });

    test('un 0x47 accidentel dans la charge utile ne verrouille pas', () {
      final TsSyncAligner aligner = TsSyncAligner();
      // 50 octets de bruit contenant un 0x47 isolé, puis de vrais paquets.
      final Uint8List noise = Uint8List.fromList(
          List<int>.generate(50, (int i) => i == 10 ? kTsSyncByte : 0x11));
      final Uint8List stream = tsPackets(4);
      final BytesBuilder b = BytesBuilder()..add(noise)..add(stream);
      final List<int> out = aligner.feed(b.takeBytes());
      expect(out.length, 4 * kTsPacketSize);
      expect(out, stream);
    });

    test('synchro trouvée à cheval sur plusieurs chunks', () {
      final TsSyncAligner aligner = TsSyncAligner();
      final Uint8List stream = tsPackets(6);
      final Uint8List cut = Uint8List.sublistView(stream, 77);
      final List<int> got = <int>[];
      // On nourrit par petits morceaux de 150 octets (< 1 paquet).
      for (int i = 0; i < cut.length; i += 150) {
        final int end = (i + 150).clamp(0, cut.length);
        got.addAll(aligner.feed(Uint8List.sublistView(cut, i, end)));
      }
      expect(aligner.isLocked, isTrue);
      // Tout ce qui sort, mis bout à bout, doit être le flux à partir du
      // paquet n°1 (frontière suivante après l'octet 77).
      expect(got, Uint8List.sublistView(stream, kTsPacketSize));
    });

    test('une fois verrouillé, les chunks passent tels quels', () {
      final TsSyncAligner aligner = TsSyncAligner();
      aligner.feed(tsPackets(3));
      expect(aligner.isLocked, isTrue);
      // Même un chunk SANS 0x47 en tête passe : la continuité du flux fait
      // foi une fois la synchro acquise (les frontières tombent où elles
      // tombent dans les chunks TCP).
      final List<int> odd = List<int>.filled(100, 0x22);
      expect(aligner.feed(odd), odd);
    });
  });

  group('TsRingBuffer', () {
    test('instantané aligné après éviction non multiple de 188', () {
      final TsRingBuffer ring = TsRingBuffer(capacityBytes: 1000);
      final Uint8List stream = tsPackets(12); // 2256 octets > capacité
      // Versé en chunks de tailles irrégulières (comme TCP).
      int i = 0;
      for (final int size in <int>[500, 300, 700, 756]) {
        ring.add(Uint8List.sublistView(stream, i, i + size));
        i += size;
      }
      expect(ring.size, lessThanOrEqualTo(1000));
      final Uint8List snap = ring.alignedSnapshot();
      expect(snap, isNotEmpty);
      expect(snap[0], kTsSyncByte);
      // L'instantané doit être un SUFFIXE aligné du flux d'origine.
      final int offset = stream.length - snap.length;
      expect(offset % kTsPacketSize, 0);
      expect(snap, Uint8List.sublistView(stream, offset));
    });

    test('clear() vide tout (reconnexion : pas de raccord bancal)', () {
      final TsRingBuffer ring = TsRingBuffer(capacityBytes: 1000);
      ring.add(tsPackets(3));
      ring.clear();
      expect(ring.size, 0);
      expect(ring.alignedSnapshot(), isEmpty);
      // Après clear, un nouveau flux aligné repart proprement à l'offset 0.
      final Uint8List fresh = tsPackets(2, seed: 9);
      ring.add(fresh);
      expect(ring.alignedSnapshot(), fresh);
    });

    test('contenu plus petit que la capacité : rendu intégral', () {
      final TsRingBuffer ring = TsRingBuffer(capacityBytes: 1024 * 1024);
      final Uint8List stream = tsPackets(4);
      ring.add(stream);
      expect(ring.alignedSnapshot(), stream);
    });
  });

  group('IngestRateMeter', () {
    test('débit moyen sur la fenêtre', () {
      final IngestRateMeter meter = IngestRateMeter();
      final DateTime t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // 100 000 octets/s pendant 5 s.
      for (int s = 0; s <= 5; s++) {
        meter.addBytes(100000, t0.add(Duration(seconds: s)));
      }
      final double? rate = meter.bytesPerSecond(t0.add(const Duration(seconds: 5)));
      expect(rate, isNotNull);
      // 600 000 octets sur 5 s de fenêtre = 120 000/s (le 1er échantillon
      // borne la fenêtre) — l'ordre de grandeur est ce qui compte.
      expect(rate, greaterThan(90000));
      expect(rate, lessThan(150000));
    });

    test('null tant que le recul est < 2 s (pas de moyenne mensongère)', () {
      final IngestRateMeter meter = IngestRateMeter();
      final DateTime t0 = DateTime(2026, 1, 1);
      meter.addBytes(5000, t0);
      meter.addBytes(5000, t0.add(const Duration(milliseconds: 500)));
      expect(meter.bytesPerSecond(t0.add(const Duration(seconds: 1))), isNull);
    });

    test('les vieux échantillons sortent de la fenêtre', () {
      final IngestRateMeter meter =
          IngestRateMeter(window: const Duration(seconds: 10));
      final DateTime t0 = DateTime(2026, 1, 1);
      meter.addBytes(1000000, t0); // gros burst ancien
      for (int s = 20; s <= 26; s++) {
        meter.addBytes(1000, t0.add(Duration(seconds: s)));
      }
      final double? rate =
          meter.bytesPerSecond(t0.add(const Duration(seconds: 26)));
      // Le burst d'il y a 26 s ne doit plus compter : débit ≈ 1 000/s.
      expect(rate, isNotNull);
      expect(rate, lessThan(5000));
      expect(meter.totalBytes, 1000000 + 7000);
    });
  });

  warmupTests();
}

// =========================================================
//  TsWarmupIndex — démarrage à chaud sur IMAGE-CLÉ (correctif macroblocs)
// =========================================================

/// Paquet TS synthétique paramétrable (188 octets exacts).
Uint8List tsPacket({
  required int pid,
  bool pusi = false,
  bool rai = false,
  List<int> payload = const <int>[],
}) {
  final Uint8List pkt = Uint8List(kTsPacketSize);
  pkt[0] = kTsSyncByte;
  pkt[1] = ((pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F));
  pkt[2] = pid & 0xFF;
  int cursor;
  if (rai) {
    // Champ d'adaptation minimal d'1 octet de drapeaux, RAI posé.
    pkt[3] = 0x30; // AF + payload
    pkt[4] = 1; // longueur AF
    pkt[5] = 0x40; // random_access_indicator
    cursor = 6;
  } else {
    pkt[3] = 0x10; // payload seul
    cursor = 4;
  }
  for (int i = 0; i < payload.length && cursor + i < kTsPacketSize; i++) {
    pkt[cursor + i] = payload[i];
  }
  // Bourrage sans faux 0x47.
  for (int i = cursor + payload.length; i < kTsPacketSize; i++) {
    pkt[i] = 0xFF;
  }
  return pkt;
}

/// Section PAT : programme 1 → PMT [pmtPid].
List<int> patPayload(int pmtPid) => <int>[
      0x00, // pointer_field
      0x00, // table_id PAT
      0xB0, 13, // section_length = 5 + 4 (programme) + 4 (CRC)
      0x00, 0x01, // transport_stream_id
      0xC1, 0x00, 0x00, // version/current + section 0/0
      0x00, 0x01, // program_number 1
      0xE0 | ((pmtPid >> 8) & 0x1F), pmtPid & 0xFF,
      0x00, 0x00, 0x00, 0x00, // CRC (non vérifié)
    ];

/// Section PMT : PCR sur [pcrPid], aucun descripteur ni flux déclaré
/// (suffisant : seul le pcr_pid nous intéresse).
List<int> pmtPayload(int pcrPid) => <int>[
      0x00, // pointer_field
      0x02, // table_id PMT
      0xB0, 13, // section_length = 9 + 0 flux + 4 CRC
      0x00, 0x01, // program_number
      0xC1, 0x00, 0x00, // version + sections
      0xE0 | ((pcrPid >> 8) & 0x1F), pcrPid & 0xFF, // pcr_pid
      0xF0, 0x00, // program_info_length = 0
      0x00, 0x00, 0x00, 0x00, // CRC
    ];

void warmupTests() {
  const int pmtPid = 0x100;
  const int videoPid = 0x101;
  const int audioPid = 0x102;

  Uint8List pat() => tsPacket(pid: 0, pusi: true, payload: patPayload(pmtPid));
  Uint8List pmt() =>
      tsPacket(pid: pmtPid, pusi: true, payload: pmtPayload(videoPid));
  Uint8List video({bool key = false}) => tsPacket(pid: videoPid, rai: key);
  Uint8List audio() => tsPacket(pid: audioPid);

  group('TsWarmupIndex', () {
    test('PAT → PMT → PCR PID lus, image-clé RAI repérée à son offset', () {
      final TsWarmupIndex idx = TsWarmupIndex();
      final BytesBuilder b = BytesBuilder()
        ..add(pat()) // offset 0
        ..add(pmt()) // 188
        ..add(video()) // 376 (pas clé)
        ..add(audio()) // 564
        ..add(video(key: true)) // 752 ← image-clé
        ..add(video()); // 940
      idx.feed(b.takeBytes());
      expect(idx.pmtPid, pmtPid);
      expect(idx.pcrPid, videoPid);
      expect(idx.lastPatPacket, isNotNull);
      expect(idx.lastPmtPacket, isNotNull);
      expect(idx.bestKeyframeOffset, 4 * kTsPacketSize);
    });

    test('paquets à cheval sur les chunks réseau : même résultat', () {
      final TsWarmupIndex idx = TsWarmupIndex();
      final BytesBuilder b = BytesBuilder()
        ..add(pat())
        ..add(pmt())
        ..add(video(key: true))
        ..add(video());
      final Uint8List all = b.takeBytes();
      // Découpes volontairement vicieuses (ni multiples ni diviseurs de 188).
      for (int i = 0; i < all.length; i += 61) {
        final int end = (i + 61 < all.length) ? i + 61 : all.length;
        idx.feed(Uint8List.sublistView(all, i, end));
      }
      expect(idx.pcrPid, videoPid);
      expect(idx.bestKeyframeOffset, 2 * kTsPacketSize);
    });

    test('RAI audio seul : repli sur n\'importe quel PID de données', () {
      final TsWarmupIndex idx = TsWarmupIndex();
      final BytesBuilder b = BytesBuilder()
        ..add(pat())
        ..add(pmt())
        ..add(tsPacket(pid: audioPid, rai: true)) // 376
        ..add(video());
      idx.feed(b.takeBytes());
      // Pas de RAI sur la vidéo (PCR) → le repli « n'importe quel PID ».
      expect(idx.bestKeyframeOffset, 2 * kTsPacketSize);
    });

    test('clear() oublie tables et image-clé (reconnexion upstream)', () {
      final TsWarmupIndex idx = TsWarmupIndex();
      idx.feed(pat());
      idx.feed(pmt());
      idx.feed(video(key: true));
      expect(idx.bestKeyframeOffset, isNonNegative);
      idx.clear();
      expect(idx.lastPatPacket, isNull);
      expect(idx.lastPmtPacket, isNull);
      expect(idx.bestKeyframeOffset, -1);
      expect(idx.pmtPid, -1);
    });

    test('section PAT tronquée/invalide : rien n\'est cru', () {
      final TsWarmupIndex idx = TsWarmupIndex();
      // PAT annoncée mais section_length aberrante (déborde du paquet).
      final Uint8List bad =
          tsPacket(pid: 0, pusi: true, payload: <int>[0x00, 0x00, 0xBF, 0xFF]);
      idx.feed(bad);
      expect(idx.lastPatPacket, isNull);
      expect(idx.pmtPid, -1);
    });
  });

  group('TsRingBuffer.snapshotFrom + rafale image-clé', () {
    test('la découpe part exactement de l\'image-clé', () {
      final TsRingBuffer ring = TsRingBuffer();
      final TsWarmupIndex idx = TsWarmupIndex();
      final BytesBuilder b = BytesBuilder()
        ..add(pat())
        ..add(pmt())
        ..add(video())
        ..add(video(key: true))
        ..add(audio());
      final Uint8List all = b.takeBytes();
      ring.add(all);
      idx.feed(all);
      final Uint8List tail = ring.snapshotFrom(idx.bestKeyframeOffset);
      expect(tail.length, 2 * kTsPacketSize); // image-clé + audio qui suit
      expect(tail[0], kTsSyncByte);
      // Le premier paquet de la découpe porte bien le RAI : champ
      // d'adaptation présent ([3] bit 0x20), longueur ≥ 1, drapeau à [5].
      expect(tail[3] & 0x20, 0x20);
      expect(tail[4], greaterThanOrEqualTo(1));
      expect(tail[5] & 0x40, 0x40);
    });

    test('image-clé évacuée du tampon : découpe vide (repli ancien burst)',
        () {
      final TsRingBuffer ring = TsRingBuffer(capacityBytes: 2 * kTsPacketSize);
      final TsWarmupIndex idx = TsWarmupIndex();
      final Uint8List key = video(key: true); // offset 0
      ring.add(key);
      idx.feed(key);
      // Deux paquets de plus : l'image-clé (offset 0) est évacuée.
      ring.add(video());
      idx.feed(video());
      ring.add(audio());
      idx.feed(audio());
      expect(ring.snapshotFrom(0), isEmpty);
    });

    test('offset pas encore atteint : découpe vide', () {
      final TsRingBuffer ring = TsRingBuffer();
      ring.add(tsPackets(2));
      expect(ring.snapshotFrom(10 * kTsPacketSize), isEmpty);
    });
  });
}
