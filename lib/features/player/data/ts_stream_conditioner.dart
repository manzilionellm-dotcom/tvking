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
