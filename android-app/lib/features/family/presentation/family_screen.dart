// =========================================================
//  family_screen.dart — Choisir qui regarde
// =========================================================
//  OK sur un nom change de profil. Quitter un profil enfant
//  demande le code parental s'il existe. Sinon on le dit, et
//  on laisse passer : la box de test ne doit pas se bloquer.
//  Ça ne lance aucune chaîne.
// =========================================================

import 'package:flutter/material.dart';

import '../../box_extras/box_text.dart';
import '../../security/data/app_pin_settings.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../data/family_profile_store.dart';
import '../domain/family_profile.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  String? _note;

  @override
  void initState() {
    super.initState();
    FamilyProfileStore.instance.load().then((_) async {
      if (!FamilyProfileStore.flag.value) return;
      await FamilyProfileStore.instance.apply();
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggle() async {
    final bool next = !FamilyProfileStore.flag.value;
    await FamilyProfileStore.instance.setEnabled(next);
    if (mounted) setState(() {});
  }

  Future<void> _switch(FamilyProfile profile) async {
    final FamilyProfile current = FamilyProfileStore.instance.active;
    if (current.child && !profile.child) {
      final bool ok = await _leaveChild(context);
      if (!ok || !mounted) return;
    }
    await FamilyProfileStore.instance.switchTo(profile.id);
    if (mounted) {
      setState(() {
        _note = profile.child
            ? boxText(
                context,
                'Mode enfants allumé pour ${profile.name}.',
                'Kids mode is on for ${profile.name}.',
              )
            : null;
      });
    }
  }

  Future<void> _add(bool child) async {
    final int n = FamilyProfileStore.instance.profiles.length;
    final FamilyProfile? created = await FamilyProfileStore.instance.add(
      name: child ? 'Enfant $n' : 'Adulte $n',
      child: child,
    );
    if (created == null || !mounted) return;
    await _switch(created);
  }

  Future<void> _remove() async {
    final FamilyProfile current = FamilyProfileStore.instance.active;
    if (current.isHome) return;
    if (current.child) {
      final bool ok = await _leaveChild(context);
      if (!ok || !mounted) return;
    }
    await FamilyProfileStore.instance.removeActive();
    if (mounted) setState(() => _note = null);
  }

  Future<bool> _leaveChild(BuildContext context) async {
    if (!await AppPinSettings.instance.hasCustomPin()) {
      if (mounted) {
        setState(() {
          _note = boxText(
            context,
            'Pas encore de code parental. Tu peux le poser dans Contrôle parental.',
            'No parental code yet. You can set one in Parental controls.',
          );
        });
      }
      return true;
    }
    final String? pin = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _PinDialog(),
    );
    if (pin == null) return false;
    final bool ok = await AppPinSettings.instance.verify(pin);
    if (!ok && mounted) {
      setState(() {
        _note = boxText(
          context,
          'Code refusé. Le profil enfant reste.',
          'Code refused. The child profile stays.',
        );
      });
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final FamilyProfileStore store = FamilyProfileStore.instance;
    final bool on = FamilyProfileStore.flag.value;
    return ListView(
      children: <Widget>[
        Text(
          boxText(context, 'Famille', 'Family'),
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          boxText(
            context,
            'Chacun a son accueil, ses favoris et son historique. Maison garde ce qui était déjà là. Un profil enfant masque le contenu adulte.',
            'Each person has a home, favorites and history. Home keeps what was already there. A child profile hides adult content.',
          ),
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 14),
        TvFocusable(
          autofocus: true,
          onSelect: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              on
                  ? boxText(context, 'Profils allumés — OK pour couper', 'Profiles on — OK to turn off')
                  : boxText(context, 'Profils coupés — OK pour allumer', 'Profiles off — OK to turn on'),
              style: TextStyle(
                fontSize: TvDimens.titleS,
                fontWeight: FontWeight.w700,
                color: TvTokens.text,
              ),
            ),
          ),
        ),
        if (_note != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_note!, style: TextStyle(fontSize: TvDimens.label, color: TvTokens.muted)),
        ],
        const SizedBox(height: 16),
        if (on)
          for (final FamilyProfile profile in store.profiles)
            _ProfileRow(
              profile: profile,
              selected: profile.id == store.activeId,
              onSelect: () => _switch(profile),
            ),
        if (on && store.profiles.length < 6) ...<Widget>[
          _Action(
            label: boxText(context, 'Ajouter un adulte', 'Add an adult'),
            onSelect: () => _add(false),
          ),
          _Action(
            label: boxText(context, 'Ajouter un enfant', 'Add a child'),
            onSelect: () => _add(true),
          ),
        ],
        if (on && !store.isHome)
          _Action(
            label: boxText(context, 'Retirer ce profil', 'Remove this profile'),
            onSelect: _remove,
          ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.selected,
    required this.onSelect,
  });

  final FamilyProfile profile;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final String kind = profile.child
        ? boxText(context, 'Enfant', 'Child')
        : boxText(context, 'Adulte', 'Adult');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        onSelect: onSelect,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
              color: selected ? TvTokens.accent : TvTokens.line,
            ),
          ),
          child: Text(
            '${profile.name} · $kind${selected ? ' · OK' : ''}',
            style: TextStyle(
              fontSize: TvDimens.titleS,
              fontWeight: FontWeight.w700,
              color: TvTokens.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onSelect});
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        onSelect: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.accentBright),
          ),
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';

  void _press(String digit) {
    if (_pin.length >= 8) return;
    setState(() => _pin += digit);
    if (_pin.length >= 4) {
      Navigator.of(context).pop(_pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TvTokens.card,
      title: Text(
        boxText(context, 'Code parental', 'Parental code'),
        style: TextStyle(fontSize: TvDimens.title, color: TvTokens.text),
      ),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (int i = 0; i < 10; i++)
            TvFocusable(
              autofocus: i == 0,
              onSelect: () => _press('$i'),
              child: SizedBox(
                width: 64,
                height: 48,
                child: Center(
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontSize: TvDimens.title,
                      color: TvTokens.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
