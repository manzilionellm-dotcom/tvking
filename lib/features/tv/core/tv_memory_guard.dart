// =========================================================
//  tv_memory_guard.dart — Garde-mémoire GLOBAL de l'app TV (anti-OOM)
// =========================================================
//  Retour terrain : « l'application s'est fermée » (box faible RAM, tuée par
//  le lowmemorykiller Android). Deux protections de fond, installées UNE
//  fois au boot TV :
//
//  1. PLAFOND DU CACHE D'IMAGES FLUTTER. Par défaut Flutter garde jusqu'à
//     1 000 images / 100 Mo décodées en mémoire. Avec des playlists de
//     10 000+ chaînes (logos PNG parfois en 1000×1000), le cache seul
//     pouvait manger 100 Mo sur une box qui en a 1 024 — à côté du lecteur
//     vidéo et de l'UI, c'est l'OOM assuré. On le borne à 260 entrées /
//     48 Mo : largement assez pour tous les logos VISIBLES, et le recyclage
//     LRU fait le reste (un logo évincé se re-décode en ~10 ms au besoin).
//
//  2. RÉPONSE À LA PRESSION MÉMOIRE SYSTÈME. Quand Android prévient qu'il
//     est à court de mémoire (didHaveMemoryPressure — c'est l'ultime
//     avertissement avant que le lowmemorykiller ne tue des process), on
//     PURGE immédiatement le cache d'images : on sacrifie quelques
//     re-décodages pour rester en vie. L'événement est tracé dans la
//     boîte noire (Réglages → Diagnostic, tag « mémoire ») pour qu'on
//     VOIE à distance si une box vit sous pression.
// =========================================================
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';

import '../../player/data/stream_diagnostics.dart';

class TvMemoryGuard with WidgetsBindingObserver {
  TvMemoryGuard._();
  static final TvMemoryGuard instance = TvMemoryGuard._();

  bool _installed = false;

  /// Nombre de purges « pression mémoire » depuis le boot (diagnostic).
  int pressureEvents = 0;

  /// À appeler UNE fois au boot TV, après WidgetsFlutterBinding.
  void install() {
    if (_installed) return;
    _installed = true;
    // 1. Plafond du cache d'images (défaut Flutter : 1000 / 100 Mo — trop
    //    pour une box TV qui doit aussi loger un décodeur vidéo).
    PaintingBinding.instance.imageCache.maximumSize = 260;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20; // 48 Mo
    // 2. Écoute de la pression mémoire système.
    WidgetsBinding.instance.addObserver(this);
    StreamDiagnostics.instance.recordEvent(
        'mémoire', 'Garde-mémoire TV installé (cache images ≤ 48 Mo)');
  }

  @override
  void didHaveMemoryPressure() {
    pressureEvents++;
    // Purge la mémoire la plus vite récupérable : les bitmaps décodés.
    // `clear()` vide les images en cache ; `clearLiveImages()` casse aussi
    // les références « vivantes » pour qu'elles soient re-décodées à la
    // demande plutôt que retenues.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    StreamDiagnostics.instance.recordEvent(
        'mémoire',
        'Pression mémoire système (n°$pressureEvents) → caches images purgés '
        '(anti-fermeture)',
        level: 'warn');
  }
}
