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

import '../../../core/app/build_info.dart' show kBuildLabel;
import '../../../core/app/device_memory.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/update/update_service.dart';
import '../../vod/data/tmdb_meta_service.dart' show kTmdbAttribution;
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

  //  ===== LE NUMÉRO QU'ON LIT DU CANAPÉ (07/09/2026) =====
  //
  //  Demande du propriétaire : « je veux que ça affiche un gros numéro de
  //  la version, on saura si c'est la dernière — si par exemple le client
  //  a mal mis à jour son app ».
  //
  //  Le problème réel qu'il décrit : au téléphone avec un client, on lui
  //  demande sa version. Il lit « 0.3.3 » — et ça ne dit RIEN, parce que
  //  deux builds différents portent le même nom de version. Le numéro qui
  //  identifie vraiment un build, c'est le NUMÉRO DE BUILD, et il était
  //  écrit en petit, entre parenthèses, au milieu d'autres lignes.
  //
  //  Ce bandeau affiche donc le numéro de build EN GRAND, et surtout il
  //  répond à la seule question qui compte pour le support : « est-ce la
  //  dernière ? ». Il interroge le même manifeste que le bouton de mise à
  //  jour, et rend un verdict en clair :
  //     • À JOUR            (vert)   — rien à faire
  //     • PAS À JOUR        (rouge)  — la mise à jour a échoué, on le voit
  //     • VÉRIFICATION IMPOSSIBLE (gris) — réseau KO, on ne conclut PAS
  //
  //  Ce troisième état est important : sans lui, une box hors ligne
  //  afficherait « à jour » et on chercherait le problème ailleurs.
  UpdateCheckResult? _verdict;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    // Lecture asynchrone de la version (n'empêche jamais l'affichage).
    PackageInfo.fromPlatform().then((PackageInfo i) {
      if (mounted) setState(() => _info = i);
    });
    // Verdict « est-ce la dernière ? » — même manifeste que le bouton de
    // mise à jour, donc jamais deux réponses différentes. Best-effort :
    // une erreur réseau donne « vérification impossible », pas un faux
    // « à jour ». Ne bloque jamais l'affichage de l'écran.
    UpdateService.instance.checkDetailed().then((UpdateCheckResult r) {
      if (mounted) {
        setState(() {
          _verdict = r;
          _checking = false;
        });
      }
    }).catchError((Object _) {
      if (mounted) setState(() => _checking = false);
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
      _cacheStatus = context.l10n
          .tvAboutCacheCleared((freed / (1024 * 1024)).toStringAsFixed(1));
    });
  }

  String _ramLabel(BuildContext context) {
    if (!DeviceMemory.isLoaded || DeviceMemory.totalMb <= 0) {
      return context.l10n.tvAboutRamUnknown;
    }
    final double gb = DeviceMemory.totalMb / 1024;
    final String value = context.l10n.tvAboutRamValue(gb.toStringAsFixed(1));
    return DeviceMemory.lowRam
        ? '$value ${context.l10n.tvAboutRamLowTag}'
        : value;
  }

  /// Le bandeau que le support fait lire au client : son numéro de build,
  /// en très grand, et le verdict face au serveur.
  Widget _buildBanner(BuildContext context) {
    //  LE NUMÉRO COURT D'ABORD (07/09) — « on peut pas commencer par le
    //  chiffre 1 ? ». `kBuildLabel` est le compteur du CI : 1, 2, 3… On
    //  l'affiche en grand parce que c'est LUI qu'on dicte au téléphone.
    //  Sans lui (build local, ou APK antérieur à ce correctif), on
    //  retombe sur le numéro technique plutôt que sur une case vide.
    final String build =
        kBuildLabel.isNotEmpty ? kBuildLabel : (_info?.buildNumber ?? '…');
    // Trois états, trois couleurs. Tant qu'on vérifie, on n'affirme rien.
    final Color color;
    final IconData icon;
    final String label;
    if (_checking) {
      color = TvTokens.muted;
      icon = Icons.hourglass_empty_rounded;
      label = context.l10n.tvAboutVersionChecking;
    } else {
      switch (_verdict?.status) {
        case UpdateAvailability.upToDate:
          color = TvTokens.success;
          icon = Icons.verified_rounded;
          label = context.l10n.tvAboutVersionLatest;
        case UpdateAvailability.available:
          color = TvTokens.live;
          icon = Icons.error_outline_rounded;
          label = context.l10n.tvAboutVersionOutdated;
        case UpdateAvailability.unavailable:
        case null:
          color = TvTokens.muted;
          icon = Icons.cloud_off_rounded;
          label = context.l10n.tvAboutVersionUnknown;
      }
    }
    // Le numéro attendu par le serveur, quand on le connaît : c'est LUI
    // que le support compare au numéro affiché sur la box du client. On
    // préfère le numéro COURT s'il est publié, pour comparer deux petits
    // nombres et non deux nombres à dix chiffres.
    final UpdateInfo? remote = _verdict?.info;
    final String? expected = remote == null
        ? null
        : (remote.buildLabel.isNotEmpty
            ? remote.buildLabel
            : '${remote.versionCode}');

    return Container(
      width: 760,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tvAboutVersionBuildLabel.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: TvTokens.mutedDim,
            ),
          ),
          const SizedBox(height: 2),
          // LE NUMÉRO, EN TRÈS GRAND. C'est ce que le client lit au
          // téléphone ; il doit être déchiffrable à trois mètres, d'un
          // seul coup d'œil, sans lunettes.
          Text(
            build,
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: 1,
              color: TvTokens.text,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          // Quand une version plus récente existe, on affiche LE numéro
          // attendu : le support n'a plus à le chercher ailleurs, il
          // compare deux nombres à l'écran.
          if (expected != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              context.l10n.tvAboutVersionExpected(expected),
              style: const TextStyle(fontSize: 16, color: TvTokens.muted),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String version =
        _info == null ? '…' : '${_info!.version} (build ${_info!.buildNumber})';
    final String appName = _info?.appName ?? context.l10n.appName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.aboutTitle,
              style: const TextStyle(
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
            const SizedBox(height: 18),
            // ----- LE GROS NUMÉRO + LE VERDICT (07/09) -----
            _buildBanner(context),
            const SizedBox(height: 18),
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
                      child: _InfoRow(
                          label: context.l10n.tvAboutVersion, value: version),
                    ),
                  ),
                  _InfoRow(
                      label: context.l10n.tvAboutSystem,
                      value: Platform.operatingSystemVersion),
                  _InfoRow(
                      label: context.l10n.tvAboutRamLabel,
                      value: _ramLabel(context)),
                  _InfoRow(
                      label: context.l10n.tvAboutChannelCap,
                      value: context.l10n
                          .tvAboutChannelCapValue(DeviceMemory.channelCap),
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
                      Icon(Icons.cleaning_services_rounded,
                          color: fg, size: 26),
                      const SizedBox(width: 12),
                      Text(
                        context.l10n.tvAboutClearCache,
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
            // MENTIONS DE SOURCES TIERCES — exigées par les conditions
            // d'utilisation de TMDb (usage commercial). Texte officiel,
            // NON traduit : c'est une mention légale.
            const SizedBox(height: 24),
            const Text(
              kTmdbAttribution,
              style: TextStyle(fontSize: 13, color: TvTokens.mutedDim),
            ),
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
