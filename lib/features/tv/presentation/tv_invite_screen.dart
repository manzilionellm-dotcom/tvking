// =========================================================
//  tv_invite_screen.dart — PARTAGE (« regarder ensemble ») sur TV
// =========================================================
//  Hub à 3 options :
//    • 🎁 Inviter un ami — l'abonné payé choisit une CHAÎNE + une DURÉE
//      (24 h / 48 h) et connecte l'ami par CODE ou par sa MAC → l'ami regarde
//      la chaîne partagée, puis doit s'abonner.
//    • 🔁 Entre MES appareils — déplace l'abonnement payé vers un autre de ses
//      appareils (jamais en même temps).
//    • 📥 J'ai un code — l'invité tape le code reçu → accès + chaîne.
//
//  Tout passe par InviteBackend (worker). Aucun contact lecteur. Télécommande.
// =========================================================
import 'package:flutter/material.dart';

import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../subscription/data/invite_backend.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart' show TvLogo;

class TvInviteScreen extends StatefulWidget {
  const TvInviteScreen({super.key});

  @override
  State<TvInviteScreen> createState() => _TvInviteScreenState();
}

class _TvInviteScreenState extends State<TvInviteScreen> {
  String _mac = '';
  String _view = 'hub'; // hub | invite | transfer | redeem

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
  }

  void _go(String v) => setState(() => _view = v);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
        child: switch (_view) {
          'invite' => _InviteFlow(mac: _mac, onBack: () => _go('hub')),
          'transfer' => _TransferFlow(mac: _mac, onBack: () => _go('hub')),
          'redeem' => _RedeemFlow(mac: _mac, onBack: () => _go('hub')),
          _ => _hub(),
        },
      ),
    );
  }

  Widget _hub() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Partage',
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w800, color: TvTokens.text)),
        const SizedBox(height: 6),
        const Text('Fais profiter un ami, ou passe d’un de tes appareils à l’autre.',
            style: TextStyle(fontSize: 15, color: TvTokens.muted)),
        const SizedBox(height: 26),
        _HubOption(
          emoji: '🎁',
          title: 'Inviter un ami',
          subtitle:
              'Il regarde le match avec toi — 24 h ou 48 h offertes, puis il s’abonne.',
          autofocus: true,
          onSelect: () => _go('invite'),
        ),
        const SizedBox(height: 14),
        _HubOption(
          emoji: '🔁',
          title: 'Entre mes appareils',
          subtitle:
              'Déplace ton abonnement vers ta TV, ton laptop, ton téléphone (un seul à la fois).',
          onSelect: () => _go('transfer'),
        ),
        const SizedBox(height: 14),
        _HubOption(
          emoji: '📥',
          title: 'J’ai un code',
          subtitle: 'Un ami t’a donné un code ? Entre-le ici.',
          onSelect: () => _go('redeem'),
        ),
      ],
    );
  }
}

// =========================================================
//  🎁 INVITER UN AMI
// =========================================================
class _InviteFlow extends StatefulWidget {
  const _InviteFlow({required this.mac, required this.onBack});
  final String mac;
  final VoidCallback onBack;

  @override
  State<_InviteFlow> createState() => _InviteFlowState();
}

class _InviteFlowState extends State<_InviteFlow> {
  int _hours = 48;
  Channel? _channel;
  bool _busy = false;
  String? _code;
  int _weeklyUsed = 0;
  int _weeklyQuota = 5;
  String? _message;
  final TextEditingController _friendMac = TextEditingController();

  bool get _canInvite =>
      SubscriptionState.instance.status == SubscriptionStatus.paid;

  @override
  void dispose() {
    _friendMac.dispose();
    super.dispose();
  }

  Map<String, Object?>? get _channelPayload => _channel == null
      ? null
      : <String, Object?>{
          'name': _channel!.name,
          'streamUrl': _channel!.streamUrl,
          'logoUrl': _channel!.logoUrl,
          'category': _channel!.category,
        };

