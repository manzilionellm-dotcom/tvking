// =========================================================
//  ts_stream_conditioner.dart — Hygiène du flux MPEG-TS relayé
// =========================================================
//  POURQUOI CE FICHIER EXISTE
//  --------------------------
//  Le mini-relais (local_stream_relay.dart) recopie les octets du serveur
//  IPTV vers le lecteur. Deux problèmes de « plomberie TS » dégradaient la
//  résilience sur connexion faible :
//
//  1. RECONNEXION AMONT EN MILIEU DE PAQUET. Un flux MPEG-TS est une suite
//     de paquets de 188 octets commençant chacun par l'octet de
//     synchronisation 0x47. Quand le serveur coupe et qu'on rouvre la
//     connexion, la nouvelle réponse HTTP repart d'un endroit ARBITRAIRE du
//     flux : si on pousse ces octets tels quels au décodeur, il reçoit un
//     demi-paquet collé au flux précédent → artefacts, voire décrochage
//     complet (ExoPlayer peut jeter l'éponge sur un TS incohérent).
//     → [TsSyncAligner] : à chaque (re)connexion, on JETTE les octets
//     jusqu'au premier point de synchronisation FIABLE (trois 0x47
//     espacés de 188 octets — un seul 0x47 peut apparaître par hasard
//     dans la charge utile).
//
//  2. RE-ATTACHEMENT DU LECTEUR À FROID. Quand ExoPlayer re-prépare après
//     un gel (watchdog anti-gel, retry silencieux natif), il rouvre l'URL
//     locale du relais et repart de ZÉRO : il doit attendre le prochain
//     PAT/PMT + la prochaine image clé avant d'afficher quoi que ce soit
//     (souvent 1 à 3 s de plus, écran noir). Les lecteurs « pro »
//     (TiviMate, tuners DVB) gardent une petite mémoire du flux.
//     → [TsRingBuffer] : le relais garde les N derniers octets ALIGNÉS du
//     flux ; au branchement d'un nouveau consommateur, il lui envoie ce
//     tampon d'un coup (burst). Le démuxeur retrouve immédiatement
//     PAT/PMT + une image clé récente → l'image revient quasi
//     instantanément au lieu d'attendre le fil de l'eau.
//
//  Ces deux classes sont PURES (zéro I/O, zéro Flutter) : testables
//  octet par octet (cf. test/features/player/ts_stream_conditioner_test.dart).
// =========================================================

import 'dart:typed_data';

/// Taille d'un paquet MPEG-TS (constante du standard ISO 13818-1).
const int kTsPacketSize = 188;

/// Octet de synchronisation en tête de CHAQUE paquet TS.
const int kTsSyncByte = 0x47;

/// Nombre de paquets consécutifs exigés pour déclarer la synchronisation
/// acquise : un 0x47 isolé apparaît par hasard ~1 fois tous les 256 octets
/// dans la charge utile ; trois 0x47 espacés d'exactement 188 octets ont une
/// probabilité de faux positif négligeable (~1/16 millions).
const int kTsSyncPackets = 3;

/// Réaligne un flux d'octets sur les frontières de paquets TS.
///
/// À créer NEUF à chaque (re)connexion upstream : tout ce qui précède le
/// premier point de synchronisation fiable est jeté, ensuite les octets
/// passent tels quels (zéro copie superflue une fois verrouillé).
class TsSyncAligner {
  bool _locked = false;

  /// Octets en attente de verrouillage (au plus ~2 paquets + 1 chunk).
  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Octets jetés avant verrouillage (diagnostic).
  int _discarded = 0;

  /// `true` dès que la synchronisation est acquise.
  bool get isLocked => _locked;

  /// Octets jetés avant le premier point de synchronisation.
  int get discardedBytes => _discarded;

