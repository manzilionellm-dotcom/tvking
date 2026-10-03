// =========================================================
//  tv_phone_source_qr.dart — QR « ajoutez votre abonnement »
// =========================================================
//  Premier lancement, ou aucune source sur la box : la télé
//  montre un QR. Le téléphone le photographie et ouvre la page
//  déjà hébergée (/mon-espace). Là, la personne saisit son lien
//  M3U ou ses identifiants Xtream. Les chaînes reviennent sur
//  CETTE box, via le code court déclaré juste avant.
//
//  TvOwnSourceQr dessine. TvPhoneSourceQr parle au Worker et
//  renouvelle le code avant les 20 minutes (toutes les 15).
//  Aucune adresse de flux n'est écrite ici.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import '../data/home_source_pair.dart';

/// Dessin du QR et des phrases. [url] null : la phrase reste, le
/// carré attend que la MAC soit connue.
class TvOwnSourceQr extends StatelessWidget {
  const TvOwnSourceQr({
    super.key,
    this.url,
    this.code,
    this.qrSize = 168,
  });

  final String? url;
  final String? code;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final bool showQr = url != null && url!.isNotEmpty;
    return SizedBox(
      width: qrSize + 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            context.l10n.tvNoChannelsSold,
            textAlign: TextAlign.center,
            style: TvTokens.ui(
              TvDimens.label,
              weight: FontWeight.w700,
              color: TvTokens.text,
            ),
          ),
          if (showQr) ...<Widget>[
            const SizedBox(height: 14),
            // Fond blanc : un QR se scanne en sombre sur clair.
            // Les modules prennent l'encre déjà définie (onAccent),
            // pas une couleur inventée pour cet écran.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border: Border.all(color: TvTokens.accent, width: 2),
              ),
              child: QrImageView(
                data: url!,
                version: QrVersions.auto,
                size: qrSize,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: TvTokens.onAccent,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: TvTokens.onAccent,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            context.l10n.tvScanSourceHelp,
            textAlign: TextAlign.center,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
          ),
          if (code != null && code!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              context.l10n.tvScanSourceCode(code!),
              textAlign: TextAlign.center,
              style: TvTokens.mono(TvDimens.label),
            ),
          ],
        ],
      ),
    );
  }
}

/// Déclare le code court et l'affiche. Le renouvellement évite
/// qu'un code expiré reste à l'écran si la personne tarde.
class TvPhoneSourceQr extends StatefulWidget {
  const TvPhoneSourceQr({super.key, required this.mac, this.qrSize = 168});

  final String mac;
  final double qrSize;

  @override
  State<TvPhoneSourceQr> createState() => _TvPhoneSourceQrState();
}

class _TvPhoneSourceQrState extends State<TvPhoneSourceQr> {
  Timer? _renew;
  int _gen = 0;
  String? _url;
  String? _code;

  @override
  void initState() {
    super.initState();
    // 15 minutes : le Worker garde le code 20 minutes. On le
    // remplace avant qu'il tombe, tant que cet écran est visible.
    _renew = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(_publish());
    });
    unawaited(_publish());
  }

  @override
  void didUpdateWidget(TvPhoneSourceQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mac != widget.mac) unawaited(_publish());
  }

  @override
  void dispose() {
    _renew?.cancel();
    super.dispose();
  }

  Future<void> _publish() async {
    final int gen = ++_gen;
    final HomeSourceLink? link = await publishHomeSourceLink(mac: widget.mac);
    if (!mounted || gen != _gen) return;
    setState(() {
      _url = link?.url;
      _code = link?.code;
    });
    if (link != null) {
      // Pas le lien : il contient le code court.
      BlackBox.instance.info('SOURCE', 'QR téléphone prêt');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvOwnSourceQr(url: _url, code: _code, qrSize: widget.qrSize);
  }
}
