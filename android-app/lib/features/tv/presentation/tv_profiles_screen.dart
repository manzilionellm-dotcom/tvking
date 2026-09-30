// =========================================================
//  tv_profiles_screen.dart — Gérer les profils (Réglages)
// =========================================================
//  Ajouter (jusqu'à 4), renommer, supprimer (pas le profil 1),
//  créer le profil Enfants, et couper le choix au démarrage.
//
//  Le profil Enfants : mode enfants forcé, code à part, on ne
//  le quitte qu'avec ce code. Ses favoris / historique / reprise
//  / rappels ne se mélangent pas avec ceux des parents.
// =========================================================

import 'package:flutter/material.dart';

import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../security/data/app_pin_settings.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_profile_picker.dart';

class TvProfilesScreen extends StatefulWidget {
  const TvProfilesScreen({super.key});

  @override
  State<TvProfilesScreen> createState() => _TvProfilesScreenState();
}

class _TvProfilesScreenState extends State<TvProfilesScreen> {
  String? _focusId;
  bool? _defaultPin;

  @override
  void initState() {
    super.initState();
    ProfileRepository.instance.addListener(_onChange);
    _refreshPin();
  }

  @override
  void dispose() {
    ProfileRepository.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
      _refreshPin();
    }
  }

  Future<void> _refreshPin() async {
    final bool def = await AppPinSettings.instance.isUsingDefault();
    if (mounted) setState(() => _defaultPin = def);
  }

  ProfileCatalog get _cat => ProfileRepository.instance.catalog;

  FamilyProfile get _focused {
    final FamilyProfile? p = _focusId == null ? null : _cat.byId(_focusId!);
    return p ?? _cat.active;
  }

  Future<void> _use(FamilyProfile target) async {
    final bool ok = await confirmProfileSwitch(context, target.id);
    if (!ok || !mounted) return;
    final bool entered =
        await ProfileRepository.instance.activate(target.id, leaveAllowed: true);
    if (entered && mounted) setState(() => _focusId = target.id);
  }

  Future<void> _add({required bool kids}) async {
    if (!_cat.canAdd) return;
    if (kids && _cat.hasKids) return;
    final String? name = await askProfileName(
      context,
      title: kids ? 'Profil Enfants' : 'Nouveau profil',
      initial: kids ? 'Enfants' : '',
    );
    if (name == null || !mounted) return;
    final FamilyProfile? created = await ProfileRepository.instance.addProfile(
      name: name,
      isKids: kids,
    );
    if (created == null || !mounted) {
      _toast(kids ? 'Un profil Enfants existe déjà.' : 'Impossible d\'ajouter.');
      return;
    }
    // Entrer dans le nouveau profil ne demande pas de code.
    // S'il est Enfants, on propose tout de suite SON code (pas celui
    // du parent : on a déjà basculé).
    final bool entered = await ProfileRepository.instance.activate(
      created.id,
      leaveAllowed: true,
    );
    if (!entered || !mounted) return;
    if (kids) await offerKidsPin(context);
    if (mounted) {
      setState(() => _focusId = created.id);
      _toast(kids
          ? 'Profil Enfants prêt. Le mode enfants reste allumé.'
          : 'Profil « $name » créé.');
    }
  }

  Future<void> _rename(FamilyProfile p) async {
    final String? name = await askProfileName(
      context,
      title: 'Renommer',
      initial: p.name,
    );
    if (name == null) return;
    final bool ok = await ProfileRepository.instance.rename(p.id, name);
    if (!ok && mounted) _toast('Nom vide ou trop long.');
  }

  Future<void> _delete(FamilyProfile p) async {
    if (p.id == ProfileIds.origin) return;
    bool allowed = true;
    if (p.isKids && p.id == ProfileRepository.instance.active.id) {
      allowed = await askLeave(context);
      if (!allowed || !mounted) return;
    }
    final bool sure = await _confirm(
      'Supprimer « ${p.name} » ?',
      'Ses favoris, son historique, sa reprise, ses rappels et son code '
          'seront effacés. Les chaînes restent. Le profil 1 n\'est pas touché.',
    );
    if (!sure || !mounted) return;
    final bool ok = await ProfileRepository.instance.remove(p.id, leaveAllowed: allowed);
    if (!ok && mounted) _toast('Ce profil ne peut pas être supprimé.');
  }

  Future<bool> askLeave(BuildContext context) => confirmProfileSwitch(
        context,
        ProfileIds.origin,
      );

  Future<void> _toggleAsk() async {
    if (_cat.profiles.length < 2) return;
    final bool now = StartupProfilePolicy.shouldOffer(
      askOnStartup: _cat.askOnStartup,
      profileCount: _cat.profiles.length,
    );
    await ProfileRepository.instance.setAskOnStartup(!now);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String body) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.86),
      builder: (BuildContext ctx) => Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: TvTokens.card,
              borderRadius: BorderRadius.circular(TvTokens.rCard),
              border: Border.all(color: TvTokens.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title,
                    textAlign: TextAlign.center,
                    style: TvTokens.display(TvDimens.headline, color: TvTokens.text)),
                const SizedBox(height: 10),
                Text(body,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(TvDimens.body, color: TvTokens.muted)),
                const SizedBox(height: 20),
                _DialogBtn(
                  label: 'Supprimer',
                  onSelect: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 10),
                _DialogBtn(
                  label: 'Annuler',
                  autofocus: true,
                  primary: true,
                  onSelect: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ProfileCatalog cat = _cat;
    final FamilyProfile focused = _focused;
    final bool ask = StartupProfilePolicy.shouldOffer(
      askOnStartup: cat.askOnStartup,
      profileCount: cat.profiles.length,
    );
    final bool origin = focused.id == ProfileIds.origin;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Text('Profils',
            style: TvTokens.display(TvDimens.displayM, color: TvTokens.text)),
        const SizedBox(height: 6),
        Text(
          'Jusqu\'à 4. Favoris, historique, reprise, rappels et code sont '
          'séparés. Les chaînes, non : elles restent pour tout le monde.',
          style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 18),
        for (final FamilyProfile p in cat.profiles) ...<Widget>[
          _Row(
            profile: p,
            active: p.id == cat.activeId,
            selected: p.id == focused.id,
            autofocus: p.id == cat.activeId,
            onSelect: () => _use(p),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(focused.name,
            style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700, color: TvTokens.text)),
        const SizedBox(height: 4),
        Text(_detail(focused, origin),
            style: TvTokens.ui(TvDimens.label, color: TvTokens.muted)),
        if (focused.isKids && focused.id == cat.activeId && _defaultPin == true) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'Le code est encore 0000. Changez-le dans Contrôle parental.',
            style: TvTokens.ui(TvDimens.label,
                weight: FontWeight.w600, color: TvTokens.accentBright),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _Action(
              label: 'Renommer',
              icon: Icons.edit_rounded,
              onSelect: () => _rename(focused),
            ),
            if (!origin)
              _Action(
                label: 'Supprimer',
                icon: Icons.delete_outline_rounded,
                onSelect: () => _delete(focused),
              ),
            if (cat.canAdd)
              _Action(
                label: 'Ajouter',
                icon: Icons.person_add_rounded,
                onSelect: () => _add(kids: false),
              ),
            if (cat.canAdd && !cat.hasKids)
              _Action(
                label: 'Profil Enfants',
                icon: Icons.child_care_rounded,
                onSelect: () => _add(kids: true),
              ),
            _Action(
              label: ask ? 'Choix au démarrage : oui' : 'Choix au démarrage : non',
              icon: ask ? Icons.waving_hand_rounded : Icons.flash_on_rounded,
              onSelect: _toggleAsk,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          cat.profiles.length < 2
              ? 'Le choix au démarrage apparaît dès le 2e profil. '
                  'Avec un seul profil, la box s\'ouvre directement.'
              : '« Non » : la box s\'ouvre sur le dernier profil, sans écran. '
                  'Vous pourrez toujours changer ici, ou depuis l\'accueil.',
          style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim),
        ),
      ],
    );
  }

  String _detail(FamilyProfile p, bool origin) {
    if (p.isKids) {
      return 'Mode enfants verrouillé. On ne sort qu\'avec le code de ce profil. '
          'L\'adulte est masqué. Le profil 1 garde vos anciennes données.';
    }
    if (origin) {
      return 'Profil d\'origine : vos favoris, votre historique, votre reprise '
          'et votre code d\'avant la mise à jour sont ici. Il ne se supprime pas.';
    }
    return 'Tiroir à part. Supprimer ce profil n\'efface pas le profil 1.';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.profile,
    required this.active,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final FamilyProfile profile;
  final bool active;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : (selected ? TvTokens.sel : TvTokens.card),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
              color: focused
                  ? TvTokens.accent
                  : (active ? TvTokens.accentBright : TvTokens.line),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(ProfileLooks.icon(profile),
                  size: 28,
                  color: focused ? TvTokens.onAccent : ProfileLooks.color(profile)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(profile.name,
                    style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700, color: fg)),
              ),
              if (profile.isKids)
                Text('Enfants',
                    style: TvTokens.ui(TvDimens.caption,
                        color: focused ? TvTokens.onAccent : TvTokens.success)),
              if (active) ...<Widget>[
                const SizedBox(width: 12),
                Text('Actif',
                    style: TvTokens.ui(TvDimens.caption,
                        weight: FontWeight.w700,
                        color: focused ? TvTokens.onAccent : TvTokens.accentBright)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.icon, required this.onSelect});
  final String label;
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style: TvTokens.ui(TvDimens.label, weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.primary = false,
  });
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.accent
                : (primary ? TvTokens.sel : Colors.transparent),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700, color: fg)),
        );
      },
    );
  }
}
