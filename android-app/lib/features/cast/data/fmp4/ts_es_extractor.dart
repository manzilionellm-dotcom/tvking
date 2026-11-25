// =========================================================
//  ts_es_extractor.dart — Démux MPEG-TS → flux élémentaires (PES)
// =========================================================
//  POURQUOI : pour ré-emballer un segment TS en fMP4 (voir
//  fmp4_remuxer.dart), il faut remonter du niveau « paquets 188
//  octets » au niveau « unités d'accès » : chaque PES vidéo (une
//  image, avec ses PTS/DTS 90 kHz) et chaque PES audio (une ou
//  plusieurs trames AC-3/AAC). Le TsHlsSegmenter, lui, ne fait que
//  recopier des octets — on ne le touche pas (chemin gagnant) : ce
//  module travaille EN AVAL, sur des segments déjà découpés.
//
//  Hypothèses assumées (v1, alignées sur les flux IPTV réels) :
//    - un PES vidéo avec PUSI = une unité d'accès (convention
//      broadcast : une image par PES) ;
//    - premier flux vidéo + premier flux audio de la PMT (mêmes
//      règles de choix que TsHlsSegmenter, y compris le raffinement
//      DVB des flux « PES privé ») ;
//    - pas de flux chiffrés (transport_scrambling_control ≠ 0 → PES
//      ignoré).
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
// =========================================================

import 'dart:typed_data';

/// Une charge PES complète, horodatée. Pour la vidéo : une unité
/// d'accès (Annex B). Pour l'audio : un paquet de trames.
class PesUnit {
  PesUnit({required this.pts90k, required this.dts90k, required this.bytes});

  /// PTS en ticks 90 kHz (33 bits, PEUT boucler — l'appelant déroule).
  /// Null si le PES n'en portait pas (rare en broadcast).
  final int? pts90k;

  /// DTS en ticks 90 kHz. Null si absent → l'appelant prend le PTS.
  final int? dts90k;

  final Uint8List bytes;
}

/// Résultat d'une extraction sur un segment TS complet.
class TsEsExtraction {
  TsEsExtraction({
    required this.videoCodec,
    required this.audioCodec,
    required this.videoUnits,
    required this.audioUnits,
  });

  /// Mêmes étiquettes que TsHlsSegmenter ('h264', 'hevc', 'mpeg2',
  /// 'mpeg4', 'unknown').
  final String videoCodec;

  /// 'aac' | 'aac-latm' | 'mp2' | 'ac3' | 'eac3' | 'dts' | 'private'
  /// | 'unknown'.
  final String audioCodec;

  final List<PesUnit> videoUnits;
  final List<PesUnit> audioUnits;
}

/// Assemble les PES d'un PID donné au fil des paquets TS.
///
/// Un PES BORNÉ (PES_packet_length ≠ 0 — l'audio, toujours) est émis
/// DÈS que sa longueur déclarée est atteinte, sans attendre le PUSI
/// suivant : ainsi la piste audio du segment reste dans SON segment
/// (init complète dès le premier segment, pas de republication à
/// chaud). Un PES NON borné (la vidéo) est clos par le PUSI suivant
/// ou par [finish] en fin de segment.
class _PesAssembler {
  final BytesBuilder _buf = BytesBuilder(copy: false);
  bool _open = false;

  /// Taille TOTALE attendue (6 + PES_packet_length) pour un PES
  /// borné, null pour un PES non borné (vidéo) ou en-tête pas encore
  /// lisible.
  int? _expected;

  /// Ingestion d'un payload TS. Renvoie les PES complétés (0, 1, ou
  /// 2 : le PUSI clôt le précédent ET le nouveau peut déjà être
  /// complet s'il tient dans un seul paquet).
  List<PesUnit> onPayload(Uint8List payload, {required bool pusi}) {
    final List<PesUnit> out = <PesUnit>[];
    if (pusi) {
      final PesUnit? prev = finish();
      if (prev != null) out.add(prev);
      _buf.add(payload);
      _open = true;
      // Longueur déclarée : les 6 premiers octets tiennent dans le
      // premier payload en pratique (184 octets) — sinon on retombe
      // sur la clôture au PUSI suivant, sans casse.
      if (payload.length >= 6) {
        final int pesLen = (payload[4] << 8) | payload[5];
        _expected = pesLen != 0 ? 6 + pesLen : null;
      } else {
        _expected = null;
      }
    } else {
      if (!_open) return out; // continuation orpheline (début manqué)
      _buf.add(payload);
    }
    final int? expected = _expected;
    if (_open && expected != null && _buf.length >= expected) {
      final PesUnit? done = finish();
      if (done != null) out.add(done);
    }
    return out;
  }

  void drop() {
    _buf.clear();
    _open = false;
    _expected = null;
  }

