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
import 'package:native_video_player/native_video_player.dart';

import '../../player/data/stream_diagnostics.dart';

class TvMemoryGuard with WidgetsBindingObserver {
  TvMemoryGuard._();
  static final TvMemoryGuard instance = TvMemoryGuard._();

  bool _installed = false;

  /// Nombre de purges « pression mémoire » depuis le boot (diagnostic).
  int pressureEvents = 0;

  /// MODE « PETITE BOX » (Fire TV Stick, box ≤ ~1,3 Go) : détecté au boot
  /// via le natif. Quand il est vrai, toute l'app s'ALLÈGE d'elle-même :
  /// caches d'images encore plus petits ici, aperçu vidéo plus prudent
  /// (TvLivePreview), accueil sans vidéo héro (logo net à la place) —
  /// premium ET simple, sur n'importe quel Android.
  bool lowSpec = false;

  /// À appeler UNE fois au boot TV, après WidgetsFlutterBinding.
  Future<void> install() async {
    if (_installed) return;
    _installed = true;
    // 1. Plafond du cache d'images (défaut Flutter : 1000 / 100 Mo — trop
    //    pour une box TV qui doit aussi loger un décodeur vidéo).
    PaintingBinding.instance.imageCache.maximumSize = 260;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20; // 48 Mo
    // 2. Écoute de la pression mémoire système.
    WidgetsBinding.instance.addObserver(this);
    // 3. Détection « petite box » (jamais bloquant : timeout 600 ms côté
    //    plugin, valeurs neutres en cas d'échec).
    final ({int totalMem, bool isLowRamDevice}) info =
        await NativeDeviceInfo.query();
    // Seuil ≈ 800 Mo — PARITÉ avec le moteur natif (NativeVideoView.kt).
    // L'ancien seuil (1,3 Go) classait « petite box » les box COURANTES
    // 1-2 Go (elles annoncent souvent ~1,0-1,2 Go utilisables) : sur ces
    // box, l'accueil Lanceur n'affichait JAMAIS sa vidéo héro (logo seul,
    // profil petite-box) — terrain « la vidéo ne vient pas sur le
    // Modèle B ». Le natif a déjà corrigé le même seuil pour ses tampons
    // (« ≤1,2 Go était classé faible RAM → box 1-2 Go courantes ») ; on
    // s'aligne : seules les VRAIES petites box (Fire TV Stick Lite & co,
    // ou isLowRamDevice) gardent le profil léger.
    const int lowSpecThresholdBytes = 800 * 1024 * 1024;
    lowSpec = info.isLowRamDevice ||
        (info.totalMem > 0 && info.totalMem <= lowSpecThresholdBytes);
    if (lowSpec) {
      PaintingBinding.instance.imageCache.maximumSize = 160;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 24 << 20;
    }
    StreamDiagnostics.instance.recordEvent(
        'mémoire',
        lowSpec
            ? 'Garde-mémoire TV : PETITE BOX détectée '
                '(${(info.totalMem / (1 << 30)).toStringAsFixed(1)} Go) → '
                'profil léger (cache ≤ 24 Mo, aperçus prudents)'
            : 'Garde-mémoire TV installé (cache images ≤ 48 Mo)');
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
