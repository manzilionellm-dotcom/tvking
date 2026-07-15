// =========================================================
//  tv_invite_screen.dart — PASS PARTAGE (« regarder ensemble ») sur TV
// =========================================================
//  Deux rôles sur un même écran :
//    • INVITER UN AMI — un abonné payé génère un code à 6 chiffres (valable
//      48 h). Il peut inviter jusqu'à 5 personnes en même temps (compteur X/5).
//    • J'AI UN CODE — un NOUVEL appareil tape le code → 2 jours d'accès, une
//      seule fois à vie, puis il doit payer.
//
//  Tout passe par InviteBackend (notre worker). Après un code réussi, on
//  pousse SubscriptionState.syncWithBackend() pour débloquer tout de suite.
//  Aucun contact avec le lecteur. 100 % télécommande.
// =========================================================
import 'package:flutter/material.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/invite_backend.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvInviteScreen extends StatefulWidget {
  const TvInviteScreen({super.key});

  @override
  State<TvInviteScreen> createState() => _TvInviteScreenState();
}

class _TvInviteScreenState extends State<TvInviteScreen> {
  String _mac = '';

  // --- Génération (abonné) ---
  bool _genBusy = false;
  String? _code;
  int _weeklyUsed = 0;
  int _weeklyQuota = 5;
  String? _genMessage;

