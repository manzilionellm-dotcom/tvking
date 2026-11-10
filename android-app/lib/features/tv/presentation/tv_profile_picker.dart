// =========================================================
//  tv_profile_picker.dart — « Qui regarde ? »
// =========================================================
//  Grandes cartes, télécommande. OK choisit. « Plus tard » ferme
//  sans changer : le profil déjà actif (profil 1 au premier
//  jour) continue, et les chaînes ne sont pas bloquées.
//
//  Quitter le profil Enfants demande son code. Y entrer, non.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import 'tv_profile_label.dart';

import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../security/data/app_pin_settings.dart';
import '../core/tv_dimens.dart';
import '../core/tv_field_keys.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_parental_screen.dart';
import 'tv_add_source_screen.dart';
import 'tv_shell.dart';

/// Une fois par lancement de l'app : on ne repose pas le choix
/// devant l'accueil à chaque retour de Direct.
class StartupPickerSession {
  static bool shown = false;
}

/// Icône + couleur d'un profil. Uniquement des tokens TV.
abstract final class ProfileLooks {
  static IconData icon(FamilyProfile p) {
    if (p.isKids) return Icons.child_care_rounded;
    const List<IconData> icons = <IconData>[
      Icons.person_rounded,
      Icons.face_rounded,
      Icons.favorite_rounded,
      Icons.star_rounded,
      Icons.home_rounded,
      Icons.pets_rounded,
    ];
    final int i = p.avatar.clamp(0, icons.length - 1);
    return icons[i];
  }

  static Color color(FamilyProfile p, {BuildContext? context}) {
    final palette =
        context == null ? const TvAppTokens() : TvAppTokens.of(context);
    if (p.isKids) return palette.success;
    final List<Color> colors = <Color>[
      palette.accent,
      palette.accentBright,
      palette.live,
      palette.success,
      palette.muted,
      palette.text,
    ];
    final int i = p.avatar.clamp(0, colors.length - 1);
    return colors[i];
  }
}

class TvProfilePickerScreen extends StatefulWidget {
  const TvProfilePickerScreen({super.key, this.sourceBuilderForTesting});

  /// Route de test utilisant le vrai formulaire sans serveur fournisseur.
  final Widget Function(String profileId)? sourceBuilderForTesting;

  @override
  State<TvProfilePickerScreen> createState() => _TvProfilePickerScreenState();
}

class _TvProfilePickerScreenState extends State<TvProfilePickerScreen> {
  bool _creating = false;

