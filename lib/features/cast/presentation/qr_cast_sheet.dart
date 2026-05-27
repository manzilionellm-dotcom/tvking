// =========================================================
//  qr_cast_sheet.dart — Cast par QR Code (multi-device)
// =========================================================
//  Bottom sheet qui génère un QR code permettant à n'importe quel
//  autre appareil (TV, ordi, tablette, autre tel) de lire le flux
//  en cours via son navigateur.
//
//  COMMENT ÇA MARCHE
//  ─────────────────
//  Le QR ne pointe PAS vers l'URL brute du flux IPTV — un navigateur
//  classique ne sait pas lire `.m3u8` / `.ts` natif. À la place, on
//  démarre le mini-serveur HTTP local (`LocalCastServer`) et on
//  encode dans le QR une URL du type :
//
//      http://<ip-LAN>:<port>/?url=<flux>&title=<chaîne>
//
//  Quand l'ordi scanne le QR, il atterrit sur la PAGE HTML5 du
//  serveur local — page qui embarque hls.js + mpegts.js (CDN
//  jsDelivr) et joue n'importe quel flux IPTV directement dans le
//  navigateur, sans installer VLC ni rien.
//
//  Avantages vs Chromecast classique :
//    - Marche avec TOUT device qui a une caméra + un navigateur
//    - Marche cross-OS : iPad scanne le QR Android, etc.
//    - Pas de mDNS / UPnP / Cast SDK
//    - On peut aussi copier l'URL et la coller dans VLC pour
//      les browsers qui n'ont pas MediaSource API
// =========================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/local_cast_server.dart';

/// Ouvre la sheet QR. `streamUrl` est l'URL absolue du flux
/// (M3U8 / TS / MP4) et `channelName` le nom affiché en bas.
Future<void> showQrCastSheet(
  BuildContext context, {
  required String streamUrl,
  required String channelName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        top: false,
        child: _QrCastBody(
          streamUrl: streamUrl,
          channelName: channelName,
        ),
      );
    },
  );
}

class _QrCastBody extends StatefulWidget {
  const _QrCastBody({
    required this.streamUrl,
    required this.channelName,
  });

  final String streamUrl;
  final String channelName;

  @override
  State<_QrCastBody> createState() => _QrCastBodyState();
}

class _QrCastBodyState extends State<_QrCastBody> {
  /// URL finale encodée dans le QR. Null tant que le serveur local
  /// n'a pas démarré + qu'on n'a pas trouvé l'IP LAN.
  String? _qrPayload;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Démarre le serveur local et construit l'URL à encoder. Si on
  /// ne trouve pas d'IP LAN (pas connecté au WiFi), on tombe sur le
  /// fallback "URL brute du flux" (utile pour scan→VLC sur ordi).
  Future<void> _bootstrap() async {
    try {
      final int port = await LocalCastServer.instance.start();
      final String? lanIp = await _detectWifiIp();
      if (!mounted) return;
      if (lanIp == null) {
        // Sans IP LAN on ne peut pas construire d'URL serveur ;
        // on tombe sur l'URL brute du flux. L'ordi devra utiliser
        // VLC ou un autre lecteur capable de lire les flux IPTV.
        setState(() => _qrPayload = widget.streamUrl);
        return;
      }
      // Encoder URL + titre dans le query string pour que la page
      // HTML5 du serveur les pioche au démarrage et joue direct.
      final Uri url = Uri(
        scheme: 'http',
        host: lanIp,
        port: port,
        path: '/',
        queryParameters: <String, String>{
          'url': widget.streamUrl,
          'title': widget.channelName,
        },
      );
      setState(() => _qrPayload = url.toString());
    } catch (e) {
      if (!mounted) return;
      // En cas d'erreur (port pris, pas de réseau...), on tombe sur
      // l'URL brute — au moins l'option "Copier dans VLC" marche.
      setState(() {
        _qrPayload = widget.streamUrl;
        _error = 'Mode dégradé : ouvre dans VLC ou un lecteur natif.';
      });
    }
  }

  /// Trouve la 1ère IPv4 privée du téléphone (192.168.x.x,
  /// 10.x.x.x, 172.16-31.x.x). Réutilise la même logique que
  /// `web_cast_setup_sheet.dart` — peut être extrait plus tard
  /// vers un helper transverse.
  Future<String?> _detectWifiIp() async {
    try {
      final NetworkInfo info = NetworkInfo();
      final String? ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') return ip;
    } catch (_) {}
    try {
      final List<NetworkInterface> ifaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final NetworkInterface iface in ifaces) {
        for (final InternetAddress addr in iface.addresses) {
          final String ip = addr.address;
          if (_isPrivateIPv4(ip)) return ip;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isPrivateIPv4(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final RegExp seventeen = RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.');
    return seventeen.hasMatch(ip);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ----- Drag handle -----
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ----- Header -----
          Row(
            children: <Widget>[
              Icon(Icons.qr_code_2_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cast par QR Code',
                  style: AppTextStyles.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Scanne ce code depuis n\'importe quel appareil '
            '(TV, ordi, tablette, autre téléphone) — la chaîne '
            's\'ouvre directement dans le navigateur.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          // ----- QR centré (ou loader si pas encore prêt) -----
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: _qrPayload == null
                  ? const SizedBox(
                      width: 260,
                      height: 260,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : QrImageView(
                      data: _qrPayload!,
                      size: 260,
                      version: QrVersions.auto,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      gapless: true,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),

          // ----- Nom de la chaîne -----
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              widget.channelName,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          // ----- Copier l'URL (fallback) -----
          OutlinedButton.icon(
            onPressed: _qrPayload == null
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: _qrPayload!),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.surfaceHigh,
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        duration: const Duration(seconds: 2),
                        content: Text(
                          'Lien copié — colle dans le navigateur '
                          'ou VLC',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier le lien'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ----- Tip d'usage -----
          Text(
            _error ??
                'Astuce : ouvre l\'appareil photo de ton autre device, '
                    'pointe vers ce QR — un lien apparaît. Tape dessus, '
                    'le navigateur lance la chaîne automatiquement.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 10.5,
              color: _error != null
                  ? AppColors.warning
                  : AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),

          // ----- Rappel WiFi (visible uniquement si on a bien
          //       construit une URL LAN, pas en mode dégradé) -----
          if (_qrPayload != null && _error == null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '⚠️ L\'appareil qui scanne doit être sur le MÊME WiFi '
              'que ton téléphone.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 10.5,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
