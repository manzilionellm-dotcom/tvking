// =========================================================
//  web_cast_setup_sheet.dart — Setup du cast via navigateur
// =========================================================
//  Sheet qui s'affiche quand l'utilisateur choisit "Cast vers
//  une TV via navigateur". On démarre le mini-serveur HTTP
//  local, on récupère l'IP du téléphone sur le WiFi, et on
//  affiche un QR code + l'URL en texte pour que l'utilisateur
//  l'ouvre sur sa TV.
//
//  Une fois la TV connectée, chaque chaîne lancée depuis le
//  téléphone sera reprise par la TV en ~2s (polling JS).
// =========================================================

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/cast_manager.dart';
import '../data/local_cast_server.dart';
import '../domain/cast_device.dart';

Future<void> showWebCastSetup(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _WebCastSetupSheet(),
  );
}

class _WebCastSetupSheet extends StatefulWidget {
  const _WebCastSetupSheet();

  @override
  State<_WebCastSetupSheet> createState() => _WebCastSetupSheetState();
}

class _WebCastSetupSheetState extends State<_WebCastSetupSheet> {
  String? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final int port = await LocalCastServer.instance.start();
      final String? ip = await _detectWifiIp();
      if (!mounted) return;
      if (ip == null) {
        setState(() {
          _error = 'Impossible de détecter ton IP WiFi. Vérifie que '
              'tu es bien connecté à un WiFi (pas en données mobiles).';
        });
        return;
      }
      final String url = 'http://$ip:$port/';
      setState(() {
        _url = url;
        _error = null;
      });

      // On crée un "device virtuel" et on le sélectionne immédiatement.
      // Comme ça, à la fermeture de la sheet, tout tap sur une chaîne
      // pousse l'URL sur le serveur → la TV la reprend en ~2s.
      final CastDevice virtual = CastDevice(
        id: 'web-browser-$ip-$port',
        name: 'TV via navigateur',
        kind: CastDeviceKind.webBrowser,
        host: ip,
        port: port,
        controlUrl: url,
        manufacturer: 'Web',
        model: 'HTML5',
      );
      CastManager.instance.selectDevice(virtual);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur : $e');
    }
  }

  Future<String?> _detectWifiIp() async {
    // 1) Tente network_info_plus (le plus précis quand ça marche)
    try {
      final NetworkInfo info = NetworkInfo();
      final String? ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') return ip;
    } catch (_) {}

    // 2) Fallback sans permission : on liste les interfaces réseau
    //    et on prend la 1ère IPv4 privée (192.168.x.x / 10.x.x.x /
    //    172.16-31.x.x). Marche sans la permission ACCESS_WIFI_STATE
    //    sur Android 10+.
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
    if (ip.startsWith('172.')) {
      final List<String> parts = ip.split('.');
      if (parts.length >= 2) {
        final int second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  Future<void> _copyUrl() async {
    if (_url == null) return;
    await Clipboard.setData(ClipboardData(text: _url!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('URL copiée : $_url'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.of(context).size.height * 0.85;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Icon(Icons.qr_code_rounded,
                          color: AppColors.accent, size: 22),
                      const SizedBox(width: 10),
                      Text('Cast via navigateur',
                          style: AppTextStyles.headlineMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Marche sur n\'importe quelle TV qui a un navigateur web '
                    '— Google TV, Samsung, LG, Hisense, vieilles smart TVs. '
                    'Ta TV doit être sur le même WiFi que le téléphone.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    _errorCard(_error!)
                  else if (_url == null)
                    const _Loading()
                  else ...<Widget>[
                    _qrCard(_url!),
                    const SizedBox(height: 14),
                    _urlCard(_url!),
                    const SizedBox(height: 14),
                    _instructions(),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _url == null
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('OK, la TV est connectée'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrCard(String url) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: QrImageView(
          data: url,
          size: 220,
          backgroundColor: Colors.white,
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
    );
  }

  Widget _urlCard(String url) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Ou tape cette URL dans le navigateur de la TV :',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  url,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyUrl,
          ),
        ],
      ),
    );
  }

  Widget _instructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _step('1', 'Sur ta TV, ouvre son navigateur web'),
          _step('2', 'Scanne le QR code ci-dessus (ou tape l\'URL)'),
          _step('3', 'Garde cet onglet ouvert sur la TV'),
          _step(
            '4',
            'Reviens ici, tape une chaîne → elle apparaît sur la TV en 2s',
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
            ),
            alignment: Alignment.center,
            child: Text(
              n,
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded,
              color: AppColors.live, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
