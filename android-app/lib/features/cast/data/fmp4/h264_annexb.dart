// =========================================================
//  h264_annexb.dart — Outillage H.264 Annex B → AVCC (fMP4)
// =========================================================
//  POURQUOI : dans le MPEG-TS, la vidéo H.264 est en « Annex B »
//  (NALs séparées par des start codes 00 00 01). Le fMP4 exige le
//  format « AVCC » : NALs préfixées par leur LONGUEUR (4 octets), et
//  SPS/PPS déportés dans la boîte avcC du segment d'init. Ce module
//  fait cette conversion, sans toucher au contenu des NALs.
//
//  On y parse aussi le minimum du SPS (profil/niveau → étiquette
//  RFC 6381 « avc1.PPCCLL », dimensions → tkhd/avc1) : Shaka lit les
//  vraies dimensions dans le flux, mais des champs cohérents évitent
//  les récepteurs pointilleux.
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
// =========================================================

import 'dart:typed_data';

/// Types de NAL utiles (nal_unit_type, 5 bits).
const int kNalIdr = 5;
const int kNalSps = 7;
const int kNalPps = 8;
const int kNalAud = 9;

int nalType(Uint8List nal) => nal.isEmpty ? -1 : nal[0] & 0x1F;

/// Découpe un buffer Annex B en NALs (sans les start codes). Gère les
/// start codes 3 ET 4 octets. Les NALs vides sont ignorées.
List<Uint8List> splitAnnexBNals(Uint8List buf) {
  final List<Uint8List> nals = <Uint8List>[];
  int i = 0;
  int nalStart = -1;
  final int n = buf.length;
  while (i + 3 <= n) {
    if (buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1) {
      if (nalStart >= 0) {
        // Fin de la NAL précédente : recule sur le zéro du start code
        // 4 octets éventuel.
        int end = i;
        if (end > nalStart && buf[end - 1] == 0) end--;
        if (end > nalStart) {
          nals.add(Uint8List.sublistView(buf, nalStart, end));
        }
      }
      nalStart = i + 3;
      i += 3;
    } else if (buf[i + 2] == 0) {
      // Petite accélération : si le 3e octet n'est pas 0, aucun start
      // code ne peut commencer avant i+3... ici il vaut 0, on avance
      // d'un cran seulement.
      i++;
    } else {
      i += 3;
    }
  }
  if (nalStart >= 0 && nalStart < n) {
    nals.add(Uint8List.sublistView(buf, nalStart, n));
  }
  return nals;
}

/// Convertit une liste de NALs en AVCC : chaque NAL préfixée par sa
/// longueur (4 octets, gros-boutiste).
Uint8List nalsToAvcc(List<Uint8List> nals) {
  int size = 0;
  for (final Uint8List nal in nals) {
    size += 4 + nal.length;
  }
  final Uint8List out = Uint8List(size);
  int off = 0;
  for (final Uint8List nal in nals) {
    final int len = nal.length;
    out[off] = (len >> 24) & 0xFF;
    out[off + 1] = (len >> 16) & 0xFF;
    out[off + 2] = (len >> 8) & 0xFF;
    out[off + 3] = len & 0xFF;
    out.setRange(off + 4, off + 4 + len, nal);
    off += 4 + len;
  }
  return out;
}

/// Étiquette RFC 6381 « avc1.PPCCLL » depuis les 3 octets de profil
/// du SPS (profile_idc, constraint_flags, level_idc).
String avc1CodecString(Uint8List sps) {
  if (sps.length < 4) return 'avc1';
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return 'avc1.${h(sps[1])}${h(sps[2])}${h(sps[3])}';
}