  /// Clôt le PES en cours et le parse. Renvoie null si vide/malformé.
  PesUnit? finish() {
    if (!_open) return null;
    _open = false;
    _expected = null;
    final Uint8List pes = _buf.takeBytes();
    return _parsePes(pes);
  }

  static PesUnit? _parsePes(Uint8List pes) {
    // En-tête PES : 00 00 01 stream_id length(2) '10'+flags(2) hdl(1).
    if (pes.length < 9 ||
        pes[0] != 0x00 ||
        pes[1] != 0x00 ||
        pes[2] != 0x01) {
      return null;
    }
    final int streamId = pes[3];
    // Seuls les stream_id « avec en-tête optionnel » nous concernent
    // (vidéo 0xE0-0xEF, audio 0xC0-0xDF, private_stream_1 0xBD).
    final bool hasOptionalHeader = (streamId >= 0xC0 && streamId <= 0xEF) ||
        streamId == 0xBD;
    if (!hasOptionalHeader) return null;
    final int pesLen = (pes[4] << 8) | pes[5];
    final int ptsDtsFlags = (pes[7] >> 6) & 0x3;
    final int headerDataLen = pes[8];
    final int payloadStart = 9 + headerDataLen;
    if (payloadStart > pes.length) return null;

    int? pts;
    int? dts;
    if (ptsDtsFlags >= 2 && 9 + 5 <= pes.length) {
      pts = _readTs(pes, 9);
    }
    if (ptsDtsFlags == 3 && 9 + 10 <= pes.length) {
      dts = _readTs(pes, 14);
    }

    // PES borné (audio) : la longueur déclarée fait foi — elle coupe
    // le stuffing de fin de paquet TS. PES non borné (vidéo, len 0) :
    // tout ce qui a été accumulé jusqu'au PUSI suivant.
    int payloadEnd = pes.length;
    if (pesLen != 0) {
      final int declaredEnd = 6 + pesLen;
      if (declaredEnd >= payloadStart && declaredEnd <= pes.length) {
        payloadEnd = declaredEnd;
      }
    }
    if (payloadEnd <= payloadStart) return null;
    return PesUnit(
      pts90k: pts,
      dts90k: dts,
      bytes: Uint8List.sublistView(pes, payloadStart, payloadEnd),
    );
  }

  /// PTS/DTS : 33 bits éclatés sur 5 octets (marqueurs intercalés).
  static int? _readTs(Uint8List p, int off) {
    if (off + 5 > p.length) return null;
    return ((p[off] >> 1) & 0x07) << 30 |
        (p[off + 1] << 22) |
        ((p[off + 2] >> 1) & 0x7F) << 15 |
        (p[off + 3] << 7) |
        ((p[off + 4] >> 1) & 0x7F);
  }
}

/// Extracteur au niveau SEGMENT : on lui donne un segment TS complet
/// (celui que TsHlsSegmenter a produit — il commence par PAT + PMT),
/// il rend les unités d'accès des deux flux élus.
class TsEsExtractor {
  int _pmtPid = -1;
  int _videoPid = -1;
  int _audioPid = -1;
  String _videoCodec = 'unknown';
  String _audioCodec = 'unknown';

  final _PesAssembler _video = _PesAssembler();
  final _PesAssembler _audio = _PesAssembler();

  /// Jette les PES en cours d'assemblage — à appeler sur une
  /// DISCONTINUITÉ (splice, reconnexion) : leurs octets appartiennent
  /// à l'ancienne ligne de temps.
  void dropPending() {
    _video.drop();
    _audio.drop();
  }

