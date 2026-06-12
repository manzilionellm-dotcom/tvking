// =========================================================
//  tv_activation_screen.dart — Écran d'ACCUEIL / ACTIVATION
// =========================================================
//  Affiché tant que l'appareil n'est pas payé/en essai. Montre :
//   • que l'app n'est PAS gratuite (À VIE : 9,99 $),
//   • le CODE D'ACTIVATION (MAC) de cette TV — stable, identique même
//     après désinstallation/réinstallation (dérivé de l'ANDROID_ID),
//   • un bouton « J'ai payé — Vérifier » qui re-synchronise le statut.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';

// Or « The Few ».
const Color _gold = Color(0xFFD9B26A);

class TvActivationScreen extends StatefulWidget {
  const TvActivationScreen({super.key});

  @override
  State<TvActivationScreen> createState() => _TvActivationScreenState();
}

class _TvActivationScreenState extends State<TvActivationScreen> {
  String _mac = '…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // --- Marque ---
            Text('The Few',
                style: TextStyle(
                    fontSize: 64,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    color: _gold)),
            Text('NOT FOR EVERYONE',
                style: TextStyle(
                    fontSize: TvDimens.label,
                    letterSpacing: 6,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 28),

            // --- Pas gratuit + prix ---
            Text('Cette application n\'est pas gratuite.',
                style: TextStyle(
                    fontSize: TvDimens.title, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                  border: Border.all(color: _gold, width: 2),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('À VIE — 9,99 \$',
                  style: TextStyle(
                      fontSize: TvDimens.headline,
                      fontWeight: FontWeight.w800,
                      color: _gold)),
            ),
            const SizedBox(height: 30),

            // --- Code d'activation (MAC) ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(TvDimens.panelRadius),
                  border: Border.all(color: AppColors.maisonBorder)),
              child: Column(
                children: <Widget>[
                  Text('TON CODE D\'ACTIVATION',
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          letterSpacing: 3,
                          color: AppColors.textTertiary)),
                  const SizedBox(height: 10),
                  SelectableText(_mac,
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          letterSpacing: 3,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  Text(
                    'Donne ce code à ton revendeur pour activer. '
                    'Il reste LE MÊME même si tu désinstalles puis réinstalles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // --- Bouton vérifier ---
            TvFocusBuilder(
              autofocus: true,
              scale: TvFocusScale.large,
              onSelect: _busy ? null : _check,
              builder: (BuildContext context, bool focused) {
                final Color bg = focused ? _gold : AppColors.surfaceHigh;
                final Color fg = focused ? AppColors.background : _gold;
                return Container(
                  decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                      border: Border.all(color: _gold)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  child: Text(_busy ? 'Vérification…' : 'J\'ai payé — Vérifier',
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w800,
                          color: fg)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
