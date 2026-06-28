// =========================================================
//  screen_cast_sheet.dart — « Caster sur un écran » (code TV)
// =========================================================
//  Une TV n'a PAS de caméra : elle ne scanne donc rien. Le bon modèle
//  (façon YouTube / Netflix) : sur la TV on ouvre une adresse FIXE
//  (app.7themotion.com/ecran) puis on TAPE un code à 4 caractères. Le
//  QR, lui, sert juste à un AUTRE téléphone.
//
//  Dès qu'on crée la session, on pousse la chaîne courante : la TV
//  démarre la lecture toute seule une fois connectée. Tout passe par le
//  Worker (cf. screen_cast_service.dart) → marche même hors du Wi-Fi du
//  téléphone.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/screen_cast_service.dart';

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
  ScreenSession? _session;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ScreenSession? s = await ScreenCastService.instance.create();
    if (!mounted) return;
    if (s == null) {
      setState(() => _status = _Status.error);
      return;
    }
    // On pousse tout de suite la chaîne : la TV démarrera la lecture dès
    // qu'elle se connecte.
    await ScreenCastService.instance
        .play(s.code, widget.streamUrl, title: widget.title);
    if (!mounted) return;
    setState(() {
      _session = s;
      _status = _Status.ready;
    });
  }

  Future<void> _stop() async {
    final ScreenSession? s = _session;
    if (s != null) await ScreenCastService.instance.stop(s.code);
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
              'Impossible de préparer l’écran pour le moment. '
              'Vérifie ta connexion et réessaie.',
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
        final ScreenSession s = _session!;
        final String pairAddr = '${Uri.parse(s.url).host}/ecran';
        return Column(
          children: <Widget>[
            // ETAPE 1 — sur la TV (qui n'a pas de camera) : ouvrir cette
            // adresse FIXE dans son navigateur.
            Text('Sur ta TV, ouvre le navigateur et va sur',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            SelectableText(
              pairAddr,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium
                  .copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            // ETAPE 2 — taper ce code sur la TV.
            Text('puis entre ce code',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(
              s.code,
              style: AppTextStyles.displayLarge.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 10,
              ),
            ),
            const SizedBox(height: 22),
            // QR = raccourci pour UN AUTRE TELEPHONE (la TV ne scanne rien).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: s.url,
                version: QrVersions.auto,
                size: 150,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text('ou scanne avec un autre téléphone',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Text(
              'La chaîne démarre toute seule dès que la TV est connectée. '
              'Marche sur n’importe quel écran avec un navigateur, même '
              'hors de ton Wi-Fi.',
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
