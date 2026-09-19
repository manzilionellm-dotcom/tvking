// =========================================================
//  ressources_moniteur.dart — RAM et CPU RÉELS de l'app, pour le panel
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026), au vu du banc de la famille :
//  « remonte la RAM et le CPU réels dans le heartbeat — Mo utilisés,
//  pic sur l'heure — pour savoir quelles box vivent au bord. »
//
//  ---------------------------------------------------------
//  CE QU'ON SAVAIT, ET CE QUI MANQUAIT
//  ---------------------------------------------------------
//  La Boîte noire compte les PURGES mémoire : Android a prévenu qu'il
//  manquait de place et on a vidé le cache. C'est le symptôme. Le
//  chiffre, lui — combien l'app pèse, à combien elle est montée dans
//  l'heure — n'existait nulle part. Une box à 1 Go qui tourne à 700 Mo
//  d'app ne purge peut-être jamais… jusqu'au soir où le fournisseur
//  envoie 60 000 chaînes. On veut la voir AVANT ce soir-là.
//
//  ---------------------------------------------------------
//  D'OÙ VIENNENT LES CHIFFRES
//  ---------------------------------------------------------
//  • RAM : `ProcessInfo.currentRss` — la mémoire résidente du processus,
//    celle que le système compte contre nous. Disponible sur Android,
//    Linux et Windows sans rien demander.
//  • CPU : `/proc/self/stat` (Android / Linux), champs utime + stime en
//    ticks d'horloge. Deux lectures à une minute d'écart donnent le
//    temps CPU consommé dans l'intervalle ; rapporté au temps écoulé et
//    au nombre de cœurs, c'est le pourcentage de l'APPAREIL entier —
//    le même que celui d'un gestionnaire de tâches. Sur Windows, ce
//    fichier n'existe pas : le CPU reste `null`, il n'est pas inventé.
//
//  ---------------------------------------------------------
//  UNE FENÊTRE D'UNE HEURE, PAS UN COMPTEUR DEPUIS LE BOOT
//  ---------------------------------------------------------
//  `ProcessInfo.maxRss` donnerait le pic depuis le démarrage — inutile
//  au bout de trois jours : un pic d'il y a lundi ne dit rien de ce
//  soir. On garde soixante échantillons (un par minute) et le pic est
//  le maximum de cette fenêtre glissante. Une box qui redescend après
//  un gros import le montre en une heure.
//
//  ---------------------------------------------------------
//  RIEN SUR CE QUE LE CLIENT REGARDE
//  ---------------------------------------------------------
//  Des mégaoctets et des pourcents de NOTRE processus. Aucun nom de
//  chaîne, aucune adresse. C'est ce qui rend ce paquet envoyable.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Un relevé : quand, combien de Mo, quel pourcentage de CPU (null quand
/// le CPU ne se lit pas — Windows, ou premier relevé sans référence).
class EchantillonRessources {
  const EchantillonRessources({
    required this.a,
    required this.memMo,
    this.cpuPct,
  });

  final DateTime a;
  final int memMo;
  final int? cpuPct;
}

/// Ticks CPU (utime + stime) d'une ligne `/proc/self/stat`. Pure.
///
/// Le nom du processus (champ 2) est entre parenthèses et peut contenir
/// des espaces : on repart de la DERNIÈRE parenthèse fermante, jamais
/// d'un `split` naïf sur toute la ligne. Après elle, les champs sont
/// dans l'ordre de proc(5) : état, ppid, … ; utime est le 14e champ de
/// la ligne (index 11 après la parenthèse), stime le 15e (index 12).
int? ticksCpuDepuisStat(String stat) {
  final int fin = stat.lastIndexOf(')');
  if (fin < 0) return null;
  final List<String> champs =
      stat.substring(fin + 1).trim().split(RegExp(r'\s+'));
  if (champs.length < 13) return null;
  final int? utime = int.tryParse(champs[11]);
  final int? stime = int.tryParse(champs[12]);
  if (utime == null || stime == null) return null;
  return utime + stime;
}

/// Pourcentage de l'APPAREIL entier consommé par ce processus entre deux
/// relevés. Pure. `null` si l'intervalle est nul ou les ticks reculent
/// (impossible en théorie, mais on ne renvoie pas un chiffre négatif).
///
/// [ticksParSeconde] : 100 sur Android et sur toutes les distributions
/// Linux courantes (USER_HZ). On ne le lit pas dynamiquement — Dart ne
/// donne pas accès à sysconf — et un appareil qui s'en écarterait
/// donnerait un pourcentage faux d'un facteur connu, pas un plantage.
int? pourcentCpu({
  required int ticksAvant,
  required int ticksApres,
  required Duration ecoule,
  required int coeurs,
  int ticksParSeconde = 100,
}) {
  if (ecoule.inMilliseconds <= 0 || coeurs <= 0 || ticksParSeconde <= 0) {
    return null;
  }
  final int delta = ticksApres - ticksAvant;
  if (delta < 0) return null;
  final double secondesCpu = delta / ticksParSeconde;
  final double secondesMur = ecoule.inMilliseconds / 1000.0;
  final double pct = secondesCpu / secondesMur / coeurs * 100.0;
  return pct.clamp(0.0, 100.0).round();
}

