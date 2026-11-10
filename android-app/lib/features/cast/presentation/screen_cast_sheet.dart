// =========================================================
//  screen_cast_sheet.dart — « Caster sur un écran » (même Wi-Fi)
// =========================================================
//  Mode LOCAL : c'est le TÉLÉPHONE qui sert le flux à l'écran (PC / TV)
//  via son navigateur. Avantage clé : ça passe par l'IP résidentielle du
//  téléphone → AUTORISÉE par les fournisseurs IPTV qui bloquent le cloud
//  (erreur 456). Le téléphone et l'écran doivent être sur le MÊME Wi-Fi.
//
//  L'utilisateur ouvre, sur son PC/TV, l'adresse affichée
//  (http://<ip-téléphone>:<port>/screen) → la chaîne démarre. Sur un PC
//  c'est facile (clavier). Le QR sert pour scanner avec un autre tel.
//
//  N'affecte PAS le cast TV (DLNA/Chromecast) existant — c'est un mode
//  en plus, branché sur le serveur local déjà présent.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../profiles/data/active_profile.dart';
import '../../security/data/adult_access.dart';
import '../../tv/core/tv_app_tokens.dart';
import '../data/local_cast_server.dart';

/// Ouvre la feuille « Caster sur un écran » pour `streamUrl`.
Future<void> showScreenCastSheet(
  BuildContext context, {
  required String streamUrl,
  required String title,
  VoidCallback? onActive,
  AdultAccessGrant? adultAccess,
}) {
  if (adultAccess?.isValid == false) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ScreenCastSheet(
      streamUrl: streamUrl,
      title: title,
      onActive: onActive,
      adultAccess: adultAccess,
    ),
  );
}

class ScreenCastSheet extends StatefulWidget {
  const ScreenCastSheet({
    required this.streamUrl,
    required this.title,
    this.onActive,
    this.adultAccess,
    super.key,
  });

  final String streamUrl;
  final String title;
  final AdultAccessGrant? adultAccess;

  /// Appelé quand l'écran est prêt à recevoir (le cast est actif). Le
  /// player s'en sert pour ARRÊTER la lecture du téléphone et libérer la
  /// connexion IPTV (handoff — utile si l'abonnement = 1 connexion).
  final VoidCallback? onActive;

  @override
  State<ScreenCastSheet> createState() => _ScreenCastSheetState();
}

enum _Status { loading, ready, error }

class _ScreenCastSheetState extends State<ScreenCastSheet> {
  _Status _status = _Status.loading;
  String? _localUrl;
  final Object _owner = Object();
  late final int _scope = ActiveProfile.instance.scopeListenable.value;
  bool _closed = false;
  int _generation = 0;

  bool get _allowed =>
      !_closed &&
      ActiveProfile.instance.scopeListenable.value == _scope &&
      (widget.adultAccess?.isValid ?? true);

  @override
  void initState() {
    super.initState();
    ActiveProfile.instance.scopeListenable.addListener(_onAccessChanged);
    widget.adultAccess?.addListener(_onAccessChanged);
    _start();
  }

  void _release() {
    _closed = true;
    ++_generation;
    _localUrl = null;
    LocalCastServer.instance.stopBrowser(owner: _owner);
  }

  void _onAccessChanged() {
    if (_allowed || _closed) return;
    _release();
    _closeRoute();
  }

  void _closeRoute() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route is! PopupRoute || !route.isActive) return;
      final navigator = Navigator.of(context);
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScreenCastSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.adultAccess, widget.adultAccess) &&
        oldWidget.streamUrl == widget.streamUrl &&
        oldWidget.title == widget.title) return;
    oldWidget.adultAccess?.removeListener(_onAccessChanged);
    widget.adultAccess?.addListener(_onAccessChanged);
    _release();
    _closeRoute();
  }

  @override
  void dispose() {
    ActiveProfile.instance.scopeListenable.removeListener(_onAccessChanged);
    widget.adultAccess?.removeListener(_onAccessChanged);
    _release();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_allowed) return;
    final generation = ++_generation;
    final String? url = await LocalCastServer.instance.serveBrowser(
      upstreamUrl: widget.streamUrl,
      title: widget.title,
      owner: _owner,
      isCancelled: () => !mounted || !_allowed || generation != _generation,
    );
    if (!mounted || !_allowed || generation != _generation) return;
    if (url == null) {
      LocalCastServer.instance.stopBrowser(owner: _owner);
      setState(() => _status = _Status.error);
      return;
    }
    setState(() {
      _localUrl = url;
      _status = _Status.ready;
    });
    // Handoff : on prévient le player qu'il peut arrêter de jouer sur le
    // téléphone (libère la connexion IPTV pour l'écran).
    widget.onActive?.call();
  }

  Future<void> _stop() async {
    _release();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    final palette = Theme.of(context).extension<TvAppTokens>();
    final double maxH = MediaQuery.of(context).size.height * 0.9;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color:
                (palette?.bg ?? AppColors.background).withValues(alpha: 0.96),
            border: Border(
                top: BorderSide(color: palette?.line ?? AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.screen_share_rounded,
                          color: palette?.accentBright ?? AppColors.accent,
                          size: 22),
                      const SizedBox(width: 10),
                      Text(context.l10n.screenCastTitle,
                          style: AppTextStyles.headlineMedium),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final palette = Theme.of(context).extension<TvAppTokens>();
    switch (_status) {
      case _Status.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(),
        );
      case _Status.error:
        return Column(
          children: <Widget>[
            Icon(Icons.wifi_off_rounded,
                color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(
              context.l10n.screenCastStartError,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => _status = _Status.loading);
                _start();
              },
              child: Text(context.l10n.buttonRetry),
            ),
          ],
        );
      case _Status.ready:
        final String url = _localUrl!;
        return Column(
          children: <Widget>[
            Text(
              context.l10n.screenCastInstructions,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: palette?.panel ?? AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette?.line ?? AppColors.border),
              ),
              child: SelectableText(
                url,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: palette?.accentBright ?? AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 150,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(context.l10n.screenCastScanHint,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 18),
            Text(
              context.l10n.screenCastKeepOpen,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _stop,
                icon: Icon(Icons.stop_rounded, color: AppColors.live),
                label: Text(context.l10n.castStop,
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.live)),
              ),
            ),
          ],
        );
    }
  }
}
