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

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
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
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const TvLogo(width: 240),
            const SizedBox(height: 26),
            Text('Accès complet, à vie. Un seul paiement.',
                style: TvTokens.ui(19, color: TvTokens.muted)),
            const SizedBox(height: 22),
            const TvPricePill(label: 'À vie', amount: '9,99 \$'),
            const SizedBox(height: 38),

            // ----- Carte code d'activation -----
            TvCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: <Widget>[
                  const TvSectionLabel('Ton code d\'activation'),
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
                    'Donne ce code à ton revendeur pour activer. '
                    'Il reste le même, même après une réinstallation.',
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(16, color: TvTokens.mutedDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            TvCtaButton(
              label: _busy ? 'Vérification…' : 'J\'ai payé — Vérifier',
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
                child: Text('J\'ajoute ma propre liste (Xtream)',
                    style: TvTokens.ui(19, weight: FontWeight.w600,
                        color: focused ? TvTokens.goldBright : TvTokens.muted)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Paiement vérifié · Activation instantanée',
                style: TvTokens.ui(13, color: TvTokens.mutedDim, spacing: 0.5)),
          ],
        ),
      ),
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
