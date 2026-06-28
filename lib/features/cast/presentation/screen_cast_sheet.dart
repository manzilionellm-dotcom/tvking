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

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/local_cast_server.dart';

/// Ouvre la feuille « Caster sur un écran » pour `streamUrl`.
Future<void> showScreenCastSheet(
  BuildContext context, {
  required String streamUrl,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ScreenCastSheet(streamUrl: streamUrl, title: title),
  );
}

class ScreenCastSheet extends StatefulWidget {
  const ScreenCastSheet({
    required this.streamUrl,
    required this.title,
    super.key,
  });

  final String streamUrl;
  final String title;

  @override
  State<ScreenCastSheet> createState() => _ScreenCastSheetState();
}

enum _Status { loading, ready, error }

class _ScreenCastSheetState extends State<ScreenCastSheet> {
  _Status _status = _Status.loading;
  String? _localUrl;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final String? url = await LocalCastServer.instance.serveBrowser(
      upstreamUrl: widget.streamUrl,
      title: widget.title,
    );
    if (!mounted) return;
    if (url == null) {
      setState(() => _status = _Status.error);
      return;
    }
    setState(() {
      _localUrl = url;
      _status = _Status.ready;
    });
  }

  Future<void> _stop() async {
    LocalCastServer.instance.stopBrowser();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.of(context).size.height * 0.9;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: AppColors.border)),
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
                          color: AppColors.accent, size: 22),
                      const SizedBox(width: 10),
                      Text('Caster sur un écran',
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
              'Impossible de démarrer le partage. '
              'Vérifie que le Wi-Fi est activé et réessaie.',
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
              child: const Text('Réessayer'),
            ),
          ],
        );
      case _Status.ready:
        final String url = _localUrl!;
        return Column(
          children: <Widget>[
            Text(
              'Sur ton ordi ou ta TV (sur le MÊME Wi-Fi que le téléphone), '
              'ouvre le navigateur et tape cette adresse :',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                url,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
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
            Text('ou scanne avec un autre téléphone',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 18),
            Text(
              'La chaîne démarre toute seule. Garde l’app ouverte : c’est '
              'le téléphone qui envoie la vidéo à l’écran. Fonctionne avec '
              'ton abonnement (pas de blocage cloud).',
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
                label: Text('Arrêter',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.live)),
              ),
            ),
          ],
        );
    }
  }
}
