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

/// Ouvre le picker en mode "envoyer ce flux maintenant".
/// → Tap sur un device = la TV se met à lire `streamUrl` immédiatement.
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

/// Ouvre le picker en mode "global" (depuis Home, Live, etc.).
/// → Tap sur un device = on mémorise la cible, sans envoyer de flux.
///   Ensuite, dès que l'utilisateur tape sur une chaîne, le flux part
///   automatiquement vers la TV (modèle YouTube/Netflix).
Future<void> showCastPickerGlobal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const CastPickerSheet(),
  );
}

class CastPickerSheet extends StatefulWidget {
  const CastPickerSheet({
    this.streamUrl,
    this.title,
    super.key,
  });

  /// Si `null`, le picker est en mode "global" — il mémorise juste le
  /// device sélectionné sans déclencher de lecture.
  final String? streamUrl;
  final String? title;

  @override
  State<CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends State<CastPickerSheet> {
  @override
  void initState() {
    super.initState();
    // Lance un scan (en gardant la liste chaude pré-warmée) pour ne
    // jamais afficher de "page vide" si le warmup a déjà trouvé du
    // monde. L'utilisateur voit instantanément les devices connus,
    // puis le scan en cours peut en ajouter d'autres.
    CastManager.instance.startDiscovery();
  }

  @override
  void dispose() {
    CastManager.instance.stopDiscovery();
    super.dispose();
  }

  bool get _isGlobalMode => widget.streamUrl == null;

  Future<void> _onDeviceTap(CastDevice device) async {
    final CastManager mgr = CastManager.instance;

    // Chromecast / Google TV : on a maintenant un VRAI bridge SDK
    // natif (cf. GoogleCastTransport). Le tap passe par le flow
    // normal — castTo → SDK ouvre son dialog → user tap sa TV →
    // playback démarre direct, comme Netflix.

    // Mode "global" : on mémorise juste la cible. Pas de flux à
    // envoyer maintenant — playChannel s'en chargera ensuite.
    if (_isGlobalMode) {
      mgr.selectDevice(device);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(
        context,
        'Connecté à ${device.displayName}. Tape une chaîne pour l\'envoyer.',
        accent: true,
      );
      return;
    }

    // Mode "flux maintenant" : si on caste déjà ailleurs → coupe propre
    if (mgr.isCasting && mgr.device?.id != device.id) {
      await mgr.disconnect();
    }

    try {
      await mgr.castTo(
        device,
        streamUrl: widget.streamUrl!,
        title: widget.title ?? 'Lecture',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(context, 'Envoi vers ${device.displayName}', accent: true);
    } on Exception catch (_) {
      if (!mounted) return;
      // Le CastManager a déjà transformé l'exception en message friendly
      // français (via _friendlyMessageFor) et l'expose via `progress`.
      final String friendly = mgr.progress.message.isNotEmpty
          ? mgr.progress.message
          : 'Le cast a échoué. Réessaie.';
      _toast(context, friendly, error: true);
    }
  }

  /// Sous-titre du picker — adaptatif. Au repos = `null` (rien affiché,
  /// pas de jargon protocolaire). Pendant un connect on relaye le
  /// `CastProgress.message` pour montrer le failover en direct.
  String? _statusLine(CastManager mgr, {required bool discovering}) {
    if (mgr.state == CastState.connecting &&
        mgr.progress.message.isNotEmpty) {
      return mgr.progress.message;
    }
    if (discovering) return 'Recherche sur ton WiFi…';
    return null;
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
                // "Actif" = soit en train de caster, soit pré-sélectionné
                // (mode global). Les deux états méritent le marqueur
                // "EN COURS" pour rassurer l'utilisateur que sa cible
                // est bien en place.
                final CastDevice? active =
                    mgr.device ?? mgr.selectedDevice;
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
                                        .startDiscovery(
                                          keepExisting: false,
                                        ),
                              ),
                            ],
                          ),
                          // Sous-titre : affiché UNIQUEMENT pendant un
                          // connect ou une discovery active. Au repos on
                          // ne montre rien — pas de jargon protocolaire
                          // ("DLNA · Roku · navigateur web") qui pollue.
                          if (_statusLine(mgr, discovering: discovering) !=
                              null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              _statusLine(mgr, discovering: discovering)!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 12,
                                color: mgr.state == CastState.connecting
                                    ? AppColors.accent
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
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
                                  onTap: () => _onDeviceTap(d),
                                );
                              },
                            ),
                    ),

                    const SizedBox(height: 8),
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
    final _BrandInfo brand = _brandFor(device);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isActive ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color:
                isActive ? AppColors.accentSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? AppColors.accent : AppColors.border,
              width: isActive ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              // ----- Monogramme de la marque (style télécommande universelle) -----
              //  Une box ronde avec les 2-4 lettres de la marque
              //  (LG, SAM, TCL, SONY...). Plus identifiable visuellement
              //  qu'une icône TV générique + badge protocolaire.
              _BrandMonogram(brand: brand, active: isActive),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.displayName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (brand.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        brand.subtitle!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

/// Box ronde 48×48 contenant les lettres de la marque (LG, SAM, TCL…).
/// Style "télécommande universelle" — l'utilisateur reconnaît
/// visuellement sa TV au lieu de lire "DLNA 192.168.8.4".
class _BrandMonogram extends StatelessWidget {
  const _BrandMonogram({required this.brand, required this.active});

  final _BrandInfo brand;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? AppColors.accent.withValues(alpha: 0.18)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppColors.accent.withValues(alpha: 0.5)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Text(
        brand.monogram,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: brand.monogram.length >= 4 ? 11 : 13,
          fontWeight: FontWeight.w800,
          color: active ? AppColors.accent : AppColors.textPrimary,
          letterSpacing: 1.0,
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
                  device.displayName,
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

// ============================================================
//  Détection de marque — style télécommande universelle
// ============================================================
//  On déduit la marque du device depuis manufacturer / model /
//  name. Le monogramme s'affiche dans la tile (LG, SAM, SONY...).
//  Le sous-titre OS (webOS / Tizen / Android TV) reste discret.
//
//  Pas de logos officiels checkés (poids APK + droits brand),
//  juste de la typo dans une box ronde — minimaliste premium.
// ============================================================

class _BrandInfo {
  const _BrandInfo({required this.monogram, this.subtitle});

  /// 2-4 lettres affichées dans la box ronde.
  final String monogram;

  /// Ligne discrète sous le nom : "LG webOS", "Samsung Tizen",
  /// "Android TV", "Apple TV"… ou `null` si on n'a aucune info.
  final String? subtitle;
}

_BrandInfo _brandFor(CastDevice d) {
  final String haystack =
      '${d.manufacturer ?? ""} ${d.model ?? ""} ${d.name}'
          .toLowerCase();

  bool has(String needle) => haystack.contains(needle);

  // ----- Marques de TV courantes -----
  if (has('lg')) return const _BrandInfo(monogram: 'LG', subtitle: 'LG · webOS');
  if (has('samsung')) {
    return const _BrandInfo(monogram: 'SAM', subtitle: 'Samsung · Tizen');
  }
  if (has('sony') || has('bravia')) {
    return const _BrandInfo(monogram: 'SONY', subtitle: 'Sony · Android TV');
  }
  if (has('tcl')) {
    return const _BrandInfo(monogram: 'TCL', subtitle: 'TCL · Android TV');
  }
  if (has('hisense')) {
    return const _BrandInfo(
        monogram: 'HIS', subtitle: 'Hisense · VIDAA / Android');
  }
  if (has('philips')) {
    return const _BrandInfo(
        monogram: 'PHIL', subtitle: 'Philips · Android TV / SAPHI');
  }
  if (has('vizio')) {
    return const _BrandInfo(monogram: 'VIZ', subtitle: 'Vizio · SmartCast');
  }
  if (has('panasonic')) {
    return const _BrandInfo(monogram: 'PAN', subtitle: 'Panasonic');
  }
  if (has('sharp')) return const _BrandInfo(monogram: 'SHRP', subtitle: 'Sharp');
  if (has('toshiba')) {
    return const _BrandInfo(monogram: 'TOSH', subtitle: 'Toshiba');
  }
  if (has('xiaomi') || has('mi tv') || has('redmi')) {
    return const _BrandInfo(monogram: 'MI', subtitle: 'Xiaomi · Android TV');
  }
  // ----- Boîtiers / dongles -----
  if (has('shield')) {
    return const _BrandInfo(monogram: 'SHLD', subtitle: 'NVIDIA SHIELD');
  }
  if (has('fire') || has('amazon')) {
    return const _BrandInfo(monogram: 'FIRE', subtitle: 'Amazon Fire TV');
  }
  if (has('roku')) {
    return const _BrandInfo(monogram: 'ROKU', subtitle: 'Roku');
  }
  if (has('apple') || has('appletv')) {
    return const _BrandInfo(monogram: 'APPL', subtitle: 'Apple TV');
  }
  if (has('chromecast') || has('google')) {
    return const _BrandInfo(monogram: 'GOOG', subtitle: 'Google · Chromecast');
  }
  // ----- Fallbacks par kind -----
  switch (d.kind) {
    case CastDeviceKind.chromecast:
    case CastDeviceKind.googleCast:
      return const _BrandInfo(monogram: 'CAST', subtitle: 'Google Cast');
    case CastDeviceKind.roku:
      return const _BrandInfo(monogram: 'ROKU', subtitle: 'Roku');
    case CastDeviceKind.webBrowser:
      return const _BrandInfo(monogram: 'WEB', subtitle: 'Navigateur');
    case CastDeviceKind.dlna:
      return const _BrandInfo(monogram: 'TV', subtitle: null);
  }
}