  Future<void> _add() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final profile = await createTvProfile(context);
      if (profile == null || !mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => TvShell(
          child: widget.sourceBuilderForTesting?.call(profile.id) ??
              TvAddSourceScreen(targetProfileId: profile.id),
        ),
      ));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileRepository.instance,
      builder: (BuildContext context, _) {
        final List<FamilyProfile> profiles =
            ProfileRepository.instance.catalog.profiles;
        final String activeId = ProfileRepository.instance.active.id;
        return TvShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.tvWhoWatching,
                style: TvAppTokens.of(context).display(
                  TvDimens.displayS,
                  color: TvAppTokens.of(context).text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.tvProfilePickerHelp,
                style: TvAppTokens.of(context)
                    .ui(TvDimens.body, color: TvAppTokens.of(context).muted),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < profiles.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 22),
                        _ProfileCard(
                          profile: profiles[i],
                          active: profiles[i].id == activeId,
                          autofocus: profiles[i].id == activeId,
                          onSelect: () => _choose(context, profiles[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Center(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    if (ProfileRepository.instance.catalog.canAdd)
                      _PickerAction(
                        key: const ValueKey<String>('tv-profile-add'),
                        label: context.l10n.buttonAdd,
                        onSelect: _creating ? null : _add,
                      ),
                    _PickerAction(
                      label: context.l10n.tvLater,
                      onSelect: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _choose(BuildContext context, FamilyProfile target) async {
    final bool ok = await confirmProfileSwitch(context, target.id);
    if (!ok || !context.mounted) return;
    await ProfileRepository.instance.activate(target.id, leaveAllowed: true);
    if (context.mounted) Navigator.of(context).pop(true);
  }
}

class _PickerAction extends StatelessWidget {
  const _PickerAction({super.key, required this.label, required this.onSelect});
  final String label;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => TvFocusBuilder(
        enabled: onSelect != null,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final palette = TvAppTokens.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: focused ? palette.accent : palette.card,
              borderRadius: BorderRadius.circular(TvTokens.rButton),
              border:
                  Border.all(color: focused ? palette.accent : palette.line),
            ),
            child: Text(label,
                style: palette.ui(
                  TvDimens.title,
                  weight: FontWeight.w700,
                  color: focused ? palette.onAccent : palette.text,
                )),
          );
        },
      );
}

/// Même création depuis l'accueil et les réglages. Le PIN est demandé avant
/// la création si l'on quitte Enfants : ajouter un profil n'est pas une sortie
/// dérobée. Un abandon du formulaire laissera un profil vide configurable.
Future<FamilyProfile?> createTvProfile(BuildContext context,
    {bool kids = false}) async {
  final repository = ProfileRepository.instance;
  await repository.load();
  if (!context.mounted ||
      !repository.catalog.canAdd ||
      (kids && repository.catalog.hasKids)) {
    return null;
  }
  String approvedFrom = repository.active.id;
  if (!await confirmProfileSwitch(context, '__new_profile__') ||
      !context.mounted) {
    return null;
  }
  final String? name = await askProfileName(
    context,
    title: kids ? context.l10n.tvKidsProfile : context.l10n.tvNewProfile,
    initial: kids ? context.l10n.tvChildren : '',
  );
  if (name == null || !context.mounted) return null;
  if (repository.active.id != approvedFrom) {
    if (!await confirmProfileSwitch(context, '__new_profile__') ||
        !context.mounted) {
      return null;
    }
    approvedFrom = repository.active.id;
  }
  final profile = await repository.addProfile(name: name, isKids: kids);
  if (!context.mounted) return null;
  if (profile == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.tvProfileAddFailed)),
    );
    return null;
  }
  if (repository.active.id != approvedFrom &&
      !await confirmProfileSwitch(context, profile.id)) {
    return null;
  }
  if (!context.mounted ||
      !await repository.activate(profile.id, leaveAllowed: true)) {
    return null;
  }
  if (kids && context.mounted) await offerKidsPin(context);
  return profile;
}

/// Demande le code si on QUITTE le profil Enfants. Sinon, laisse passer.
/// Le code vérifié est celui du profil encore actif (le profil Enfants).
Future<bool> confirmProfileSwitch(BuildContext context, String nextId) async {
  final FamilyProfile current = ProfileRepository.instance.active;
  if (!KidsProfilePolicy.mustConfirmLeave(
    currentIsKids: current.isKids,
    currentId: current.id,
    nextId: nextId,
  )) {
    return true;
  }
  return askParentalPin(context);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onSelect,
    this.autofocus = false,
  });

  final FamilyProfile profile;
  final bool active;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).text;
        return Container(
          width: 200,
          height: 240,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : TvAppTokens.of(context).card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
              color: focused
                  ? TvAppTokens.of(context).accent
                  : (active
                      ? TvAppTokens.of(context).accentBright
                      : TvAppTokens.of(context).line),
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                ProfileLooks.icon(profile),
                size: 64,
                color: focused
                    ? TvAppTokens.of(context).onAccent
                    : ProfileLooks.color(profile, context: context),
              ),
              const SizedBox(height: 16),
              Text(
                tvProfileLabel(context, profile),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvAppTokens.of(context)
                    .ui(TvDimens.title, weight: FontWeight.w700, color: fg),
              ),
              const SizedBox(height: 6),
              Text(
                profile.isKids
                    ? context.l10n.tvChildren
                    : (active
                        ? context.l10n.tvProfileActive
                        : context.l10n.navProfile),
                style: TvAppTokens.of(context).ui(
                  TvDimens.caption,
                  color: focused
                      ? TvAppTokens.of(context).onAccent
                      : TvAppTokens.of(context).muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Saisie d'un prénom, avec des suggestions (la télécommande
/// n'aime pas les claviers). Retourne null si on annule.
Future<String?> askProfileName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => TvShell(
        child: _NameScreen(title: title, initial: initial),
      ),
    ),
  );
}