/// Dimensions (largeur, hauteur) parsées du SPS, ou null si le SPS
/// est illisible — l'appelant retombe alors sur des dimensions
/// neutres, les décodeurs lisent de toute façon le flux.
({int width, int height})? parseSpsDimensions(Uint8List sps) {
  try {
    // Retire les octets d'anti-émulation (00 00 03 xx → 00 00 xx).
    final BytesBuilder clean = BytesBuilder(copy: false);
    for (int i = 0; i < sps.length; i++) {
      if (i >= 2 && sps[i] == 3 && sps[i - 1] == 0 && sps[i - 2] == 0) {
        continue;
      }
      clean.addByte(sps[i]);
    }
    final _ExpGolombReader r = _ExpGolombReader(clean.takeBytes());
    r.skipBits(8); // nal header
    final int profileIdc = r.bits(8);
    r.skipBits(8); // constraint flags + reserved
    r.skipBits(8); // level_idc
    r.ue(); // seq_parameter_set_id

    int chromaFormatIdc = 1; // 4:2:0 par défaut (profils Baseline/Main)
    if (const <int>{100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135}
        .contains(profileIdc)) {
      chromaFormatIdc = r.ue();
      if (chromaFormatIdc == 3) r.skipBits(1); // separate_colour_plane
      r.ue(); // bit_depth_luma_minus8
      r.ue(); // bit_depth_chroma_minus8
      r.skipBits(1); // qpprime_y_zero_transform_bypass
      if (r.bits(1) == 1) {
        // seq_scaling_matrix_present : sauter les listes.
        final int count = chromaFormatIdc != 3 ? 8 : 12;
        for (int i = 0; i < count; i++) {
          if (r.bits(1) == 1) {
            _skipScalingList(r, i < 6 ? 16 : 64);
          }
        }
      }
    }

    r.ue(); // log2_max_frame_num_minus4
    final int pocType = r.ue();
    if (pocType == 0) {
      r.ue(); // log2_max_pic_order_cnt_lsb_minus4
    } else if (pocType == 1) {
      r.skipBits(1); // delta_pic_order_always_zero
      r.se(); // offset_for_non_ref_pic
      r.se(); // offset_for_top_to_bottom_field
      final int cycle = r.ue();
      for (int i = 0; i < cycle; i++) {
        r.se();
      }
    }
    r.ue(); // max_num_ref_frames
    r.skipBits(1); // gaps_in_frame_num_value_allowed
    final int widthMbs = r.ue() + 1;
    final int heightMapUnits = r.ue() + 1;
    final int frameMbsOnly = r.bits(1);
    if (frameMbsOnly == 0) r.skipBits(1); // mb_adaptive_frame_field
    r.skipBits(1); // direct_8x8_inference

    int cropLeft = 0;
    int cropRight = 0;
    int cropTop = 0;
    int cropBottom = 0;
    if (r.bits(1) == 1) {
      cropLeft = r.ue();
      cropRight = r.ue();
      cropTop = r.ue();
      cropBottom = r.ue();
    }

    // Unités de rognage selon le sous-échantillonnage chroma.
    final int subWidthC = chromaFormatIdc == 3 ? 1 : 2;
    final int subHeightC = chromaFormatIdc == 1 ? 2 : 1;
    final int cropUnitX = chromaFormatIdc == 0 ? 1 : subWidthC;
    final int cropUnitY =
        (chromaFormatIdc == 0 ? 1 : subHeightC) * (2 - frameMbsOnly);

    final int width = widthMbs * 16 - cropUnitX * (cropLeft + cropRight);
    final int height = (2 - frameMbsOnly) * heightMapUnits * 16 -
        cropUnitY * (cropTop + cropBottom);
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192) {
      return null;
    }
    return (width: width, height: height);
  } on Object {
    return null; // SPS exotique/tronqué : dimensions neutres
  }
}

void _skipScalingList(_ExpGolombReader r, int size) {
  int lastScale = 8;
  int nextScale = 8;
  for (int i = 0; i < size; i++) {
    if (nextScale != 0) {
      final int delta = r.se();
      nextScale = (lastScale + delta + 256) % 256;
    }
    lastScale = nextScale == 0 ? lastScale : nextScale;
  }
}

/// Lecteur de bits + codes Exp-Golomb (ue(v)/se(v)) du H.264.
class _ExpGolombReader {
  _ExpGolombReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  int bits(int n) {
    int v = 0;
    for (int i = 0; i < n; i++) {
      final int byte = _bytes[_pos >> 3];
      v = (v << 1) | ((byte >> (7 - (_pos & 7))) & 1);
      _pos++;
    }
    return v;
  }

  void skipBits(int n) {
    _pos += n;
    if ((_pos >> 3) > _bytes.length) {
      throw RangeError('SPS tronqué');
    }
  }

  int ue() {
    int zeros = 0;
    while (bits(1) == 0) {
      zeros++;
      if (zeros > 31) throw const FormatException('ue(v) délirant');
    }
    return (1 << zeros) - 1 + (zeros == 0 ? 0 : bits(zeros));
  }

  int se() {
    final int k = ue();
    return k.isEven ? -(k ~/ 2) : (k + 1) ~/ 2;
  }
}
