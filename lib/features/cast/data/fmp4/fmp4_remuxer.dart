// =========================================================
//  fmp4_remuxer.dart — Ré-emballage TS → fMP4 au niveau segment
// =========================================================
//  LE POURQUOI BUSINESS : sur un VRAI Chromecast (récepteur web), le
//  relais HLS actuel sert du MPEG-TS que mux.js transmuxe — et mux.js
//  ne sait ré-emballer QUE l'AAC/MP3. Une chaîne en AC-3/E-AC-3 meurt
//  en « idle » (terrain 2026-07-16) et le sauvetage TV-directe est
//  interdit sur récepteur web (CORS). En servant du fMP4, Shaka lit
//  les segments NATIVEMENT (sans mux.js) et l'audio Dolby passe en
//  passthrough. Ce module transforme les segments TS déjà découpés
//  par TsHlsSegmenter (qu'on ne touche pas : chemin gagnant) en
//  segments fMP4 + segment d'init (#EXT-X-MAP).
//
//  Ce qui est géré (v1) :
//    - vidéo H.264 (Annex B → AVCC, SPS/PPS → avcC, IDR → sync) ;
//    - audio AC-3 / E-AC-3 / AAC-ADTS (une trame = un sample) ;
//    - PES audio À CHEVAL sur deux segments : l'assembleur PERSISTE
//      entre les appels — sans ça, on perdrait 1 à 3 trames à chaque
//      frontière (~toutes les 3 s), un hachage audible ;
//    - déroulage des horloges 33 bits (wrap ~26,5 h) → tfdt 64 bits
//      monotone, pour des sessions « qui ne coupent jamais » ;
//    - ré-ancrage propre sur discontinuité (splice/pub/reconnexion).
//
//  Ce qui est HORS périmètre v1 (le TS+mux.js reste alors la voie) :
//    HEVC/MPEG-2 vidéo, MP2/DTS/AAC-LATM audio (l'audio est retiré
//    du fMP4 → vidéo muette plutôt qu'échec, l'appelant journalise).
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
// =========================================================

import 'dart:typed_data';

import 'audio_frames.dart';
import 'fmp4_writer.dart';
import 'h264_annexb.dart';
import 'ts_es_extractor.dart';

/// Segment d'initialisation (à servir via #EXT-X-MAP).
class Fmp4InitSegment {
  Fmp4InitSegment({required this.bytes, required this.codecs});

  final Uint8List bytes;

  /// Attribut CODECS de la master playlist (RFC 6381), ex.
  /// 'avc1.64001f,ec-3'.
  final String codecs;
}

/// Segment média fMP4 (moof + mdat), équivalent du TsSegment.
class Fmp4MediaSegment {
  Fmp4MediaSegment({required this.bytes, required this.durationSec});

  final Uint8List bytes;
  final double durationSec;
}

/// Résultat d'un ré-emballage : [init] n'est renseigné que quand le
/// segment d'init vient d'être (ré)généré (premier segment, ou
/// changement de SPS/PPS/codec audio → le serveur doit republier).
class Fmp4RemuxResult {
  Fmp4RemuxResult({required this.media, this.init, this.droppedAudioCodec});

  final Fmp4MediaSegment media;
  final Fmp4InitSegment? init;

  /// Codec audio présent dans le TS mais NON transportable en fMP4
  /// v1 ('mp2', 'dts', 'aac-latm', 'private') — l'appelant journalise
  /// un WARN boîte noire (vidéo muette assumée, comme aujourd'hui).
  final String? droppedAudioCodec;
}

/// Déroule une horloge 33 bits (PTS/DTS 90 kHz) en temps monotone.
class _ClockUnwrapper {
  static const int _kWrap = 1 << 33;

  int? _lastRaw;
  int _offset = 0;

  int unwrap(int raw) {
    final int? last = _lastRaw;
    if (last != null) {
      // Saut en arrière de plus d'un demi-tour = wrap 33 bits.
      if (raw < last - (_kWrap >> 1)) {
        _offset += _kWrap;
      } else if (raw > last + (_kWrap >> 1)) {
        _offset -= _kWrap; // horloge repartie en arrière (rare)
      }
    }
    _lastRaw = raw;
    return raw + _offset;
  }

  void reset() {
    _lastRaw = null;
    _offset = 0;
  }
}

class Fmp4Remuxer {
  Fmp4Remuxer();

