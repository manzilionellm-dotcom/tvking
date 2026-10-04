// =========================================================
//  panel_button.dart — Bouton des cartes venues du panel
// =========================================================
//  Même dessin que les boutons du bandeau « Tes émissions » :
//  une pilule sombre, l'or au focus (TvFocusable). Rien d'autre.
// =========================================================

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';

class PanelButton extends StatelessWidget {
  const PanelButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon,
  });

  final String label;
  final VoidCallback onSelect;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: TvTokens.sel,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: TvTokens.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: TvTokens.text),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TvTokens.ui(
                TvDimens.label,
                weight: FontWeight.w700,
                color: TvTokens.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petit QR sur fond clair, pour le téléphone (un lien ne s'ouvre pas
/// sur une télé). [size] en px logiques.
class PanelQr extends StatelessWidget {
  const PanelQr({super.key, required this.data, this.size = 96});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
      ),
      // qr_flutter est déjà dans l'app (QR WhatsApp, QR « Mon espace »).
      child: QrImageView(
        data: data,
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
    );
  }
}
