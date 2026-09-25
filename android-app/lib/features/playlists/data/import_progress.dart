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

/// Nature de l'étape en cours (la couche données ne connaît PAS la langue de
/// l'utilisateur : elle publie des FAITS, l'écran les met en mots via l10n).
enum ImportStage {
  /// Connexion au serveur (aucun chiffre).
  connecting,

  /// Lecture des catégories Xtream (aucun chiffre).
  categories,

  /// Téléchargement en cours : [ImportProgress.bytes] reçus.
  downloading,

  /// Décodage / analyse du contenu : [ImportProgress.bytes] à traiter.
  decoding,

  /// Import par catégorie : [ImportProgress.index] / [ImportProgress.total],
  /// [ImportProgress.count] chaînes déjà trouvées.
  category,

  /// [ImportProgress.count] chaînes trouvées (fin de décodage).
  found,

  /// Enregistrement : [ImportProgress.index] / [ImportProgress.total] chaînes.
  saving,

  /// Terminé : [ImportProgress.count] chaînes prêtes.
  done,
}

/// Une étape de l'import, avec ce qu'on peut chiffrer.
class ImportProgress {
  const ImportProgress(
    this.stage, {
    this.bytes = 0,
    this.index = 0,
    this.total = 0,
    this.count = 0,
  });

  final ImportStage stage;

  /// Octets reçus / à analyser (étapes [ImportStage.downloading] et
  /// [ImportStage.decoding]).
  final int bytes;

  /// Position courante (catégorie ou chaîne enregistrée) et total.
  final int index;
  final int total;

  /// Nombre de chaînes trouvées / prêtes.
  final int count;

  /// « 12.4 » (Mo, 1 décimale) — pour l'affichage.
  String get mb => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  String toString() =>
      'ImportProgress(${stage.name} bytes=$bytes $index/$total count=$count)';
}

abstract final class ImportProgressBus {
  /// Étape courante, `null` = aucun import en cours.
  static final ValueNotifier<ImportProgress?> current =
      ValueNotifier<ImportProgress?>(null);

  static DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kMinGap = Duration(milliseconds: 120);

  /// Publie une étape. [force] = publier même si la précédente est récente
  /// (début / fin d'étape, pour ne jamais rater un jalon).
  static void set(ImportProgress p, {bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastEmit) < _kMinGap) return;
    _lastEmit = now;
    current.value = p;
  }

  static void clear() {
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    current.value = null;
  }

  /// « 12 400 » (séparateur de milliers, lisible à 3 m). Utilisé par les
  /// écrans pour formater les nombres, quelle que soit la langue.
  static String n(int v) {
    final String s = v.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  // ---- Raccourcis lisibles (un seul endroit pour les jalons) ----

  static void connecting() =>
      set(const ImportProgress(ImportStage.connecting), force: true);
  static void categories() =>
      set(const ImportProgress(ImportStage.categories), force: true);
  static void downloading(int bytes) =>
      set(ImportProgress(ImportStage.downloading, bytes: bytes));
  static void decoding(int bytes) =>
      set(ImportProgress(ImportStage.decoding, bytes: bytes), force: true);
  static void category(int i, int total, int found) => set(ImportProgress(
      ImportStage.category, index: i, total: total, count: found));
  static void found(int count) =>
      set(ImportProgress(ImportStage.found, count: count), force: true);
  static void saving(int done, int total) => set(
      ImportProgress(ImportStage.saving, index: done, total: total),
      force: done >= total);
  static void done(int count) =>
      set(ImportProgress(ImportStage.done, count: count), force: true);
}
