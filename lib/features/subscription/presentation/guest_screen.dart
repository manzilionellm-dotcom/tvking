// =========================================================
//  guest_screen.dart — MODE INVITÉ (mobile)
// =========================================================
//  Pendant MOBILE du hub de partage TV (tv_invite_screen.dart). Toujours
//  accessible côté téléphone (accueil vide ET accueil rempli) car c'est LÀ
//  qu'un nouvel utilisateur « invité » arrive en premier.
//
//  Trois usages, tous branchés sur InviteBackend (worker /api/invite/*) :
//
//   • « J'ai un code »  (invité) — l'ami tape le code à 6 chiffres reçu →
//       il gagne un pass (5 h « ensemble », 24 h « prêt » ou 48 h) puis
//       l'app synchronise son abonnement et charge la source partagée.
//
//   • « Envoyer ma MAC »  (invité sans code) — l'ami montre SON identifiant
//       (MAC) et l'envoie à celui qui l'a invité (WhatsApp / copier). Le
//       parrain l'active alors À DISTANCE par sa MAC (grant) — l'invité n'a
//       rien à taper. C'est le geste demandé : « il envoie sa marque à celui
//       qui l'a invité ».
//
//   • « Inviter un ami »  (abonné payé) — choisit une durée (5 h / 24 h /
//       48 h) et génère un code, OU active directement l'ami par sa MAC.
//
//  Aucune URL de flux en dur, aucune playlist pré-remplie : tout vient du
//  worker et de la playlist déjà chargée par l'abonné.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/support/support_choice_sheet.dart';
import '../../../core/support/vip_support.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../device/data/device_identity.dart';
import '../data/invite_backend.dart';
import '../data/subscription_state.dart';

/// Ouvre le mode invité en plein écran (push classique).
Future<void> openGuestScreen(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const GuestScreen()),
  );
}