  Future<void> _pickChannel() async {
    final Channel? c = await showModalBottomSheet<Channel>(
      context: context,
      backgroundColor: TvTokens.bg,
      isScrollControlled: true,
      builder: (BuildContext ctx) => const _ChannelPicker(),
    );
    if (c != null && mounted) setState(() => _channel = c);
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    final Map<String, dynamic>? r = await InviteBackend.create(
      widget.mac,
      hours: _hours,
      channel: _channelPayload,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _code = (r['code'] ?? '').toString();
        _weeklyUsed = (r['weekly_used'] as num?)?.toInt() ?? _weeklyUsed;
        _weeklyQuota = (r['weekly_quota'] as num?)?.toInt() ?? _weeklyQuota;
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
  }

  Future<void> _grantByMac() async {
    final String g = _normalizeMac(_friendMac.text);
    if (g.isEmpty) { setState(() => _message = 'Entre la MAC de ton ami.'); return; }
    setState(() { _busy = true; _message = null; });
    final Map<String, dynamic>? r = await InviteBackend.grant(
      widget.mac, g, hours: _hours, channel: _channelPayload,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _message = 'Activé ! Ton ami a $_hours h pour regarder avec toi. 🎉';
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
  }

  String _errText(String e) => switch (e) {
        'not_paid' =>
          'Le partage est réservé aux abonnés. Active ton abonnement d’abord.',
        'issuer_quota' =>
          'Tu as utilisé tes 5 invitations de la semaine. Ça se renouvelle bientôt.',
        'already_active' => 'Cet appareil a déjà un accès actif.',
        'already_used_once' =>
          'Cet appareil a déjà profité d’un pass gratuit.',
        'own_code' => 'C’est ta propre adresse 🙂',
        _ => 'Action impossible pour le moment.',
      };

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: 'Inviter un ami',
      onBack: widget.onBack,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!_canInvite)
              _note('Réservé aux abonnés. Une fois abonné, tu auras '
                  '$_weeklyQuota invitations CHAQUE SEMAINE à partager.'),
            // 1) Durée
            const _StepLabel('1 · Durée offerte'),
            Row(children: <Widget>[
              _Chip(label: '24 heures', on: _hours == 24, onSelect: () => setState(() => _hours = 24)),
              const SizedBox(width: 12),
              _Chip(label: '48 heures', on: _hours == 48, onSelect: () => setState(() => _hours = 48)),
            ]),
            const SizedBox(height: 20),
            // 2) Chaîne
            const _StepLabel('2 · Chaîne à regarder ensemble'),
            _BigButton(
              icon: Icons.live_tv_rounded,
              label: _channel == null ? 'Choisir une chaîne' : _channel!.cleanName,
              onSelect: _pickChannel,
            ),
            const SizedBox(height: 20),
            // 3) Connexion
            const _StepLabel('3 · Connecter ton ami'),
            if (_code != null) ...<Widget>[
              _codeBox(_code!),
              const SizedBox(height: 8),
              Text('Cette semaine : $_weeklyUsed / $_weeklyQuota · code valable 48 h',
                  style: const TextStyle(fontSize: 13, color: TvTokens.mutedDim)),
              const SizedBox(height: 14),
            ],
            _BigButton(
              icon: Icons.qr_code_2_rounded,
              label: _busy ? 'Patiente…' : (_code == null ? 'Générer un code' : 'Nouveau code'),
              autofocus: true,
              onSelect: _busy ? null : _generate,
            ),
            const SizedBox(height: 16),
            const Text('— ou active-le directement par sa MAC —',
                style: TextStyle(fontSize: 13, color: TvTokens.mutedDim)),
            const SizedBox(height: 10),
            _MacField(controller: _friendMac, hint: 'MAC de l’ami (ex. MK:1A:2B:3C:4D:5E)'),
            const SizedBox(height: 10),
            _BigButton(
              icon: Icons.bolt_rounded,
              label: _busy ? 'Patiente…' : 'Activer par MAC',
              onSelect: _busy ? null : _grantByMac,
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 16),
              _note(_message!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _codeBox(String code) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          border: Border.all(color: TvTokens.gold),
        ),
        child: Text(code.split('').join(' '),
            style: const TextStyle(
                fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 6,
                color: TvTokens.goldBright)),
      );

  Widget _note(String s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TvTokens.card.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          border: Border.all(color: TvTokens.lineSoft),
        ),
        child: Text(s, style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
      );
}

