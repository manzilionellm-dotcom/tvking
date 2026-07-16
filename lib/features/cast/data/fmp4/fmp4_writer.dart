// =========================================================
//  fmp4_writer.dart — Sérialisation des segments fMP4 (CMAF-like)
// =========================================================
//  POURQUOI : servir au récepteur Cast (Shaka Player) des segments
//  fMP4 au lieu de MPEG-TS. Shaka lit le fMP4 NATIVEMENT via MSE,
//  sans passer par mux.js — c'est ce qui permet enfin l'AC-3/E-AC-3
//  (passthrough) sur les vrais Chromecast, où le TS+mux.js meurt en
//  « idle » (terrain 2026-07-16).
//
//  On produit la forme la plus interopérable :
//    - segment d'init : ftyp + moov (avc1/avcC, ac-3/dac3, ec-3/dec3,
//      mp4a/esds, mvex/trex) — référencé par #EXT-X-MAP ;
//    - segments médias : moof (mfhd, traf → tfhd/tfdt/trun) + mdat,
//      base-data-offset = début du moof (flag default-base-is-moof,
//      comme hls.js/mux.js — seul mode fiable en MSE).
//
//  Timescales : vidéo 90 000 (l'horloge MPEG-TS native — aucune
//  conversion, aucun arrondi) ; audio = fréquence d'échantillonnage
//  (durée de trame ENTIÈRE : 1536 ticks AC-3, 1024 AAC — zéro dérive).
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
//  Références : ISO 14496-12, ETSI TS 102 366 annexe F, RFC 6381.
// =========================================================

import 'dart:typed_data';

import 'audio_frames.dart';

/// Configuration de la piste vidéo H.264 (extraite du flux Annex B).
class VideoTrackConfig {
  VideoTrackConfig({
    required this.sps,
    required this.pps,
    required this.width,
    required this.height,
    required this.rfc6381,
  });

  final Uint8List sps;
  final Uint8List pps;
  final int width;
  final int height;

  /// 'avc1.PPCCLL' pour l'attribut CODECS de la master playlist.
  final String rfc6381;
}

/// Un sample vidéo prêt à écrire : unité d'accès au format AVCC
/// (NALs préfixées par leur longueur sur 4 octets).
class VideoSample {
  VideoSample({
    required this.data,
    required this.durationTicks,
    required this.ctsOffsetTicks,
    required this.keyframe,
  });

  final Uint8List data;

  /// Durée en ticks 90 kHz (DTS suivant − DTS courant).
  final int durationTicks;

  /// PTS − DTS en ticks 90 kHz (B-frames → offsets non nuls, signés).
  final int ctsOffsetTicks;

  final bool keyframe;
}

/// Un sample audio : une trame complète (AC-3/E-AC-3 telle quelle,
/// AAC nue sans en-tête ADTS).
class AudioSample {
  AudioSample({required this.data, required this.durationTicks});

  final Uint8List data;

  /// Durée en ticks « timescale = sampleRate » (1536, numblks×256…).
  final int durationTicks;
}

/// Piste d'un segment média : son ancre temporelle + ses samples.
class VideoRun {
  VideoRun({required this.baseMediaDecodeTime, required this.samples});
  final int baseMediaDecodeTime; // ticks 90 kHz, déroulés (monotone)
  final List<VideoSample> samples;
}

class AudioRun {
  AudioRun({required this.baseMediaDecodeTime, required this.samples});
  final int baseMediaDecodeTime; // ticks « sampleRate », déroulés
  final List<AudioSample> samples;
}

/// IDs de pistes FIXES (identiques entre init et segments médias).
const int kVideoTrackId = 1;
const int kAudioTrackId = 2;

class Fmp4Writer {
  // ---------- Segment d'initialisation ----------

  /// ftyp + moov. Au moins une des deux pistes doit être présente.
  static Uint8List initSegment({
    VideoTrackConfig? video,
    AudioCodecConfig? audio,
  }) {
    assert(video != null || audio != null, 'init sans aucune piste');
    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(_ftyp());

    final List<Uint8List> traks = <Uint8List>[];
    final List<Uint8List> trexs = <Uint8List>[];
    if (video != null) {
      traks.add(_videoTrak(video));
      trexs.add(_trex(kVideoTrackId));
    }
    if (audio != null) {
      traks.add(_audioTrak(audio));
      trexs.add(_trex(kAudioTrackId));
    }
    out.add(_box('moov', <List<int>>[
      _mvhd(),
      ...traks,
      _box('mvex', trexs),
    ]));
    return out.takeBytes();
  }

  // ---------- Segment média ----------

