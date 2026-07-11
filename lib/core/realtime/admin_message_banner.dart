// =========================================================
//  admin_message_banner.dart — Bannière « message admin » temps réel
// =========================================================
//  Affiche le dernier message poussé par le panel via le WebSocket
//  (RealtimeSyncService.lastMessage) : petit bandeau en haut de
//  l'écran, style aligné sur announcement_banner.dart (même famille
//  visuelle : fond teinté + bordure de la couleur de catégorie).
//
//  Comportement :
//    - invisible tant qu'il n'y a rien (SizedBox.shrink → zéro coût) ;
//    - auto-dismiss après `durationSec` (défaut 15 s, borné au parsing) ;
//    - croix de fermeture FOCUSABLE (D-pad TV : atteignable par les
//      flèches, `autofocus: false` → ne vole JAMAIS le focus courant) ;
//    - la fermeture (croix ou auto) remonte au service
//      (`dismissMessage`) pour que toutes les surfaces se vident.
//
//  Couleurs/typo : uniquement AppColors / AppTextStyles (convention
//  AGENTS.md — aucune couleur en dur).
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'realtime_sync_service.dart';

/// Style visuel résolu depuis la catégorie du message (`kind`).
class _KindStyle {
  const _KindStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

_KindStyle _styleFor(String kind) {
  switch (kind) {
    case 'success':
      return const _KindStyle(AppColors.success, Icons.check_circle_rounded);
    case 'warning':
      return const _KindStyle(
          AppColors.warning, Icons.warning_amber_rounded);
    case 'info':
    default:
      return const _KindStyle(AppColors.info, Icons.info_rounded);
  }
}

/// Bannière auto-gérée : écoute [RealtimeSyncService.instance] et
/// s'affiche/se cache toute seule. À poser DANS un Stack au-dessus du
/// home (cf. main.dart `_AppEntry` / tv_app.dart). Ne rend RIEN quand
/// il n'y a pas de message.
class AdminMessageBanner extends StatefulWidget {
  const AdminMessageBanner({super.key});

  @override
  State<AdminMessageBanner> createState() => _AdminMessageBannerState();
}

class _AdminMessageBannerState extends State<AdminMessageBanner> {
  AdminMessage? _visible;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    RealtimeSyncService.instance.addListener(_onServiceChanged);
    _onServiceChanged(); // au cas où un message est déjà en attente
  }

  @override
  void dispose() {
    RealtimeSyncService.instance.removeListener(_onServiceChanged);
    _autoDismiss?.cancel();
    super.dispose();
  }

  /// Le service a changé (nouveau message, ou message effacé ailleurs).
  void _onServiceChanged() {
    final AdminMessage? msg = RealtimeSyncService.instance.lastMessage;
    if (!mounted) return;
    if (msg == null) {
      // Effacé (dismiss depuis une autre surface) → on se cache aussi.
      if (_visible != null) {
        _autoDismiss?.cancel();
        setState(() => _visible = null);
      }
      return;
    }
    // Même message déjà affiché → rien à faire (évite de réarmer le timer).
    if (_visible != null &&
        _visible!.id == msg.id &&
        _visible!.body == msg.body) {
      return;
    }
    setState(() => _visible = msg);
    // Auto-dismiss après la durée demandée par le panel (défaut 15 s).
    _autoDismiss?.cancel();
    _autoDismiss = Timer(Duration(seconds: msg.durationSec), _dismiss);
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    if (mounted && _visible != null) setState(() => _visible = null);
    // Vide aussi le service (idempotent) → cohérent partout.
    RealtimeSyncService.instance.dismissMessage();
  }

  @override
  Widget build(BuildContext context) {
    final AdminMessage? msg = _visible;
    if (msg == null) return const SizedBox.shrink();

    final _KindStyle style = _styleFor(msg.kind);
    final Color color = style.color;

    // Largeur bornée : joli sur téléphone (pleine largeur - marges) comme
    // sur TV/desktop (bandeau centré, pas une banderole d'un bord à l'autre).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        // Material transparent : la bannière vit HORS de tout Scaffold
        // (posée dans un Stack racine) → l'IconButton exige un ancêtre
        // Material, comme dans announcement_banner.dart.
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              // Fond OPAQUE (surface sombre + voile teinté) : la bannière
              // passe au-dessus de n'importe quel écran, il faut qu'elle
              // reste lisible même sur une vidéo.
              color: Color.alphaBlend(
                color.withValues(alpha: 0.16),
                AppColors.voidSurface,
              ),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Icône de catégorie (info / succès / avertissement).
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 12),
                  child: Icon(style.icon, color: color, size: 24),
                ),
                // Titre + corps.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (msg.title.isNotEmpty)
                        Text(
                          msg.title,
                          // Taille prise dans l'échelle AppTextStyles
                          // (règle AGENTS.md n°5 : pas de fontSize magique).
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      if (msg.title.isNotEmpty && msg.body.isNotEmpty)
                        const SizedBox(height: 2),
                      if (msg.body.isNotEmpty)
                        Text(
                          msg.body,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                // Croix de fermeture — focusable (D-pad), sans autofocus.
                IconButton(
                  autofocus: false,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  tooltip:
                      MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  onPressed: _dismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
