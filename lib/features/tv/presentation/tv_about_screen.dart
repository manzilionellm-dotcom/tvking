// =========================================================
//  tv_about_screen.dart — Écran « À propos » (TV)
// =========================================================
//  Écran de CONFORT et de SUPPORT, 100 % isolé :
//    • Affiche la VERSION de l'app (utile au support : « quelle version
//      as-tu ? »), le numéro de build, la version Android et la MÉMOIRE
//      de l'appareil (rassurant + diagnostic).
//    • Bouton « Vider le cache » : libère la mémoire des IMAGES décodées
//      (logos/affiches) — un vrai gain de RAM sur une box limitée.
//
//  RÈGLE DE STABILITÉ : ce fichier ne touche NI au lecteur vidéo, NI au
//  rendu de l'image, NI au décodage/mémoire du player. Il ne fait que lire
//  des infos (package_info + DeviceMemory) et vider le cache d'images
//  Flutter (opération sûre et documentée). Aucune dépendance native ajoutée.
// =========================================================
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app/device_memory.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_diagnostics_screen.dart';

class TvAboutScreen extends StatefulWidget {
  const TvAboutScreen({super.key});

  @override
  State<TvAboutScreen> createState() => _TvAboutScreenState();
}

class _TvAboutScreenState extends State<TvAboutScreen> {
  PackageInfo? _info;
  String _cacheStatus = '';

  @override
  void initState() {
    super.initState();
    // Lecture asynchrone de la version (n'empêche jamais l'affichage).
    PackageInfo.fromPlatform().then((PackageInfo i) {
      if (mounted) setState(() => _info = i);
    });
  }

  // Vide le cache d'IMAGES décodées gardé en RAM par Flutter (logos, affiches).
  // C'est un gain de mémoire immédiat et SANS risque : les images seront
  // simplement re-décodées à la demande. On ne touche à rien d'autre.
  void _clearCache() {
    final ImageCache cache = PaintingBinding.instance.imageCache;
    final int freed = cache.currentSizeBytes;
    cache.clear();
    cache.clearLiveImages();
    setState(() {
      _cacheStatus =
          'Cache image vidé ✓  (${(freed / (1024 * 1024)).toStringAsFixed(1)} Mo libérés)';
    });
  }

  String get _ramLabel {
    if (!DeviceMemory.isLoaded || DeviceMemory.totalMb <= 0) {
      return 'inconnue';
    }
    final double gb = DeviceMemory.totalMb / 1024;
    final String tier = DeviceMemory.lowRam ? ' (faible)' : '';
    return '${gb.toStringAsFixed(1)} Go$tier';
  }

  @override
  Widget build(BuildContext context) {
    final String version = _info == null
        ? '…'
        : '${_info!.version} (build ${_info!.buildNumber})';
    final String appName = _info?.appName ?? 'The Few';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'À propos',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: TvTokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              appName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: TvTokens.gold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // ----- Bloc d'informations (lecture seule) -----
            Container(
              width: 760,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              decoration: BoxDecoration(
                color: TvTokens.card,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                border: Border.all(color: TvTokens.lineSoft),
              ),
              child: Column(
                children: <Widget>[
                  // Version FOCUSABLE : la sélectionner ouvre la boîte
                  // noire (équivalent D-pad de l'appui long sur la
                  // version côté mobile — accès support, semi-caché).
                  TvFocusBuilder(
                    scale: TvFocusScale.small,
                    onSelect: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TvDiagnosticsScreen(),
                      ),
                    ),
                    builder: (BuildContext context, bool focused) => Container(
                      decoration: BoxDecoration(
                        color: focused ? TvTokens.sel : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                focused ? TvTokens.gold : Colors.transparent),
                      ),
                      child: _InfoRow(label: 'Version', value: version),
                    ),
                  ),
                  _InfoRow(
                      label: 'Système', value: Platform.operatingSystemVersion),
                  _InfoRow(label: 'Mémoire (RAM)', value: _ramLabel),
                  _InfoRow(
                      label: 'Capacité chaînes',
                      value: '${DeviceMemory.channelCap} max',
                      last: true),
                ],
              ),
            ),
            const SizedBox(height: 22),
            // ----- Bouton « Vider le cache » -----
            TvFocusBuilder(
              scale: TvFocusScale.large,
              onSelect: _clearCache,
              builder: (BuildContext context, bool focused) {
                final Color bg = focused ? TvTokens.gold : TvTokens.sel;
                final Color fg =
                    focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
                return Container(
                  width: 760,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.cleaning_services_rounded, color: fg, size: 26),
                      const SizedBox(width: 12),
                      Text(
                        'Vider le cache (libère de la mémoire)',
                        style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (_cacheStatus.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _cacheStatus,
                style: const TextStyle(
                  fontSize: 15,
                  color: TvTokens.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ligne d'information (libellé à gauche, valeur à droite).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: TvTokens.lineSoft)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: TvTokens.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                color: TvTokens.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