  // --- Saisie (invité) ---
  String _entry = '';
  bool _redeemBusy = false;
  bool _redeemed = false;
  String? _redeemMessage;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
  }

  // ---------- INVITER ----------
  Future<void> _generate() async {
    if (_genBusy) return;
    setState(() {
      _genBusy = true;
      _genMessage = null;
    });
    final String mac = _mac.isNotEmpty ? _mac : await DeviceIdentity.instance.mac;
    final Map<String, dynamic>? r = await InviteBackend.create(mac);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _genBusy = false;
        _genMessage = 'Connexion impossible. Réessaie dans un instant.';
      });
      return;
    }
    if (r['ok'] == true) {
      setState(() {
        _genBusy = false;
        _code = (r['code'] ?? '').toString();
        _weeklyUsed = (r['weekly_used'] as num?)?.toInt() ?? _weeklyUsed;
        _weeklyQuota = (r['weekly_quota'] as num?)?.toInt() ?? _weeklyQuota;
        _genMessage = null;
      });
      return;
    }
    final String err = (r['error'] ?? '').toString();
    setState(() {
      _genBusy = false;
      _genMessage = switch (err) {
        'not_paid' =>
          'Le partage est réservé aux abonnés. Active ton abonnement d’abord.',
        'invite_unavailable' =>
          'Service indisponible pour l’instant. Réessaie plus tard.',
        _ => 'Impossible de générer le code pour le moment.',
      };
    });
  }

  // ---------- SAISIR UN CODE ----------
  void _type(String d) {
    if (_redeemBusy || _redeemed || _entry.length >= 6) return;
    setState(() {
      _entry += d;
      _redeemMessage = null;
    });
    if (_entry.length == 6) _redeem();
  }

  void _backspace() {
    if (_redeemBusy || _redeemed || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _redeem() async {
    if (_redeemBusy || _entry.length != 6) return;
    setState(() => _redeemBusy = true);
    final String mac = _mac.isNotEmpty ? _mac : await DeviceIdentity.instance.mac;
    final Map<String, dynamic>? r = await InviteBackend.redeem(mac, _entry);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _redeemBusy = false;
        _redeemMessage = 'Connexion impossible. Réessaie dans un instant.';
      });
      return;
    }
    if (r['ok'] == true) {
      setState(() {
        _redeemBusy = false;
        _redeemed = true;
        _redeemMessage =
            'C’est bon ! Tu as 2 jours d’accès pour regarder ensemble. 🎉';
      });
      await SubscriptionState.instance.syncWithBackend();
      return;
    }
    final String err = (r['error'] ?? '').toString();
    setState(() {
      _redeemBusy = false;
      _entry = '';
      _redeemMessage = switch (err) {
        'code_invalid' => 'Code inconnu. Vérifie les 6 chiffres.',
        'code_used' => 'Ce code a déjà été utilisé.',
        'code_expired' => 'Ce code a expiré. Demande-en un nouveau.',
        'own_code' => 'C’est ton propre code 🙂',
        'issuer_not_paid' => 'L’abonnement de ton ami n’est plus actif.',
        'issuer_quota' =>
          'Ton ami a utilisé ses 5 invitations de la semaine. Ça se renouvelle dans quelques jours.',
        'already_active' => 'Ton appareil a déjà un accès actif.',
        'already_used_once' =>
          'Tu as déjà profité d’un pass gratuit. Pour continuer, passe à l’abonnement.',
        _ => 'Impossible d’activer ce code pour le moment.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Pass Partage',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const SizedBox(height: 6),
            const Text(
              'Invite un ami à regarder le match ou un film avec toi — '
              'il profite de 2 jours d’accès.',
              style: TextStyle(fontSize: 15, color: TvTokens.muted),
            ),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _inviteCard()),
                const SizedBox(width: 22),
                Expanded(child: _redeemCard()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----- Carte « Inviter un ami » -----
  Widget _inviteCard() {
    final bool canInvite =
        SubscriptionState.instance.status == SubscriptionStatus.paid;
    return _panel(
      icon: Icons.card_giftcard_rounded,
      title: 'Inviter un ami',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            canInvite
                ? 'Génère un code et donne-le à ton ami. Tu as $_weeklyQuota invitations par semaine — ça se renouvelle chaque semaine. 🎉'
                : 'Réservé aux abonnés. Une fois abonné, tu recevras $_weeklyQuota invitations CHAQUE SEMAINE à partager avec tes amis.',
            style: const TextStyle(fontSize: 15, color: TvTokens.muted),
          ),
          const SizedBox(height: 18),
          if (_code != null) ...<Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: TvTokens.card,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                border: Border.all(color: TvTokens.gold),
              ),
              child: Text(
                _code!.split('').join(' '),
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: TvTokens.goldBright),
              ),
            ),
            const SizedBox(height: 10),
            Text('Cette semaine : $_weeklyUsed / $_weeklyQuota invitations · code valable 48 h',
                style: const TextStyle(fontSize: 13, color: TvTokens.mutedDim)),
            const SizedBox(height: 14),
          ],
          if (_genMessage != null) ...<Widget>[
            Text(_genMessage!,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.muted)),
            const SizedBox(height: 14),
          ],
          _bigButton(
            label: _genBusy
                ? 'Génération…'
                : (_code == null ? 'Générer un code' : 'Nouveau code'),
            icon: Icons.qr_code_2_rounded,
            autofocus: true,
            onSelect: _genBusy ? null : _generate,
          ),
        ],
      ),
    );
  }

  // ----- Carte « J'ai un code » -----
  Widget _redeemCard() {
    final String shown = List<String>.generate(
      6,
      (int i) => i < _entry.length ? _entry[i] : '·',
    ).join(' ');
    return _panel(
      icon: Icons.vpn_key_rounded,
      title: 'J’ai un code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Tape le code que ton ami t’a donné pour 2 jours d’accès.',
            style: TextStyle(fontSize: 15, color: TvTokens.muted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: TvTokens.card,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(
                  color: _redeemed ? TvTokens.success : TvTokens.gold),
            ),
            child: Text(
              shown,
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: _redeemed ? TvTokens.success : TvTokens.goldBright),
            ),
          ),
          if (_redeemMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_redeemMessage!,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _redeemed ? TvTokens.success : TvTokens.muted)),
          ],
          const SizedBox(height: 16),
          if (!_redeemed)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (int d = 1; d <= 9; d++)
                  _key('$d', onSelect: () => _type('$d')),
                _key('0', onSelect: () => _type('0')),
                _key('⌫', onSelect: _backspace),
              ],
            ),
          if (_redeemBusy) ...<Widget>[
            const SizedBox(height: 16),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: TvTokens.gold),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel(
      {required IconData icon,
      required String title,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: TvTokens.goldBright, size: 26),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _bigButton(
      {required String label,
      required IconData icon,
      required VoidCallback? onSelect,
      bool autofocus = false}) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }

  Widget _key(String label, {required VoidCallback onSelect}) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          width: 60,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
        );
      },
    );
  }
}