class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key});

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  String _mac = '';
  String _macNu = '';

  /// Statut du pass invité de CET appareil (via InviteBackend.mine), s'il en
  /// a un : { active, ms_left, mode, inviter, channel }. Null tant qu'on n'a
  /// pas répondu ; on l'affiche en bandeau « ton accès invité ».
  Map<String, dynamic>? _pass;

  bool get _isPaid =>
      SubscriptionState.instance.status == SubscriptionStatus.paid;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (!mounted) return;
      setState(() {
        _mac = m;
        _macNu = DeviceIdentity.stripPrefix(m);
      });
      _refreshPass();
    });
  }

  Future<void> _refreshPass() async {
    if (_mac.isEmpty) return;
    final Map<String, dynamic>? r = await InviteBackend.mine(_mac);
    if (!mounted) return;
    // On n'affiche le bandeau que si l'appareil a RÉELLEMENT été invité.
    setState(() => _pass = (r != null && r['invited'] == true) ? r : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Mode invité',
          style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Bandeau « ton accès invité » (si un pass est actif/passé).
                if (_pass != null) ...<Widget>[
                  _GuestPassBanner(pass: _pass!),
                  const SizedBox(height: 18),
                ],

                const _Intro(),
                const SizedBox(height: 18),

                // 1) J'ai un code
                _RedeemCard(mac: _mac, onRedeemed: _refreshPass),
                const SizedBox(height: 16),

                // 2) Envoyer ma MAC à celui qui m'invite
                _ShareMacCard(macNu: _macNu),

                // 3) Inviter un ami (réservé aux abonnés payés)
                if (_isPaid) ...<Widget>[
                  const SizedBox(height: 16),
                  _InviteCard(mac: _mac),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  Intro
// =========================================================
class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Invité, ou tu as ton propre code ?',
          style: AppTextStyles.headlineLarge.copyWith(fontSize: 22, height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          'Un ami t’a invité ? Tape son code, ou envoie-lui ton identifiant '
          'pour qu’il t’active à distance. Tu regardes avec lui, puis tu '
          'pourras t’abonner pour continuer.',
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  Bandeau : accès invité en cours
// =========================================================
class _GuestPassBanner extends StatelessWidget {
  const _GuestPassBanner({required this.pass});
  final Map<String, dynamic> pass;

  String get _modeLabel => switch ((pass['mode'] ?? '').toString()) {
        'lend' => 'Abonnement prêté',
        'test' => 'Essai',
        _ => 'On regarde ensemble',
      };

  String _remaining() {
    final int ms = (pass['ms_left'] as num?)?.toInt() ?? 0;
    if (ms <= 0) return 'Ton accès invité est terminé.';
    final int totalMin = (ms / 60000).floor();
    final int h = totalMin ~/ 60;
    final int m = totalMin % 60;
    if (h > 0) return 'Encore ${h}h ${m.toString().padLeft(2, '0')} min.';
    return 'Encore $m min.';
  }

  @override
  Widget build(BuildContext context) {
    final bool active = pass['active'] == true;
    final Map<String, dynamic>? channel =
        pass['channel'] is Map ? (pass['channel'] as Map).cast<String, dynamic>() : null;
    final String? inviter = pass['inviter']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(active ? Icons.card_giftcard_rounded : Icons.lock_clock_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _modeLabel,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontSize: 15,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _remaining(),
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
          ),
          if (channel != null && channel['name'] != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Chaîne partagée : ${channel['name']}',
              style: AppTextStyles.bodyMedium
                  .copyWith(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (inviter != null && inviter.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              'Invité par $inviter',
              style: AppTextStyles.bodyMedium
                  .copyWith(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// =========================================================
//  1) J'ai un code
// =========================================================
class _RedeemCard extends StatefulWidget {
  const _RedeemCard({required this.mac, required this.onRedeemed});
  final String mac;
  final VoidCallback onRedeemed;

  @override
  State<_RedeemCard> createState() => _RedeemCardState();
}

class _RedeemCardState extends State<_RedeemCard> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  bool _ok = false;
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String code = _code.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (code.length != 6) {
      setState(() => _message = 'Entre les 6 chiffres du code.');
      return;
    }
    if (widget.mac.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final Map<String, dynamic>? r = await InviteBackend.redeem(widget.mac, code);
    if (!mounted) return;
    if (r != null && r['ok'] == true) {
      setState(() {
        _busy = false;
        _ok = true;
        _message = 'C’est bon ! Profite du programme. À la fin, tu pourras '
            't’abonner pour continuer. 🎉';
      });
      // Synchronise : la licence invité vient d'être posée côté serveur →
      // l'app bascule en « payé » et la source partagée se charge.
      await SubscriptionState.instance.syncWithBackend();
      widget.onRedeemed();
      return;
    }
    setState(() {
      _busy = false;
      _message = switch ((r?['error'] ?? '').toString()) {
        'code_invalid' => 'Code inconnu. Vérifie les 6 chiffres.',
        'code_used' => 'Ce code a déjà été utilisé.',
        'code_expired' => 'Ce code a expiré. Demande-en un nouveau.',
        'own_code' => 'C’est ton propre code 🙂',
        'issuer_not_paid' => 'L’abonnement de ton ami n’est plus actif.',
        'issuer_quota' => 'Ton ami a atteint ses invitations de la semaine.',
        'already_active' => 'Ton appareil a déjà un accès actif.',
        'already_used_once' =>
          'Tu as déjà profité d’un pass gratuit. Pour continuer, abonne-toi.',
        '' => 'Connexion impossible. Réessaie.',
        _ => 'Impossible d’activer ce code.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.vpn_key_rounded,
      title: 'J’ai un code',
      subtitle: 'Un ami t’a donné un code à 6 chiffres ? Tape-le ici.',
      children: <Widget>[
        TextField(
          controller: _code,
          enabled: !_ok,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
            color: AppColors.accent,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(
              fontSize: 26,
              letterSpacing: 8,
              color: AppColors.textTertiary,
            ),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || _ok) ? null : _submit,
            icon: Icon(_ok ? Icons.check_rounded : Icons.login_rounded, size: 18),
            label: Text(_busy ? 'Patiente…' : (_ok ? 'Activé' : 'Activer mon accès')),
            style: FilledButton.styleFrom(
              backgroundColor: _ok ? AppColors.success : AppColors.accent,
              foregroundColor: AppColors.voidSurface,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _message!,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 13,
              color: _ok ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// =========================================================
//  2) Envoyer ma MAC
// =========================================================
class _ShareMacCard extends StatelessWidget {
  const _ShareMacCard({required this.macNu});
  final String macNu;

  @override
  Widget build(BuildContext context) {
    final String display = macNu.isEmpty ? '??:??:??:??:??' : macNu;
    return _Card(
      icon: Icons.qr_code_2_rounded,
      title: 'Pas de code ? Envoie ton identifiant',
      subtitle:
          'Montre ton identifiant à celui qui t’invite : il t’active à '
          'distance, tu n’as rien d’autre à faire.',
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            display,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: macNu.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: macNu));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text('Identifiant copié : $macNu',
                                style: AppTextStyles.bodyMedium),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: macNu.isEmpty
                    ? null
                    : () async {
                        final String msg =
                            'Salut ! Invite-moi sur l’appli : mon identifiant '
                            'est $macNu';
                        final bool ok =
                            await VipSupport.openWhatsApp(customMessage: msg);
                        if (!context.mounted) return;
                        if (!ok) {
                          showSupportChoiceSheet(context, customMessage: msg);
                        }
                      },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Envoyer'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.voidSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =========================================================
//  3) Inviter un ami (abonné payé)
// =========================================================
class _InviteCard extends StatefulWidget {
  const _InviteCard({required this.mac});
  final String mac;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  // Deux flux : « ensemble » (5 h) et « prêt » (24 h). 48 h reste possible.
  int _hours = 5;
  bool _busy = false;
  String? _code;
  String? _message;
  final TextEditingController _friendMac = TextEditingController();

  @override
  void dispose() {
    _friendMac.dispose();
    super.dispose();
  }

  /// Durée « ensemble » (5 h) → mode together ; « prêt » (24 h) → mode lend.
  String get _mode => _hours == 24 ? 'lend' : 'together';

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final Map<String, dynamic>? r = await InviteBackend.create(
      widget.mac,
      hours: _hours,
      mode: _mode,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _code = (r['code'] ?? '').toString();
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
  }

  Future<void> _grantByMac() async {
    final String g = _normalizeMac(_friendMac.text);
    if (g.isEmpty) {
      setState(() => _message = 'Entre l’identifiant de ton ami.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final Map<String, dynamic>? r = await InviteBackend.grant(
      widget.mac,
      g,
      hours: _hours,
      mode: _mode,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _message = 'Activé ! Ton ami a ${_hours} h d’accès. 🎉';
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
  }

  String _errText(String e) => switch (e) {
        'not_paid' =>
          'Le partage est réservé aux abonnés. Active ton abonnement d’abord.',
        'issuer_quota' =>
          'Tu as utilisé tes invitations de la semaine. Ça se renouvelle bientôt.',
        'already_active' => 'Cet appareil a déjà un accès actif.',
        'already_used_once' => 'Cet appareil a déjà profité d’un pass gratuit.',
        'own_code' => 'C’est ta propre adresse 🙂',
        _ => 'Action impossible pour le moment.',
      };

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.card_giftcard_rounded,
      title: 'Inviter un ami',
      subtitle: 'Fais-lui profiter de tes chaînes. Il devra s’abonner ensuite.',
      children: <Widget>[
        // Durée : 5 h (ensemble) / 24 h (prêt) / 48 h.
        Row(
          children: <Widget>[
            _DurChip(
              label: '5 h',
              hint: 'ensemble',
              on: _hours == 5,
              onTap: () => setState(() => _hours = 5),
            ),
            const SizedBox(width: 10),
            _DurChip(
              label: '24 h',
              hint: 'prêt',
              on: _hours == 24,
              onTap: () => setState(() => _hours = 24),
            ),
            const SizedBox(width: 10),
            _DurChip(
              label: '48 h',
              hint: 'week-end',
              on: _hours == 48,
              onTap: () => setState(() => _hours = 48),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_code != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent),
            ),
            child: Text(
              _code!.split('').join(' '),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 5,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Donne ce code à ton ami — valable 48 h.',
            style: AppTextStyles.bodyMedium
                .copyWith(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text(_busy
                ? 'Patiente…'
                : (_code == null ? 'Générer un code' : 'Nouveau code')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.voidSurface,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '— ou active-le directement par son identifiant —',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium
              .copyWith(fontSize: 12, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _friendMac,
          textCapitalization: TextCapitalization.characters,
          style: AppTextStyles.bodyLarge.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 1.2,
          ),
          decoration: InputDecoration(
            hintText: 'Identifiant de l’ami',
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _grantByMac,
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: Text(_busy ? 'Patiente…' : 'Activer par identifiant'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _message!,
            style: AppTextStyles.bodyMedium
                .copyWith(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DurChip extends StatelessWidget {
  const _DurChip({
    required this.label,
    required this.hint,
    required this.on,
    required this.onTap,
  });
  final String label;
  final String hint;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSurface : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? AppColors.accent : AppColors.border,
              width: on ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: <Widget>[
              Text(
                label,
                style: AppTextStyles.headlineMedium.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: on ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  color: on ? AppColors.accent : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  Brique commune : carte de section
// =========================================================
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.headlineMedium
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Normalise un identifiant saisi (MAC) → « MK:XX:XX:… » ou '' si invalide.
String _normalizeMac(String raw) {
  final String hex = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hex.length != 12) return '';
  final List<String> p = <String>[];
  for (int i = 0; i < 12; i += 2) {
    p.add(hex.substring(i, i + 2));
  }
  return 'MK:${p.join(':')}';
}
