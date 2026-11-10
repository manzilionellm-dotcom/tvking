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

import '../../../core/i18n/l10n_extension.dart';
import 'tv_profile_label.dart';

import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../security/data/app_pin_settings.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_profile_picker.dart';
import 'tv_add_source_screen.dart';
import 'tv_sources_screen.dart';
import 'tv_shell.dart';

class TvProfilesScreen extends StatefulWidget {
  const TvProfilesScreen({super.key});

  @override
  State<TvProfilesScreen> createState() => _TvProfilesScreenState();
}

class _TvProfilesScreenState extends State<TvProfilesScreen> {
  String? _focusId;
  bool? _defaultPin;
  bool _creating = false;

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
    final bool entered = await ProfileRepository.instance.activate(
      target.id,
      leaveAllowed: true,
    );
    if (entered && mounted) setState(() => _focusId = target.id);
  }

  Future<void> _add({required bool kids}) async {
    if (_creating) return;
    _creating = true;
    try {
      final FamilyProfile? created = await createTvProfile(context, kids: kids);
      if (created == null || !mounted) return;
      setState(() => _focusId = created.id);
      await _sources(created, newProfile: true);
    } finally {
      _creating = false;
    }
  }

  Future<void> _sources(FamilyProfile profile,
      {bool newProfile = false}) async {
    if (!await confirmProfileSwitch(context, profile.id) || !mounted) return;
    if (!await ProfileRepository.instance
            .activate(profile.id, leaveAllowed: true) ||
        !mounted) {
      return;
    }
    final current = ProfileRepository.instance.profileById(profile.id);
    if (current == null) return;
    final bool empty = current.playlistIds?.isEmpty == true;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => TvShell(
        child: newProfile || empty
            ? TvAddSourceScreen(targetProfileId: profile.id)
            : TvSourcesScreen(targetProfileId: profile.id),
      ),
    ));
  }

  Future<void> _rename(FamilyProfile p) async {
    final String initial = tvProfileLabel(context, p);
    final String? name = await askProfileName(
      context,
      title: context.l10n.tvRename,
      initial: initial,
    );
    if (name == null || name == initial) return;
    final bool ok = await ProfileRepository.instance.rename(p.id, name);
    if (!ok && mounted) _toast(context.l10n.tvNameInvalid);
  }

  Future<void> _delete(FamilyProfile p) async {
    if (p.id == ProfileIds.origin) return;
    bool allowed = true;
    if (p.isKids && p.id == ProfileRepository.instance.active.id) {
      allowed = await askLeave(context);
      if (!allowed || !mounted) return;
    }
    final bool sure = await _confirm(
      context.l10n.tvProfileDeleteTitle(tvProfileLabel(context, p)),
      context.l10n.tvProfileDeleteBody,
    );
    if (!sure || !mounted) return;
    final bool ok = await ProfileRepository.instance.remove(
      p.id,
      leaveAllowed: allowed,
    );
    if (!ok && mounted) _toast(context.l10n.tvProfileDeleteFailed);
  }

  Future<bool> askLeave(BuildContext context) =>
      confirmProfileSwitch(context, ProfileIds.origin);

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
              color: TvAppTokens.of(context).card,
              borderRadius: BorderRadius.circular(TvTokens.rCard),
              border: Border.all(color: TvAppTokens.of(context).line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TvAppTokens.of(context).display(
                    TvDimens.headline,
                    color: TvAppTokens.of(context).text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TvAppTokens.of(context)
                      .ui(TvDimens.body, color: TvAppTokens.of(context).muted),
                ),
                const SizedBox(height: 20),
                _DialogBtn(
                  label: context.l10n.buttonDelete,
                  onSelect: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 10),
                _DialogBtn(
                  label: context.l10n.buttonCancel,
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
        Text(
          context.l10n.tvProfiles,
          style: TvAppTokens.of(context)
              .display(TvDimens.displayM, color: TvAppTokens.of(context).text),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.tvProfilesHelp,
          style: TvAppTokens.of(context)
              .ui(TvDimens.body, color: TvAppTokens.of(context).muted),
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
        Text(
          tvProfileLabel(context, focused),
          style: TvAppTokens.of(context).ui(
            TvDimens.title,
            weight: FontWeight.w700,
            color: TvAppTokens.of(context).text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _detail(focused, origin),
          style: TvAppTokens.of(context)
              .ui(TvDimens.label, color: TvAppTokens.of(context).muted),
        ),
        if (focused.isKids &&
            focused.id == cat.activeId &&
            _defaultPin == true) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            context.l10n.tvDefaultPinWarning,
            style: TvAppTokens.of(context).ui(
              TvDimens.label,
              weight: FontWeight.w600,
              color: TvAppTokens.of(context).accentBright,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _Action(
              label: context.l10n.tvProfileSources,
              icon: Icons.playlist_play_rounded,
              onSelect: () => _sources(focused),
            ),
            _Action(
              label: context.l10n.tvRename,
              icon: Icons.edit_rounded,
              onSelect: () => _rename(focused),
            ),
            if (!origin)
              _Action(
                label: context.l10n.buttonDelete,
                icon: Icons.delete_outline_rounded,
                onSelect: () => _delete(focused),
              ),
            if (cat.canAdd)
              _Action(
                label: context.l10n.buttonAdd,
                icon: Icons.person_add_rounded,
                onSelect: () => _add(kids: false),
              ),
            if (cat.canAdd && !cat.hasKids)
              _Action(
                label: context.l10n.tvKidsProfile,
                icon: Icons.child_care_rounded,
                onSelect: () => _add(kids: true),
              ),
            _Action(
              label: ask
                  ? context.l10n.tvAskProfileOn
                  : context.l10n.tvAskProfileOff,
              icon: ask ? Icons.waving_hand_rounded : Icons.flash_on_rounded,
              onSelect: _toggleAsk,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          cat.profiles.length < 2
              ? context.l10n.tvProfileStartupSingle
              : context.l10n.tvProfileStartupHelp,
          style: TvAppTokens.of(context)
              .ui(TvDimens.caption, color: TvAppTokens.of(context).mutedDim),
        ),
      ],
    );
  }

  String _detail(FamilyProfile p, bool origin) {
    if (p.isKids) {
      return context.l10n.tvKidsProfileHelp;
    }
    if (origin) {
      return context.l10n.tvOriginProfileHelp;
    }
    return context.l10n.tvSeparateProfileHelp;
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
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : (selected
                      ? TvAppTokens.of(context).sel
                      : TvAppTokens.of(context).card),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
              color: focused
                  ? TvAppTokens.of(context).accent
                  : (active
                        ? TvAppTokens.of(context).accentBright
                        : TvAppTokens.of(context).line),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                ProfileLooks.icon(profile),
                size: 28,
                color: focused
                    ? TvAppTokens.of(context).onAccent
                    : ProfileLooks.color(profile, context: context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  tvProfileLabel(context, profile),
                  style: TvAppTokens.of(context)
                      .ui(TvDimens.title, weight: FontWeight.w700, color: fg),
                ),
              ),
              if (profile.isKids)
                Text(
                  context.l10n.tvChildren,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.caption,
                    color: focused
                        ? TvAppTokens.of(context).onAccent
                        : TvAppTokens.of(context).success,
                  ),
                ),
              if (active) ...<Widget>[
                const SizedBox(width: 12),
                Text(
                  context.l10n.tvProfileActive,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.caption,
                    weight: FontWeight.w700,
                    color: focused
                        ? TvAppTokens.of(context).onAccent
                        : TvAppTokens.of(context).accentBright,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onSelect,
  });
  final String label;
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : TvAppTokens.of(context).card,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
              color: focused
                  ? TvAppTokens.of(context).accent
                  : TvAppTokens.of(context).line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TvAppTokens.of(context)
                    .ui(TvDimens.label, weight: FontWeight.w700, color: fg),
              ),
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
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).text;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : (primary ? TvAppTokens.of(context).sel : Colors.transparent),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(
              color: focused
                  ? TvAppTokens.of(context).accent
                  : TvAppTokens.of(context).line,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TvAppTokens.of(context)
                .ui(TvDimens.title, weight: FontWeight.w700, color: fg),
          ),
        );
      },
    );
  }
}
