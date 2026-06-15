// =========================================================
//  tv_parental_screen.dart — Contrôle parental & Mode Enfants (TV)
// =========================================================
//  Fonctionnalité « famille » des grandes apps US (Netflix Kids, Disney+
//  Junior) : un MODE ENFANTS qui masque automatiquement tout l'Adulte,
//  protégé par le code PIN à 4 chiffres de l'app. Un enfant ne peut pas le
//  désactiver sans le code.
//
//  100 % LOCAL — aucune incidence sur le lecteur vidéo. Pavé numérique
//  navigable à la télécommande (D-pad).
// =========================================================
import 'package:flutter/material.dart';

import '../../security/data/app_pin_settings.dart';
import '../../security/data/parental_controls.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';

class TvParentalScreen extends StatefulWidget {
  const TvParentalScreen({super.key});

  @override
  State<TvParentalScreen> createState() => _TvParentalScreenState();
}

class _TvParentalScreenState extends State<TvParentalScreen> {
  bool _usingDefaultPin = true;

  @override
  void initState() {
    super.initState();
    AppPinSettings.instance.isUsingDefault().then((bool v) {
      if (mounted) setState(() => _usingDefaultPin = v);
    });
  }

  // ----- Bascule du Mode Enfants -----
  Future<void> _toggleKids(bool wantOn) async {
    // Activer : libre. Désactiver : code parental obligatoire (sinon un
    // enfant le couperait lui-même).
    if (!wantOn) {
      final bool ok = await _askPin(context, 'Entre le code parental');
      if (!ok) return;
    }
    await ParentalControls.instance.setKidsMode(wantOn);
    if (mounted) setState(() {});
  }

