// =========================================================
//  sync_source_button.dart — Le bouton « Synchroniser »
// =========================================================
//  Le geste que le client réclamait sur téléphone : un seul appui, et
//  l'app reflète EXACTEMENT ce que le revendeur a dans son panel.
//  Le moteur est dans `data/source_sync.dart` ; ici, il n'y a que la
//  mise en scène — mais elle compte :
//
//    • pendant la synchro, l'icône TOURNE et l'appui est ignoré : sur
//      une source de 40 000 chaînes, ça prend du temps, et sans signe
//      visible le client appuie six fois de suite ;
//    • à la fin, on ne dit pas « terminé » — on dit CE QUI A CHANGÉ :
//      « 12 chaînes ajoutées, 340 retirées ». C'est la seule preuve
//      que le bouton a servi à quelque chose ;
//    • si toutes les sources ont échoué, on le dit franchement au lieu
//      d'afficher un « à jour » mensonger.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/source_sync.dart';

/// Bouton d'en-tête. À poser dans les `actions` d'un AppBar ou dans une
/// Row d'en-tête maison — il se débrouille avec la taille d'une icône.
class SyncSourceButton extends StatefulWidget {
  const SyncSourceButton({super.key});

  @override
  State<SyncSourceButton> createState() => _SyncSourceButtonState();
}

class _SyncSourceButtonState extends State<SyncSourceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _busy = false;
  SyncPhase _phase = SyncPhase.source;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _phase = SyncPhase.source;
    });
    _spin.repeat();
    final SyncReport report = await SourceSync.run(
      onPhase: (SyncPhase p) {
        if (mounted) setState(() => _phase = p);
      },
    );
    _spin.stop();
    _spin.reset();
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(report);
  }

  void _showResult(SyncReport r) {
    final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: <Widget>[
            Icon(
              r.allFailed
                  ? Icons.cloud_off_rounded
                  : (r.unchanged
                      ? Icons.check_circle_outline_rounded
                      : Icons.sync_alt_rounded),
              color: r.allFailed ? AppColors.warning : AppColors.accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                syncResultText(r),
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(SyncPhase p) {
    switch (p) {
      case SyncPhase.source:
        return 'Vérification de ta source…';
      case SyncPhase.channels:
        return 'Mise à jour des chaînes…';
      case SyncPhase.cinema:
        return 'Films et séries…';
      case SyncPhase.done:
        return 'Presque fini…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      // Le libellé de l'étape passe dans l'info-bulle : sur un appui
      // long, le client sait où on en est sans qu'on lui vole l'écran
      // avec une boîte de dialogue.
      tooltip: _busy ? _phaseLabel(_phase) : 'Synchroniser ma source',
      onPressed: _busy ? null : _go,
      icon: RotationTransition(
        turns: _spin,
        child: Icon(
          Icons.sync_rounded,
          color: _busy ? AppColors.accent : null,
        ),
      ),
    );
  }
}
