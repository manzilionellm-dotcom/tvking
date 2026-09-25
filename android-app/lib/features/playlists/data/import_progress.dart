// =========================================================
//  import_progress.dart — Progression d'un import de liste (M3U / Xtream)
// =========================================================
//  Demande du propriétaire (25/09/2026) : pendant « Connexion… », le client
//  doit VOIR que ça avance (octets reçus, chaînes trouvées, chaînes
//  enregistrées) au lieu d'un bouton figé qui fait croire à un plantage.
//
//  Un seul bus, ultra simple : un ValueNotifier que les couches données
//  (téléchargement, décodage, insertion) mettent à jour, et que l'écran
//  d'ajout écoute pour changer le TEXTE de son bouton. Aucun élément visuel
//  nouveau : seul le libellé change. Les mises à jour sont LIMITÉES (≥ 120 ms
//  d'écart) pour ne pas reconstruire le bouton à chaque paquet réseau.
// =========================================================
import 'package:flutter/foundation.dart';

/// Une étape de l'import, avec ce qu'on peut chiffrer.
class ImportProgress {
  const ImportProgress(this.label);

  /// Texte prêt à afficher (ex. « Connexion… 12 400 chaînes trouvées »).
  final String label;

  @override
  String toString() => label;
}

abstract final class ImportProgressBus {
  /// Étape courante, `null` = aucun import en cours.
  static final ValueNotifier<ImportProgress?> current =
      ValueNotifier<ImportProgress?>(null);

  static DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kMinGap = Duration(milliseconds: 120);

  /// Publie une étape. [force] = publier même si la précédente est récente
  /// (début / fin d'étape, pour ne jamais rater un jalon).
  static void set(String label, {bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastEmit) < _kMinGap) return;
    _lastEmit = now;
    current.value = ImportProgress(label);
  }

  static void clear() {
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    current.value = null;
  }

  // ---- Raccourcis lisibles (un seul endroit pour les formulations) ----

  static String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// « 12 400 » (séparateur de milliers, lisible à 3 m).
  static String n(int v) {
    final String s = v.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  static void connecting() => set('Connexion au serveur…', force: true);
  static void categories() => set('Lecture des catégories…', force: true);
  static void downloading(int bytes) => set('Téléchargement… ${mb(bytes)} Mo');
  static void decoding(int bytes) =>
      set('Analyse de ${mb(bytes)} Mo…', force: true);
  static void category(int i, int total, int found) =>
      set('Catégorie $i/$total · ${n(found)} chaînes trouvées');
  static void found(int count) =>
      set('${n(count)} chaînes trouvées', force: true);
  static void saving(int done, int total) =>
      set('Enregistrement ${n(done)} / ${n(total)} chaînes', force: done >= total);
  static void done(int count) =>
      set('${n(count)} chaînes prêtes', force: true);
}