class RessourcesMoniteur {
  RessourcesMoniteur._();
  static final RessourcesMoniteur instance = RessourcesMoniteur._();

  /// Un relevé par minute : assez fin pour voir un pic d'import, assez
  /// rare pour ne rien coûter (deux lectures de fichier).
  static const Duration periode = Duration(minutes: 1);

  /// La fenêtre du « pic sur l'heure ».
  static const Duration fenetre = Duration(hours: 1);

  final List<EchantillonRessources> _releves = <EchantillonRessources>[];
  Timer? _timer;
  int? _ticksPrecedents;
  DateTime? _tempsPrecedent;

  /// Lance les relevés. Idempotent : un deuxième appel ne double pas la
  /// cadence. Le premier relevé part tout de suite (la RAM est connue
  /// dès le premier heartbeat), le CPU attend le deuxième — il lui faut
  /// deux points.
  void demarrer() {
    if (_timer != null) return;
    _relever();
    _timer = Timer.periodic(periode, (_) => _relever());
  }

  void arreter() {
    _timer?.cancel();
    _timer = null;
  }

  int? get memMo => _releves.isEmpty ? null : _releves.last.memMo;

  int? get memPicMo {
    if (_releves.isEmpty) return null;
    int pic = 0;
    for (final EchantillonRessources e in _releves) {
      if (e.memMo > pic) pic = e.memMo;
    }
    return pic;
  }

  int? get cpuPct {
    for (final EchantillonRessources e in _releves.reversed) {
      if (e.cpuPct != null) return e.cpuPct;
    }
    return null;
  }

  int? get cpuPicPct {
    int? pic;
    for (final EchantillonRessources e in _releves) {
      final int? c = e.cpuPct;
      if (c != null && (pic == null || c > pic)) pic = c;
    }
    return pic;
  }

  /// Le paquet du heartbeat. VIDE tant qu'aucun relevé n'existe : un
  /// champ absent, le serveur n'écrase rien ; un `0` inventé, si.
  Map<String, Object?> toJson() {
    final int? mem = memMo;
    if (mem == null) return const <String, Object?>{};
    return <String, Object?>{
      'mem_mb': mem,
      'mem_peak_mb': memPicMo,
      if (cpuPct != null) 'cpu_pct': cpuPct,
      if (cpuPicPct != null) 'cpu_peak_pct': cpuPicPct,
    };
  }

  void _relever() {
    try {
      final int mem = ProcessInfo.currentRss ~/ (1024 * 1024);
      final int? cpu = _cpuMaintenant();
      injecter(EchantillonRessources(a: DateTime.now(), memMo: mem, cpuPct: cpu));
    } on Object {
      // Un moniteur ne fait jamais tomber l'app qu'il observe.
    }
  }

  int? _cpuMaintenant() {
    if (!(Platform.isAndroid || Platform.isLinux)) return null;
    try {
      final int? ticks = ticksCpuDepuisStat(
          File('/proc/self/stat').readAsStringSync());
      final DateTime maintenant = DateTime.now();
      int? pct;
      final int? avant = _ticksPrecedents;
      final DateTime? tAvant = _tempsPrecedent;
      if (ticks != null && avant != null && tAvant != null) {
        pct = pourcentCpu(
          ticksAvant: avant,
          ticksApres: ticks,
          ecoule: maintenant.difference(tAvant),
          coeurs: Platform.numberOfProcessors,
        );
      }
      _ticksPrecedents = ticks;
      _tempsPrecedent = maintenant;
      return pct;
    } on Object {
      return null;
    }
  }

  /// Ajoute un relevé et taille la fenêtre. Visible pour les tests, qui
  /// injectent des relevés datés sans attendre une heure.
  @visibleForTesting
  void injecter(EchantillonRessources e) {
    _releves.add(e);
    final DateTime limite = e.a.subtract(fenetre);
    _releves.removeWhere((EchantillonRessources x) => x.a.isBefore(limite));
  }

  @visibleForTesting
  void reinitialiser() {
    arreter();
    _releves.clear();
    _ticksPrecedents = null;
    _tempsPrecedent = null;
  }
}
