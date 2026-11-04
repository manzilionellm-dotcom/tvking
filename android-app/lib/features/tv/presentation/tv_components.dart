// =========================================================
//  tv_components.dart — Composants « Maison Noir » réutilisables
// =========================================================
//  Logo (vrai asset), Card (filet or), Button (CTA or), Pill (prix),
//  EmptyState. Tout référence TvTokens — zéro couleur en dur.
// =========================================================
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../device/domain/display_mac.dart';
import '../../theme/data/remote_theme_repository.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';

/// Nom produit affiché PARTOUT.
const String kAppName = 'Zuno';
// Logo « naturel » sur fond TRANSPARENT (pas le carré noir, qui se voyait
// comme un rectangle plus sombre sur les surfaces gris foncé de l'app).
// Le carré noir reste UNIQUEMENT pour l'icône de lancement (cf. yaml dédié),
// où un fond est normal.
const String _kLogoAsset = 'assets/branding/zuno_logo.png';

/// Numéro WhatsApp business (format international, sans + ni espaces).
const String kWhatsAppPhone = '447307410512';

/// Construit le lien wa.me avec un message pré-rempli (code MAC inclus,
/// sans « MK: » : le panel le remet tout seul, voir display_mac.dart).
String tvWhatsAppUrl(String mac, AppLocalizations l10n) {
  final String code = (mac == '…' || mac.isEmpty)
      ? ''
      : displayMac(mac, showPrefix: RepairFlags.macShowPrefix);
  // La phrase suit la langue TV. La MAC reste seule sur une ligne commençant
  // par un sigle latin : Unicode conserve ainsi l'ordre de tous ses groupes,
  // même dans un message arabe. Aucun caractère invisible dans le code copié.
  final String msg = Uri.encodeComponent(
    '${l10n.tvWhatsAppActivationRequest}${code.isEmpty ? '' : '\nMAC: $code'}',
  );
  return 'https://wa.me/$kWhatsAppPhone?text=$msg';
}

/// Panneau QR « Scanne-moi » → WhatsApp du revendeur, MAC pré-remplie.
/// Resté sur l'écran Direct quand aucune chaîne n'est encore là.
/// L'accueil vide, lui, montre le QR vers « Mon espace » (tv_phone_source_qr).
class TvWhatsAppQr extends StatelessWidget {
  const TvWhatsAppQr({super.key, required this.mac, this.size = 220});
  final String mac;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // QR sur fond clair (un QR se scanne en sombre-sur-clair).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(TvTokens.rCard),
              border: Border.all(
                color: TvAppTokens.of(context).accent,
                width: 2,
              ),
            ),
            child: QrImageView(
              data: tvWhatsAppUrl(mac, context.l10n),
              version: QrVersions.auto,
              size: size,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0B0B0B),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.qr_code_scanner_rounded,
                color: TvAppTokens.of(context).accentBright,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.tvScanToActivate,
                  textAlign: TextAlign.center,
                  style: TvAppTokens.of(context).ui(
                    18,
                    weight: FontWeight.w700,
                    color: TvAppTokens.of(context).accentBright,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 40,
            child: Text(
              context.l10n.tvScanHelp,
              textAlign: TextAlign.center,
              style: TvAppTokens.of(context)
                  .ui(13, color: TvAppTokens.of(context).mutedDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo réel « Zuno » (calligraphie or, fond transparent).
///
/// Pose courte (échelle 0,985 → 1, opacité pleine) : le mot reste
/// visible dès la première image, il ne « disparaît » pas après le
/// splash natif. Transform seulement, 180 ms, coupé si la box demande
/// moins d'animations.
class TvLogo extends StatefulWidget {
  const TvLogo({super.key, this.width = 180});
  final double width;

  @override
  State<TvLogo> createState() => _TvLogoState();
}

class _TvLogoState extends State<TvLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: TvDimens.focusAnim,
  );
  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
    } else {
      _settle.forward();
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> scale = Tween<double>(begin: 0.985, end: 1).animate(
      CurvedAnimation(parent: _settle, curve: TvDimens.focusCurve),
    );
    return ScaleTransition(
      scale: scale,
      child: ValueListenableBuilder(
        valueListenable: RemoteThemeRepository.current,
        builder: (context, settings, _) => settings.appName.isEmpty
            ? Image.asset(_kLogoAsset, width: widget.width, fit: BoxFit.contain)
            : SizedBox(
                width: widget.width,
                child: Text(
                  settings.appName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvAppTokens.of(context)
                      .display(28, color: TvAppTokens.of(context).accentBright),
                ),
              ),
      ),
    );
  }
}

