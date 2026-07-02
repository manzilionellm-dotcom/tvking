// =========================================================
//  tv_family_screen.dart — Abonnement Famille (TV)
// =========================================================
//  Vue PROPRIÉTAIRE (abonnement payé) : générer/afficher le code
//  d'invitation à 6 chiffres (48 h), voir les appareils rattachés
//  (5 max, proprio inclus), détacher un membre (2 temps).
//  Vue MEMBRE : « rattaché à … » + bouton « Quitter la famille ».
//
//  Tout passe par FamilyBackend (notre worker) — aucun contact lecteur.
// =========================================================
import 'package:flutter/material.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/family_backend.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvFamilyScreen extends StatefulWidget {
  const TvFamilyScreen({super.key});

  @override
  State<TvFamilyScreen> createState() => _TvFamilyScreenState();
}

class _TvFamilyScreenState extends State<TvFamilyScreen> {
  bool _loading = true;
  bool _busy = false;
  String _mac = '';
  Map<String, dynamic>? _info; // réponse /api/family/info
  String? _error; // message doux (réseau / pas payé…)
  String? _confirmRemove; // MAC du membre en attente de confirmation

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _mac = await DeviceIdentity.instance.mac;
    final Map<String, dynamic>? info = await FamilyBackend.info(_mac);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
      _error = info == null ? 'Connexion impossible. Réessaie plus tard.' : null;
    });
  }

  Future<void> _invite() async {
    if (_busy) return;
    setState(() => _busy = true);
    final Map<String, dynamic>? r = await FamilyBackend.invite(_mac);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) {
      setState(() => _error = 'Connexion impossible. Réessaie plus tard.');
      return;
    }
    if (r['ok'] != true) {
      final String err = (r['error'] ?? '').toString();
      setState(() => _error = switch (err) {
            'not_paid' =>
              'Réservé aux abonnements ACTIFS (payés). Active d\'abord cet appareil.',
            'is_member' =>
              'Cet appareil est déjà rattaché à une famille — il ne peut pas inviter.',
            'family_full' => 'Famille complète (5 appareils maximum).',
            _ => 'Impossible pour le moment. Réessaie plus tard.',
          });
      return;
    }
    setState(() => _error = null);
    await _refresh();
  }

  Future<void> _remove(String member) async {
    if (_busy) return;
    setState(() => _busy = true);
    await FamilyBackend.remove(_mac, member: member);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirmRemove = null;
    });
    await _refresh();
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() => _busy = true);
    await FamilyBackend.remove(_mac);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: <Widget>[
                  const Text(
                    'Abonnement Famille',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Partage ton abonnement avec 4 proches (5 appareils au '
                    'total, comme Netflix). Tu génères un code, ton proche le '
                    'tape sur son appareil — c\'est tout.',
                    style: TextStyle(fontSize: 15, color: TvTokens.muted),
                  ),
                  const SizedBox(height: 22),
                  if (_error != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: TvTokens.card,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius),
                        border: Border.all(color: TvTokens.lineSoft),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 15, color: TvTokens.muted)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ..._buildBody(),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildBody() {
    final Map<String, dynamic>? info = _info;
    if (info == null || info['ok'] != true) {
      // Pas d'info (réseau / fonctionnalité pas encore dispo) → bouton retry.
      return <Widget>[
        _goldButton(
          icon: Icons.refresh_rounded,
          label: 'Réessayer',
          onSelect: _refresh,
          autofocus: true,
        ),
      ];
    }

    // ----- Vue MEMBRE -----
    if (info['role'] == 'member') {
      return <Widget>[
        _card(Row(
          children: <Widget>[
            const Icon(Icons.family_restroom_rounded,
                color: TvTokens.gold, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Cet appareil est rattaché à l\'abonnement famille '
                '${info['owner'] ?? ''}.',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.text),
              ),
            ),
          ],
        )),
        const SizedBox(height: 16),
        _goldButton(
          icon: Icons.logout_rounded,
          label: _busy ? 'Un instant…' : 'Quitter la famille',
          onSelect: _busy ? null : _leave,
          autofocus: true,
        ),
      ];
    }

    // ----- Vue PROPRIÉTAIRE -----
    final List<dynamic> members =
        (info['members'] as List<dynamic>?) ?? <dynamic>[];
    final String? code = info['code'] as String?;
    return <Widget>[
      // Code d'invitation (gros, lisible à 3 mètres).
      if (code != null) ...<Widget>[
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('CODE D\'INVITATION (valable 48 h)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: TvTokens.mutedDim,
                    letterSpacing: 1.6)),
            const SizedBox(height: 10),
            Text(
              '${code.substring(0, 3)} ${code.substring(3)}',
              style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: TvTokens.goldBright),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sur l\'appareil de ton proche : écran d\'activation → '
              '« J\'ai un code famille » → taper ce code.',
              style: TextStyle(fontSize: 14, color: TvTokens.muted),
            ),
          ],
        )),
        const SizedBox(height: 14),
      ],
      _goldButton(
        icon: Icons.qr_code_rounded,
        label: _busy
            ? 'Un instant…'
            : (code == null
                ? 'Générer un code d\'invitation'
                : 'Générer un NOUVEAU code'),
        onSelect: _busy ? null : _invite,
        autofocus: true,
      ),
      const SizedBox(height: 24),
      Text(
        'APPAREILS RATTACHÉS (${members.length}/4 + celui-ci)',
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TvTokens.mutedDim,
            letterSpacing: 1.6),
      ),
      const SizedBox(height: 12),
      if (members.isEmpty)
        const Text('Aucun appareil rattaché pour l\'instant.',
            style: TextStyle(fontSize: 15, color: TvTokens.mutedDim))
      else
        for (final dynamic m in members)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _card(Row(
                    children: <Widget>[
                      const Icon(Icons.tv_rounded,
                          color: TvTokens.muted, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        (m is Map ? (m['mac'] ?? '') : '').toString(),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: TvTokens.text),
                      ),
                    ],
                  )),
                ),
                const SizedBox(width: 10),
                // Détacher (2 temps anti-fausse-manip).
                TvFocusBuilder(
                  scale: TvFocusScale.small,
                  onSelect: () {
                    final String mm =
                        (m is Map ? (m['mac'] ?? '') : '').toString();
                    if (_confirmRemove == mm) {
                      _remove(mm);
                    } else {
                      setState(() => _confirmRemove = mm);
                    }
                  },
                  builder: (BuildContext context, bool focused) {
                    final String mm =
                        (m is Map ? (m['mac'] ?? '') : '').toString();
                    final bool confirming = _confirmRemove == mm;
                    final Color bg = focused
                        ? (confirming ? TvTokens.live : TvTokens.gold)
                        : TvTokens.card;
                    final Color fg = focused
                        ? Colors.white
                        : (confirming ? TvTokens.live : TvTokens.muted);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius),
                        border: Border.all(color: TvTokens.lineSoft),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.link_off_rounded, size: 20, color: fg),
                          if (confirming) ...<Widget>[
                            const SizedBox(width: 6),
                            Text('Confirmer ?',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: fg)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      const SizedBox(height: 18),
      // Rappel honnête pour le revendeur ET le client.
      _card(const Text(
        'ℹ️ Le nombre d\'appareils qui regardent EN MÊME TEMPS dépend de '
        'ton abonnement (connexions simultanées de la ligne).',
        style: TextStyle(fontSize: 13, color: TvTokens.mutedDim),
      )),
    ];
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          border: Border.all(color: TvTokens.lineSoft),
        ),
        child: child,
      );

  Widget _goldButton({
    required IconData icon,
    required String label,
    required VoidCallback? onSelect,
    bool autofocus = false,
  }) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.badgeBg;
        final Color fg =
            focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(color: TvTokens.gold),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 24),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
            ],
          ),
        );
      },
    );
  }
}
