// =========================================================
//  tv_import_progress.dart — L'import qui RASSURE (jamais un spinner muet)
// =========================================================
//  Ajouter sa liste est LE moment de vérité : si l'écran semble gelé,
//  le client débranche la box. Ici, l'attente devient un récit :
//
//    « Connexion… » → « ✓ Ta liste est bonne » →
//    « Téléchargement des chaînes… 4 231 chaînes ajoutées · Sport… » →
//    « ✓ 8 412 chaînes prêtes · 143 catégories ».
//
//  Deux pièces :
//    • TvImportProgress (ChangeNotifier) — l'état : étapes finies, étape
//      en cours, compteur de chaînes, catégorie, message de patience
//      après 15 s. Les mises à jour du compteur sont THROTTLÉES (≤ 4
//      rafraîchissements/s) : une grosse liste insère des dizaines de
//      lots par seconde et une box 1 Go n'a pas à repeindre autant.
//    • TvImportProgressView — l'affichage (liste d'étapes ✓, gros
//      compteur vivant, catégorie en cours, patience).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../playlists/data/import_progress.dart';
import '../core/tv_tokens.dart';

class TvImportProgress extends ChangeNotifier {
  /// Étapes TERMINÉES (affichées avec ✓).
  final List<String> done = <String>[];

  /// Étape EN COURS (null = rien ne tourne).
  String? current;

  /// Compteur de chaînes insérées (0 = pas encore commencé).
  int channels = 0;

  /// Catégorie en cours d'import (« Sport »…), si le serveur la donne.
  String? category;

  /// Catégories distinctes vues pendant l'import (pour le récap final).
  final Set<String> categoriesSeen = <String>{};

  /// Message doux après ~15 s sur la même étape (grosse liste).
  bool patience = false;

  Timer? _patienceTimer;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  /// ≤ 4 rafraîchissements/s (même esprit que le throttling des
  /// téléchargements VOD) : le compteur reste vivant sans saturer l'UI.
  static const Duration _paintEvery = Duration(milliseconds: 250);
  static const Duration _patienceAfter = Duration(seconds: 15);

  bool get running => current != null;

  /// Démarre une étape (« Connexion… », « Téléchargement des chaînes… »).
  void startStage(String label) {
    current = label;
    patience = false;
    _armPatience();
    _paint(force: true);
  }

  /// Termine l'étape en cours en l'affichant ✓ sous [doneLabel]
  /// (ex. « ✓ Ta liste est bonne »).
  void completeStage(String doneLabel) {
    done.add(doneLabel);
    current = null;
    patience = false;
    _patienceTimer?.cancel();
    _paint(force: true);
  }

  /// À brancher sur le `onProgress` TYPÉ du repository (fusion
  /// 2026-07-10 : l'API canonique est ImportProgressCallback — phases,
  /// octets, compteur, catégorie).
  void onImportProgress(ImportProgress p) =>
      onChannels(p.channelsFound, p.categoryName);

  /// Variante brute (compteur + catégorie).
  void onChannels(int total, String? categoryName) {
    channels = total;
    if (categoryName != null && categoryName.isNotEmpty) {
      category = categoryName;
      categoriesSeen.add(categoryName);
    }
    // Le compteur bouge = l'import VIT : on repousse le message de
    // patience (il ne vise que les VRAIS silences).
    _armPatience();
    _paint();
  }

  /// Remet tout à zéro (nouvelle tentative après erreur/annulation).
  void reset() {
    done.clear();
    current = null;
    channels = 0;
    category = null;
    categoriesSeen.clear();
    patience = false;
    _patienceTimer?.cancel();
    _paint(force: true);
  }

  void _armPatience() {
    _patienceTimer?.cancel();
    _patienceTimer = Timer(_patienceAfter, () {
      patience = true;
      _paint(force: true);
    });
  }

  void _paint({bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastPaint) < _paintEvery) return;
    _lastPaint = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _patienceTimer?.cancel();
    super.dispose();
  }
}

/// Formatte 8412 → « 8 412 » (espace fine insécable, lisible de loin).
String tvFormatCount(int n) {
  final String s = n.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
    out.write(s[i]);
  }
  return out.toString();
}

class TvImportProgressView extends StatelessWidget {
  const TvImportProgressView({super.key, required this.progress});
  final TvImportProgress progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (BuildContext context, _) {
        final TvImportProgress p = progress;
        if (p.done.isEmpty && !p.running) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Étapes déjà FRANCHIES : des ✓ qui restent visibles — le
              // client voit le chemin parcouru, pas juste l'instant.
              for (final String d in p.done)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_rounded,
                          size: 18, color: TvTokens.success),
                      const SizedBox(width: 8),
                      Text(d,
                          style: TvTokens.ui(15,
                              weight: FontWeight.w600,
                              color: TvTokens.success)),
                    ],
                  ),
                ),
              if (p.current != null)
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: TvTokens.gold),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.current!,
                          style: TvTokens.ui(16,
                              weight: FontWeight.w600, color: TvTokens.text)),
                    ),
                  ],
                ),
              // Le COMPTEUR VIVANT : la preuve que ça avance.
              if (p.channels > 0) ...<Widget>[
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: <InlineSpan>[
                    TextSpan(
                        text: tvFormatCount(p.channels),
                        style: TvTokens.display(30,
                            weight: FontWeight.w700,
                            color: TvTokens.goldBright)),
                    TextSpan(
                        text: '  chaînes ajoutées…',
                        style: TvTokens.ui(15, color: TvTokens.muted)),
                  ]),
                ),
                if (p.category != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${p.category}…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(14, color: TvTokens.mutedDim)),
                  ),
              ],
              if (p.patience && p.running) ...<Widget>[
                const SizedBox(height: 8),
                Text('Grosse liste — encore un instant, on prépare tout pour toi.',
                    style: TvTokens.ui(14, color: TvTokens.gold)),
              ],
            ],
          ),
        );
      },
    );
  }
}
