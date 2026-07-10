// =========================================================
//  import_progress_screen.dart — Écran d'import VIVANT (téléphone)
// =========================================================
//  TERRAIN (2026-07-10) : à l'ajout d'une liste, l'ancien bouton se
//  contentait d'un mini-spinner « Vérification… ». Sur une grosse
//  source, l'app paraissait FIGÉE → le client croit que ça plante et
//  quitte. Ici, un plein-écran premium qui BOUGE en permanence :
//
//    • un halo qui pulse (jamais figé) ;
//    • la phase en clair (Connexion → Téléchargement → Analyse → …) ;
//    • une barre déterminée quand le serveur annonce la taille, sinon
//      une barre animée + les octets reçus ;
//    • un COMPTEUR de chaînes qui grimpe en direct (dopamine) ;
//    • un chrono mm:ss + des messages rassurants qui tournent.
//
//  Piloté par les ImportProgress émis par PlaylistRepository. Générique
//  sur le type de résultat (Playlist) → réutilisable. Pendant l'import,
//  le retour arrière est bloqué (on ne laisse pas une source à moitié
//  importée). Style Maison Noir : fond mat + accent or.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/import_progress.dart';

/// Résultat d'un import mené par [ImportProgressScreen].
class ImportOutcome<T> {
  const ImportOutcome.success(this.value)
      : error = null,
        ok = true;
  const ImportOutcome.failure(this.error)
      : value = null,
        ok = false;

  final T? value;
  final Object? error;
  final bool ok;
}