// =========================================================
//  🔁 ENTRE MES APPAREILS
// =========================================================
class _TransferFlow extends StatefulWidget {
  const _TransferFlow({required this.mac, required this.onBack});
  final String mac;
  final VoidCallback onBack;

  @override
  State<_TransferFlow> createState() => _TransferFlowState();
}

class _TransferFlowState extends State<_TransferFlow> {
  final TextEditingController _target = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _transfer() async {
    final String t = _normalizeMac(_target.text);
    if (t.isEmpty) { setState(() => _message = 'Entre la MAC de l’appareil cible.'); return; }
    setState(() { _busy = true; _message = null; });
    final Map<String, dynamic>? r = await InviteBackend.transfer(widget.mac, t);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _message = 'C’est fait ! Ton abonnement est passé sur l’autre appareil. '
            'CET appareil est en pause jusqu’au prochain transfert.';
      } else {
        _message = switch ((r['error'] ?? '').toString()) {
          'not_paid' => 'Réservé aux appareils payés (abonnement à l’année).',
          'same_device' => 'C’est déjà cet appareil 🙂',
          _ => 'Transfert impossible pour le moment.',
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: 'Entre mes appareils',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Déplace ton abonnement vers un autre de tes appareils. Un seul '
            'appareil regarde à la fois — tu peux le ramener quand tu veux.',
            style: TextStyle(fontSize: 15, color: TvTokens.muted),
          ),
          const SizedBox(height: 20),
          const _StepLabel('MAC de l’appareil cible'),
          _MacField(controller: _target, hint: 'MAC (visible dans Réglages de l’autre appareil)'),
          const SizedBox(height: 14),
          _BigButton(
            icon: Icons.swap_horiz_rounded,
            label: _busy ? 'Transfert…' : 'Transférer ici → là-bas',
            autofocus: true,
            onSelect: _busy ? null : _transfer,
          ),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_message!, style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
          ],
        ],
      ),
    );
  }
}

// =========================================================
//  📥 J'AI UN CODE
// =========================================================
class _RedeemFlow extends StatefulWidget {
  const _RedeemFlow({required this.mac, required this.onBack});
  final String mac;
  final VoidCallback onBack;

  @override
  State<_RedeemFlow> createState() => _RedeemFlowState();
}

class _RedeemFlowState extends State<_RedeemFlow> {
  String _entry = '';
  bool _busy = false;
  bool _ok = false;
  String? _message;

  void _type(String d) {
    if (_busy || _ok || _entry.length >= 6) return;
    setState(() { _entry += d; _message = null; });
    if (_entry.length == 6) _submit();
  }

  void _back() {
    if (_busy || _ok || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _entry.length != 6) return;
    setState(() => _busy = true);
    final Map<String, dynamic>? r = await InviteBackend.redeem(widget.mac, _entry);
    if (!mounted) return;
    if (r != null && r['ok'] == true) {
      setState(() {
        _busy = false; _ok = true;
        _message = 'C’est bon ! Profite du match. À la fin, tu pourras t’abonner pour continuer. 🎉';
      });
      await SubscriptionState.instance.syncWithBackend();
      return;
    }
    setState(() {
      _busy = false; _entry = '';
      _message = switch ((r?['error'] ?? '').toString()) {
        'code_invalid' => 'Code inconnu. Vérifie les 6 chiffres.',
        'code_used' => 'Ce code a déjà été utilisé.',
        'code_expired' => 'Ce code a expiré. Demande-en un nouveau.',
        'own_code' => 'C’est ton propre code 🙂',
        'issuer_not_paid' => 'L’abonnement de ton ami n’est plus actif.',
        'issuer_quota' => 'Ton ami a atteint ses 5 invitations de la semaine.',
        'already_active' => 'Ton appareil a déjà un accès actif.',
        'already_used_once' =>
          'Tu as déjà profité d’un pass gratuit. Pour continuer, abonne-toi.',
        _ => 'Impossible d’activer ce code.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final String shown = List<String>.generate(
        6, (int i) => i < _entry.length ? _entry[i] : '·').join(' ');
    return _FlowScaffold(
      title: 'J’ai un code',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Tape le code que ton ami t’a donné.',
              style: TextStyle(fontSize: 15, color: TvTokens.muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: TvTokens.card,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(color: _ok ? TvTokens.success : TvTokens.gold),
            ),
            child: Text(shown,
                style: TextStyle(
                    fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 6,
                    color: _ok ? TvTokens.success : TvTokens.goldBright)),
          ),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_message!,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: _ok ? TvTokens.success : TvTokens.muted)),
          ],
          const SizedBox(height: 16),
          if (!_ok)
            Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
              for (int d = 1; d <= 9; d++) _Key('$d', onSelect: () => _type('$d')),
              _Key('0', onSelect: () => _type('0')),
              _Key('⌫', onSelect: _back),
            ]),
        ],
      ),
    );
  }
}

