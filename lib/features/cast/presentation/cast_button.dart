// =========================================================
//  cast_button.dart — Bouton cast global réutilisable
// =========================================================
//  Un seul widget à droppr dans la barre du haut de n'importe
//  quel écran. Reflète automatiquement l'état du CastManager :
//
//    - Idle                  → icône "cast" estompée
//    - Scan en cours         → icône qui pulse doucement
//    - Connecté (pas de flux)→ icône "cast_connected" dorée
//    - Casting actif         → icône "cast_connected" dorée + halo
//
//  Au tap :
//    - Aucun device sélectionné → ouvre le picker en mode global
//      (sélection seule, sans flux à envoyer)
//    - Device sélectionné      → ouvre une feuille minimaliste
//      "Déconnecter de <device>"
//
//  C'est exactement le modèle YouTube/Netflix : tu connectes
//  une fois, ensuite tout tap de chaîne part vers la TV.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/cast_manager.dart';
import 'cast_picker_sheet.dart';

class CastButton extends StatelessWidget {
  const CastButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CastManager.instance,
      builder: (BuildContext context, _) {
        final CastManager mgr = CastManager.instance;
        final bool hasTarget = mgr.hasTarget;
        final bool isActive = mgr.isCasting;
        final bool scanning = mgr.state == CastState.discovering;

        final Color color = hasTarget
            ? AppColors.accent
            : AppColors.textSecondary;

        final IconData icon = hasTarget
            ? Icons.cast_connected_rounded
            : Icons.cast_rounded;

        Widget child = Icon(icon, color: color, size: 22);
        if (scanning && !hasTarget) {
          child = _PulseIcon(icon: icon, color: AppColors.accent);
        } else if (isActive) {
          // Petit halo doré quand un flux est réellement en cours
          child = Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.18),
                ),
              ),
              Icon(icon, color: AppColors.accent, size: 22),
            ],
          );
        }

        return IconButton(
          tooltip: hasTarget
              ? 'Cast vers ${mgr.selectedDevice?.name ?? mgr.device?.name ?? "TV"}'
              : 'Cast vers une TV',
          icon: child,
          onPressed: () => _onTap(context, mgr),
        );
      },
    );
  }

  Future<void> _onTap(BuildContext context, CastManager mgr) async {
    if (mgr.hasTarget) {
      // Déjà connecté → on propose le picker pour changer de device
      // ET un bouton "Déconnecter" via le bandeau actif du picker.
      await showCastPickerGlobal(context);
      return;
    }
    await showCastPickerGlobal(context);
  }
}

/// Petite icône qui pulse doucement pendant la découverte SSDP.
/// Donne un retour visuel "ça scanne" sans bloquer l'utilisateur.
class _PulseIcon extends StatefulWidget {
  const _PulseIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_ctrl),
      child: Icon(widget.icon, color: widget.color, size: 22),
    );
  }
}

/// Helper : snackbar discret confirmant que la cible cast est active.
/// Appelé depuis `playChannel` quand un flux part vers la TV.
void showCastRoutedToast(
  BuildContext context, {
  required String deviceName,
  required String channelName,
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.accent,
      duration: const Duration(seconds: 2),
      content: Row(
        children: <Widget>[
          const Icon(Icons.cast_connected_rounded,
              color: Colors.black, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$channelName → $deviceName',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Helper : toast d'erreur si le cast échoue. La lecture retombe
/// automatiquement sur le player local.
void showCastFailedToast(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.live,
      content: Text(
        'Cast impossible — lecture en local. '
        '(${error.toString().replaceFirst("Exception: ", "")})',
        style: AppTextStyles.bodyMedium,
      ),
    ),
  );
}