/// Lance [task] en affichant un plein-écran d'import animé, et renvoie
/// son résultat (succès + valeur, ou échec + erreur). [task] reçoit le
/// rappel de progression à passer au dépôt.
Future<ImportOutcome<T>> runImportWithProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(ImportProgressCallback onProgress) task,
  double scale = 1.0,
}) async {
  final ImportOutcome<T>? outcome =
      await Navigator.of(context).push<ImportOutcome<T>>(
    PageRouteBuilder<ImportOutcome<T>>(
      opaque: true,
      barrierColor: AppColors.background,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          ImportProgressScreen<T>(title: title, task: task, scale: scale),
      transitionsBuilder: (_, Animation<double> anim, __, Widget child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
  // Route fermée par un imprévu (rare) → considéré comme un échec neutre.
  return outcome ?? ImportOutcome<T>.failure(null);
}

class ImportProgressScreen<T> extends StatefulWidget {
  const ImportProgressScreen({
    super.key,
    required this.title,
    required this.task,
    this.scale = 1.0,
  });

  final String title;
  final Future<T> Function(ImportProgressCallback onProgress) task;

  /// Facteur d'échelle (téléphone = 1.0 ; TV 10-foot ≈ 1.6).
  final double scale;

  @override
  State<ImportProgressScreen<T>> createState() =>
      _ImportProgressScreenState<T>();
}

class _ImportProgressScreenState<T> extends State<ImportProgressScreen<T>>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<ImportProgress> _progress =
      ValueNotifier<ImportProgress>(
    const ImportProgress(phase: ImportPhase.connecting),
  );
  late final AnimationController _pulse;
  Timer? _clock;
  Duration _elapsed = Duration.zero;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final T result = await widget.task((ImportProgress p) {
        if (mounted && !_finished) _progress.value = p;
      });
      _finished = true;
      _progress.value = _progress.value.copyWith(phase: ImportPhase.done);
      // Petit temps de « victoire » : le client voit le total prêt.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        Navigator.of(context).pop(ImportOutcome<T>.success(result));
      }
    } catch (e) {
      _finished = true;
      if (mounted) Navigator.of(context).pop(ImportOutcome<T>.failure(e));
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On BLOQUE le retour tant que l'import n'est pas fini : pas de
      // source importée à moitié.
      canPop: _finished,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420 * widget.scale),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ValueListenableBuilder<ImportProgress>(
                  valueListenable: _progress,
                  builder: (BuildContext context, ImportProgress p, _) =>
                      _content(p),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _s => widget.scale;

  Widget _content(ImportProgress p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _orb(p),
        SizedBox(height: 34 * _s),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textTertiary,
            fontSize: 11 * _s,
            letterSpacing: 2,
          ),
        ),
        SizedBox(height: 8 * _s),
        Text(
          _phaseTitle(p.phase),
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLarge.copyWith(fontSize: 23 * _s),
        ),
        SizedBox(height: 22 * _s),
        _bar(p),
        SizedBox(height: 14 * _s),
        _counter(p),
        SizedBox(height: 22 * _s),
        Text(
          _reassurance(p),
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 13 * _s,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 10 * _s),
        Text(
          _fmtDuration(_elapsed),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13 * _s,
            letterSpacing: 1.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  /// Halo pulsant + icône de phase — le mouvement qui « rassure ».
  Widget _orb(ImportProgress p) {
    final bool done = p.phase == ImportPhase.done;
    return SizedBox(
      height: 132 * _s,
      width: 132 * _s,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, Widget? child) {
          final double t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: (96 + t * 34) * _s,
                height: (96 + t * 34) * _s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done ? AppColors.success : AppColors.royalGold)
                      .withValues(alpha: 0.10 * (1 - t)),
                ),
              ),
              Container(
                width: 96 * _s,
                height: 96 * _s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceHigh,
                  border: Border.all(
                    color: (done ? AppColors.success : AppColors.royalGold)
                        .withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: child,
              ),
            ],
          );
        },
        child: Icon(
          done ? Icons.check_rounded : _phaseIcon(p.phase),
          color: done ? AppColors.success : AppColors.royalGold,
          size: 40 * _s,
        ),
      ),
    );
  }

  /// Barre de progression : déterminée si on connaît la fraction, sinon
  /// animée (indéterminée) — jamais figée.
  Widget _bar(ImportProgress p) {
    final double? value = _displayValue(p);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8 * _s,
        backgroundColor: AppColors.surfaceHigh,
        valueColor: AlwaysStoppedAnimation<Color>(
          p.phase == ImportPhase.done
              ? AppColors.success
              : AppColors.royalGold,
        ),
      ),
    );
  }

  /// Compteur VIVANT : chaînes trouvées (grimpe en douceur) ou octets
  /// reçus quand le téléchargement n'annonce pas de total.
  Widget _counter(ImportProgress p) {
    if (p.channelsFound > 0) {
      return TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        tween: Tween<double>(begin: 0, end: p.channelsFound.toDouble()),
        builder: (BuildContext context, double v, _) => Text.rich(
          TextSpan(children: <InlineSpan>[
            TextSpan(
              text: _fmtInt(v.round()),
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 30 * _s,
                color: AppColors.royalGold,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: '  chaînes trouvées',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 14 * _s,
                color: AppColors.textSecondary,
              ),
            ),
          ]),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (p.phase == ImportPhase.downloading && p.bytesReceived > 0) {
      final String got = _fmtBytes(p.bytesReceived);
      final int? total = p.totalBytes;
      return Text(
        total != null ? '$got / ${_fmtBytes(total)}' : '$got reçus',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyLarge.copyWith(
          fontFamily: 'monospace',
          fontSize: 16 * _s,
          color: AppColors.royalGold,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return const SizedBox(height: 4);
  }

  // ---------- valeurs & libellés ----------

  double? _displayValue(ImportProgress p) {
    switch (p.phase) {
      case ImportPhase.connecting:
        return null; // indéterminée
      case ImportPhase.downloading:
        return p.downloadFraction; // fraction réelle, ou null → animée
      case ImportPhase.analyzing:
        return null; // total inconnu → animée + compteur
      case ImportPhase.saving:
        return 0.97;
      case ImportPhase.done:
        return 1.0;
      case ImportPhase.failed:
        return null;
    }
  }

  String _phaseTitle(ImportPhase phase) {
    switch (phase) {
      case ImportPhase.connecting:
        return 'Connexion au serveur…';
      case ImportPhase.downloading:
        return 'Téléchargement de ta liste…';
      case ImportPhase.analyzing:
        return 'Analyse des chaînes…';
      case ImportPhase.saving:
        return 'Presque prêt…';
      case ImportPhase.done:
        return 'C\'est prêt ✨';
      case ImportPhase.failed:
        return 'Échec de l\'import';
    }
  }

  IconData _phaseIcon(ImportPhase phase) {
    switch (phase) {
      case ImportPhase.connecting:
        return Icons.wifi_tethering_rounded;
      case ImportPhase.downloading:
        return Icons.cloud_download_rounded;
      case ImportPhase.analyzing:
        return Icons.playlist_add_check_rounded;
      case ImportPhase.saving:
        return Icons.save_rounded;
      case ImportPhase.done:
        return Icons.check_rounded;
      case ImportPhase.failed:
        return Icons.error_outline_rounded;
    }
  }

  /// Micro-copie qui TOURNE selon le temps écoulé → l'utilisateur sent
  /// que ça vit même quand une étape dure.
  String _reassurance(ImportProgress p) {
    if (p.phase == ImportPhase.done) {
      return 'Tes chaînes sont chargées. Bon visionnage !';
    }
    const List<String> lines = <String>[
      'On récupère tout ton bouquet, garde l\'app ouverte…',
      'Les grosses listes prennent quelques secondes de plus.',
      'On range tes chaînes pour un zapping instantané.',
      'Presque fini — on optimise le démarrage.',
    ];
    final int i = (_elapsed.inSeconds ~/ 4) % lines.length;
    return lines[i];
  }

  // ---------- formats ----------

  String _fmtDuration(Duration d) {
    final String m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtInt(int n) {
    // Séparateur de milliers « espace » (format FR), sans dépendance intl.
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
      out.write(s[i]);
    }
    return out.toString();
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
