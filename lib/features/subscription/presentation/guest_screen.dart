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
  const GuestScreen({super.key, this.consoleMode = false});

  /// Mode CONSOLE MAÎTRE (build dédié) : l'écran ne montre QUE le générateur
  /// de tests (pas « j'ai un code » ni « envoyer ma MAC »), et c'est l'écran
  /// de démarrage de l'app. Le pouvoir reste verrouillé serveur sur la MAC.
  final bool consoleMode;

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

  /// PRÊT en cours dont CET appareil est le PROPRIÉTAIRE (via myLoan) :
  /// { active, return_at, ms_left, guest }. On affiche alors un bandeau
  /// « tu as prêté ton abonnement » + le bouton Reprendre — visible MÊME
  /// quand l'app est en pause (c'est le seul moyen de reprendre la main).
  Map<String, dynamic>? _loan;
  bool _reclaiming = false;

  /// CET appareil est-il un compte MAÎTRE (démo illimitée) ? Débloque l'envoi
  /// de tests sans quota ni abonnement.
  bool _isMaster = false;

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
      _refresh();
    });
  }

  Future<void> _refresh() async {
    if (_mac.isEmpty) return;
    final Map<String, dynamic>? pass = await InviteBackend.mine(_mac);
    final Map<String, dynamic>? loan = await InviteBackend.myLoan(_mac);
    final bool master = await InviteBackend.isMaster(_mac);
    if (!mounted) return;
    setState(() {
      // On n'affiche le bandeau invité que si l'appareil a RÉELLEMENT été invité.
      _pass = (pass != null && pass['invited'] == true) ? pass : null;
      _loan = (loan != null && loan['active'] == true) ? loan : null;
      _isMaster = master;
    });
  }

  Future<void> _reclaim() async {
    if (_reclaiming || _mac.isEmpty) return;
    setState(() => _reclaiming = true);
    final Map<String, dynamic>? r = await InviteBackend.reclaim(_mac);
    if (!mounted) return;
    setState(() {
      _reclaiming = false;
      if (r != null && r['ok'] == true) _loan = null;
    });
    if (r != null && r['ok'] == true) {
      // L'abonnement est revenu : on resynchronise le statut de l'app.
      await SubscriptionState.instance.syncWithBackend();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Abonnement repris — c’est de nouveau à toi. 👍'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool console = widget.consoleMode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !console, // pas de « retour » : c'est l'app
        title: Text(
          console ? 'Console de test' : 'Mode invité',
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
              children: console
                  ? _consoleChildren()
                  : _guestChildren(),
            ),
          ),
        ),
      ),
    );
  }

  /// Écran invité classique (client) : bandeaux + code + envoyer MAC + inviter.
  List<Widget> _guestChildren() {
    return <Widget>[
      // Compte maître → boîte noire (diagnostic sécurité) en tête.
      if (_isMaster) ...<Widget>[
        _BlackBox(mac: _mac),
        const SizedBox(height: 18),
      ],
      if (_loan != null) ...<Widget>[
        _LoanOwnerBanner(loan: _loan!, busy: _reclaiming, onReclaim: _reclaim),
        const SizedBox(height: 18),
      ],
      if (_pass != null) ...<Widget>[
        _GuestPassBanner(pass: _pass!),
        const SizedBox(height: 18),
      ],
      const _Intro(),
      const SizedBox(height: 18),
      _RedeemCard(mac: _mac, onRedeemed: _refresh),
      const SizedBox(height: 16),
      _ShareMacCard(macNu: _macNu),
      // Inviter un ami (abonnés) OU envoyer des tests illimités (maîtres).
      if (_isPaid || _isMaster) ...<Widget>[
        const SizedBox(height: 16),
        _InviteCard(mac: _mac, onLent: _refresh, isMaster: _isMaster),
      ],
    ];
  }

  /// Écran CONSOLE MAÎTRE (build dédié) : seulement le générateur de tests.
  /// Si la MAC n'est pas (encore) maître, on l'explique — le pouvoir vient du
  /// panel (serveur), pas du build.
  List<Widget> _consoleChildren() {
    return <Widget>[
      // BOÎTE NOIRE : diagnostic de sécurité en direct (en tête de console).
      _BlackBox(mac: _mac),
      const SizedBox(height: 18),
      Text(
        'Console de test — codes & accès illimités',
        style: AppTextStyles.headlineLarge.copyWith(fontSize: 22, height: 1.2),
      ),
      const SizedBox(height: 6),
      Text(
        'Génère un code ou active quelqu’un par son identifiant : il reçoit un '
        'accès complet le temps du test (1 h…), autant de fois que tu veux.',
        style: AppTextStyles.bodyMedium.copyWith(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.55,
        ),
      ),
      const SizedBox(height: 18),
      if (!_isMaster) ...<Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Cette MAC n’est pas encore « maître »',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ajoute cet identifiant dans le panel (Comptes maîtres) pour '
                'débloquer l’envoi de tests : ${_macNu.isEmpty ? '…' : _macNu}',
                style: AppTextStyles.bodyMedium
                    .copyWith(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      // Le générateur (forcé en mode maître : durée 1/5/24/48 h, illimité).
      _InviteCard(mac: _mac, onLent: _refresh, isMaster: true),
    ];
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
//  Bandeau : j'ai PRÊTÉ mon abonnement (propriétaire en pause)
// =========================================================
class _LoanOwnerBanner extends StatelessWidget {
  const _LoanOwnerBanner({
    required this.loan,
    required this.busy,
    required this.onReclaim,
  });
  final Map<String, dynamic> loan;
  final bool busy;
  final VoidCallback onReclaim;

  String _remaining() {
    final int ms = (loan['ms_left'] as num?)?.toInt() ?? 0;
    if (ms <= 0) return 'Retour imminent.';
    final int totalMin = (ms / 60000).floor();
    final int h = totalMin ~/ 60;
    final int m = totalMin % 60;
    if (h > 0) return 'Retour auto dans ${h}h ${m.toString().padLeft(2, '0')}.';
    return 'Retour auto dans $m min.';
  }

  @override
  Widget build(BuildContext context) {
    final String? guest = loan['guest']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.volunteer_activism_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu as prêté ton abonnement',
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
            '${guest != null && guest.isNotEmpty ? 'Prêté à $guest. ' : ''}${_remaining()}',
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onReclaim,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: Text(busy ? 'Reprise…' : 'Reprendre mon abonnement'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.voidSurface,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  BOÎTE NOIRE — diagnostic de sécurité (console maître)
// =========================================================
//  Sonde les FAITS RÉELS via /api/invite/selftest et affiche un verdict
//  honnête : MAC maître ?, source active + hôte, routage relais (le
//  fournisseur ne voit qu'une IP), + les garanties d'architecture.
class _BlackBox extends StatefulWidget {
  const _BlackBox({required this.mac});
  final String mac;

  @override
  State<_BlackBox> createState() => _BlackBoxState();
}

class _BlackBoxState extends State<_BlackBox> {
  bool _busy = false;
  Map<String, dynamic>? _data;
  bool _done = false;

  @override
  void didUpdateWidget(covariant _BlackBox old) {
    super.didUpdateWidget(old);
    // La MAC arrive de façon asynchrone dans le parent → scanne dès qu'on l'a.
    if (old.mac.isEmpty && widget.mac.isNotEmpty && !_done) _scan();
  }

  @override
  void initState() {
    super.initState();
    if (widget.mac.isNotEmpty) _scan();
  }

  Future<void> _scan() async {
    if (_busy || widget.mac.isEmpty) return;
    setState(() => _busy = true);
    final Map<String, dynamic>? r = await InviteBackend.selftest(widget.mac);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
      _data = r;
    });
  }

  /// Statut d'une ligne : 0 = ok (vert), 1 = à vérifier (ambre), 2 = KO (rouge).
  ({int level, String label, String detail}) _row(String key) {
    final Map<String, dynamic>? d = _data;
    switch (key) {
      case 'backend':
        final bool ok = d != null && d['ok'] == true;
        return (
          level: ok ? 0 : 2,
          label: 'Serveur joignable',
          detail: ok ? 'Backend en ligne.' : 'Pas de réponse du backend.',
        );
      case 'master':
        final bool ok = d != null && d['master'] == true;
        return (
          level: ok ? 0 : 2,
          label: 'MAC maître reconnue',
          detail: ok
              ? 'Cet appareil peut envoyer des tests illimités.'
              : 'Ajoute cette MAC dans le panel (Comptes maîtres).',
        );
      case 'source':
        final Map<String, dynamic>? s =
            d != null && d['source'] is Map ? (d['source'] as Map).cast<String, dynamic>() : null;
        final bool present = s != null && s['present'] == true;
        return (
          level: present ? 0 : 1,
          label: 'Source active',
          detail: present
              ? '${s['count'] ?? 1} source(s) · ${s['origin'] ?? 'panel'}'
              : 'Aucune source assignée à cet appareil.',
        );
      case 'relay':
        final Map<String, dynamic>? s =
            d != null && d['source'] is Map ? (d['source'] as Map).cast<String, dynamic>() : null;
        final String host = (s?['host'] ?? '').toString();
        if (host.isEmpty) {
          return (
            level: 1,
            label: 'Fournisseur ne voit qu’une IP',
            detail: 'Hôte inconnu — impossible de confirmer le routage.',
          );
        }
        // Un domaine (avec des lettres) = façade gateway → une seule IP de
        // sortie. Une IP brute (chiffres/points) = risque de sortie directe.
        final bool isDomain = RegExp(r'[a-zA-Z]').hasMatch(host);
        return (
          level: isDomain ? 0 : 1,
          label: 'Fournisseur ne voit qu’une IP',
          detail: isDomain
              ? 'Sortie via $host (relais) → le fournisseur ne voit que cette IP.'
              : 'Source directe ($host) — vérifie que c’est bien ton gateway.',
        );
      default:
        return (level: 0, label: '', detail: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Garanties d'architecture (toujours vraies par conception).
    const List<String> facts = <String>[
      'Aucune structure (famille/test) n’est envoyée au fournisseur.',
      'La liste des maîtres vit uniquement dans le panel.',
      'Chaque test est coupé automatiquement à l’échéance.',
    ];
    final List<({int level, String label, String detail})> rows = _done
        ? <({int level, String label, String detail})>[
            _row('backend'),
            _row('master'),
            _row('source'),
            _row('relay'),
          ]
        : const <({int level, String label, String detail})>[];
    // Verdict global : tout vert = sécurité pleine.
    final bool allGreen = _done && rows.every((r) => r.level == 0);
    final int worst = rows.isEmpty ? 1 : rows.map((r) => r.level).reduce((a, b) => a > b ? a : b);
    final Color headColor = !_done
        ? AppColors.textSecondary
        : (worst == 0 ? AppColors.success : (worst == 2 ? AppColors.accent : AppColors.warning));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: headColor.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_moon_rounded, color: headColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Boîte noire — sécurité',
                  style: AppTextStyles.headlineMedium
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: _scan,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.refresh_rounded,
                        color: AppColors.textTertiary, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            !_done
                ? 'Analyse en cours…'
                : (allGreen
                    ? 'Sécurité pleine ✓ — le fournisseur ne voit qu’une IP.'
                    : 'À vérifier — voir les points ambre/rouge ci-dessous.'),
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              color: headColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final r in rows) ...<Widget>[
            _line(
              level: r.level,
              label: r.label,
              detail: r.detail,
            ),
            const SizedBox(height: 8),
          ],
          if (_done) ...<Widget>[
            const SizedBox(height: 2),
            for (final String f in facts)
              _line(level: 0, label: f, detail: null, dim: true),
          ],
        ],
      ),
    );
  }

  Widget _line({
    required int level,
    required String label,
    String? detail,
    bool dim = false,
  }) {
    final Color c = level == 0
        ? AppColors.success
        : (level == 2 ? AppColors.accent : AppColors.warning);
    final IconData ic = level == 0
        ? Icons.check_circle_rounded
        : (level == 2 ? Icons.cancel_rounded : Icons.error_rounded);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(ic, color: c, size: dim ? 14 : 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: dim ? 11.5 : 13,
                  color: dim ? AppColors.textTertiary : AppColors.textPrimary,
                  fontWeight: dim ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              if (detail != null)
                Text(
                  detail,
                  style: AppTextStyles.labelSmall
                      .copyWith(fontSize: 11, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ],
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
  const _InviteCard({
    required this.mac,
    required this.onLent,
    this.isMaster = false,
  });
  final String mac;

  /// Appelé après un PRÊT réussi (le parent rafraîchit l'état « j'ai prêté »).
  final VoidCallback onLent;

  /// Compte MAÎTRE : envoi de tests illimité (durée 1 h dispo, pas de quota).
  final bool isMaster;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  // Deux FLUX bien distincts :
  //  • 'together' = « on regarde ensemble » (5 h) — je GARDE mon abonnement,
  //    l'ami regarde une chaîne partagée puis devra s'abonner.
  //  • 'lend'     = « je prête mon abonnement » (24 h / 48 h max) — JE passe
  //    en pause, l'ami a tout, et ça me revient tout seul à l'échéance.
  String _flow = 'together';
  int _lendHours = 24; // durée du prêt (24 ou 48)
  int _testHours = 1; // durée du test (comptes maîtres) : 1 / 5 / 24 / 48 h
  bool _busy = false;
  String? _code;
  String? _message;
  final TextEditingController _friendMac = TextEditingController();

  /// Durée du flux « ensemble » : 5 h pour un abonné, choisie (défaut 1 h)
  /// pour un compte maître (tests courts).
  int get _ensembleHours => widget.isMaster ? _testHours : 5;

  @override
  void dispose() {
    _friendMac.dispose();
    super.dispose();
  }

  // --- Flux « ensemble » : code à 6 chiffres (5 h, chaîne partagée). ---
  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final Map<String, dynamic>? r = await InviteBackend.create(
      widget.mac,
      hours: _ensembleHours,
      mode: widget.isMaster ? 'test' : 'together',
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

  // --- Flux « ensemble » : activation directe par identifiant (5 h). ---
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
      hours: _ensembleHours,
      mode: widget.isMaster ? 'test' : 'together',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _message = widget.isMaster
            ? 'Test envoyé ! Ton contact a $_ensembleHours h d’accès. 🎉'
            : 'Activé ! Ton ami a 5 h pour regarder avec toi. 🎉';
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
  }

  // --- Flux « prêt » : je prête mon abonnement (24/48 h) par identifiant. ---
  Future<void> _lend() async {
    final String g = _normalizeMac(_friendMac.text);
    if (g.isEmpty) {
      setState(() => _message = 'Entre l’identifiant de ton ami.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final Map<String, dynamic>? r =
        await InviteBackend.lend(widget.mac, g, hours: _lendHours);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _message = 'Connexion impossible. Réessaie.';
      } else if (r['ok'] == true) {
        _message = 'Prêté ! Ton ami a $_lendHours h. Toi, tu es en pause — '
            'ça te revient tout seul à la fin (ou reprends quand tu veux).';
      } else {
        _message = _errText((r['error'] ?? '').toString());
      }
    });
    // Un prêt réussi met le propriétaire en pause → le parent affiche le
    // bandeau « j'ai prêté » avec le bouton Reprendre.
    if (r != null && r['ok'] == true) widget.onLent();
  }

  String _errText(String e) => switch (e) {
        'not_paid' =>
          'Le partage est réservé aux abonnés. Active ton abonnement d’abord.',
        'issuer_quota' =>
          'Tu as utilisé tes invitations de la semaine. Ça se renouvelle bientôt.',
        'already_active' => 'Cet appareil a déjà un accès actif.',
        'already_used_once' => 'Cet appareil a déjà profité d’un pass gratuit.',
        'loan_active' =>
          'Tu as déjà un prêt en cours. Reprends-le d’abord pour en refaire un.',
        'same_device' => 'C’est ton propre appareil 🙂',
        'own_code' => 'C’est ta propre adresse 🙂',
        _ => 'Action impossible pour le moment.',
      };

  @override
  Widget build(BuildContext context) {
    final bool lend = _flow == 'lend';
    return _Card(
      icon: widget.isMaster
          ? Icons.workspace_premium_rounded
          : Icons.card_giftcard_rounded,
      title: widget.isMaster ? 'Envoyer un test' : 'Inviter un ami',
      subtitle: widget.isMaster
          ? 'Mode maître : envoie un test à qui tu veux, autant que tu veux.'
          : 'Deux façons de partager : regarder ensemble, ou lui prêter '
              'ton abonnement.',
      children: <Widget>[
        // Bandeau « mode maître » : envoi illimité, durée au choix (dont 1 h).
        if (widget.isMaster) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(Icons.bolt_rounded, color: AppColors.accent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Compte maître — tests illimités',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  'Durée du test',
                  style: AppTextStyles.labelSmall
                      .copyWith(fontSize: 10, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (final int h in <int>[1, 5, 24, 48]) ...<Widget>[
                      _DurChip(
                        label: '$h h',
                        hint: h == 1 ? 'test' : '',
                        on: _testHours == h,
                        onTap: () => setState(() => _testHours = h),
                      ),
                      if (h != 48) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        // Choix du FLUX : ensemble (5 h) vs prêt (24/48 h). Caché pour un
        // maître (il envoie des tests, il ne prête pas son abonnement).
        if (!widget.isMaster) ...<Widget>[
          Row(
            children: <Widget>[
              _FlowTab(
                label: 'Ensemble',
                hint: '5 h · tu gardes tes chaînes',
                on: !lend,
                onTap: () => setState(() {
                  _flow = 'together';
                  _message = null;
                }),
              ),
              const SizedBox(width: 10),
              _FlowTab(
                label: 'Prêter',
                hint: '24-48 h · tu passes en pause',
                on: lend,
                onTap: () => setState(() {
                  _flow = 'lend';
                  _message = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        if (!lend) ...<Widget>[
          // ---------- FLUX ENSEMBLE (5 h, code ou identifiant) ----------
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
        ] else ...<Widget>[
          // ---------- FLUX PRÊT (24/48 h, identifiant obligatoire) ----------
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Tu prêtes TON abonnement complet. Pendant le prêt, toi tu es en '
              'pause. À la fin, ça revient tout seul sur ton appareil (ou tu le '
              'reprends quand tu veux).',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _DurChip(
                label: '24 h',
                hint: 'max',
                on: _lendHours == 24,
                onTap: () => setState(() => _lendHours = 24),
              ),
              const SizedBox(width: 10),
              _DurChip(
                label: '48 h',
                hint: 'max',
                on: _lendHours == 48,
                onTap: () => setState(() => _lendHours = 48),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),
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
          child: lend
              ? FilledButton.icon(
                  onPressed: _busy ? null : _lend,
                  icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
                  label: Text(_busy ? 'Patiente…' : 'Prêter mon abonnement'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.voidSurface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: _busy ? null : _grantByMac,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(_busy ? 'Patiente…' : 'Activer par identifiant'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side:
                        BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
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

/// Onglet de choix de FLUX (Ensemble / Prêter) — plus grand qu'une puce.
class _FlowTab extends StatelessWidget {
  const _FlowTab({
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSurface : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? AppColors.accent : AppColors.border,
              width: on ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: AppTextStyles.headlineMedium.copyWith(
                  fontSize: 15,
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
