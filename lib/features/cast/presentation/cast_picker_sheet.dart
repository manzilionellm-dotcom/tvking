// =========================================================
//  cast_picker_sheet.dart — Sheet de sélection du récepteur
// =========================================================
//  S'ouvre quand l'utilisateur tap le bouton "Cast" du player.
//  Lance une discovery SSDP, liste les MediaRenderers trouvés,
//  envoie le flux au device sélectionné.
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
    // Démarre une découverte fraîche dès l'ouverture du sheet
    CastManager.instance.startDiscovery();
  }

  @override
  void dispose() {
    CastManager.instance.stopDiscovery();
    super.dispose();
  }

  Future<void> _castTo(CastDevice device) async {
    try {
      await CastManager.instance.castTo(
        device,
        streamUrl: widget.streamUrl,
        title: widget.title,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Envoi vers ${device.name}',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.live,
          behavior: SnackBarBehavior.floating,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: CastManager.instance,
              builder: (BuildContext context, _) {
                final CastManager mgr = CastManager.instance;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _grabber(),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          Icon(Icons.cast_rounded,
                              color: AppColors.accent, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Envoyer vers...',
                            style: AppTextStyles.headlineMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Récepteurs DLNA / UPnP détectés sur ton WiFi.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ----- Devices -----
                      if (mgr.discoveredDevices.isEmpty)
                        _searching(mgr.state == CastState.discovering)
                      else
                        ...mgr.discoveredDevices.map(_DeviceTile.new),

                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed:
                                mgr.state == CastState.discovering
                                    ? null
                                    : () => mgr.startDiscovery(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Rechercher à nouveau'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ----- Aide -----
                      _help(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _searching(bool active) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          if (active)
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
              active
                  ? 'Recherche de récepteurs sur ton WiFi...'
                  : 'Aucun récepteur trouvé. Vérifie que ton TV / Fire TV est sur le même WiFi.',
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
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
          color: AppColors.accentCyan.withValues(alpha: 0.2),
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
              'Fire TV : installe d\'abord "AirReceiver" ou "BubbleUPnP" pour activer DLNA. Sur Smart TV, active "Partage réseau" ou "DLNA".',
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.device);
  final CastDevice device;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final _CastPickerSheetState? parent = context
                .findAncestorStateOfType<_CastPickerSheetState>();
            parent?._castTo(device);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.tv_rounded,
                    color: AppColors.accent,
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
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.manufacturer ?? "?"} · ${device.host}',
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
                Icon(
                  Icons.cast_connected_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
