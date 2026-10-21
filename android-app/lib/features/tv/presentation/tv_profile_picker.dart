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

import '../../../core/app/zuno_edition.dart';
import '../../../core/i18n/l10n_extension.dart';
import 'tv_profile_label.dart';

import '../../cast/data/cast_platform.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_policies.dart';
import '../../security/data/app_pin_settings.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_parental_screen.dart';
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

  static Color color(FamilyProfile p) {
    if (p.isKids) return TvTokens.success;
    const List<Color> colors = <Color>[
      TvTokens.accent,
      TvTokens.accentBright,
      TvTokens.live,
      TvTokens.success,
      TvTokens.muted,
      TvTokens.text,
    ];
    final int i = p.avatar.clamp(0, colors.length - 1);
    return colors[i];
  }
}

class TvProfilePickerScreen extends StatelessWidget {
  const TvProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileRepository.instance,
      builder: (BuildContext context, _) {
        final List<FamilyProfile> profiles =
            ProfileRepository.instance.catalog.profiles;
        final String activeId = ProfileRepository.instance.active.id;
        if (CastPlatform.zunoEdition == ZunoEdition.touch) {
          return TvShell(child: _touchPicker(context, profiles, activeId));
        }
        return TvShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.tvWhoWatching,
                style: TvTokens.display(
                  TvDimens.displayS,
                  color: TvTokens.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.tvProfilePickerHelp,
                style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
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
                child: TvFocusBuilder(
                  onSelect: () => Navigator.of(context).pop(false),
                  builder: (BuildContext context, bool focused) {
                    final Color fg =
                        focused ? TvTokens.onAccent : TvTokens.text;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: focused ? TvTokens.accent : TvTokens.card,
                        borderRadius: BorderRadius.circular(TvTokens.rButton),
                        border: Border.all(
                          color: focused ? TvTokens.accent : TvTokens.line,
                        ),
                      ),
                      child: Text(
                        context.l10n.tvLater,
                        style: TvTokens.ui(
                          TvDimens.title,
                          weight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Les profils gardent leurs règles et leur action de sélection. Seule la
  /// disposition change : des lignes souples évitent de couper les prénoms
  /// sur un téléphone, même lorsque la police système est agrandie.
  Widget _touchPicker(
    BuildContext context,
    List<FamilyProfile> profiles,
    String activeId,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TvDimens.touchFormWidth),
        child: SingleChildScrollView(
          key: const ValueKey<String>('zuno-touch-profile-picker-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.tvWhoWatching,
                style: TvTokens.display(TvDimens.title),
              ),
              const SizedBox(height: TvDimens.touchGap),
              Text(
                context.l10n.tvProfilePickerHelp,
                style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
              ),
              const SizedBox(height: TvDimens.touchSafeV),
              for (final FamilyProfile profile in profiles) ...<Widget>[
                Semantics(
                  selected: profile.id == activeId,
                  child: OutlinedButton(
                    key: ValueKey<String>('zuno-touch-profile-${profile.id}'),
                    onPressed: () => _choose(context, profile),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TvTokens.text,
                      backgroundColor: TvTokens.card,
                      alignment: AlignmentDirectional.centerStart,
                      minimumSize: const Size(0, TvDimens.touchButtonHeight),
                      padding: const EdgeInsets.all(TvDimens.touchSafeH),
                      side: BorderSide(
                        color: profile.id == activeId
                            ? TvTokens.accentBright
                            : TvTokens.line,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TvTokens.rCard),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          ProfileLooks.icon(profile),
                          size: TvDimens.touchIcon,
                          color: ProfileLooks.color(profile),
                        ),
                        const SizedBox(width: TvDimens.touchGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                tvProfileLabel(context, profile),
                                style: TvTokens.ui(
                                  TvDimens.title,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: TvDimens.rowGap),
                              Text(
                                profile.isKids
                                    ? context.l10n.tvChildren
                                    : (profile.id == activeId
                                        ? context.l10n.tvProfileActive
                                        : context.l10n.navProfile),
                                style: TvTokens.ui(
                                  TvDimens.label,
                                  color: TvTokens.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: TvDimens.touchGap),
              ],
              OutlinedButton(
                key: const ValueKey<String>('zuno-touch-profile-later'),
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TvTokens.text,
                  minimumSize: const Size(0, TvDimens.touchButtonHeight),
                  padding: const EdgeInsets.all(TvDimens.touchGap),
                  side: const BorderSide(color: TvTokens.line),
                  textStyle: TvTokens.ui(
                    TvDimens.label,
                    weight: FontWeight.w700,
                  ),
                ),
                child: Text(context.l10n.tvLater, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, FamilyProfile target) async {
    final bool ok = await confirmProfileSwitch(context, target.id);
    if (!ok || !context.mounted) return;
    await ProfileRepository.instance.activate(target.id, leaveAllowed: true);
    if (context.mounted) Navigator.of(context).pop(true);
  }
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
        final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
        return Container(
          width: 200,
          height: 240,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
              color: focused
                  ? TvTokens.accent
                  : (active ? TvTokens.accentBright : TvTokens.line),
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                ProfileLooks.icon(profile),
                size: 64,
                color:
                    focused ? TvTokens.onAccent : ProfileLooks.color(profile),
              ),
              const SizedBox(height: 16),
              Text(
                tvProfileLabel(context, profile),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(
                  TvDimens.title,
                  weight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                profile.isKids
                    ? context.l10n.tvChildren
                    : (active
                        ? context.l10n.tvProfileActive
                        : context.l10n.navProfile),
                style: TvTokens.ui(
                  TvDimens.caption,
                  color: focused ? TvTokens.onAccent : TvTokens.muted,
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
    if (CastPlatform.zunoEdition == ZunoEdition.touch) {
      return _touchNameForm(context);
    }
    return Center(
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.title,
              style: TvTokens.display(TvDimens.displayS, color: TvTokens.text),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tvNameLimit,
              style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _text,
              autofocus: widget.initial.isEmpty,
              style: TvTokens.ui(TvDimens.title, color: TvTokens.text),
              cursorColor: TvTokens.accent,
              maxLength: 18,
              decoration: InputDecoration(
                counterStyle: TvTokens.ui(
                  TvDimens.caption,
                  color: TvTokens.mutedDim,
                ),
                hintText: context.l10n.tvFirstName,
                hintStyle: TvTokens.ui(
                  TvDimens.title,
                  color: TvTokens.mutedDim,
                ),
                filled: true,
                fillColor: TvTokens.card,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  borderSide: const BorderSide(color: TvTokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  borderSide: const BorderSide(
                    color: TvTokens.accent,
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _save(),
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
                      final Color fg =
                          focused ? TvTokens.onAccent : TvTokens.text;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: focused ? TvTokens.accent : TvTokens.sel,
                          borderRadius: BorderRadius.circular(TvTokens.rButton),
                        ),
                        child: Text(
                          idea,
                          style: TvTokens.ui(
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

  /// Le clavier Android réduit l'espace disponible via TvShell. Le nom,
  /// les suggestions et les deux actions restent donc dans le même scroll.
  Widget _touchNameForm(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TvDimens.touchFormWidth),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(widget.title, style: TvTokens.display(TvDimens.title)),
              const SizedBox(height: TvDimens.touchGap),
              Text(
                context.l10n.tvNameLimit,
                style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
              ),
              const SizedBox(height: TvDimens.touchSafeV),
              TextField(
                key: const ValueKey<String>('zuno-touch-profile-name'),
                controller: _text,
                autofocus: widget.initial.isEmpty,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: 18,
                style: TvTokens.ui(TvDimens.body),
                cursorColor: TvTokens.accent,
                decoration: InputDecoration(
                  hintText: context.l10n.tvFirstName,
                  hintStyle:
                      TvTokens.ui(TvDimens.body, color: TvTokens.mutedDim),
                  counterStyle:
                      TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
                  filled: true,
                  fillColor: TvTokens.card,
                  contentPadding: const EdgeInsets.all(TvDimens.touchSafeH),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TvTokens.rButton),
                    borderSide: const BorderSide(color: TvTokens.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TvTokens.rButton),
                    borderSide: const BorderSide(color: TvTokens.accent),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: TvDimens.touchGap),
              Wrap(
                spacing: TvDimens.touchGap,
                runSpacing: TvDimens.touchGap,
                children: <Widget>[
                  for (final String idea in _ideas)
                    OutlinedButton(
                      onPressed: () {
                        _text.value = TextEditingValue(
                          text: idea,
                          selection: TextSelection.collapsed(
                            offset: idea.length,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TvTokens.text,
                        backgroundColor: TvTokens.sel,
                        minimumSize: const Size(0, TvDimens.touchTarget),
                        padding: const EdgeInsets.all(TvDimens.touchGap),
                        side: const BorderSide(color: TvTokens.line),
                        textStyle: TvTokens.ui(TvDimens.label),
                      ),
                      child: Text(idea, textAlign: TextAlign.center),
                    ),
                ],
              ),
              const SizedBox(height: TvDimens.touchSafeV),
              FilledButton(
                key: const ValueKey<String>('zuno-touch-profile-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  foregroundColor: TvTokens.onAccent,
                  backgroundColor: TvTokens.accent,
                  minimumSize: const Size(0, TvDimens.touchButtonHeight),
                  padding: const EdgeInsets.all(TvDimens.touchGap),
                  textStyle: TvTokens.ui(
                    TvDimens.label,
                    weight: FontWeight.w700,
                  ),
                ),
                child:
                    Text(context.l10n.buttonSave, textAlign: TextAlign.center),
              ),
              const SizedBox(height: TvDimens.touchGap),
              OutlinedButton(
                key: const ValueKey<String>('zuno-touch-profile-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TvTokens.text,
                  minimumSize: const Size(0, TvDimens.touchButtonHeight),
                  padding: const EdgeInsets.all(TvDimens.touchGap),
                  side: const BorderSide(color: TvTokens.line),
                  textStyle: TvTokens.ui(TvDimens.label),
                ),
                child: Text(
                  context.l10n.buttonCancel,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, bool focused, {bool primary = false}) {
    final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: focused
            ? TvTokens.accent
            : (primary ? TvTokens.sel : Colors.transparent),
        borderRadius: BorderRadius.circular(TvTokens.rButton),
        border: Border.all(color: focused ? TvTokens.accent : TvTokens.line),
      ),
      child: Text(
        label,
        style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700, color: fg),
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