/// Carte sombre avec filet d'accent or en haut.
class TvCard extends StatelessWidget {
  const TvCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TvAppTokens.of(context).card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvAppTokens.of(context).lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Filet d'accent or (1px) en haut.
          SizedBox(
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: TvAppTokens.of(context).accentHairline,
              ),
            ),
          ),
          Padding(padding: padding ?? const EdgeInsets.all(24), child: child),
        ],
      ),
    );
  }
}

/// Libellé de section. Taille plancher 14 (Fire TV), graisse 500,
/// interlettrage 0,5 px (label Material 3). On garde la casse du texte :
/// un titre de rangée n'est pas crié en capitales.
class TvSectionLabel extends StatelessWidget {
  const TvSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TvAppTokens.of(context).ui(
      TvDimens.caption,
      weight: FontWeight.w500,
      color: TvAppTokens.of(context).mutedDim,
      spacing: 0.5,
    ),
  );
}

/// Pastille prix : « À VIE » + montant or.
class TvPricePill extends StatelessWidget {
  const TvPricePill({super.key, required this.label, required this.amount});
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        gradient: TvAppTokens.of(context).pillGradient,
        border: Border.all(color: TvAppTokens.of(context).line),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: TvAppTokens.of(context).ui(
              TvDimens.caption,
              weight: FontWeight.w500,
              color: TvAppTokens.of(context).accent,
              spacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: TvAppTokens.of(context).display(
              26,
              weight: FontWeight.w600,
              color: TvAppTokens.of(context).accentBright,
            ),
          ),
        ],
      ),
    );
  }
}

/// CTA principal : dégradé or, texte sombre, ombre. Focusable (or au focus).
class TvCtaButton extends StatelessWidget {
  const TvCtaButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(TvTokens.rButton);
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      borderRadius: radius,
      // Le dégradé or EST le focus. Pas de second halo (néon + coût GPU).
      showGlow: false,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: expand ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            gradient: TvAppTokens.of(context).ctaGradient,
            borderRadius: radius,
            border: focused
                ? Border.all(color: TvAppTokens.of(context).text, width: 2)
                : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: TvAppTokens.of(context).accent.withValues(
                      alpha: focused ? 0.40 : 0.16,
                    ),
                blurRadius: focused ? 22 : 14,
                spreadRadius: -8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            label,
            style: TvAppTokens.of(context).ui(
              TvDimens.title,
              weight: FontWeight.w600,
              color: TvAppTokens.of(context).onAccent,
            ),
          ),
        );
      },
    );
  }
}

/// État vide : titre de l'échelle display, sous-texte en corps 24/16.
class TvEmptyState extends StatelessWidget {
  const TvEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.footer,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  /// Bouton optionnel sous le texte (Réessayer, par exemple).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: TvAppTokens.of(context).pillGradient,
              border: Border.all(color: TvAppTokens.of(context).line),
              borderRadius: BorderRadius.circular(TvTokens.rButton),
            ),
            child: Icon(icon, color: TvAppTokens.of(context).accent, size: 38),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: TvAppTokens.of(context)
                .display(34, color: TvAppTokens.of(context).text),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 460,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TvAppTokens.of(context)
                  .body(TvDimens.label, color: TvAppTokens.of(context).mutedDim),
            ),
          ),
          if (footer != null) ...<Widget>[const SizedBox(height: 22), footer!],
        ],
      ),
    );
  }
}
