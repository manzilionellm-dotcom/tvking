import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/mobile_services.dart';
import '../data/background_guide.dart';
import '../data/optional_services.dart';

class MobileServicesHost extends StatefulWidget {
  const MobileServicesHost({super.key, required this.child});
  final Widget child;
  @override
  State<MobileServicesHost> createState() => _MobileServicesHostState();
}

class _MobileServicesHostState extends State<MobileServicesHost>
    with WidgetsBindingObserver {
  Timer? _lease;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(BackgroundGuide.markForeground(true));
    _lease = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(BackgroundGuide.markForeground(true));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(MobileServices.instance.initialize());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(BackgroundGuide.markForeground(_foreground));
  }

  @override
  void dispose() {
    _lease?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(BackgroundGuide.markForeground(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MobileOptionsScreen extends StatefulWidget {
  const MobileOptionsScreen({super.key});
  @override
  State<MobileOptionsScreen> createState() => _MobileOptionsScreenState();
}

class _MobileOptionsScreenState extends State<MobileOptionsScreen> {
  bool _guide = false, _busy = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    BackgroundGuide.enabled().then((bool value) {
      if (mounted) setState(() => _guide = value);
    });
    unawaited(MobileServices.instance.initialize());
  }

  Future<void> _change(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await work();
    } catch (_) {
      if (mounted) setState(() => _error = 'Réglage indisponible. Réessaie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Confort mobile')),
    body: ListenableBuilder(
      listenable: MobileServices.instance,
      builder: (BuildContext context, Widget? child) {
        final MobileServices s = MobileServices.instance;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SwitchListTile(
              title: const Text('Téléchargements en Wi-Fi'),
              subtitle: const Text(
                'Les nouveaux téléchargements attendent une connexion Wi-Fi.',
              ),
              value: s.wifiDownloads,
              onChanged: _busy
                  ? null
                  : (bool v) => _change(() => s.setWifiDownloads(v)),
            ),
            if (Platform.isAndroid)
              SwitchListTile(
                title: const Text('Préparer le guide TV'),
                subtitle: const Text(
                  'Actualisation en arrière-plan sur réseau non limité, lorsque la batterie le permet. Ne démarre pas pendant l’utilisation de l’app.',
                ),
                value: _guide,
                onChanged: _busy
                    ? null
                    : (bool v) => _change(() async {
                        await BackgroundGuide.configure(v);
                        if (mounted) setState(() => _guide = v);
                        if (v) unawaited(s.used('guide_background_enabled'));
                      }),
              ),
            SwitchListTile(
              title: const Text('Animations des petites publicités'),
              subtitle: const Text('Mouvements doux et courts sur l’accueil.'),
              value: s.visualMotion,
              onChanged: _busy
                  ? null
                  : (bool v) => _change(() => s.setVisualMotion(v)),
            ),
            if (MobileServices.posthogKey.isNotEmpty)
              SwitchListTile(
                title: const Text('Aider à améliorer 7MOTION'),
                subtitle: const Text(
                  'Partager l’usage de ces fonctions. Aucun message privé ni lien de lecture n’est envoyé.',
                ),
                value: s.analyticsConsent,
                onChanged: _busy
                    ? null
                    : (bool v) => _change(() => s.setAnalytics(v)),
              ),
            if (VoiceInvitation.configured)
              ListTile(
                leading: const Icon(Icons.headset_mic_outlined),
                title: const Text('Salon vocal privé'),
                subtitle: const Text('Rejoindre avec une invitation'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const VoiceRoomScreen(),
                  ),
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({super.key});
  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  final TextEditingController _code = TextEditingController();
  Room? _room;
  bool _busy = false, _mic = false;
  String _error = '';
  Future<void> _join() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final Room r = await VoiceInvitation.join(_code.text.trim());
      if (!mounted) {
        await r.dispose();
        return;
      }
      setState(() => _room = r);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Invitation expirée ou connexion impossible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    final Room? room = _room;
    if (room != null) unawaited(room.dispose().then((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Salon vocal privé')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Text(
            _room == null ? 'Rejoins tes proches avec leur invitation.' : 'Tu as rejoint le salon. Le micro reste coupé jusqu’à ton choix.',
            style: AppTextStyles.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (_room == null) ...<Widget>[
            TextField(
              controller: _code,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'Code d’invitation'),
            ),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: Text(_busy ? 'Connexion…' : 'Rejoindre'),
            ),
          ] else ...<Widget>[
            SwitchListTile(
              title: const Text('Microphone'),
              value: _mic,
              onChanged: (bool value) async {
                try {
                  await _room?.localParticipant?.setMicrophoneEnabled(value);
                  if (mounted) setState(() => _mic = value);
                } catch (_) {
                  if (mounted)
                    setState(() => _error = 'Microphone indisponible.');
                }
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Quitter le salon'),
            ),
          ],
          if (_error.isNotEmpty)
            Text(
              _error,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.warning,
              ),
            ),
        ],
      ),
    ),
  );
}