  /// Traite [chunk] et renvoie les octets À TRANSMETTRE (vide tant que la
  /// synchronisation n'est pas trouvée). Une fois verrouillé, les chunks
  /// suivants ressortent tels quels sans copie.
  List<int> feed(List<int> chunk) {
    if (_locked) return chunk;
    _pending.add(chunk);
    final Uint8List buf = _pending.takeBytes();
    // Cherche le premier i où kTsSyncPackets paquets consécutifs commencent
    // par 0x47. On ne peut valider i que si i + (n-1)*188 est visible.
    final int lastCheckable = buf.length - (kTsSyncPackets - 1) * kTsPacketSize - 1;
    for (int i = 0; i <= lastCheckable; i++) {
      if (buf[i] != kTsSyncByte) continue;
      bool ok = true;
      for (int p = 1; p < kTsSyncPackets; p++) {
        if (buf[i + p * kTsPacketSize] != kTsSyncByte) {
          ok = false;
          break;
        }
      }
      if (ok) {
        _locked = true;
        _discarded += i;
        return Uint8List.sublistView(buf, i);
      }
    }
    // Pas encore trouvé : on garde une fenêtre de recherche suffisante
    // ((n-1) paquets + 187 octets) et on jette le début — un flux qui
    // n'accroche jamais ne doit pas accumuler de la mémoire sans fin.
    final int keep = (kTsSyncPackets - 1) * kTsPacketSize + kTsPacketSize;
    if (buf.length > keep) {
      _discarded += buf.length - keep;
      _pending.add(Uint8List.sublistView(buf, buf.length - keep));
    } else {
      _pending.add(buf);
    }
    return const <int>[];
  }
}

/// Mémoire glissante des derniers octets ALIGNÉS du flux TS.
///
/// Le relais y verse tout ce qu'il transmet (octets déjà passés par
/// [TsSyncAligner], donc alignés depuis le début de session). Au
/// branchement d'un nouveau consommateur, [alignedSnapshot] renvoie le
/// contenu à partir d'une frontière de paquet — prêt à envoyer d'un bloc.
class TsRingBuffer {
  TsRingBuffer({this.capacityBytes = 3 * 1024 * 1024});

  /// Taille max retenue. 3 Mo ≈ 3–5 s d'un flux TS typique (5–8 Mbit/s) :
  /// assez pour contenir PAT/PMT + une image clé récente, sans peser sur
  /// la RAM des petites box (leçon OOM du tampon ExoPlayer, cf.
  /// NativeVideoView.kt).
  final int capacityBytes;

  final List<Uint8List> _chunks = <Uint8List>[];
  int _size = 0;

  /// Octets ÉVACUÉS par l'avant depuis le début de session. Comme le flux
  /// entre aligné (offset 0 = frontière de paquet), la position globale du
  /// premier octet retenu est `_dropped` : il suffit de sauter
  /// `(-_dropped) mod 188` octets pour retomber sur une frontière.
  int _dropped = 0;

  /// Octets actuellement retenus.
  int get size => _size;

  /// Vide la mémoire (nouvelle connexion upstream : le contenu d'avant la
  /// coupure ne se raccorde plus au flux réaligné qui suit).
  void clear() {
    _chunks.clear();
    _size = 0;
    _dropped = 0;
  }

  /// Ajoute [chunk] (octets DÉJÀ alignés) et évacue le plus ancien au-delà
  /// de [capacityBytes].
  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(
        chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    _size += chunk.length;
    while (_size > capacityBytes && _chunks.isNotEmpty) {
      final Uint8List head = _chunks.first;
      final int excess = _size - capacityBytes;
      if (head.length <= excess) {
        _chunks.removeAt(0);
        _size -= head.length;
        _dropped += head.length;
      } else {
        _chunks[0] = Uint8List.sublistView(head, excess);
        _size -= excess;
        _dropped += excess;
        break;
      }
    }
  }

  /// Contenu courant, démarrant sur une frontière de paquet TS (vérifiée
  /// sur l'octet 0x47 par ceinture-bretelles). Renvoie une liste vide si
  /// rien d'exploitable.
  Uint8List alignedSnapshot() {
    if (_size == 0) return Uint8List(0);
    final Uint8List all = Uint8List(_size);
    int off = 0;
    for (final Uint8List c in _chunks) {
      all.setRange(off, off + c.length, c);
      off += c.length;
    }
    // Frontière théorique d'après la position globale…
    int skip = (kTsPacketSize - (_dropped % kTsPacketSize)) % kTsPacketSize;
    // …vérifiée sur les octets réels (si l'amont a menti sur l'alignement,
    // on re-cherche une vraie synchronisation plutôt que d'envoyer du bruit).
    if (skip >= all.length || all[skip] != kTsSyncByte) {
      final int found = _findSync(all);
      if (found < 0) return Uint8List(0);
      skip = found;
    }
    return skip == 0 ? all : Uint8List.sublistView(all, skip);
  }