  /// Extrait les unités d'accès d'un segment TS aligné (multiple de
  /// 188 octets, ou avec du bruit résiduel — on saute au prochain
  /// octet de sync). L'état PERSISTE entre les appels : les segments
  /// d'une même session doivent être présentés DANS L'ORDRE.
  TsEsExtraction extract(Uint8List ts) {
    final List<PesUnit> videoUnits = <PesUnit>[];
    final List<PesUnit> audioUnits = <PesUnit>[];

    int off = 0;
    while (ts.length - off >= 188) {
      if (ts[off] != 0x47) {
        off++;
        continue;
      }
      final Uint8List p = Uint8List.sublistView(ts, off, off + 188);
      off += 188;

      final bool pusi = (p[1] & 0x40) != 0;
      final int pid = ((p[1] & 0x1F) << 8) | p[2];
      final int scrambling = (p[3] >> 6) & 0x3;
      final int afc = (p[3] >> 4) & 0x3;
      if (scrambling != 0) continue; // chiffré : indéchiffrable ici
      if (afc == 0 || afc == 2) continue; // pas de payload

      int payloadOff = 4;
      if (afc == 3) {
        payloadOff += 1 + p[4];
        if (payloadOff >= 188) continue; // adaptation malformée
      }
      final Uint8List payload = Uint8List.sublistView(p, payloadOff);

      if (pid == 0 && pusi) {
        _parsePat(payload);
        continue;
      }
      if (pid == _pmtPid && pusi) {
        _parsePmt(payload);
        continue;
      }

      if (pid == _videoPid) {
        videoUnits.addAll(_video.onPayload(payload, pusi: pusi));
      } else if (pid == _audioPid) {
        audioUnits.addAll(_audio.onPayload(payload, pusi: pusi));
      }
    }

    // Fin de segment : le PES vidéo non borné se termine ICI par
    // construction (le segmenteur coupe TOUJOURS sur un début de PES
    // vidéo → le dernier PES vidéo est complet). L'audio, lui, peut
    // être À CHEVAL sur la frontière : on le laisse EN ATTENTE — ses
    // paquets de continuation arrivent au début du segment suivant et
    // le PES complet sera livré là-bas (l'ancre PTS remet chaque
    // trame à sa place). Le clore ici perdrait 1 à 3 trames par
    // frontière : hachage audible toutes les ~3 s.
    final PesUnit? vTail = _video.finish();
    if (vTail != null) videoUnits.add(vTail);

    return TsEsExtraction(
      videoCodec: _videoCodec,
      audioCodec: _audioCodec,
      videoUnits: videoUnits,
      audioUnits: audioUnits,
    );
  }

  // ---- PSI (mêmes règles d'élection que TsHlsSegmenter) ----

  static Uint8List? _sectionOf(Uint8List payload) {
    if (payload.isEmpty) return null;
    final int pointer = payload[0];
    final int off = 1 + pointer;
    if (off >= payload.length) return null;
    return Uint8List.sublistView(payload, off);
  }

  void _parsePat(Uint8List payload) {
    final Uint8List? s = _sectionOf(payload);
    if (s == null || s.isEmpty || s[0] != 0x00 || s.length < 12) return;
    final int sectionLen = ((s[1] & 0x0F) << 8) | s[2];
    final int end = 3 + sectionLen - 4;
    for (int i = 8; i + 4 <= end && i + 4 <= s.length; i += 4) {
      final int program = (s[i] << 8) | s[i + 1];
      final int pid = ((s[i + 2] & 0x1F) << 8) | s[i + 3];
      if (program != 0) {
        _pmtPid = pid;
        return;
      }
    }
  }

  void _parsePmt(Uint8List payload) {
    final Uint8List? s = _sectionOf(payload);
    if (s == null || s.isEmpty || s[0] != 0x02 || s.length < 16) return;
    final int sectionLen = ((s[1] & 0x0F) << 8) | s[2];
    final int end = 3 + sectionLen - 4;
    final int programInfoLen = ((s[10] & 0x0F) << 8) | s[11];
    int i = 12 + programInfoLen;
    while (i + 5 <= end && i + 5 <= s.length) {
      final int streamType = s[i];
      final int pid = ((s[i + 1] & 0x1F) << 8) | s[i + 2];
      final int esInfoLen = ((s[i + 3] & 0x0F) << 8) | s[i + 4];
      final String? video = _videoCodecOf(streamType);
      if (video != null && _videoPid == -1) {
        _videoPid = pid;
        _videoCodec = video;
      }
      String? audio = _audioCodecOf(streamType);
      if (streamType == 0x06) {
        final String? refined = _privateEsAudioCodec(s, i + 5, esInfoLen);
        if (refined != null) audio = refined;
      }
      if (audio != null &&
          (_audioCodec == 'unknown' || _audioCodec == 'private')) {
        _audioCodec = audio;
        _audioPid = pid;
      }
      i += 5 + esInfoLen;
    }
  }

  static String? _privateEsAudioCodec(Uint8List s, int off, int len) {
    int i = off;
    final int end = off + len;
    while (i + 2 <= end && i + 2 <= s.length) {
      switch (s[i]) {
        case 0x6A:
          return 'ac3';
        case 0x7A:
          return 'eac3';
        case 0x7B:
          return 'dts';
      }
      i += 2 + s[i + 1];
    }
    return null;
  }

  static String? _videoCodecOf(int streamType) {
    switch (streamType) {
      case 0x01:
      case 0x02:
        return 'mpeg2';
      case 0x10:
        return 'mpeg4';
      case 0x1B:
        return 'h264';
      case 0x24:
        return 'hevc';
    }
    return null;
  }

  static String? _audioCodecOf(int streamType) {
    switch (streamType) {
      case 0x03:
      case 0x04:
        return 'mp2';
      case 0x0F:
        return 'aac';
      case 0x11:
        return 'aac-latm';
      case 0x81:
        return 'ac3';
      case 0x87:
        return 'eac3';
      case 0x06:
        return 'private';
    }
    return null;
  }
}
