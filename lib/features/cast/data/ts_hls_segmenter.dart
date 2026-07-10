// =========================================================
//  ts_hls_segmenter.dart — Découpe d'un flux MPEG-TS en segments HLS
// =========================================================
//  POURQUOI (diag SHIELD 2026-07-09, 8 casts / 8 échecs "IDLE:error") :
//  l'ancien repli « local_hls_relay » servait une playlist HLS à
//  SEGMENT UNIQUE INFINI (technique BubbleUPnP historique). Or le
//  Default Media Receiver moderne (CAF / Shaka Player) télécharge
//  chaque segment EN ENTIER (XHR arraybuffer) avant de l'append au
//  MediaSource : un segment sans fin ne se termine jamais → aucune
//  frame décodée → la TV rejette le flux au bout de ~10-20 s
//  (« codec / format non supporté » alors que le codec n'y est pour
//  rien). La seule forme de HLS que le récepteur accepte est du VRAI
//  HLS live : des segments FINIS (~3 s) + une playlist GLISSANTE
//  rafraîchie en continu.
//
//  Ce fichier fait la moitié « parsing » du travail : il lit le flux
//  d'octets MPEG-TS upstream (paquets de 188 octets) et le découpe en
//  segments finis, alignés sur les images-clés quand le flux les
//  signale (random_access_indicator), datés au PCR. Chaque segment
//  démarre par les derniers PAT + PMT vus pour être décodable
//  indépendamment. Aucun transcodage : les octets sont recopiés tels
//  quels (le téléphone ne fait que du découpage).
//
//  La moitié « réseau / playlist / HTTP » vit dans
//  hls_relay_session.dart + local_cast_server.dart.
//
//  Pur Dart (dart:typed_data uniquement) → testable sans device.
// =========================================================

import 'dart:typed_data';

/// Un segment HLS fini, prêt à être servi tel quel (video/mp2t).
class TsSegment {
  TsSegment({required this.bytes, required this.durationSec});

  final Uint8List bytes;

  /// Durée réelle mesurée au PCR (repli : horloge murale). Sert à
  /// l'EXTINF de la playlist — Shaka se sert de ces durées pour caler
  /// sa fenêtre live, elles doivent être honnêtes.
  final double durationSec;
}