  /// Codecs audio transportables en fMP4 v1.
  static const Set<String> kSupportedAudio = <String>{'ac3', 'eac3', 'aac'};

  /// Le remuxeur v1 ne transporte que la vidéo H.264.
  static const Set<String> kSupportedVideo = <String>{'h264'};

  final TsEsExtractor _extractor = TsEsExtractor();
  final _ClockUnwrapper _videoClock = _ClockUnwrapper();
  final _ClockUnwrapper _audioClock = _ClockUnwrapper();

  int _sequence = 0;

  // Configuration courante — l'init est (ré)générée quand elle change.
  Uint8List? _sps;
  Uint8List? _pps;
  AudioCodecConfig? _audioConfig;
  Fmp4InitSegment? _init;

  /// Durée vidéo nominale de secours (25 i/s) quand un segment n'a
  /// qu'un seul sample — remplacée dès qu'un delta DTS réel existe.
  int _lastVideoDuration = 3600;

  /// Segment d'init courant (null tant qu'aucun segment exploitable).
  Fmp4InitSegment? get initSegment => _init;

  /// Ré-emballe un segment TS fini (produit par TsHlsSegmenter). Rend
  /// null si le segment n'est pas exploitable (codec vidéo non géré,
  /// aucune unité d'accès, SPS/PPS introuvables) — l'appelant garde
  /// alors le chemin TS historique.
  Fmp4RemuxResult? remux(Uint8List tsSegment, {bool discontinuity = false}) {
    if (discontinuity) {
      // Nouvelle ligne de temps (splice, reconnexion) : on jette le
      // PES audio en cours d'assemblage et le reliquat de trame (ses
      // octets appartiennent à l'ancienne horloge), puis on ré-ancre
      // les horloges déroulées et la base de temps audio continue.
      _extractor.dropPending();
      _videoClock.reset();
      _audioClock.reset();
      _audioEsRest = null;
      _audioBmdtNext = null;
    }
    final TsEsExtraction ex = _extractor.extract(tsSegment);

    final bool hasVideo = ex.videoUnits.isNotEmpty &&
        kSupportedVideo.contains(ex.videoCodec);
    // Un TS avec une vidéo NON gérée (hevc/mpeg2) ne doit pas devenir
    // un fMP4 audio seul : on refuse, l'appelant reste en TS.
    if (!hasVideo && ex.videoCodec != 'unknown') return null;

    // ---- Vidéo : PES → samples AVCC datés ----
    _pendingFirstVideoDts = null;
    final List<VideoSample> videoSamples = <VideoSample>[];
    if (hasVideo) {
      final List<_TimedAu> aus = <_TimedAu>[];
      for (final PesUnit pes in ex.videoUnits) {
        final int? pts = pes.pts90k;
        if (pts == null) continue; // AU non datée : indécodable proprement
        final int dts = pes.dts90k ?? pts;
        final List<Uint8List> nals = splitAnnexBNals(pes.bytes);
        if (nals.isEmpty) continue;
        bool key = false;
        for (final Uint8List nal in nals) {
          switch (nalType(nal)) {
            case kNalSps:
              _sps = Uint8List.fromList(nal);
            case kNalPps:
              _pps = Uint8List.fromList(nal);
            case kNalIdr:
              key = true;
          }
        }
        // CTS = PTS − DTS. À l'instant précis du wrap 33 bits, PTS et
        // DTS peuvent être de part et d'autre du tour d'horloge : on
        // renormalise (sinon offset délirant de ±2^33 une fois par
        // ~26,5 h).
        int cts = pts - dts;
        if (cts > _ClockUnwrapper._kWrap >> 1) {
          cts -= _ClockUnwrapper._kWrap;
        } else if (cts < -(_ClockUnwrapper._kWrap >> 1)) {
          cts += _ClockUnwrapper._kWrap;
        }
        final int unwrappedDts = _videoClock.unwrap(dts);
        _pendingFirstVideoDts ??= unwrappedDts;
        aus.add(_TimedAu(
          dts: unwrappedDts,
          cts: cts,
          avcc: nalsToAvcc(nals),
          keyframe: key,
        ));
      }
      for (int i = 0; i < aus.length; i++) {
        int duration;
        if (i + 1 < aus.length) {
          // Delta DTS borné : jamais ≤ 0 (DTS non monotone = flux
          // malade) ni > 10 s (saut d'horloge non signalé).
          duration = aus[i + 1].dts - aus[i].dts;
          if (duration < 1) duration = 1;
          if (duration > 90000 * 10) duration = 90000 * 10;
          _lastVideoDuration = duration;
        } else {
          // Dernier sample : le DTS suivant vit dans le PROCHAIN
          // segment — on reprend le delta précédent (cadence stable),
          // le tfdt du prochain fragment re-cale de toute façon.
          duration = _lastVideoDuration;
        }
        videoSamples.add(VideoSample(
          data: aus[i].avcc,
          durationTicks: duration,
          ctsOffsetTicks: aus[i].cts,
          keyframe: aus[i].keyframe,
        ));
      }
    }

    // ---- Audio : PES → trames élémentaires ----
    String? droppedAudio;
    final List<AudioSample> audioSamples = <AudioSample>[];
    AudioCodecConfig? segmentAudioConfig;
    int? firstAudioPts;
    int segmentAudioTicks = 0;
    if (ex.audioUnits.isNotEmpty) {
      if (kSupportedAudio.contains(ex.audioCodec)) {
        final BytesBuilder es = BytesBuilder(copy: false);
        // Reliquat du segment précédent : certains multiplexeurs ne
        // s'alignent pas trame/PES — une trame AC-3 peut commencer en
        // fin de segment et finir dans le suivant. Sans report, on la
        // perdrait à CHAQUE segment (hachage audible).
        final Uint8List? carried = _audioEsRest;
        if (carried != null && carried.isNotEmpty) es.add(carried);
        _audioEsRest = null;
        for (final PesUnit pes in ex.audioUnits) {
          // L'ancre temporelle = PTS du PREMIER PES qui porte un PTS.
          // Les trames suivantes avancent d'une durée de trame — les
          // PTS intermédiaires sont redondants sur un débit constant.
          firstAudioPts ??= pes.pts90k;
          es.add(pes.bytes);
        }
        final AudioSplitResult split = ex.audioCodec == 'aac'
            ? splitAdtsFrames(es.takeBytes())
            : splitAc3Frames(es.takeBytes());
        segmentAudioConfig = split.config;
        for (final AudioFrame f in split.frames) {
          audioSamples.add(AudioSample(
            data: f.bytes,
            durationTicks: f.sampleCount,
          ));
          segmentAudioTicks += f.sampleCount;
        }
        // COPIE du reliquat (une vue épinglerait tout le buffer ES du
        // segment en mémoire pour quelques centaines d'octets).
        _audioEsRest =
            split.rest.isEmpty ? null : Uint8List.fromList(split.rest);
      } else if (ex.audioCodec != 'unknown') {
        droppedAudio = ex.audioCodec;
      }
    }

    if (videoSamples.isEmpty && audioSamples.isEmpty) return null;

    // ---- (Ré)génération du segment d'init si la config a changé ----
    final bool audioChanged = segmentAudioConfig != null &&
        (_audioConfig == null ||
            _audioConfig!.codec != segmentAudioConfig.codec ||
            _audioConfig!.sampleRate != segmentAudioConfig.sampleRate ||
            !_sameBytes(_audioConfig!.codecConfigBytes,
                segmentAudioConfig.codecConfigBytes));
    if (audioChanged) _audioConfig = segmentAudioConfig;

    Fmp4InitSegment? freshInit;
    if (hasVideo && (_sps == null || _pps == null)) {
      // Vidéo sans SPS/PPS : indécodable en fMP4 (pas d'avcC). Le
      // segmenteur démarre sur keyframe → cas normalement impossible,
      // mais on refuse proprement plutôt que d'émettre un init faux.
      return null;
    }
    final bool needInit = _init == null || audioChanged || _spsPpsChanged();
    if (needInit) {
      freshInit = _buildInit(hasVideo: hasVideo);
      if (freshInit == null) return null;
      _init = freshInit;
      _spsInInit = _sps;
      _ppsInInit = _pps;
    }

    // ---- Assemblage du segment média ----
    VideoRun? videoRun;
    if (videoSamples.isNotEmpty) {
      videoRun = VideoRun(
        baseMediaDecodeTime: _firstVideoDts!,
        samples: videoSamples,
      );
    }
    AudioRun? audioRun;
    if (audioSamples.isNotEmpty && _audioConfig != null) {
      final int rate = _audioConfig!.sampleRate;
      // Base de temps audio CONTINUE : on avance du nombre exact
      // d'échantillons émis (zéro dérive d'arrondi), et on ne se
      // ré-ancre sur le PTS que s'il révèle un VRAI trou (> 2 trames)
      // — un PES pouvant référencer sa première trame ENTAMÉE dans le
      // segment précédent, un écart d'UNE trame est normal quand un
      // reliquat a été porté.
      final int? fromPts = firstAudioPts != null
          ? (_audioClock.unwrap(firstAudioPts) * rate) ~/ 90000
          : null;
      int bmdt;
      final int? cont = _audioBmdtNext;
      if (cont != null) {
        bmdt = cont;
        final int tolerance = 2 * audioSamples.first.durationTicks;
        if (fromPts != null && (fromPts - cont).abs() > tolerance) {
          bmdt = fromPts; // trou/splice réel : on suit le PTS
        }
      } else if (fromPts != null) {
        bmdt = fromPts;
      } else {
        // Aucun PTS audio depuis le début : cale sur la vidéo.
        bmdt = ((_firstVideoDts ?? 0) * rate) ~/ 90000;
      }
      _audioBmdtNext = bmdt + segmentAudioTicks;
      audioRun = AudioRun(
        baseMediaDecodeTime: bmdt,
        samples: audioSamples,
      );
    }
    if (videoRun == null && audioRun == null) return null;

    _sequence++;
    final Uint8List media = Fmp4Writer.mediaSegment(
      sequenceNumber: _sequence,
      video: videoRun,
      audio: audioRun,
    );

    // Durée du segment : somme des durées vidéo (base EXTINF), repli
    // audio pour les flux sans vidéo (radio).
    double durationSec;
    if (videoSamples.isNotEmpty) {
      final int ticks = videoSamples.fold<int>(
          0, (int a, VideoSample s) => a + s.durationTicks);
      durationSec = ticks / 90000.0;
    } else {
      final int ticks = audioSamples.fold<int>(
          0, (int a, AudioSample s) => a + s.durationTicks);
      durationSec = ticks / _audioConfig!.sampleRate;
    }

    return Fmp4RemuxResult(
      media: Fmp4MediaSegment(bytes: media, durationSec: durationSec),
      init: freshInit,
      droppedAudioCodec: droppedAudio,
    );
  }