  // ----- Changer le code PIN -----
  Future<void> _changePin() async {
    final bool ok = await _askPin(context, 'Code actuel');
    if (!ok) return;
    final String? next = await _pickNewPin(context);
    if (next == null) return;
    try {
      await AppPinSettings.instance.setPin(next);
    } catch (_) {
      /* l'UI a déjà validé la longueur/format */
    }
    final bool def = await AppPinSettings.instance.isUsingDefault();
    if (mounted) {
      setState(() => _usingDefaultPin = def);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code parental mis à jour ✔')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool kids = ParentalControls.instance.kidsMode.value;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Contrôle parental',
              style: TextStyle(
                  fontSize: TvDimens.displayM,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          const SizedBox(height: 6),
          Text(
            'Le Mode Enfants masque automatiquement toutes les chaînes Adulte. '
            'Sa désactivation et le changement de code demandent le code parental.',
            style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
          ),
          const SizedBox(height: 22),

          // ----- Carte Mode Enfants -----
          _Card(
            child: Row(
              children: <Widget>[
                Icon(Icons.child_care_rounded,
                    color: kids ? TvTokens.gold : TvTokens.muted, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Mode Enfants',
                          style: TextStyle(
                              fontSize: TvDimens.title,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                      const SizedBox(height: 2),
                      Text(
                          kids
                              ? 'Activé — le contenu Adulte est masqué.'
                              : 'Désactivé — toutes les chaînes sont visibles.',
                          style: TextStyle(
                              fontSize: TvDimens.label,
                              color: kids ? TvTokens.gold : TvTokens.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _TogglePill(
                  on: kids,
                  autofocus: true,
                  onSelect: () => _toggleKids(!kids),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ----- Carte Code PIN -----
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.lock_rounded, color: TvTokens.muted, size: 26),
                    const SizedBox(width: 12),
                    Text('Code parental',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: TvTokens.text)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_usingDefaultPin)
                  Text(
                    'Tu utilises encore le code par défaut 0000. '
                    'Change-le pour protéger le Mode Enfants.',
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        fontWeight: FontWeight.w600,
                        color: TvTokens.live),
                  )
                else
                  Text('Un code personnalisé est en place.',
                      style: TextStyle(
                          fontSize: TvDimens.label, color: TvTokens.muted)),
                const SizedBox(height: 16),
                TvFocusBuilder(
                  scale: TvFocusScale.large,
                  onSelect: _changePin,
                  builder: (BuildContext context, bool focused) {
                    final Color bg = focused ? TvTokens.gold : TvTokens.sel;
                    final Color fg = focused
                        ? const Color(0xFF1A1206)
                        : TvTokens.goldBright;
                    return Container(
                      decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(TvDimens.cardRadius)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.pin_rounded, color: fg, size: 22),
                          const SizedBox(width: 10),
                          Text('Changer le code PIN',
                              style: TextStyle(
                                  fontSize: TvDimens.title,
                                  fontWeight: FontWeight.w700,
                                  color: fg)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Helpers de flux PIN (pushés en plein écran, façon app TV)
// =========================================================

/// Demande le code parental et le vérifie. Retourne true si correct.
Future<bool> _askPin(BuildContext context, String title) async {
  final bool? ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => TvShell(
        child: _PinPadScreen(
          title: title,
          subtitle: 'Code parental à 4 chiffres',
          onComplete: (String pin) async {
            final bool good = await AppPinSettings.instance.verify(pin);
            return good ? null : 'Code incorrect, réessaie.';
          },
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Choisit un NOUVEAU code (saisie + confirmation). Retourne le code, ou null.
Future<String?> _pickNewPin(BuildContext context) async {
  String? chosen;
  final bool? ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => TvShell(
        child: _PinPadScreen(
          title: 'Nouveau code',
          subtitle: 'Choisis 4 chiffres, puis confirme',
          confirm: true,
          onComplete: (String pin) async {
            chosen = pin;
            return null; // succès → la page se ferme
          },
        ),
      ),
    ),
  );
  return (ok == true) ? chosen : null;
}

// =========================================================
//  Pavé numérique D-pad (saisie de code)
// =========================================================
class _PinPadScreen extends StatefulWidget {
  const _PinPadScreen({
    required this.title,
    required this.subtitle,
    required this.onComplete,
    this.confirm = false,
  });

  final String title;
  final String subtitle;
  final bool confirm;

  /// Appelé quand 4 chiffres sont saisis (et confirmés si [confirm]).
  /// Retourne un message d'erreur à afficher, ou null en cas de succès
  /// (la page se ferme alors avec `true`).
  final Future<String?> Function(String pin) onComplete;

  @override
  State<_PinPadScreen> createState() => _PinPadScreenState();
}

class _PinPadScreenState extends State<_PinPadScreen> {
  String _entry = '';
  String? _firstEntry; // 1re saisie en mode confirmation
  String? _error;
  bool _busy = false;

  static const int _len = 4;

  Future<void> _onDigit(String d) async {
    if (_busy || _entry.length >= _len) return;
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == _len) await _maybeSubmit();
  }

  void _onBackspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _maybeSubmit() async {
    // Mode confirmation : 1re saisie mémorisée, on redemande.
    if (widget.confirm && _firstEntry == null) {
      setState(() {
        _firstEntry = _entry;
        _entry = '';
      });
      return;
    }
    if (widget.confirm && _firstEntry != null && _entry != _firstEntry) {
      setState(() {
        _error = 'Les deux codes ne correspondent pas.';
        _firstEntry = null;
        _entry = '';
      });
      return;
    }
    setState(() => _busy = true);
    final String? err = await widget.onComplete(_entry);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = err;
        _entry = '';
        _firstEntry = null;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool confirmStep = widget.confirm && _firstEntry != null;
    final String title = confirmStep ? 'Confirme le code' : widget.title;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title,
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
            const SizedBox(height: 22),
            // Points indiquant le nombre de chiffres saisis.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < _len; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entry.length
                          ? TvTokens.gold
                          : Colors.transparent,
                      border: Border.all(color: TvTokens.gold, width: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 24,
              child: _error == null
                  ? null
                  : Text(_error!,
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.live)),
            ),
            const SizedBox(height: 8),
            // Pavé 1-9 puis ⌫ / 0.
            for (final List<String> row in const <List<String>>[
              <String>['1', '2', '3'],
              <String>['4', '5', '6'],
              <String>['7', '8', '9'],
              <String>['back', '0', 'done'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final String k in row) _key(k),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _key(String k) {
    if (k == 'done') {
      // Touche neutre (espace réservé) — la validation est automatique à 4
      // chiffres ; on garde la grille alignée avec une touche « fermer ».
      return _PadButton(
        label: '',
        icon: Icons.close_rounded,
        onSelect: () => Navigator.of(context).maybePop(false),
      );
    }
    if (k == 'back') {
      return _PadButton(
        label: '',
        icon: Icons.backspace_rounded,
        onSelect: _onBackspace,
      );
    }
    return _PadButton(
      label: k,
      autofocus: k == '5',
      onSelect: () => _onDigit(k),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.onSelect,
    this.label = '',
    this.icon,
    this.autofocus = false,
  });
  final VoidCallback onSelect;
  final String label;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(7),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.large,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color bg = focused ? TvTokens.gold : TvTokens.card;
          final Color fg =
              focused ? const Color(0xFF1A1206) : TvTokens.text;
          return Container(
            width: 84,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(color: TvTokens.lineSoft),
            ),
            child: icon != null
                ? Icon(icon, color: fg, size: 28)
                : Text(label,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w800,
                        color: fg)),
          );
        },
      ),
    );
  }
}

// ----- Petits éléments visuels -----

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 760,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: child,
    );
  }
}

/// Interrupteur ON/OFF focusable (style « pilule »).
class _TogglePill extends StatelessWidget {
  const _TogglePill(
      {required this.on, required this.onSelect, this.autofocus = false});
  final bool on;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.gold
                : (on ? TvTokens.gold.withValues(alpha: 0.18) : TvTokens.sel),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(on ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                  size: 22, color: focused ? fg : (on ? TvTokens.gold : TvTokens.muted)),
              const SizedBox(width: 8),
              Text(on ? 'Activé' : 'Désactivé',
                  style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: focused ? fg : (on ? TvTokens.goldBright : TvTokens.muted))),
            ],
          ),
        );
      },
    );
  }
}
