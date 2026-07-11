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

import '../../../core/i18n/l10n_extension.dart';
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
  String? _renamingMember; // MAC du membre en cours de nommage (chips)

  /// Noms proposés pour les membres (un clic, pas de clavier).
  List<String> _memberNames(BuildContext context) => <String>[
        context.l10n.tvFamilyNameDad,
        context.l10n.tvFamilyNameMom,
        context.l10n.tvFamilyNameChild1,
        context.l10n.tvFamilyNameChild2,
        context.l10n.tvFamilyNameTeen,
        context.l10n.tvFamilyNameLivingRoom,
        context.l10n.tvFamilyNameBedroom,
      ];

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
      _error = info == null ? context.l10n.tvFamilyConnectionError : null;
    });
  }

  Future<void> _invite() async {
    if (_busy) return;
    setState(() => _busy = true);
    final Map<String, dynamic>? r = await FamilyBackend.invite(_mac);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) {
      setState(() => _error = context.l10n.tvFamilyConnectionError);
      return;
    }
    if (r['ok'] != true) {
      final String err = (r['error'] ?? '').toString();
      setState(() => _error = switch (err) {
            'not_paid' => context.l10n.tvFamilyErrorNotPaid,
            'is_member' => context.l10n.tvFamilyErrorIsMember,
            'family_full' => context.l10n.tvFamilyErrorFull,
            'plan_required' => context.l10n.tvFamilyErrorPlanRequired,
            _ => context.l10n.tvFamilyErrorGeneric,
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
                  Text(
                    context.l10n.tvFamilyTitle,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.tvFamilySubtitle,
                    style: const TextStyle(fontSize: 15, color: TvTokens.muted),
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
          label: context.l10n.buttonRetry,
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
                context.l10n
                    .tvFamilyAttachedTo((info['owner'] ?? '').toString()),
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
          label: _busy
              ? context.l10n.tvFamilyOneMoment
              : context.l10n.tvFamilyLeaveButton,
          onSelect: _busy ? null : _leave,
          autofocus: true,
        ),
      ];
    }

    // ----- Vue PROPRIÉTAIRE -----
    final List<dynamic> members =
        (info['members'] as List<dynamic>?) ?? <dynamic>[];
    final String? code = info['code'] as String?;
    final bool planOn = info['plan'] == true;
    final int maxM = (info['max'] as num?)?.toInt() ?? 4;

    // PLAN FAMILLE NON ACTIVÉ : le partage est une OPTION vendue par le
    // revendeur → écran « vitrine » qui donne envie et explique quoi faire.
    if (!planOn) {
      return <Widget>[
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.tvFamilyPlanBadge,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.goldBright)),
            const SizedBox(height: 10),
            Text(
              context.l10n.tvFamilyPlanPitch,
              style: const TextStyle(fontSize: 15, color: TvTokens.muted),
            ),
          ],
        )),
        const SizedBox(height: 16),
        _goldButton(
          icon: Icons.refresh_rounded,
          label: context.l10n.tvFamilyPlanCheckButton,
          onSelect: _refresh,
          autofocus: true,
        ),
      ];
    }

    return <Widget>[
      // Code d'invitation (gros, lisible à 3 mètres).
      if (code != null) ...<Widget>[
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.tvFamilyInviteCodeLabel,
                style: const TextStyle(
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
            Text(
              context.l10n.tvFamilyInviteCodeHelp,
              style: const TextStyle(fontSize: 14, color: TvTokens.muted),
            ),
          ],
        )),
        const SizedBox(height: 14),
      ],
      _goldButton(
        icon: Icons.qr_code_rounded,
        label: _busy
            ? context.l10n.tvFamilyOneMoment
            : (code == null
                ? context.l10n.tvFamilyGenerateCode
                : context.l10n.tvFamilyGenerateNewCode),
        onSelect: _busy ? null : _invite,
        autofocus: true,
      ),
      const SizedBox(height: 24),
      Text(
        context.l10n.tvFamilyMembersHeader(members.length, maxM),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TvTokens.mutedDim,
            letterSpacing: 1.6),
      ),
      const SizedBox(height: 12),
      if (members.isEmpty)
        Text(context.l10n.tvFamilyNoMembers,
            style: const TextStyle(fontSize: 15, color: TvTokens.mutedDim))
      else
        for (final dynamic m in members)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
              children: <Widget>[
                Expanded(
                  child: _card(Row(
                    children: <Widget>[
                      const Icon(Icons.tv_rounded,
                          color: TvTokens.muted, size: 22),
                      const SizedBox(width: 12),
                      // Nom du profil (« Papa »…) en grand ; la MAC en petit
                      // dessous (utile au support). Sans nom → MAC seule.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              (m is Map &&
                                      (m['label'] ?? '').toString().isNotEmpty)
                                  ? (m['label']).toString()
                                  : (m is Map ? (m['mac'] ?? '') : '')
                                      .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: TvTokens.text),
                            ),
                            if (m is Map &&
                                (m['label'] ?? '').toString().isNotEmpty)
                              Text(
                                (m['mac'] ?? '').toString(),
                                style: const TextStyle(
                                    fontSize: 12, color: TvTokens.mutedDim),
                              ),
                          ],
                        ),
                      ),
                    ],
                  )),
                ),
                const SizedBox(width: 10),
                // Nommer (« Papa », « Maman »… — ouvre les pastilles).
                TvFocusBuilder(
                  scale: TvFocusScale.small,
                  onSelect: () {
                    final String mm =
                        (m is Map ? (m['mac'] ?? '') : '').toString();
                    setState(() => _renamingMember =
                        _renamingMember == mm ? null : mm);
                  },
                  builder: (BuildContext context, bool focused) {
                    final Color bg = focused ? TvTokens.gold : TvTokens.card;
                    final Color fg = focused
                        ? const Color(0xFF1A1206)
                        : TvTokens.muted;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius),
                        border: Border.all(color: TvTokens.lineSoft),
                      ),
                      child: Icon(Icons.edit_rounded, size: 20, color: fg),
                    );
                  },
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
                            Text(context.l10n.tvFamilyConfirmRemove,
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
                // ----- Pastilles de nommage (sous la ligne, façon Netflix) -----
                if (_renamingMember ==
                    (m is Map ? (m['mac'] ?? '') : '').toString())
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String name in _memberNames(context))
                          TvFocusBuilder(
                            scale: TvFocusScale.small,
                            onSelect: () async {
                              final String mm =
                                  (m is Map ? (m['mac'] ?? '') : '')
                                      .toString();
                              await FamilyBackend.rename(_mac, mm, name);
                              if (!mounted) return;
                              setState(() => _renamingMember = null);
                              await _refresh();
                            },
                            builder: (BuildContext context, bool focused) {
                              final Color bg =
                                  focused ? TvTokens.gold : TvTokens.card;
                              final Color fg = focused
                                  ? const Color(0xFF1A1206)
                                  : TvTokens.text;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(
                                      TvDimens.cardRadius),
                                  border:
                                      Border.all(color: TvTokens.lineSoft),
                                ),
                                child: Text(name,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: fg)),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      const SizedBox(height: 18),
      // Rappel honnête pour le revendeur ET le client.
      _card(Text(
        context.l10n.tvFamilySimultaneousNote,
        style: const TextStyle(fontSize: 13, color: TvTokens.mutedDim),
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