// =========================================================
//  Briques communes
// =========================================================
String _normalizeMac(String raw) {
  final String hex = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hex.length != 12) return '';
  final List<String> p = <String>[];
  for (int i = 0; i < 12; i += 2) p.add(hex.substring(i, i + 2));
  return 'MK:${p.join(':')}';
}

class _FlowScaffold extends StatelessWidget {
  const _FlowScaffold(
      {required this.title, required this.onBack, required this.child});
  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          TvFocusBuilder(
            scale: TvFocusScale.small,
            onSelect: onBack,
            builder: (BuildContext c, bool f) => Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: f ? TvTokens.sel : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: f ? Border.all(color: TvTokens.gold) : null,
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: f ? TvTokens.goldBright : TvTokens.muted, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: TvTokens.text)),
          const Spacer(),
          const TvLogo(width: 78),
        ]),
        const SizedBox(height: 20),
        Expanded(child: child),
      ],
    );
  }
}

class _HubOption extends StatelessWidget {
  const _HubOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.goldBright : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(TvDimens.panelRadius),
            border: Border.all(color: focused ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w800, color: fg)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: focused ? TvTokens.goldBright : TvTokens.muted, size: 26),
          ]),
        );
      },
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2,
                color: TvTokens.mutedDim)),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onSelect});
  final String label;
  final bool on;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext c, bool f) {
        final Color bg = f ? TvTokens.gold : (on ? TvTokens.sel : TvTokens.card);
        final Color fg = f ? const Color(0xFF1A1206) : (on ? TvTokens.goldBright : TvTokens.text);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(color: on || f ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
        );
      },
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton(
      {required this.icon, required this.label, required this.onSelect, this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;
  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
          ]),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label, {required this.onSelect});
  final String label;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext c, bool f) => Container(
        width: 60,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: f ? TvTokens.gold : TvTokens.sel,
          borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: f ? const Color(0xFF1A1206) : TvTokens.text)),
      ),
    );
  }
}

/// Champ MAC : on ouvre le clavier système Android TV via un TextField focus.
class _MacField extends StatelessWidget {
  const _MacField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
            color: TvTokens.text, fontSize: 20, fontWeight: FontWeight.w700,
            letterSpacing: 1.5),
        cursorColor: TvTokens.gold,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: TvTokens.mutedDim, fontSize: 14),
        ),
      ),
    );
  }
}

/// Sélecteur de chaîne : la liste des chaînes chargées de l'inviteur.
class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker();
  @override
  Widget build(BuildContext context) {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    return Container(
      height: 560,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: TvTokens.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Choisir la chaîne à partager',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: TvTokens.text)),
          const SizedBox(height: 14),
          Expanded(
            child: all.isEmpty
                ? const Center(
                    child: Text('Aucune chaîne chargée.',
                        style: TextStyle(color: TvTokens.muted, fontSize: 16)))
                : ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (BuildContext c, int i) {
                      final Channel ch = all[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TvFocusBuilder(
                          autofocus: i == 0,
                          scale: TvFocusScale.small,
                          onSelect: () => Navigator.of(context).pop(ch),
                          builder: (BuildContext c, bool f) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: f ? TvTokens.gold : TvTokens.card,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: <Widget>[
                              TvChannelLogo(
                                  logoUrl: ch.logoUrl, label: ch.name, size: 40, radius: 8),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(ch.cleanName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.w700,
                                        color: f ? const Color(0xFF1A1206) : TvTokens.text)),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
