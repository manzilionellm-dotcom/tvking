// =========================================================
//  tv_activation_screen.dart — Licence « The Few » (Maison Noir)
// =========================================================
//  Logo hero + tagline sobre + prix en pastille or + code d'activation
//  (mono) dans une carte + CTA or « J'ai payé — Vérifier ». Poll 5 s :
//  dès que le revendeur active la MAC, la TV se débloque toute seule.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_family_join_screen.dart';
import 'tv_shell.dart';

class TvActivationScreen extends StatefulWidget {
  const TvActivationScreen({super.key});

  @override
  State<TvActivationScreen> createState() => _TvActivationScreenState();
}

class _TvActivationScreenState extends State<TvActivationScreen> {
  String _mac = '…';
  bool _busy = false;
  bool _copied = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Code NU (sans « MK: ») : le panel du revendeur rajoute déjà « MK »,
    // donc on n'affiche/copie/envoie QUE les octets pour éviter le doublon.
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
    // Activation instantanée : revérifie toutes les 5 s.
    _poll = Timer.periodic(const Duration(seconds: 5),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _mac));
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le design est pensé à une taille FIXE puis MIS À L'ÉCHELLE pour tenir
    // dans n'importe quel écran TV (720p → 4K, overscan inclus). FittedBox =
    // jamais de débordement, jamais « trop zoomé ». On neutralise aussi le
    // textScale système (certaines box TV le poussent à 1.3-1.5).
    return MediaQuery.withNoTextScaling(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1000,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // ----- Colonne gauche : marque + code + CTA -----
                SizedBox(width: 600, child: _activationColumn(context)),
                const SizedBox(width: 56),
                // ----- Colonne droite : QR « Scanne-moi » → WhatsApp -----
                TvWhatsAppQr(mac: _mac),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activationColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
            const TvLogo(width: 240),
            const SizedBox(height: 26),
            Text(context.l10n.tvActivationTagline,
                textAlign: TextAlign.center,
                style: TvTokens.ui(19, color: TvTokens.muted)),
            const SizedBox(height: 22),
            TvPricePill(label: context.l10n.tvLifetime, amount: '9,99 \$'),
            const SizedBox(height: 38),

            // ----- Carte code d'activation -----
            TvCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: <Widget>[
                  TvSectionLabel(context.l10n.tvActivationCodeLabel),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(_mac, style: TvTokens.mono(38, color: TvTokens.goldBright, spacing: 2)),
                      const SizedBox(width: 16),
                      _CopyButton(copied: _copied, onSelect: _copy),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.l10n.tvActivationCodeHelp,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(16, color: TvTokens.mutedDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            TvCtaButton(
              label: _busy ? context.l10n.tvChecking : context.l10n.tvPaidCheck,
              autofocus: true,
              onSelect: _busy ? null : _check,
            ),
            const SizedBox(height: 14),
            // Le client peut apporter SA propre liste (The Few ne vend pas
            // de liste) → il a le droit de l'ajouter lui-même.
            TvFocusBuilder(
              scale: TvFocusScale.large,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TvShell(child: TvAddSourceScreen()),
                ),
              ),
              builder: (BuildContext context, bool focused) => Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  border: Border.all(color: focused ? TvTokens.gold : TvTokens.line),
                  color: focused ? TvTokens.sel : Colors.transparent,
                ),
                child: Text(context.l10n.tvAddOwnList,
                    style: TvTokens.ui(19, weight: FontWeight.w600,
                        color: focused ? TvTokens.goldBright : TvTokens.muted)),
              ),
            ),
            const SizedBox(height: 14),
            // ABONNEMENT FAMILLE : un proche a déjà payé → il suffit de taper
            // son code à 6 chiffres (généré dans Réglages → Abonnement
            // Famille) pour rattacher CET appareil au même abonnement.
            TvFocusBuilder(
              scale: TvFocusScale.large,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TvShell(child: TvFamilyJoinScreen()),
                ),
              ),
              builder: (BuildContext context, bool focused) => Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  border: Border.all(color: focused ? TvTokens.gold : TvTokens.line),
                  color: focused ? TvTokens.sel : Colors.transparent,
                ),
                child: Text('👨‍👩‍👧  ${context.l10n.tvActivationFamilyCode}',
                    style: TvTokens.ui(19, weight: FontWeight.w600,
                        color: focused ? TvTokens.goldBright : TvTokens.muted)),
              ),
            ),
            const SizedBox(height: 18),
            Text(context.l10n.tvActivationFooter,
                style: TvTokens.ui(13, color: TvTokens.mutedDim, spacing: 0.5)),
            const SizedBox(height: 10),
            // Positionnement « lecteur » (bouclier juridique) visible dès le gate.
            SizedBox(
              width: 540,
              child: Text(
                context.l10n.tvActivationLegal,
                textAlign: TextAlign.center,
                style: TvTokens.ui(12, color: TvTokens.mutedDim),
              ),
            ),
          ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onSelect});
  final bool copied;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      onSelect: onSelect,
      scale: TvFocusScale.small,
      builder: (BuildContext context, bool focused) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: TvTokens.card,
          border: Border.all(color: focused ? TvTokens.gold : TvTokens.line),
          borderRadius: BorderRadius.circular(TvTokens.rSmall),
        ),
        child: Icon(copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 22, color: copied ? const Color(0xFF5FA975) : TvTokens.gold),
      ),
    );
  }
}