class _NameScreen extends StatefulWidget {
  const _NameScreen({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<_NameScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  List<String> get _ideas => <String>[
        context.l10n.tvNameMum,
        context.l10n.tvNameDad,
        context.l10n.tvChildren,
        context.l10n.tvNameGuest,
        context.l10n.tvNameLivingRoom,
      ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _text.text.trim();
    if (name.isEmpty || name.length > 18) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.title,
              style: TvAppTokens.of(
                context,
              ).display(TvDimens.displayS, color: TvAppTokens.of(context).text),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tvNameLimit,
              style: TvAppTokens.of(context)
                  .ui(TvDimens.body, color: TvAppTokens.of(context).muted),
            ),
            const SizedBox(height: 18),
            TvFieldKeys(
              child: TextField(
              controller: _text,
              autofocus: widget.initial.isEmpty,
              style: TvAppTokens.of(context)
                  .ui(TvDimens.title, color: TvAppTokens.of(context).text),
              cursorColor: TvAppTokens.of(context).accent,
              maxLength: 18,
              decoration: InputDecoration(
                counterStyle: TvAppTokens.of(
                  context,
                ).ui(TvDimens.caption, color: TvAppTokens.of(context).mutedDim),
                hintText: context.l10n.tvFirstName,
                hintStyle: TvAppTokens.of(
                  context,
                ).ui(TvDimens.title, color: TvAppTokens.of(context).mutedDim),
                filled: true,
                fillColor: TvAppTokens.of(context).card,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  borderSide: BorderSide(color: TvAppTokens.of(context).line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  borderSide: BorderSide(
                    color: TvAppTokens.of(context).accent,
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final String idea in _ideas)
                  TvFocusBuilder(
                    autofocus: idea == widget.initial,
                    onSelect: () => setState(() => _text.text = idea),
                    builder: (BuildContext context, bool focused) {
                      final Color fg = focused
                          ? TvAppTokens.of(context).onAccent
                          : TvAppTokens.of(context).text;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? TvAppTokens.of(context).accent
                              : TvAppTokens.of(context).sel,
                          borderRadius: BorderRadius.circular(TvTokens.rButton),
                        ),
                        child: Text(
                          idea,
                          style: TvAppTokens.of(context).ui(
                            TvDimens.label,
                            weight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                TvFocusBuilder(
                  onSelect: _save,
                  builder: (BuildContext context, bool focused) =>
                      _btn(context.l10n.buttonSave, focused, primary: true),
                ),
                const SizedBox(width: 12),
                TvFocusBuilder(
                  onSelect: () => Navigator.of(context).pop(),
                  builder: (BuildContext context, bool focused) =>
                      _btn(context.l10n.buttonCancel, focused),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, bool focused, {bool primary = false}) {
    final Color fg = focused
        ? TvAppTokens.of(context).onAccent
        : TvAppTokens.of(context).text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
        style: TvAppTokens.of(context)
            .ui(TvDimens.title, weight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Le code du profil Enfants vient d'être choisi ? On l'enregistre
/// sur le profil ACTIF (il faut donc avoir basculé avant).
Future<void> offerKidsPin(BuildContext context) async {
  final String? pin = await pickNewParentalPin(context);
  if (pin == null) return;
  try {
    await AppPinSettings.instance.setPin(pin);
  } catch (_) {
    // L'écran a déjà vérifié 4 chiffres.
  }
}