  // DTS déroulé du premier sample vidéo du segment en cours — posé
  // par remux() au moment du découpage des AU.
  int? get _firstVideoDts => _pendingFirstVideoDts;
  int? _pendingFirstVideoDts;

  /// Reliquat d'ES audio (trame coupée en fin de segment, reportée).
  Uint8List? _audioEsRest;

  /// Prochaine base de temps audio attendue (ticks « sampleRate ») —
  /// la continuité parfaite entre segments, sans dérive d'arrondi.
  int? _audioBmdtNext;

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Uint8List? _spsInInit;
  Uint8List? _ppsInInit;

  bool _spsPpsChanged() {
    final Uint8List? sps = _sps;
    final Uint8List? pps = _pps;
    if (sps == null || pps == null) return false;
    final Uint8List? inInitSps = _spsInInit;
    final Uint8List? inInitPps = _ppsInInit;
    if (inInitSps == null || inInitPps == null) return true;
    return !_sameBytes(sps, inInitSps) || !_sameBytes(pps, inInitPps);
  }

  Fmp4InitSegment? _buildInit({required bool hasVideo}) {
    VideoTrackConfig? video;
    final List<String> codecs = <String>[];
    if (hasVideo) {
      final Uint8List? sps = _sps;
      final Uint8List? pps = _pps;
      if (sps == null || pps == null) return null;
      final ({int width, int height})? dims = parseSpsDimensions(sps);
      video = VideoTrackConfig(
        sps: sps,
        pps: pps,
        // Dimensions neutres si SPS exotique : les décodeurs lisent
        // de toute façon le flux, ces champs sont informatifs.
        width: dims?.width ?? 1920,
        height: dims?.height ?? 1080,
        rfc6381: avc1CodecString(sps),
      );
      codecs.add(video.rfc6381);
    }
    final AudioCodecConfig? audio = _audioConfig;
    if (audio != null) codecs.add(audio.rfc6381);
    if (video == null && audio == null) return null;
    return Fmp4InitSegment(
      bytes: Fmp4Writer.initSegment(video: video, audio: audio),
      codecs: codecs.join(','),
    );
  }
}

class _TimedAu {
  _TimedAu({
    required this.dts,
    required this.cts,
    required this.avcc,
    required this.keyframe,
  });

  final int dts;
  final int cts;
  final Uint8List avcc;
  final bool keyframe;
}