class TsHlsSegmenter {
  TsHlsSegmenter({
    this.targetDurationSec = 3.0,
    this.maxDurationSec = 6.0,
    this.startupSegments = 0,
    this.startupTargetSec = 1.8,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Durée visée d'un segment. 3 s = compromis latence de zapping /
  /// nombre de requêtes HTTP côté TV.
  final double targetDurationSec;

  /// Démarrage progressif (fluidité 2026-07-10) : les [startupSegments]
  /// premiers segments visent [startupTargetSec] au lieu de
  /// [targetDurationSec]. Le récepteur obtient sa matière initiale
  /// (2 segments) presque deux fois plus vite → première image plus
  /// tôt au zapping, puis on revient aux segments longs (stabilité,
  /// moins de requêtes). `0` = comportement historique (segments
  /// uniformes), défaut pour ne pas surprendre les autres usages.
  final int startupSegments;

  /// Durée visée des segments de démarrage (voir [startupSegments]).
  final double startupTargetSec;

  /// Au-delà, on coupe au prochain début de PES vidéo MÊME sans
  /// image-clé (certains encodeurs IPTV ne posent jamais le
  /// random_access_indicator) — le récepteur re-synchronise seul.
  final double maxDurationSec;

  /// Garde-fou mémoire : coupe inconditionnelle (frontière paquet) si
  /// un segment dépasse cette taille — flux à très haut débit ou PES
  /// vidéo introuvable (PIDs chiffrés, etc.).
  static const int kMaxSegmentBytes = 16 * 1024 * 1024;

  /// En-dessous de ~un paquet on ne publie pas : segment vide = 404
  /// chez le récepteur.
  static const int kMinSegmentBytes = 188 * 8;

  final DateTime Function() _clock;

  // ---- État de parsing ----
  final BytesBuilder _pending = BytesBuilder(copy: false); // octets non alignés
  Uint8List? _patPacket; // dernier paquet PAT complet (188 o)
  Uint8List? _pmtPacket; // dernier paquet PMT complet (188 o)
  int _pmtPid = -1;
  int _videoPid = -1;

  /// `true` si une section PSI s'étale sur plusieurs paquets : on ne
  /// la ré-injecte pas en tête de segment, elle vit dans le flux.
  bool _psiInline = false;

  /// Codec vidéo annoncé par la PMT ('h264' | 'hevc' | 'mpeg2' |
  /// 'mpeg4' | 'unknown'). Publié dans les diagnostics : un flux HEVC
  /// qui échoue sur Chromecast 1-3 est une LIMITE du récepteur (HEVC
  /// exige du fMP4 côté CAF), pas un bug du relais.
  String videoCodec = 'unknown';

  /// Codec audio annoncé par la PMT ('aac' | 'aac-latm' | 'mp2' |
  /// 'ac3' | 'eac3' | 'private' | 'unknown'). Précieux pour trancher
  /// les plaintes « son de vieille radio » : une piste mp2 mono bas
  /// débit côté fournisseur n'est PAS un bug de lecture.
  String audioCodec = 'unknown';

  // ---- État de découpe ----
  final BytesBuilder _segment = BytesBuilder(copy: false);
  bool _started = false; // on n'accumule qu'à partir de PAT+PMT+keyframe
  double? _segStartPcr;
  double? _lastPcr;
  double? _firstPcr;

  /// Première / dernière PCR observées sur CE flux. Utilisées par la
  /// session pour détecter qu'une re-connexion upstream CONTINUE la
  /// même horloge (transition invisible, pas de EXT-X-DISCONTINUITY).
  double? get firstPcrSeen => _firstPcr;
  double? get lastPcrSeen => _lastPcr;
  DateTime? _segStartWall;
  DateTime? _firstVideoWall;

  /// Segments déjà émis — pilote la rampe de démarrage.
  int _emitted = 0;

  /// Cible effective du segment EN COURS (rampe de démarrage).
  double get _currentTargetSec =>
      _emitted < startupSegments ? startupTargetSec : targetDurationSec;

  // Fiabilité du random_access_indicator : si on voit beaucoup de
  // débuts de PES vidéo sans jamais un seul RAI, l'encodeur ne le pose
  // pas → on démarre/coupe sans alignement keyframe.
  int _videoPusiSeen = 0;
  bool _raiSeen = false;
  static const int _kRaiGiveUpAfterPusi = 250;
  static const Duration _kRaiGiveUpAfter = Duration(seconds: 8);

  bool get _raiUnusable =>
      !_raiSeen &&
      (_videoPusiSeen >= _kRaiGiveUpAfterPusi ||
          (_firstVideoWall != null &&
              _clock().difference(_firstVideoWall!) >= _kRaiGiveUpAfter));

  /// Ingestion d'un chunk d'octets upstream (taille quelconque).
  /// Renvoie les segments TERMINÉS par ce chunk (souvent vide).
  List<TsSegment> ingest(List<int> chunk) {
    final List<TsSegment> out = <TsSegment>[];
    _pending.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    Uint8List buf = _pending.takeBytes();

    int off = 0;
    while (buf.length - off >= 188) {
      if (buf[off] != 0x47) {
        // Resynchronisation : cherche le prochain 0x47 suivi d'un 0x47
        // 188 octets plus loin (évite les faux positifs dans la payload).
        final int next = _resync(buf, off);
        if (next < 0) {
          off = buf.length; // rien d'exploitable, on jette
          break;
        }
        off = next;
        if (buf.length - off < 188) break;
      }
      final TsSegment? done =
          _handlePacket(Uint8List.sublistView(buf, off, off + 188));
      if (done != null) out.add(done);
      off += 188;
    }
    if (off < buf.length) {
      _pending.add(Uint8List.sublistView(buf, off));
    }
    return out;
  }

  /// Publie le segment en cours (fin de connexion upstream). Peut
  /// renvoyer null si trop petit pour être utile.
  TsSegment? flush() {
    if (_segment.length < kMinSegmentBytes) {
      _segment.clear();
      return null;
    }
    return _emit();
  }

  int _resync(Uint8List buf, int from) {
    for (int i = from; i + 188 < buf.length; i++) {
      if (buf[i] == 0x47 && buf[i + 188] == 0x47) return i;
    }
    return -1;
  }

  TsSegment? _handlePacket(Uint8List p) {
    final bool pusi = (p[1] & 0x40) != 0;
    final int pid = ((p[1] & 0x1F) << 8) | p[2];
    final int afc = (p[3] >> 4) & 0x3;

    // --- PSI : PAT (PID 0) et PMT ---
    // Revue 2026-07-09 (MINEUR 5) : une section PSI qui NE TIENT PAS
    // dans son paquet (PMT chargée en pistes/descripteurs) ne peut pas
    // etre re-injectee en tete de segment (elle serait tronquee, et
    // ses paquets de continuation resteraient orphelins). Dans ce cas
    // on la laisse DANS le flux (elle se repete ~2x/s) et on ne cache
    // rien.
    if (pid == 0 && pusi) {
      _parsePat(p);
      if (_sectionFitsInPacket(p)) {
        _patPacket = Uint8List.fromList(p);
        return null; // ré-injecté en tête de segment
      }
      _patPacket = null;
      _psiInline = true;
    } else if (pid == _pmtPid && pusi) {
      _parsePmt(p);
      if (_sectionFitsInPacket(p)) {
        _pmtPacket = Uint8List.fromList(p);
        return null;
      }
      _pmtPacket = null;
      _psiInline = true;
    }

    // --- PCR (sur n'importe quel PID qui en porte) ---
    double? pcr;
    if (afc == 2 || afc == 3) {
      final int afLen = p[4];
      if (afLen >= 7 && (p[5] & 0x10) != 0) {
        pcr = _readPcrSeconds(p, 6);
        if (pcr != null) {
          _firstPcr ??= pcr;
          // Saut d'horloge (wrap 33 bits / discontinuité serveur) :
          // on repart de là plutôt que de produire une durée délirante.
          if (_lastPcr != null && (pcr < _lastPcr! || pcr - _lastPcr! > 10)) {
            _segStartPcr = pcr - _elapsedSec();
          }
          _lastPcr = pcr;
        }
      }
    }

    final bool isVideo = pid == _videoPid;
    bool keyframe = false;
    if (isVideo && pusi) {
      _videoPusiSeen++;
      _firstVideoWall ??= _clock();
      if ((afc == 2 || afc == 3) && p[4] > 0 && (p[5] & 0x40) != 0) {
        keyframe = true;
        _raiSeen = true;
      }
    }

    TsSegment? completed;

    if (!_started) {
      // Démarrage : il faut PAT + PMT (sinon rien n'est décodable) et
      // une image-clé — ou la preuve que le flux n'en signale pas.
      // PSI multi-paquets : elles restent dans le flux (_psiInline),
      // le récepteur les retrouvera dans le segment lui-même.
      final bool psiReady =
          _psiInline || (_patPacket != null && _pmtPacket != null);
      final bool startNow =
          psiReady && isVideo && pusi && (keyframe || _raiUnusable);
      if (!startNow) return null;
      _beginSegment();
    } else if (isVideo && pusi) {
      // Frontière de découpe possible (début d'une nouvelle PES vidéo).
      final double elapsed = _elapsedSec();
      final bool cutOnKey = keyframe && elapsed >= _currentTargetSec;
      final bool cutNoKey =
          elapsed >= (_raiUnusable ? _currentTargetSec : maxDurationSec);
      if ((cutOnKey || cutNoKey) && _segment.length >= kMinSegmentBytes) {
        completed = _emit();
        _beginSegment();
      }
    } else if (_segment.length >= kMaxSegmentBytes) {
      completed = _emit();
      _beginSegment();
    }

    _segment.add(Uint8List.fromList(p));
    return completed;
  }

  void _beginSegment() {
    _started = true;
    _segment.clear();
    if (_patPacket != null) _segment.add(_patPacket!);
    if (_pmtPacket != null) _segment.add(_pmtPacket!);
    _segStartPcr = _lastPcr;
    _segStartWall = _clock();
  }

  double _elapsedSec() {
    if (_segStartPcr != null && _lastPcr != null && _lastPcr! >= _segStartPcr!) {
      return _lastPcr! - _segStartPcr!;
    }
    if (_segStartWall != null) {
      return _clock().difference(_segStartWall!).inMilliseconds / 1000.0;
    }
    return 0;
  }

  TsSegment _emit() {
    final double dur = _elapsedSec().clamp(0.5, 30.0).toDouble();
    final TsSegment seg =
        TsSegment(bytes: _segment.takeBytes(), durationSec: dur);
    _segment.clear();
    _emitted++;
    return seg;
  }

  // ---- Parsing PSI ----

  /// La section PSI démarrée dans [p] tient-elle ENTIÈREMENT dans ce
  /// paquet ? (section_length + en-tête ≤ payload disponible)
  bool _sectionFitsInPacket(Uint8List p) {
    final Uint8List? s = _sectionOf(p);
    if (s == null || s.length < 3) return false;
    final int sectionLen = ((s[1] & 0x0F) << 8) | s[2];
    return 3 + sectionLen <= s.length;
  }

  /// Section pointée par pointer_field, ou null si le paquet est
  /// trop court / malformé (on ignore alors sans casser le flux).
  Uint8List? _sectionOf(Uint8List p) {
    int off = 4;
    final int afc = (p[3] >> 4) & 0x3;
    if (afc == 2) return null; // adaptation seule, pas de payload
    if (afc == 3) {
      if (off >= 188) return null;
      off += 1 + p[4];
    }
    if (off >= 188) return null;
    final int pointer = p[off];
    off += 1 + pointer;
    if (off >= 188) return null;
    return Uint8List.sublistView(p, off);
  }

  void _parsePat(Uint8List p) {
    final Uint8List? s = _sectionOf(p);
    if (s == null || s.isEmpty || s[0] != 0x00 || s.length < 12) return;
    final int sectionLen = ((s[1] & 0x0F) << 8) | s[2];
    final int end = 3 + sectionLen - 4; // - CRC32
    for (int i = 8; i + 4 <= end && i + 4 <= s.length; i += 4) {
      final int program = (s[i] << 8) | s[i + 1];
      final int pid = ((s[i + 2] & 0x1F) << 8) | s[i + 3];
      if (program != 0) {
        _pmtPid = pid;
        return;
      }
    }
  }

  void _parsePmt(Uint8List p) {
    final Uint8List? s = _sectionOf(p);
    if (s == null || s.isEmpty || s[0] != 0x02 || s.length < 16) return;
    final int sectionLen = ((s[1] & 0x0F) << 8) | s[2];
    final int end = 3 + sectionLen - 4;
    final int programInfoLen = ((s[10] & 0x0F) << 8) | s[11];
    int i = 12 + programInfoLen;
    while (i + 5 <= end && i + 5 <= s.length) {
      final int streamType = s[i];
      final int pid = ((s[i + 1] & 0x1F) << 8) | s[i + 2];
      final int esInfoLen = ((s[i + 3] & 0x0F) << 8) | s[i + 4];
      final String? codec = _videoCodecOf(streamType);
      if (codec != null && _videoPid == -1) {
        _videoPid = pid;
        videoCodec = codec;
      }
      final String? audio = _audioCodecOf(streamType);
      if (audio != null && audioCodec == 'unknown') {
        audioCodec = audio;
      }
      i += 5 + esInfoLen;
    }
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
        // PES privé : souvent AC-3/DVB-sub selon les descripteurs (non
        // parsés ici) — on le signale sans trancher.
        return 'private';
    }
    return null;
  }

  /// PCR = base 33 bits à 90 kHz (on ignore l'extension 27 MHz,
  /// précision inutile ici). Renvoie des secondes.
  static double? _readPcrSeconds(Uint8List p, int off) {
    if (off + 6 > 188) return null;
    final int base = (p[off] << 25) |
        (p[off + 1] << 17) |
        (p[off + 2] << 9) |
        (p[off + 3] << 1) |
        (p[off + 4] >> 7);
    return base / 90000.0;
  }
}
