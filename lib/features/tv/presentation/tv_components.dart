// =========================================================
//  tv_components.dart — Composants « Maison Noir » réutilisables
// =========================================================
//  Logo (vrai asset), Card (filet or), Button (CTA or), Pill (prix),
//  EmptyState. Tout référence TvTokens — zéro couleur en dur.
// =========================================================
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Nom produit affiché PARTOUT.
const String kAppName = 'The Few TV';
const String _kLogoAsset = 'assets/branding/thefew_tv_icon.png';

/// Numéro WhatsApp business (format international, sans + ni espaces).
const String kWhatsAppPhone = '447307410512';

/// Construit le lien wa.me avec un message pré-rempli (code MAC inclus).
String tvWhatsAppUrl(String mac) {
  final String code = (mac == '…' || mac.isEmpty) ? '' : mac;
  final String msg = Uri.encodeComponent(
      'Bonjour, je souhaite activer The Few TV.'
      '${code.isEmpty ? '' : ' Mon code : $code'}');
  return 'https://wa.me/$kWhatsAppPhone?text=$msg';
}

/// Panneau QR « Scanne-moi » → WhatsApp du revendeur, MAC pré-remplie.
/// Réutilisé sur l'écran d'activation ET sur l'accueil (quand aucune chaîne).
class TvWhatsAppQr extends StatelessWidget {
  const TvWhatsAppQr({super.key, required this.mac, this.size = 220});
  final String mac;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // QR sur fond clair (un QR se scanne en sombre-sur-clair).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.gold, width: 2),
          ),
          child: QrImageView(
            data: tvWhatsAppUrl(mac),
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0B0B0B)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.qr_code_scanner_rounded,
                color: TvTokens.goldBright, size: 22),
            const SizedBox(width: 10),
            Text(context.l10n.tvScanToActivate,
                style: TvTokens.ui(18,
                    weight: FontWeight.w700, color: TvTokens.goldBright)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: size + 40,
          child: Text(context.l10n.tvScanHelp,
              textAlign: TextAlign.center,
              style: TvTokens.ui(13, color: TvTokens.mutedDim)),
        ),
      ],
    );
  }
}

/// Logo réel « The Few » (or sur noir).
class TvLogo extends StatelessWidget {
  const TvLogo({super.key, this.width = 180});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(_kLogoAsset, width: width, fit: BoxFit.contain);
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
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Filet d'accent or (1px) en haut.
          const SizedBox(
            height: 1,
            child: DecoratedBox(decoration: BoxDecoration(gradient: TvTokens.goldHairline)),
          ),
          Padding(padding: padding ?? const EdgeInsets.all(24), child: child),
        ],
      ),
    );
  }
}

/// Libellé de section : Inter 600, letterspaced, majuscules, gris.
class TvSectionLabel extends StatelessWidget {
  const TvSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TvTokens.ui(10.5, weight: FontWeight.w600, color: TvTokens.mutedDim, spacing: 2.8),
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
        gradient: TvTokens.pillGradient,
        border: Border.all(color: TvTokens.line),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(),
              style: TvTokens.ui(15, weight: FontWeight.w600, color: TvTokens.gold, spacing: 2)),
          const SizedBox(width: 12),
          Text(amount,
              style: TvTokens.display(26, weight: FontWeight.w600, color: TvTokens.goldBright)),
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
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: expand ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            gradient: TvTokens.ctaGradient,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: focused ? Border.all(color: TvTokens.text, width: 2) : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFCCB089).withValues(alpha: focused ? 0.55 : 0.35),
                blurRadius: focused ? 36 : 24,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(label,
              style: TvTokens.ui(TvDimens.title,
                  weight: FontWeight.w600, color: const Color(0xFF1A1206))),
        );
      },
    );
  }
}

/// État vide soigné : carré or léger + titre Oswald + sous-texte gris.
class TvEmptyState extends StatelessWidget {
  const TvEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

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
              gradient: TvTokens.pillGradient,
              border: Border.all(color: TvTokens.line),
              borderRadius: BorderRadius.circular(TvTokens.rButton),
            ),
            child: Icon(icon, color: TvTokens.gold, size: 38),
          ),
          const SizedBox(height: 22),
          Text(title, style: TvTokens.display(34, color: TvTokens.text)),
          const SizedBox(height: 10),
          SizedBox(
            width: 460,
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TvTokens.ui(16, color: TvTokens.mutedDim)),
          ),
        ],
      ),
    );
  }
}
