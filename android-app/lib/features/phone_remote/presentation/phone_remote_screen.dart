// =========================================================
//  phone_remote_screen.dart — QR pour le téléphone
// =========================================================
//  Le QR reprend l'adresse du mini-serveur. On réutilise
//  `qr_flutter`, déjà dans le projet pour le cast : pas de
//  nouvelle dépendance. Si le serveur ne part pas, on
//  l'écrit en clair. Aucune chaîne n'est ouverte ici.
// =========================================================

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../box_extras/box_text.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../data/phone_remote_session.dart';

class PhoneRemoteScreen extends StatefulWidget {
  const PhoneRemoteScreen({super.key});

  @override
  State<PhoneRemoteScreen> createState() => _PhoneRemoteScreenState();
}

class _PhoneRemoteScreenState extends State<PhoneRemoteScreen> {
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await PhoneRemoteSession.instance.ensureStarted();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle() async {
    final bool next = !PhoneRemoteSession.flag.value;
    await PhoneRemoteSession.flag.set(next);
    if (next) {
      await PhoneRemoteSession.instance.ensureStarted();
    } else {
      await PhoneRemoteSession.instance.stop();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final PhoneRemoteSession session = PhoneRemoteSession.instance;
    final bool on = PhoneRemoteSession.flag.value;
    final String? url = session.url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          boxText(context, 'Téléphone', 'Phone'),
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          boxText(
            context,
            'Scanne le QR avec l\'appareil photo. Le téléphone et la box doivent être sur le même Wi-Fi. Ça ne lance pas de chaîne.',
            'Scan the QR with the camera. The phone and the box must share Wi-Fi. This does not start a channel.',
          ),
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 16),
        TvFocusable(
          autofocus: true,
          onSelect: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              on
                  ? boxText(context, 'Allumé — OK pour couper', 'On — OK to turn off')
                  : boxText(context, 'Coupé — OK pour allumer', 'Off — OK to turn on'),
              style: TextStyle(
                fontSize: TvDimens.titleS,
                fontWeight: FontWeight.w700,
                color: TvTokens.text,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_busy)
          const CircularProgressIndicator(color: TvTokens.accent)
        else if (!on)
          Text(
            boxText(
              context,
              'La télécommande téléphone est coupée.',
              'The phone remote is off.',
            ),
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
          )
        else if (url == null)
          Text(
            _errorText(context, session.error),
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ColoredBox(
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  size: 280,
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
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  url,
                  style: TextStyle(
                    fontSize: TvDimens.label,
                    color: TvTokens.accentBright,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _errorText(BuildContext context, String? error) {
    if (error == 'no-ip') {
      return boxText(
        context,
        'Pas d\'adresse Wi-Fi. Branche la box au réseau, puis reviens. La chaîne n\'est pas touchée.',
        'No Wi-Fi address. Connect the box, then come back. The channel is untouched.',
      );
    }
    return boxText(
      context,
      'Le téléphone ne peut pas se brancher pour le moment. La chaîne n\'est pas touchée.',
      'The phone cannot connect right now. The channel is untouched.',
    );
  }
}