  /// moof + mdat. La donnée mdat est ordonnée vidéo PUIS audio ; les
  /// data_offset des trun pointent au bon endroit (relatifs au début
  /// du moof — flag default-base-is-moof).
  static Uint8List mediaSegment({
    required int sequenceNumber,
    VideoRun? video,
    AudioRun? audio,
  }) {
    assert(video != null || audio != null, 'segment média vide');
    final int videoBytes = video == null
        ? 0
        : video.samples.fold<int>(0, (int a, VideoSample s) => a + s.data.length);

    // Deux passes : la taille du moof détermine les data_offset, qui
    // vivent DANS le moof. Passe 1 avec offsets nuls → taille ; passe
    // 2 avec les vrais offsets (la taille ne change pas : les champs
    // sont de largeur fixe).
    Uint8List buildMoof(int videoOffset, int audioOffset) {
      final List<Uint8List> trafs = <Uint8List>[];
      if (video != null) {
        trafs.add(_box('traf', <List<int>>[
          _tfhd(kVideoTrackId),
          _tfdt(video.baseMediaDecodeTime),
          _trunVideo(video.samples, videoOffset),
        ]));
      }
      if (audio != null) {
        trafs.add(_box('traf', <List<int>>[
          _tfhd(kAudioTrackId),
          _tfdt(audio.baseMediaDecodeTime),
          _trunAudio(audio.samples, audioOffset),
        ]));
      }
      return _box('moof', <List<int>>[_mfhd(sequenceNumber), ...trafs]);
    }

    final int moofSize = buildMoof(0, 0).length;
    // mdat : en-tête de 8 octets après le moof.
    final int videoOffset = moofSize + 8;
    final int audioOffset = videoOffset + videoBytes;
    final Uint8List moof = buildMoof(videoOffset, audioOffset);

    final BytesBuilder mdatPayload = BytesBuilder(copy: false);
    if (video != null) {
      for (final VideoSample s in video.samples) {
        mdatPayload.add(s.data);
      }
    }
    if (audio != null) {
      for (final AudioSample s in audio.samples) {
        mdatPayload.add(s.data);
      }
    }

    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(moof);
    out.add(_box('mdat', <List<int>>[mdatPayload.takeBytes()]));
    return out.takeBytes();
  }

  // ---------- Boîtes génériques ----------

  static Uint8List _box(String type, List<List<int>> parts) {
    int size = 8;
    for (final List<int> p in parts) {
      size += p.length;
    }
    final BytesBuilder b = BytesBuilder(copy: false);
    b.add(_u32(size));
    b.add(type.codeUnits);
    for (final List<int> p in parts) {
      b.add(p);
    }
    return b.takeBytes();
  }

  static Uint8List _fullBox(String type, int version, int flags,
      List<List<int>> parts) {
    return _box(type, <List<int>>[
      <int>[version, (flags >> 16) & 0xFF, (flags >> 8) & 0xFF, flags & 0xFF],
      ...parts,
    ]);
  }

