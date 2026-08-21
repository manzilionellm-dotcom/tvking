// =========================================================
//  tv_help_screen.dart — « Aide & contact » (Réglages TV)
// =========================================================
//  Demande propriétaire (21/08) : l'aide de l'app doit pointer sur le
//  canal de MESSAGERIE du support (wa.me — le mot « WhatsApp » n'est
//  jamais écrit côté UI, règle du support_choice_sheet) OU sur le site
//  web ; le site, lui, pointe déjà sur la messagerie.
//
//  Sur une TV on ne peut pas « ouvrir » ces liens : on affiche DEUX QR
//  à scanner avec le téléphone, plus les adresses en clair (secours si
//  l'appareil photo ne coopère pas) :
//    • Nous écrire  → wa.me/<numéro> avec un message pré-rempli qui
//      contient le CODE de l'appareil (le support sait tout de suite
//      quelle box appelle à l'aide) ;
//    • Notre site   → https://app.7themotion.com.
//
//  Réutilise les briques existantes : kWhatsAppPhone (tv_components),
//  DeviceIdentity (le code), TvShell/TvTokens (habillage), QrImageView
//  (déjà dans l'app pour l'activation). 100 % télécommande : un seul
//  élément focusable (Retour), les QR se scannent, ne se cliquent pas.
// =========================================================
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../device/data/device_identity.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

/// Site public — même adresse que les liens de téléchargement clients.
const String kTvHelpWebsiteUrl = 'https://app.7themotion.com';

class TvHelpScreen extends StatefulWidget {
  const TvHelpScreen({super.key});

  @override
  State<TvHelpScreen> createState() => _TvHelpScreenState();
}

class _TvHelpScreenState extends State<TvHelpScreen> {
  String _mac = '…';

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
  }

  /// Lien messagerie avec le code de l'appareil pré-rempli — français
  /// assumé (même choix que tvWhatsAppUrl : le message part au support,
  /// pas au client).
  String get _messageUrl {
    final String code = (_mac == '…' || _mac.isEmpty) ? '' : _mac;
    final String msg = Uri.encodeComponent(
        'Bonjour, j\'ai besoin d\'aide avec l\'app TV.'
        '${code.isEmpty ? '' : ' Mon code : $code'}');
    return 'https://wa.me/$kWhatsAppPhone?text=$msg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(context.l10n.tvHelpTitle,
                  style: TvTokens.ui(30,
                      weight: FontWeight.w800, color: TvTokens.text)),
              const SizedBox(height: 8),
              Text(context.l10n.tvScanHelp,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(14, color: TvTokens.mutedDim)),
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _QrPanel(
                    data: _messageUrl,
                    icon: Icons.forum_rounded,
                    title: context.l10n.tvHelpScanWrite,
                    subtitle: '+$kWhatsAppPhone',
                  ),
                  const SizedBox(width: 40),
                  _QrPanel(
                    data: kTvHelpWebsiteUrl,
                    icon: Icons.language_rounded,
                    title: context.l10n.tvHelpWebsite,
                    subtitle: 'app.7themotion.com',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Le code de l'appareil en clair : le support le demande
              // toujours — autant l'avoir sous les yeux sans naviguer.
              Text(context.l10n.tvActivationCodeLabel,
                  style: TvTokens.ui(14, color: TvTokens.mutedDim)),
              const SizedBox(height: 4),
              Text(_mac,
                  style: TvTokens.mono(26,
                      color: TvTokens.goldBright, spacing: 2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un QR sur fond clair (un QR se scanne en sombre-sur-clair) + son
/// libellé. Même habillage que le QR d'activation (TvWhatsAppQr).
class _QrPanel extends StatelessWidget {
  const _QrPanel({
    required this.data,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String data;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.gold, width: 2),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0B0B0B)),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: TvTokens.goldBright, size: 20),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              child: Text(title,
                  style: TvTokens.ui(15,
                      weight: FontWeight.w700, color: TvTokens.goldBright)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TvTokens.ui(13, color: TvTokens.mutedDim)),
      ],
    );
  }
}
