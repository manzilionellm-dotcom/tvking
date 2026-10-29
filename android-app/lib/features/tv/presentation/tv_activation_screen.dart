// =========================================================
//  tv_activation_screen.dart — Licence « The Few » (Maison Noir)
// =========================================================
//  Logo hero + tagline sobre + prix en pastille or + code d'activation
//  (mono) dans une carte + CTA or « J'ai payé — Vérifier ».
//  La veille de l'app lit le statut toute seule (quelques secondes) :
//  dès que le revendeur active la MAC, la TV se débloque.
// =========================================================
import 'package:flutter/material.dart';
import '../../subscription/data/gold_trial_controller.dart';
import 'tv_gold_trial_card.dart';
import 'package:flutter/services.dart';

import '../../device/domain/display_mac.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/remote_activation_watch.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_source_setup.dart';

class TvActivationScreen extends StatefulWidget {
  const TvActivationScreen({super.key, this.trialController});
  final GoldTrialController? trialController;

  @override
  State<TvActivationScreen> createState() => _TvActivationScreenState();
}

class _TvActivationScreenState extends State<TvActivationScreen> {
  late final GoldTrialController _goldTrial;
  String _mac = '…';
  bool _busy = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _goldTrial = widget.trialController ?? GoldTrialController();
    _goldTrial.addListener(_onSub);
    if (widget.trialController == null) _goldTrial.initialize();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    SubscriptionState.instance.addListener(_onSub);
    // La veille unique (RemoteActivationWatch) lit le statut.
    // Cet écran n'envoie plus de heartbeat toutes les 5 secondes.
  }

  void _onSub() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _goldTrial.removeListener(_onSub);
    if (widget.trialController == null) _goldTrial.dispose();
    SubscriptionState.instance.removeListener(_onSub);
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await SubscriptionState.instance.syncWithBackend();
      RemoteActivationWatch.instance.nudge();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy() {
    Clipboard.setData(
      ClipboardData(
        text: displayMac(_mac, showPrefix: RepairFlags.macShowPrefix),
      ),
    );
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le formulaire est visible dès le premier lancement. Les informations
    // d'activation restent à côté ; seul TvGate décide ensuite de l'accès.
    // Aucun QR ni changement de route n'est nécessaire pour saisir sa liste.
    return TvSourceSetup(details: _activationColumn(context));
  }

  Widget _activationColumn(BuildContext context) {
    final String? hint = switch (SubscriptionState.instance.syncHint) {
      'offline' => context.l10n.tvNetworkUnavailableHelp,
      'expired' => context.l10n.tvCodeInactive,
      'frozen' => context.l10n.subFrozenMsg,
      'banned' => context.l10n.tvStatusBanned,
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const TvLogo(width: 180),
        TvGoldTrialCard(controller: _goldTrial),
        const SizedBox(height: 26),
        Text(
          context.l10n.tvActivationTagline,
          textAlign: TextAlign.center,
          style: TvTokens.ui(19, color: TvTokens.muted),
        ),
        const SizedBox(height: 22),
        // La colonne d'aide est plus étroite que l'ancien écran TV. Le prix
        // passe à la ligne si le texte est agrandi, sans réduire sa lisibilité.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            gradient: TvTokens.pillGradient,
            border: Border.all(color: TvTokens.line),
            borderRadius: BorderRadius.circular(TvTokens.rCard),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: <Widget>[
              Text(context.l10n.tvLifetime.toUpperCase(),
                  style: TvTokens.ui(15, weight: FontWeight.w600,
                      color: TvTokens.accent, spacing: 2)),
              Text('9,99 \$', style: TvTokens.display(26,
                  weight: FontWeight.w600, color: TvTokens.accentBright)),
            ],
          ),
        ),
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
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        displayMac(_mac, showPrefix: RepairFlags.macShowPrefix),
                        // Une MAC reste gauche → droite, même dans une UI arabe.
                        // Sinon Unicode déplace ses premiers groupes chiffrés.
                        textDirection: TextDirection.ltr,
                        style: TvTokens.mono(
                          38,
                          color: TvTokens.accentBright,
                          spacing: 2,
                        ),
                      ),
                    ),
                  ),
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
          onSelect: _busy ? null : _check,
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TvTokens.ui(16, color: TvTokens.live),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          context.l10n.tvActivationFooter,
          style: TvTokens.ui(13, color: TvTokens.mutedDim, spacing: 0.5),
        ),
        const SizedBox(height: 10),
        // Positionnement « lecteur » (bouclier juridique) visible dès le gate.
        SizedBox(
          width: 540,
          child: Text(
            // Le lien affiché migre sans modifier les catalogues de traduction.
            context.l10n.tvActivationDisclaimer.replaceFirst(
              RegExp(r'[A-Za-z0-9.-]+/terms\b'),
              'api.zuno8k.com/terms',
            ),
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
          border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          borderRadius: BorderRadius.circular(TvTokens.rSmall),
        ),
        child: Icon(
          copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 22,
          color: copied ? const Color(0xFF5FA975) : TvTokens.accent,
        ),
      ),
    );
  }
}