  static List<int> _u16(int v) => <int>[(v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u32(int v) =>
      <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u64(int v) => <int>[
        (v >> 56) & 0xFF,
        (v >> 48) & 0xFF,
        (v >> 40) & 0xFF,
        (v >> 32) & 0xFF,
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  /// Matrice de transformation identité (tkhd/mvhd).
  static List<int> _identityMatrix() => <int>[
        ..._u32(0x00010000), ..._u32(0), ..._u32(0),
        ..._u32(0), ..._u32(0x00010000), ..._u32(0),
        ..._u32(0), ..._u32(0), ..._u32(0x40000000),
      ];

  // ---------- ftyp / moov ----------

  static Uint8List _ftyp() {
    // iso6 : requis par tfdt v1 (base 64 bits). Marques volontairement
    // minimales — Shaka ne vérifie pas les profils, il lit les boîtes.
    return _box('ftyp', <List<int>>[
      'iso5'.codeUnits,
      _u32(512),
      'iso5'.codeUnits,
      'iso6'.codeUnits,
      'mp41'.codeUnits,
    ]);
  }

  static Uint8List _mvhd() {
    return _fullBox('mvhd', 0, 0, <List<int>>[
      _u32(0), // creation_time (époque neutre : reproductible)
      _u32(0), // modification_time
      _u32(1000), // timescale film (les pistes ont le leur)
      _u32(0), // duration inconnue (live)
      _u32(0x00010000), // rate 1.0
      _u16(0x0100), // volume 1.0
      _u16(0), // reserved
      _u32(0), _u32(0), // reserved
      _identityMatrix(),
      _u32(0), _u32(0), _u32(0), _u32(0), _u32(0), _u32(0), // pre_defined
      _u32(3), // next_track_ID
    ]);
  }

  static Uint8List _trex(int trackId) {
    return _fullBox('trex', 0, 0, <List<int>>[
      _u32(trackId),
      _u32(1), // default_sample_description_index
      _u32(0), // default_sample_duration
      _u32(0), // default_sample_size
      _u32(0), // default_sample_flags
    ]);
  }

  // ---------- Piste vidéo ----------

  static Uint8List _videoTrak(VideoTrackConfig v) {
    return _box('trak', <List<int>>[
      _tkhd(kVideoTrackId, width: v.width, height: v.height, audio: false),
      _box('mdia', <List<int>>[
        _mdhd(90000),
        _hdlr('vide', 'VideoHandler'),
        _box('minf', <List<int>>[
          _fullBox('vmhd', 0, 1, <List<int>>[_u16(0), _u16(0), _u16(0), _u16(0)]),
          _dinf(),
          _stblFor(_avc1(v)),
        ]),
      ]),
    ]);
  }

  static Uint8List _avc1(VideoTrackConfig v) {
    final Uint8List avcC = _box('avcC', <List<int>>[
      <int>[
        1, // configurationVersion
        v.sps.length > 1 ? v.sps[1] : 0, // AVCProfileIndication
        v.sps.length > 2 ? v.sps[2] : 0, // profile_compatibility
        v.sps.length > 3 ? v.sps[3] : 0, // AVCLevelIndication
        0xFF, // lengthSizeMinusOne = 3 (NALs préfixées 4 octets)
        0xE1, // 1 SPS
      ],
      _u16(v.sps.length),
      v.sps,
      <int>[1], // 1 PPS
      _u16(v.pps.length),
      v.pps,
    ]);
    return _box('avc1', <List<int>>[
      <int>[0, 0, 0, 0, 0, 0], // reserved
      _u16(1), // data_reference_index
      _u16(0), _u16(0), // pre_defined / reserved
      _u32(0), _u32(0), _u32(0), // pre_defined
      _u16(v.width),
      _u16(v.height),
      _u32(0x00480000), // horizresolution 72 dpi
      _u32(0x00480000), // vertresolution
      _u32(0), // reserved
      _u16(1), // frame_count
      List<int>.filled(32, 0), // compressorname
      _u16(0x0018), // depth 24
      _u16(0xFFFF), // pre_defined -1
      avcC,
    ]);
  }

  // ---------- Piste audio ----------

  static Uint8List _audioTrak(AudioCodecConfig a) {
    return _box('trak', <List<int>>[
      _tkhd(kAudioTrackId, width: 0, height: 0, audio: true),
      _box('mdia', <List<int>>[
        _mdhd(a.sampleRate),
        _hdlr('soun', 'SoundHandler'),
        _box('minf', <List<int>>[
          _fullBox('smhd', 0, 0, <List<int>>[_u16(0), _u16(0)]),
          _dinf(),
          _stblFor(_audioSampleEntry(a)),
        ]),
      ]),
    ]);
  }

  static Uint8List _audioSampleEntry(AudioCodecConfig a) {
    final List<int> common = <int>[
      0, 0, 0, 0, 0, 0, // reserved
      ..._u16(1), // data_reference_index
      ..._u32(0), ..._u32(0), // reserved
      ..._u16(a.channelCount),
      ..._u16(16), // samplesize
      ..._u16(0), // pre_defined
      ..._u16(0), // reserved
      ..._u32(a.sampleRate << 16), // 16.16
    ];
    switch (a.codec) {
      case 'ac3':
        return _box('ac-3', <List<int>>[
          common,
          _box('dac3', <List<int>>[a.codecConfigBytes]),
        ]);
      case 'eac3':
        return _box('ec-3', <List<int>>[
          common,
          _box('dec3', <List<int>>[a.codecConfigBytes]),
        ]);
      default: // 'aac'
        return _box('mp4a', <List<int>>[
          common,
          _esds(a.codecConfigBytes),
        ]);
    }
  }

  /// esds : ES_Descriptor → DecoderConfig (OTI 0x40 = AAC) →
  /// DecoderSpecificInfo (AudioSpecificConfig) → SLConfig.
  static Uint8List _esds(Uint8List asc) {
    final List<int> dsi = <int>[0x05, asc.length, ...asc];
    final List<int> dcd = <int>[
      0x04, 13 + dsi.length,
      0x40, // objectTypeIndication : Audio ISO 14496-3
      0x15, // streamType audio (0x05 << 2) | reserved 1
      0, 0, 0, // bufferSizeDB
      ..._u32(0), // maxBitrate (inconnu)
      ..._u32(0), // avgBitrate
      ...dsi,
    ];
    final List<int> esd = <int>[
      0x03, 3 + dcd.length + 3,
      0, 0, // ES_ID
      0, // flags
      ...dcd,
      0x06, 0x01, 0x02, // SLConfigDescriptor (MP4 : predefined 2)
    ];
    return _fullBox('esds', 0, 0, <List<int>>[esd]);
  }

  // ---------- Boîtes communes aux deux pistes ----------

  static Uint8List _tkhd(int trackId,
      {required int width, required int height, required bool audio}) {
    return _fullBox('tkhd', 0, 3, <List<int>>[
      _u32(0), // creation_time
      _u32(0), // modification_time
      _u32(trackId),
      _u32(0), // reserved
      _u32(0), // duration inconnue (live)
      _u32(0), _u32(0), // reserved
      _u16(0), // layer
      _u16(audio ? 1 : 0), // alternate_group
      _u16(audio ? 0x0100 : 0), // volume
      _u16(0), // reserved
      _identityMatrix(),
      _u32(width << 16),
      _u32(height << 16),
    ]);
  }

  static Uint8List _mdhd(int timescale) {
    return _fullBox('mdhd', 0, 0, <List<int>>[
      _u32(0),
      _u32(0),
      _u32(timescale),
      _u32(0), // duration inconnue
      _u16(0x55C4), // language 'und'
      _u16(0),
    ]);
  }

  static Uint8List _hdlr(String type, String name) {
    return _fullBox('hdlr', 0, 0, <List<int>>[
      _u32(0), // pre_defined
      type.codeUnits,
      _u32(0), _u32(0), _u32(0), // reserved
      <int>[...name.codeUnits, 0],
    ]);
  }

  static Uint8List _dinf() {
    final Uint8List url = _fullBox('url ', 0, 1, const <List<int>>[]);
    return _box('dinf', <List<int>>[
      _fullBox('dref', 0, 0, <List<int>>[
        _u32(1),
        url,
      ]),
    ]);
  }

  /// stbl vide (tout vit dans les fragments) autour du sample entry.
  static Uint8List _stblFor(Uint8List sampleEntry) {
    return _box('stbl', <List<int>>[
      _fullBox('stsd', 0, 0, <List<int>>[_u32(1), sampleEntry]),
      _fullBox('stts', 0, 0, <List<int>>[_u32(0)]),
      _fullBox('stsc', 0, 0, <List<int>>[_u32(0)]),
      _fullBox('stsz', 0, 0, <List<int>>[_u32(0), _u32(0)]),
      _fullBox('stco', 0, 0, <List<int>>[_u32(0)]),
    ]);
  }

  // ---------- moof ----------

  static Uint8List _mfhd(int sequenceNumber) {
    return _fullBox('mfhd', 0, 0, <List<int>>[_u32(sequenceNumber)]);
  }

  /// tfhd : default-base-is-moof (0x020000) — les data_offset des
  /// trun sont relatifs au DÉBUT du moof (seul mode fiable en MSE).
  static Uint8List _tfhd(int trackId) {
    return _fullBox('tfhd', 0, 0x020000, <List<int>>[_u32(trackId)]);
  }

  /// tfdt v1 (64 bits) : l'horloge 90 kHz déroulée dépasse 2^32 en
  /// ~13 h — 64 bits obligatoire pour des sessions « qui ne coupent
  /// jamais ».
  static Uint8List _tfdt(int baseMediaDecodeTime) {
    return _fullBox('tfdt', 1, 0, <List<int>>[_u64(baseMediaDecodeTime)]);
  }

  /// Flags trun : data-offset + duration + size + flags + cts (v1,
  /// offsets de composition SIGNÉS — B-frames).
  static Uint8List _trunVideo(List<VideoSample> samples, int dataOffset) {
    const int flags = 0x000001 | 0x000100 | 0x000200 | 0x000400 | 0x000800;
    final List<int> rows = <int>[];
    for (final VideoSample s in samples) {
      rows.addAll(_u32(s.durationTicks));
      rows.addAll(_u32(s.data.length));
      // sample_flags : depends_on(2 bits) + non_sync(1 bit). Keyframe :
      // ne dépend de rien (0x02000000). Autre : dépend (0x01000000) +
      // non-sync (0x00010000) — ce que mux.js/hls.js écrivent.
      rows.addAll(_u32(s.keyframe ? 0x02000000 : 0x01010000));
      rows.addAll(_u32(s.ctsOffsetTicks & 0xFFFFFFFF));
    }
    return _fullBox('trun', 1, flags, <List<int>>[
      _u32(samples.length),
      _u32(dataOffset),
      rows,
    ]);
  }

  /// Audio : data-offset + duration + size (pas de flags/cts — les
  /// trames audio sont toutes des sync samples par nature).
  static Uint8List _trunAudio(List<AudioSample> samples, int dataOffset) {
    const int flags = 0x000001 | 0x000100 | 0x000200;
    final List<int> rows = <int>[];
    for (final AudioSample s in samples) {
      rows.addAll(_u32(s.durationTicks));
      rows.addAll(_u32(s.data.length));
    }
    return _fullBox('trun', 0, flags, <List<int>>[
      _u32(samples.length),
      _u32(dataOffset),
      rows,
    ]);
  }
}
