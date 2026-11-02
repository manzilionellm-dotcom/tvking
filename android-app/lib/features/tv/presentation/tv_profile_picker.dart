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
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
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
                child: TvFocusBuilder(
                  onSelect: () => Navigator.of(context).pop(false),
                  builder: (BuildContext context, bool focused) {
                    final Color fg = focused
                        ? TvAppTokens.of(context).onAccent
                        : TvAppTokens.of(context).text;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
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
                      child: Text(
                        context.l10n.tvLater,
                        style: TvAppTokens.of(context).ui(
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
            TextField(
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
