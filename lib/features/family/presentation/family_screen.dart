// =========================================================
//  family_screen.dart — Bouquet famille (MOBILE)
// =========================================================
//  Le téléphone est presque toujours un MEMBRE : la TV du salon porte la
//  ligne payée, les téléphones s'y rattachent avec le code à 6 chiffres
//  affiché sur la TV (Réglages, Famille). Cet écran fait trois choses :
//    1. rattacher ce téléphone (saisie du code) ;
//    2. montrer QUI REGARDE EN CE MOMENT sur la ligne (jamais quoi) ;
//    3. rappeler la promesse : chacun son profil, chacun son film, la
//       reprise suit la personne d'un appareil à l'autre.
//  Même FamilyBackend que la TV ; widgets Material (tactile).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/family_backend.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  bool _loading = true;
  bool _busy = false;
  String _mac = '';
  Map<String, dynamic>? _info;
  String? _message;
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _mac = await DeviceIdentity.instance.mac;
    final Map<String, dynamic>? info = await FamilyBackend.info(_mac);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  Future<void> _join() async {
    final String code = _code.text.trim();
    if (_busy || code.length != 6) return;
    setState(() => _busy = true);
    final Map<String, dynamic>? r = await FamilyBackend.join(_mac, code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = (r != null && r['ok'] == true)
          ? context.l10n.familyJoinDone
          : context.l10n.familyJoinFailed;
    });
    if (r != null && r['ok'] == true) {
      _code.clear();
      await _refresh();
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() => _busy = true);
    await FamilyBackend.remove(_mac);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  String _whoName(Map<String, dynamic> w) {
    if (w['me'] == true) return context.l10n.tvFamilyThisDevice;
    final Object? label = w['label'];
    if (label is String && label.isNotEmpty) return label;
    return w['role'] == 'owner'
        ? context.l10n.tvFamilyOwnerLabel
        : context.l10n.tvFamilyUnnamedMember;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? info = _info;
    final bool isMember = info != null && info['role'] == 'member';
    final List<dynamic> who =
        (info?['who'] as List<dynamic>?) ?? const <dynamic>[];
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsFamilyTile)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.family_restroom_rounded),
                    title: Text(context.l10n.settingsFamilySubtitle,
                        style: AppTextStyles.bodyMedium),
                  ),
                  if (isMember)
                    ListTile(
                      leading: const Icon(Icons.link_rounded),
                      title: Text(context.l10n.tvFamilyAttachedTo(
                          (info['owner'] ?? '').toString())),
                    ),
                  if (who.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(context.l10n.tvFamilyWhoHeader,
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 1.4)),
                    for (final dynamic raw in who)
                      if (raw is Map<String, dynamic>)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            raw['playing'] == true
                                ? Icons.play_circle_fill_rounded
                                : Icons.circle,
                            size: raw['playing'] == true ? 22 : 12,
                            color: raw['playing'] == true
                                ? AppColors.royalGold
                                : (raw['online'] == true
                                    ? AppColors.success
                                    : AppColors.textMuted),
                          ),
                          title: Text(_whoName(raw)),
                          trailing: Text(
                            raw['playing'] == true
                                ? context.l10n.tvFamilyPlayingNow
                                : (raw['online'] == true
                                    ? context.l10n.tvFamilyOnline
                                    : context.l10n.tvFamilyOffline),
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: raw['playing'] == true
                                    ? AppColors.royalGold
                                    : AppColors.textSecondary),
                          ),
                        ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(context.l10n.tvFamilyResumeSyncNote,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (isMember)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _leave,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(_busy
                          ? context.l10n.tvFamilyBusy
                          : context.l10n.tvFamilyLeave),
                    )
                  else ...<Widget>[
                    Text(context.l10n.familyJoinTitle,
                        style: AppTextStyles.headlineMedium),
                    const SizedBox(height: 6),
                    Text(context.l10n.familyJoinHint,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: const TextStyle(
                          fontSize: 28, letterSpacing: 8),
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _join(),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _join,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(_busy
                          ? context.l10n.tvFamilyBusy
                          : context.l10n.familyJoinButton),
                    ),
                  ],
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(_message!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                  Text(context.l10n.tvFamilySimultaneousNote,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
    );
  }
}
