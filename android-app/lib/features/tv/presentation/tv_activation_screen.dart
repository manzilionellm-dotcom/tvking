// =========================================================
//  tv_activation_screen.dart — Licence « The Few » (Maison Noir)
// =========================================================
//  Logo hero + tagline sobre + prix en pastille or + code d'activation
//  (mono) dans une carte + CTA or « J'ai payé — Vérifier ».
//  La veille de l'app lit le statut toute seule (quelques secondes) :
//  dès que le revendeur active la MAC, la TV se débloque.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../device/domain/display_mac.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/app/zuno_edition.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cast/data/cast_platform.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/remote_activation_watch.dart';
import '../../subscription/data/subscription_state.dart';
import '../../playlists/domain/open_source_input.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_phone_source_qr.dart';
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

  @override
  void initState() {
    super.initState();
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
    SubscriptionState.instance.removeListener(_onSub);
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    RemoteActivationWatch.instance.nudge();
    if (mounted) setState(() => _busy = false);
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
    // L'identité envoyée au panel reste celle de ZUNO. Seule l'édition
    // explicite choisit cette présentation : une grande tablette reste
    // tactile, tandis que la TV et le bureau gardent leur canevas actuel.
    if (CastPlatform.zunoEdition == ZunoEdition.touch) {
      return _touchActivation(context);
    }
    // Le design est pensé à une taille FIXE puis MIS À L'ÉCHELLE pour tenir
    // dans n'importe quel écran TV (720p → 4K, overscan inclus). FittedBox =
    // jamais de débordement, jamais « trop zoomé ». On neutralise aussi le
    // textScale système (certaines box TV le poussent à 1.3-1.5).
    return MediaQuery.withNoTextScaling(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            // Largeurs complètes, textes compris : 540 + 48 + 250 + 40 + 322.
            // Le FittedBox adapte cet ensemble à la zone sûre de la télévision.
            width: 1200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // ----- Colonne gauche : marque + code + CTA -----
                SizedBox(width: 540, child: _activationColumn(context)),
                const SizedBox(width: 48),
                // ----- Droite : DEUX grands QR (demande du 04/10/2026) -----
                //  1. WhatsApp du revendeur, code MAC déjà dans le message :
                //     la personne qui vient d'installer l'app te contacte.
                //  2. Page « Mon espace » : elle ajoute SA propre liste
                //     depuis son téléphone (la mention « ne vend aucune
                //     chaîne » est au-dessus du QR, dans TvOwnSourceQr).
                TvWhatsAppQr(mac: _mac, size: 210),
                const SizedBox(width: 40),
                TvPhoneSourceQr(mac: _mac, qrSize: 210),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _touchActivation(BuildContext context) {
    final String? hint = switch (SubscriptionState.instance.syncHint) {
      'offline' => context.l10n.tvNetworkUnavailableHelp,
      'expired' => context.l10n.tvCodeInactive,
      'frozen' => context.l10n.subFrozenMsg,
      'banned' => context.l10n.tvStatusBanned,
      _ => null,
    };
    // Le shell fournit la zone sûre et l'espace du clavier. Ici, le contenu
    // utilise ses vraies contraintes et peut défiler, même en paysage ou
    // avec de grands caractères. Aucun texte n'est réduit par un FittedBox.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            constraints.maxWidth.clamp(0, TvDimens.touchFormWidth).toDouble();
        // Le panneau « Mon espace » ajoute 112 dp autour de son QR. Adapter
        // le seul dessin conserve ses phrases lisibles sur les petits écrans.
        final double qrSize = (width - 112).clamp(72, 168).toDouble();
        return SingleChildScrollView(
          key: const ValueKey<String>('zuno-touch-activation-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(
              top: TvDimens.touchGap, bottom: TvDimens.touchGap * 2),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: TvDimens.touchFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: TvLogo()),
                  const SizedBox(height: TvDimens.touchSafeV),
                  Text(
                    context.l10n.tvActivationTagline,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(TvDimens.title, color: TvTokens.text),
                  ),
                  const SizedBox(height: TvDimens.touchSafeV),
                  // Wrap conserve le prix et sa légende à leur taille normale
                  // lorsque l'accessibilité ou une traduction prend deux lignes.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDimens.touchSafeH,
                      vertical: TvDimens.touchGap,
                    ),
                    decoration: BoxDecoration(
                      gradient: TvTokens.pillGradient,
                      border: Border.all(color: TvTokens.line),
                      borderRadius: BorderRadius.circular(TvTokens.rCard),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: TvDimens.touchGap,
                      runSpacing: TvDimens.touchGap,
                      children: <Widget>[
                        Text(
                          context.l10n.tvLifetime.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(
                            TvDimens.label,
                            weight: FontWeight.w600,
                            color: TvTokens.accent,
                          ),
                        ),
                        Text(
                          '9,99 \$',
                          style: TvTokens.display(
                            TvDimens.title,
                            color: TvTokens.accentBright,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TvDimens.touchSafeV),
                  TvCard(
                    padding: const EdgeInsets.all(TvDimens.touchSafeH),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          context.l10n.tvActivationCodeLabel,
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(
                            TvDimens.label,
                            color: TvTokens.muted,
                          ),
                        ),
                        const SizedBox(height: TvDimens.touchGap),
                        Text(
                          displayMac(
                            _mac,
                            showPrefix: RepairFlags.macShowPrefix,
                          ),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: TvTokens.mono(TvDimens.title),
                        ),
                        const SizedBox(height: TvDimens.touchGap),
                        // Le bouton est sous le code pour lui laisser toute la
                        // largeur. Copier utilise exactement la même MAC que TV.
                        Center(
                          child: TextButton.icon(
                            key: const ValueKey<String>(
                              'zuno-touch-activation-copy',
                            ),
                            onPressed: _copy,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                  TvDimens.touchTarget, TvDimens.touchTarget),
                              foregroundColor: _copied
                                  ? TvTokens.success
                                  : TvTokens.accentBright,
                              textStyle: TvTokens.ui(TvDimens.label),
                            ),
                            icon: Icon(
                              _copied
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                            ),
                            label: Text(
                              _copied
                                  ? context.l10n.tvCopied
                                  : context.l10n.tvCopy,
                            ),
                          ),
                        ),
                        const SizedBox(height: TvDimens.touchGap),
                        Text(
                          context.l10n.tvActivationCodeHelp,
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(
                            TvDimens.label,
                            color: TvTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TvDimens.touchSafeV),
                  FilledButton(
                    key: const ValueKey<String>('zuno-touch-activation-check'),
                    onPressed: _busy ? null : _check,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, TvDimens.touchButtonHeight),
                      padding: const EdgeInsets.symmetric(
                        horizontal: TvDimens.touchSafeH,
                        vertical: TvDimens.touchSafeV,
                      ),
                      backgroundColor: TvTokens.accent,
                      foregroundColor: TvTokens.onAccent,
                      textStyle: TvTokens.ui(
                        TvDimens.body,
                        weight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TvTokens.rButton),
                      ),
                    ),
                    child: Text(
                      _busy
                          ? context.l10n.tvChecking
                          : context.l10n.tvPaidCheck,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (hint != null) ...<Widget>[
                    const SizedBox(height: TvDimens.touchGap),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: TvTokens.ui(TvDimens.label, color: TvTokens.live),
                    ),
                  ],
                  const SizedBox(height: TvDimens.touchGap * 2),
                  Text(
                    context.l10n.sourceOwnSub,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(
                      TvDimens.label,
                      weight: FontWeight.w600,
                      color: TvTokens.muted,
                    ),
                  ),
                  const SizedBox(height: TvDimens.touchGap),
                  _touchSourceButton(
                    context,
                    OpenEntryMode.xtream,
                    Icons.vpn_key_rounded,
                    context.l10n.playlistTypeXtream,
                  ),
                  const SizedBox(height: TvDimens.touchGap),
                  _touchSourceButton(
                    context,
                    OpenEntryMode.m3u,
                    Icons.link_rounded,
                    context.l10n.playlistTypeM3u,
                  ),
                  const SizedBox(height: TvDimens.touchGap),
                  _touchSourceButton(
                    context,
                    OpenEntryMode.player,
                    Icons.play_circle_outline_rounded,
                    context.l10n.tvPlayerLink,
                  ),
                  const SizedBox(height: TvDimens.touchSafeV),
                  Text(
                    context.l10n.tvActivationFooter,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
                  ),
                  const SizedBox(height: TvDimens.touchGap),
                  Text(
                    context.l10n.tvActivationDisclaimer,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
                  ),
                  const SizedBox(height: TvDimens.touchGap * 2),
                  const Divider(color: TvTokens.line),
                  const SizedBox(height: TvDimens.touchSafeV),
                  // Les QR restent disponibles pour un autre appareil, après
                  // les actions utilisables directement sur ce téléphone.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: TvDimens.touchGap * 2,
                    runSpacing: TvDimens.touchSafeV * 2,
                    children: <Widget>[
                      TvWhatsAppQr(mac: _mac, size: qrSize),
                      TvPhoneSourceQr(mac: _mac, qrSize: qrSize),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _touchSourceButton(
    BuildContext context,
    OpenEntryMode mode,
    IconData icon,
    String label,
  ) {
    return OutlinedButton.icon(
      key: ValueKey<String>('zuno-touch-source-${mode.name}'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TvShell(child: TvAddSourceScreen(initialMode: mode)),
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, TvDimens.touchButtonHeight),
        padding: const EdgeInsets.symmetric(
            horizontal: TvDimens.touchSafeH, vertical: TvDimens.touchSafeV),
        foregroundColor: TvTokens.text,
        backgroundColor: TvTokens.card,
        side: const BorderSide(color: TvTokens.line),
        textStyle: TvTokens.ui(TvDimens.body, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TvTokens.rButton),
        ),
      ),
      icon: Icon(icon, color: TvTokens.accent),
      label: Text(label, textAlign: TextAlign.center),
    );
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
        const TvLogo(width: 240),
        const SizedBox(height: 26),
        Text(
          context.l10n.tvActivationTagline,
          textAlign: TextAlign.center,
          style: TvTokens.ui(19, color: TvTokens.muted),
        ),
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
          autofocus: true,
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
        const SizedBox(height: 22),
        // ----- CONNEXION : l'utilisateur apporte sa propre source -----
        //  Trois entrées, sans liste de serveurs : Xtream (adresse +
        //  nom + mot de passe), lien M3U/M3U8, ou lien lecteur get.php.
        //  N'importe quel fournisseur. La licence (code MAC + « J'ai
        //  payé ») reste le verrou : sans essai ni abonnement valide,
        //  l'accueil ne s'ouvre pas, même après avoir saisi une source.
        Text(
          context.l10n.sourceOwnSub.toUpperCase(),
          style: TvTokens.ui(
            11,
            weight: FontWeight.w600,
            color: TvTokens.mutedDim,
            spacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _ConnectButton(
            icon: Icons.vpn_key_rounded,
            label: context.l10n.playlistTypeXtream,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(
                  child: TvAddSourceScreen(initialMode: OpenEntryMode.xtream),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _ConnectButton(
            icon: Icons.link_rounded,
            label: context.l10n.playlistTypeM3u,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(
                  child: TvAddSourceScreen(initialMode: OpenEntryMode.m3u),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _ConnectButton(
            icon: Icons.play_circle_outline_rounded,
            label: OpenSourceInput.playerLabel,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(
                  child: TvAddSourceScreen(initialMode: OpenEntryMode.player),
                ),
              ),
            ),
          ),
        ),
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
            context.l10n.tvActivationDisclaimer,
            textAlign: TextAlign.center,
            style: TvTokens.ui(12, color: TvTokens.mutedDim),
          ),
        ),
      ],
    );
  }
}

/// Bouton de CONNEXION (Xtream / M3U) sur le gate : icône + libellé, bordure
/// braise au focus, remplissage discret. Même langage visuel que le reste du
/// design system TV (aucune couleur en dur — tout via TvTokens).
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.icon,
    required this.label,
    required this.onSelect,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          color: focused ? TvTokens.sel : TvTokens.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 22,
              color: focused ? TvTokens.accentBright : TvTokens.accent,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(
                  18,
                  weight: FontWeight.w600,
                  color: focused ? TvTokens.accentBright : TvTokens.text,
                ),
              ),
            ),
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
