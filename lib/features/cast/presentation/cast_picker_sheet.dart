// =========================================================
//  cast_picker_sheet.dart — Sheet de sélection (refonte v2)
// =========================================================
//  Améliorations vs v1 :
//    - Layout en colonne avec Flexible → la liste scrolle si
//      elle dépasse, plus de RenderFlex overflow.
//    - Hauteur max = 80% de l'écran.
//    - Bandeau en haut "Casting vers <device>" + bouton
//      "Déconnecter" si une session est active.
//    - L'appareil actuellement connecté est marqué d'un check
//      doré et n'est plus cliquable comme un nouveau target.
//    - Switch propre : si on tap un autre device alors qu'on
//      caste déjà, on disconnect d'abord puis on connecte au
//      nouveau.
//    - Bouton "Arrêter" toujours visible quand session active.
//    - Le bouton "Rechercher à nouveau" relance la discovery.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/cast_manager.dart';
import '../domain/cast_device.dart';

Future<void> showCastPicker(
  BuildContext context, {
  required String streamUrl,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CastPickerSheet(streamUrl: streamUrl, title: title),
  );
}

class CastPickerSheet extends StatefulWidget {
  const CastPickerSheet({
    required this.streamUrl,
    required this.title,
    super.key,
  });

  final String streamUrl;
  final String title;

  @override
  State<CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends State<CastPickerSheet> {
  @override
  void initState() {
    super.initState();
    CastManager.instance.startDiscovery();
  }

  @override
  void dispose() {
    CastManager.instance.stopDiscovery();
    super.dispose();
  }

  Future<void> _castTo(CastDevice device) async {
    final CastManager mgr = CastManager.instance;

    // Si on caste déjà sur un AUTRE device → on coupe propre d'abord
    if (mgr.isCasting && mgr.device?.id != device.id) {
      await mgr.disconnect();
    }

    try {
      await mgr.castTo(
        device,
        streamUrl: widget.streamUrl,
        title: widget.title,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(context, 'Envoi vers ${device.name}', accent: true);
    } on Exception catch (e) {
      if (!mounted) return;
      _toast(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    }
  }

  Future<void> _disconnect() async {
    await CastManager.instance.disconnect();
    if (!mounted) return;
    _toast(context, 'Session de cast arrêtée');
  }

  void _toast(BuildContext context, String message,
      {bool error = false, bool accent = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? AppColors.live
            : accent
                ? AppColors.accent
                : AppColors.surfaceHigh,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(
            color: accent ? Colors.black : Colors.white,
            fontWeight: accent ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.of(context).size.height * 0.8;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: CastManager.instance,
              builder: (BuildContext context, _) {
                final CastManager mgr = CastManager.instance;
                final List<CastDevice> devices = mgr.discoveredDevices;
                final CastDevice? active = mgr.device;
                final bool discovering = mgr.state == CastState.discovering;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // ----- Grabber -----
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ----- Titre + bandeau session -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.cast_rounded,
                                  color: AppColors.accent, size: 22),
                              const SizedBox(width: 10),
                              Text('Envoyer vers...',
                                  style: AppTextStyles.headlineMedium),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  Icons.refresh_rounded,
                                  color: discovering
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                ),
                                tooltip: 'Rafraîchir',
                                onPressed: discovering
                                    ? null
                                    : () => CastManager.instance
                                        .startDiscovery(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            discovering
                                ? 'Recherche sur ton WiFi...'
                                : 'Récepteurs DLNA / UPnP détectés.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          if (active != null) ...<Widget>[
                            const SizedBox(height: 14),
                            _ActiveSessionBanner(
                              device: active,
                              onDisconnect: _disconnect,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ----- Liste devices (scroll si besoin) -----
                    Flexible(
                      child: devices.isEmpty
                          ? _empty(discovering)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 0, 20, 12),
                              physics: const BouncingScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: devices.length,
                              separatorBuilder:
                                  (BuildContext _, int __) =>
                                      const SizedBox(height: 8),
                              itemBuilder: (BuildContext context,
                                  int index) {
                                final CastDevice d = devices[index];
                                final bool isActive =
                                    active?.id == d.id;
                                return _DeviceTile(
                                  device: d,
                                  isActive: isActive,
                                  onTap: () => _castTo(d),
                                );
                              },
                            ),
                    ),

                    // ----- Aide en bas -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: _help(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(bool searching) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            if (searching)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.tv_off_rounded,
                  size: 20, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                searching
                    ? 'Recherche en cours...'
                    : 'Aucun récepteur. Vérifie que ton TV est sur le même WiFi et que DLNA est activé.',
                style: AppTextStyles.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _help() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fire TV : installe "AirReceiver" pour activer DLNA. '
              'Smart TV : active "Partage réseau" ou "DLNA" dans ses paramètres.',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  Tile d'un device
// ============================================================

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.onTap,
  });

  final CastDevice device;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isActive ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accentSurface
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.accent : AppColors.border,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.accent
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.tv_rounded,
                  color: isActive ? Colors.black : AppColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.manufacturer ?? "DLNA"} · ${device.host}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_rounded,
                          color: Colors.black, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'EN COURS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.black,
                          fontSize: 9,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.cast_connected_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Bandeau "Session active" (avec bouton Arrêter)
// ============================================================

class _ActiveSessionBanner extends StatelessWidget {
  const _ActiveSessionBanner({
    required this.device,
    required this.onDisconnect,
  });

  final CastDevice device;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.cast_connected_rounded,
            color: AppColors.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Cast en cours sur',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.accent,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  device.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.live,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('Arrêter'),
          ),
        ],
      ),
    );
  }
}