  static int _findSync(Uint8List buf) {
    final int lastCheckable =
        buf.length - (kTsSyncPackets - 1) * kTsPacketSize - 1;
    for (int i = 0; i <= lastCheckable; i++) {
      if (buf[i] != kTsSyncByte) continue;
      bool ok = true;
      for (int p = 1; p < kTsSyncPackets; p++) {
        if (buf[i + p * kTsPacketSize] != kTsSyncByte) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  /// Contenu retenu À PARTIR de la position GLOBALE [globalOffset] (repère :
  /// octets alignés depuis le début de session — celui de [TsWarmupIndex]).
  /// Renvoie vide si la position est déjà évacuée, pas encore atteinte, ou
  /// ne tombe pas sur un octet de synchro (ceinture-bretelles) — l'appelant
  /// retombe alors sur [alignedSnapshot].
  Uint8List snapshotFrom(int globalOffset) {
    if (_size == 0) return Uint8List(0);
    final int skip = globalOffset - _dropped;
    if (skip < 0 || skip >= _size) return Uint8List(0);
    final Uint8List all = Uint8List(_size);
    int off = 0;
    for (final Uint8List c in _chunks) {
      all.setRange(off, off + c.length, c);
      off += c.length;
    }
    if (all[skip] != kTsSyncByte) return Uint8List(0);
    return skip == 0 ? all : Uint8List.sublistView(all, skip);
  }
}

/// Débitmètre à fenêtre glissante : le relais y déclare chaque paquet reçu,
/// le lecteur TV l'interroge pour détecter une connexion qui ne suit plus
/// (débit d'arrivée < débit du flux → gel imminent). Pur et testable via
/// des horodatages injectés.
class IngestRateMeter {
  IngestRateMeter({this.window = const Duration(seconds: 10)});

  /// Largeur de la fenêtre de mesure.
  final Duration window;

  final List<_RateSample> _samples = <_RateSample>[];
  int _totalBytes = 0;

  /// Total d'octets depuis le début de session (diagnostic).
  int get totalBytes => _totalBytes;

  /// Déclare [bytes] reçus à l'instant [now].
  void addBytes(int bytes, DateTime now) {
    _totalBytes += bytes;
    _samples.add(_RateSample(now, bytes));
    _evict(now);
  }

  /// Débit moyen (octets/seconde) sur la fenêtre. `null` tant qu'on n'a pas
  /// au moins ~2 s de recul (une moyenne sur 3 échantillons ment).
  double? bytesPerSecond(DateTime now) {
    _evict(now);
    if (_samples.isEmpty) return null;
    final Duration span = now.difference(_samples.first.time);
    if (span < const Duration(seconds: 2)) return null;
    int sum = 0;
    for (final _RateSample s in _samples) {
      sum += s.bytes;
    }
    return sum / (span.inMilliseconds / 1000.0);
  }

  void _evict(DateTime now) {
    final DateTime cutoff = now.subtract(window);
    while (_samples.isNotEmpty && _samples.first.time.isBefore(cutoff)) {
      _samples.removeAt(0);
    }
  }
}

class _RateSample {
  const _RateSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

// =========================================================
//  DÉMARRAGE À CHAUD SUR IMAGE-CLÉ (correctif macroblocs)
// =========================================================
//  CONSTAT TERRAIN (photos client, 2026-07-31) : au (re)branchement d'un
//  lecteur, la rafale de démarrage à chaud partait du PLUS VIEUX octet du
//  tampon — un point arbitraire au milieu d'un groupe d'images (GOP). Le
//  décodeur matériel recevait donc des images P/B SANS leur image de
//  référence → grosse « bouillie » de macroblocs pendant plusieurs
//  secondes (et de vieilles images rejouées), le temps qu'une image-clé
//  arrive au fil de l'eau.
//
//  Les lecteurs « pro » (TiviMate, tuners DVB) démarrent proprement : les
//  TABLES d'abord (PAT + PMT, pour que le démuxeur mappe les PID), puis le
//  flux À PARTIR DE LA DERNIÈRE IMAGE-CLÉ. Le standard MPEG-TS marque ces
//  points d'accès : bit RAI (random_access_indicator) du champ
//  d'adaptation (ISO 13818-1 §2.4.3.5).
//
//  [TsWarmupIndex] suit en continu, paquet par paquet (même à cheval sur
//  les chunks réseau) : la dernière PAT, la dernière PMT (PID lu dans la
//  PAT), le PID de la PCR (lu dans la PMT — porté par la vidéo dans la
//  quasi-totalité des mux) et l'offset GLOBAL du dernier paquet RAI. Le
//  relais assemble alors : PAT + PMT + flux depuis l'image-clé. Si un des
//  ingrédients manque (flux exotique sans RAI, image-clé déjà évacuée du
//  tampon), on retombe sur l'ancienne rafale — jamais pire qu'avant.
//
//  Pur (zéro I/O), testé octet par octet dans
//  test/features/player/ts_stream_conditioner_test.dart.
// =========================================================

class TsWarmupIndex {
  /// Position globale (en octets, depuis le début du flux ALIGNÉ) du
  /// prochain octet attendu par [feed]. Même repère que le comptage
  /// interne de [TsRingBuffer] nourri des mêmes chunks.
  int _globalOffset = 0;

  /// Reliquat d'un paquet à cheval entre deux chunks réseau.
  final Uint8List _carry = Uint8List(kTsPacketSize);
  int _carryLen = 0;

  Uint8List? _lastPat;
  Uint8List? _lastPmt;
  int _pmtPid = -1;
  int _pcrPid = -1;

  /// Offset global du dernier paquet RAI porté par le PID de la PCR (le
  /// signal image-clé le plus fiable) et, à défaut, par n'importe quel PID
  /// de données (certains mux ne posent le RAI que sur l'audio).
  int _lastRaiPcr = -1;
  int _lastRaiAny = -1;

  /// Dernier paquet PAT complet (copie de 188 octets), ou null.
  Uint8List? get lastPatPacket => _lastPat;

  /// Dernier paquet PMT complet (copie de 188 octets), ou null.
  Uint8List? get lastPmtPacket => _lastPmt;

  /// PID de la PMT lu dans la PAT (diagnostic/tests). -1 si inconnu.
  int get pmtPid => _pmtPid;

  /// PID de la PCR lu dans la PMT (diagnostic/tests). -1 si inconnu.
  int get pcrPid => _pcrPid;

  /// Offset global du meilleur point d'accès (image-clé) connu, -1 sinon.
  ///
  /// SEUL le RAI porté par le PID de la PCR compte (c'est la piste vidéo
  /// dans la quasi-totalité des mux) : un RAI audio est posé à chaque trame
  /// audio par certains mux — démarrer là donnerait une rafale SANS
  /// image-clé vidéo → son présent, image absente jusqu'à la prochaine IDR
  /// du direct (terrain 2026-07-31 : « seulement l'audio »). Pas de RAI
  /// vidéo → -1 → l'appelant renvoie la rafale complète (comportement
  /// historique, qui contient forcément une image-clé quelque part).
  int get bestKeyframeOffset => _lastRaiPcr;

  /// Dernier RAI vu sur un PID NON-vidéo (diagnostic/tests uniquement).
  int get lastRaiAnyOffset => _lastRaiAny;

  /// Oublie tout (reconnexion upstream : le repère d'octets repart de 0,
  /// et les tables de l'ancien flux ne décrivent plus le nouveau).
  void clear() {
    _globalOffset = 0;
    _carryLen = 0;
    _lastPat = null;
    _lastPmt = null;
    _pmtPid = -1;
    _pcrPid = -1;
    _lastRaiPcr = -1;
    _lastRaiAny = -1;
  }

  /// Déclare [chunk] (octets ALIGNÉS, les mêmes que ceux versés au tampon).
  void feed(List<int> chunk) {
    if (chunk.isEmpty) return;
    final Uint8List bytes =
        chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    int i = 0;
    // 1) Compléter un éventuel paquet à cheval.
    if (_carryLen > 0) {
      final int need = kTsPacketSize - _carryLen;
      final int take = need <= bytes.length ? need : bytes.length;
      _carry.setRange(_carryLen, _carryLen + take, bytes);
      _carryLen += take;
      i += take;
      if (_carryLen < kTsPacketSize) return; // toujours incomplet
      _parsePacket(_carry, _globalOffset);
      _globalOffset += kTsPacketSize;
      _carryLen = 0;
    }
    // 2) Paquets entiers du chunk.
    while (i + kTsPacketSize <= bytes.length) {
      _parsePacket(Uint8List.sublistView(bytes, i, i + kTsPacketSize),
          _globalOffset);
      _globalOffset += kTsPacketSize;
      i += kTsPacketSize;
    }
    // 3) Mettre de côté le début du paquet suivant.
    final int rest = bytes.length - i;
    if (rest > 0) {
      _carry.setRange(0, rest, bytes, i);
      _carryLen = rest;
    }
  }

  void _parsePacket(Uint8List pkt, int offset) {
    if (pkt[0] != kTsSyncByte) return; // flux désaligné : on n'invente rien
    final bool pusi = (pkt[1] & 0x40) != 0;
    final int pid = ((pkt[1] & 0x1F) << 8) | pkt[2];
    final int afc = (pkt[3] >> 4) & 0x3;
    int payloadStart = 4;
    if (afc == 2 || afc == 3) {
      final int afLen = pkt[4];
      // RAI = bit 0x40 du premier octet de drapeaux du champ d'adaptation.
      if (afLen > 0 && (pkt[5] & 0x40) != 0 && pid != 0 && pid != _pmtPid) {
        if (pid == _pcrPid) {
          _lastRaiPcr = offset;
        } else {
          _lastRaiAny = offset;
        }
      }
      payloadStart = 5 + afLen;
    }
    if (afc == 2 || payloadStart >= kTsPacketSize) return; // pas de payload
    if (!pusi) {
      // Les tables PSI qui nous intéressent tiennent dans UN paquet et
      // commencent toujours avec PUSI ; le reste ne nous concerne pas.
      return;
    }
    if (pid == 0) {
      final int pmt = _parsePatFirstPmtPid(pkt, payloadStart);
      if (pmt > 0) {
        _lastPat = Uint8List.fromList(pkt);
        if (pmt != _pmtPid) {
          // Nouveau programme : la PMT (et la PCR) d'avant ne valent plus.
          _pmtPid = pmt;
          _lastPmt = null;
          _pcrPid = -1;
        }
      }
    } else if (pid == _pmtPid) {
      final int pcr = _parsePmtPcrPid(pkt, payloadStart);
      if (pcr > 0) {
        _lastPmt = Uint8List.fromList(pkt);
        _pcrPid = pcr;
      }
    }
  }

  /// PID de la PMT du premier programme de la PAT (0 = réseau, ignoré).
  /// -1 si la section est invalide/tronquée — on préfère ne rien croire.
  static int _parsePatFirstPmtPid(Uint8List pkt, int payloadStart) {
    int p = payloadStart;
    if (p >= kTsPacketSize) return -1;
    p += 1 + pkt[p]; // pointer_field
    if (p + 8 > kTsPacketSize) return -1;
    if (pkt[p] != 0x00) return -1; // table_id PAT
    final int sectionLength = ((pkt[p + 1] & 0x0F) << 8) | pkt[p + 2];
    final int sectionEnd = p + 3 + sectionLength; // fin CRC comprise
    if (sectionLength < 9 || sectionEnd > kTsPacketSize) return -1;
    int q = p + 8; // après transport_stream_id/version/section numbers
    while (q + 4 <= sectionEnd - 4) {
      final int programNumber = (pkt[q] << 8) | pkt[q + 1];
      final int pmtPid = ((pkt[q + 2] & 0x1F) << 8) | pkt[q + 3];
      if (programNumber != 0) return pmtPid;
      q += 4;
    }
    return -1;
  }

  /// PID de la PCR dans la PMT. -1 si section invalide/tronquée.
  static int _parsePmtPcrPid(Uint8List pkt, int payloadStart) {
    int p = payloadStart;
    if (p >= kTsPacketSize) return -1;
    p += 1 + pkt[p]; // pointer_field
    if (p + 10 > kTsPacketSize) return -1;
    if (pkt[p] != 0x02) return -1; // table_id PMT
    final int sectionLength = ((pkt[p + 1] & 0x0F) << 8) | pkt[p + 2];
    if (sectionLength < 13 || p + 3 + sectionLength > kTsPacketSize) return -1;
    return ((pkt[p + 8] & 0x1F) << 8) | pkt[p + 9];
  }
}
