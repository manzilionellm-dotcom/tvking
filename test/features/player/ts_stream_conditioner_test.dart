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
}
