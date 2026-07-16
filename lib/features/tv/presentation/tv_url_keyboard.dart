// =========================================================
//  tv_url_keyboard.dart — Clavier D-PAD intégré pour URL / codes
// =========================================================
//  Le clavier SYSTÈME des box (IME) varie selon les marques et il est
//  parfois inutilisable au D-pad. Ici : un clavier À NOUS, dessiné dans
//  l'écran, qui ne demande QUE flèches + OK + Retour → il marche sur
//  TOUTES les télécommandes. Le TextField système reste utilisable en
//  parallèle (clavier physique/USB, IME, copier-coller) mais n'est
//  JAMAIS obligatoire.
//
//  Trois pièces, réutilisées par les écrans d'ajout de source :
//    • TvUrlKeyboard   — bandeau valeur + CURSEUR visible, chips
//      d'insertion rapide (http://, .com, /get.php?username=…) qui
//      insèrent un BLOC entier en un OK (le cœur du « naturel » pour
//      quelqu'un fâché avec l'orthographe), grille de touches, touches
// de contrôle (MAJ, 123, espace, ◀ ▶ curseur, ⌫ à répétition, ).
//    • TvKeyboardField — champ de formulaire : un OK le désigne comme
//      CIBLE du clavier ; il contient un VRAI TextField (hors parcours
//      D-pad, cf. skipTraversal) qu'un bouton ⌨ dédié permet de
//      focaliser pour l'IME / un clavier physique.
//
//  PERF : aucune image, que des Container/Text ; la grille est statique
//  (pas de ListView) → zéro allocation par frame, zéro risque OOM.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Pages du clavier : lettres (min/MAJ via _shift) ou chiffres+symboles.
enum _KbPage { letters, symbols }

class TvUrlKeyboard extends StatefulWidget {
  const TvUrlKeyboard({
    super.key,
    required this.controller,
    this.fieldLabel,
    this.obscured = false,
    this.showUrlChips = true,
    this.autofocus = false,
  });

  /// Le champ CIBLE : le clavier tape dedans, à la position du curseur.
  final TextEditingController controller;

  /// Nom du champ affiché dans le bandeau (« Serveur », « Mot de passe »…)
  /// pour que le client sache toujours OÙ il tape.
  final String? fieldLabel;

  /// Mot de passe masqué : le bandeau affiche des points.
  final bool obscured;

  /// Chips d'insertion rapide d'URL (inutiles pour identifiant/mot de passe).
  final bool showUrlChips;

  /// Donne le focus initial à la première touche.
  final bool autofocus;

  @override
  State<TvUrlKeyboard> createState() => _TvUrlKeyboardState();
}

class _TvUrlKeyboardState extends State<TvUrlKeyboard> {
  _KbPage _page = _KbPage.letters;
  bool _shift = false;

  // ---- Grilles (statiques → const, aucune allocation au build) ----
  static const List<List<String>> _letters = <List<String>>[
    <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],
    <String>['j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r'],
    <String>['s', 't', 'u', 'v', 'w', 'x', 'y', 'z', '.'],
  ];
  // Chiffres + TOUS les symboles d'une URL (: / . _ - @ ? = &) à portée
  // d'un seul OK — pas de 3e page à chercher.
  static const List<List<String>> _symbols = <List<String>>[
    <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    <String>['.', ',', ':', ';', '/', '\\', '-', '_', '@', '&'],
    <String>['?', '=', '#', '%', '+', '~', '!', '*', '(', ')'],
  ];

  @override
  void initState() {
    super.initState();
    // Le bandeau (valeur + curseur) et les chips contextuelles doivent
    // suivre AUSSI les frappes venues d'ailleurs (IME, clavier physique).
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(TvUrlKeyboard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  // ---- Édition à la position du CURSEUR (pas seulement en fin) ----

  int get _cursor {
    final TextSelection sel = widget.controller.selection;
    final int len = widget.controller.text.length;
    if (!sel.isValid) return len;
    return sel.extentOffset.clamp(0, len);
  }

  void _insert(String s) {
    final String text = widget.controller.text;
    final int pos = _cursor;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(pos, pos, s),
      selection: TextSelection.collapsed(offset: pos + s.length),
    );
  }

  void _backspace() {
    final String text = widget.controller.text;
    final int pos = _cursor;
    if (pos == 0) return;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(pos - 1, pos, ''),
      selection: TextSelection.collapsed(offset: pos - 1),
    );
  }

  void _clearAll() {
    widget.controller.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  void _moveCursor(int delta) {
    final int len = widget.controller.text.length;
    final int pos = (_cursor + delta).clamp(0, len);
    widget.controller.selection = TextSelection.collapsed(offset: pos);
    setState(() {}); // le bandeau redessine le curseur
  }

  // ---- Chips CONTEXTUELLES : on propose le bloc dont le client a le
  //  plus probablement besoin MAINTENANT (début de lien → schéma ;
  //  username tapé → &password= ; etc.). Un OK = tout le bloc inséré. ----
  List<String> _chips() {
    final String t = widget.controller.text;
    final bool hasScheme =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(t);
    if (!hasScheme) {
      return <String>['http://', 'https://', 'www.', '192.168.'];
    }
    final List<String> out = <String>[];
    if (t.endsWith('://')) out.add('www.');
    if (t.contains('username=') && !t.contains('&password=')) {
      out.add('&password=');
    }
    out.addAll(<String>[
      '.com', ':8080', '/get.php?username=', '.m3u', '.m3u8',
    ]);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final List<List<String>> grid =
        _page == _KbPage.letters ? _letters : _symbols;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TvTokens.panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ValueStrip(
            controller: widget.controller,
            label: widget.fieldLabel,
            obscured: widget.obscured,
            cursor: _cursor,
          ),
          if (widget.showUrlChips) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String c in _chips())
                  _QuickChip(label: c, onSelect: () => _insert(c)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          for (final List<String> row in grid) ...<Widget>[
            Row(
              children: <Widget>[
                for (int i = 0; i < row.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Key(
                      label: _shift && _page == _KbPage.letters
                          ? row[i].toUpperCase()
                          : row[i],
                      autofocus: widget.autofocus &&
                          identical(row, grid.first) &&
                          i == 0,
                      onTap: () => _insert(_shift && _page == _KbPage.letters
                          ? row[i].toUpperCase()
                          : row[i]),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],
          // ---- Rangée de contrôle : MAJ, page, espace, curseur, effacer ----
          Row(
            children: <Widget>[
              Expanded(
                child: _Key(
                  label: '⇧',
                  active: _shift,
                  enabled: _page == _KbPage.letters,
                  onTap: () => setState(() => _shift = !_shift),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Key(
                  label: _page == _KbPage.letters ? '123' : 'abc',
                  onTap: () => setState(() => _page =
                      _page == _KbPage.letters
                          ? _KbPage.symbols
                          : _KbPage.letters),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: _Key(label: '␣', onTap: () => _insert(' '))),
              const SizedBox(width: 6),
              // Déplacement du CURSEUR (répétition en appui maintenu) :
              // corriger une lettre AU MILIEU sans tout effacer.
              Expanded(child: _RepeatKey(label: '◀', onTap: () => _moveCursor(-1))),
              const SizedBox(width: 6),
              Expanded(child: _RepeatKey(label: '▶', onTap: () => _moveCursor(1))),
              const SizedBox(width: 6),
              // Effacer : RÉPÉTITION en appui maintenu (OK tenu ou doigt).
              Expanded(child: _RepeatKey(label: '⌫', onTap: _backspace)),
              const SizedBox(width: 6),
              Expanded(child: _Key(label: '✕', onTap: _clearAll)),
            ],
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Bandeau VALEUR + CURSEUR : le TextField ne montre son curseur que
//  focalisé (IME) — or ici le focus vit sur les TOUCHES. Le bandeau
//  redessine donc la valeur du champ cible avec un curseur or, toujours
//  visible, déplacé par ◀ ▶.
// =========================================================
class _ValueStrip extends StatelessWidget {
  const _ValueStrip({
    required this.controller,
    required this.label,
    required this.obscured,
    required this.cursor,
  });
  final TextEditingController controller;
  final String? label;
  final bool obscured;
  final int cursor;

  @override
  Widget build(BuildContext context) {
    final String raw = controller.text;
    final String text = obscured ? '•' * raw.length : raw;
    final int pos = cursor.clamp(0, text.length);
    final TextStyle style =
        TvTokens.mono(17, weight: FontWeight.w500, color: TvTokens.text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
        border: Border.all(color: TvTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(label!.toUpperCase(),
                  style: TvTokens.ui(10,
                      weight: FontWeight.w700,
                      color: TvTokens.gold,
                      spacing: 1.6)),
            ),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: text.substring(0, pos), style: style),
                // Le CURSEUR : une barre or entre deux caractères.
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                      width: 2, height: 20, color: TvTokens.goldBright),
                ),
                TextSpan(text: text.substring(pos), style: style),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Chip d'insertion rapide : un OK insère le BLOC entier au curseur.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onSelect});
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.badgeBg,
            borderRadius: BorderRadius.circular(TvTokens.rSmall),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.hairline),
          ),
          child: Text(label,
              style: TvTokens.mono(14,
                  color: focused
                      ? const Color(0xFF1A1206)
                      : TvTokens.goldBright)),
        );
      },
    );
  }
}

/// Touche simple (une frappe par OK).
class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.active = false,
    this.enabled = true,
  });
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  /// Touche à état (MAJ enclenchée) : reste marquée or.
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        enabled: enabled,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused
                  ? TvTokens.gold
                  : (active ? TvTokens.surface3 : TvTokens.sel),
              borderRadius: BorderRadius.circular(TvTokens.rSmall),
              border: active && !focused
                  ? Border.all(color: TvTokens.gold)
                  : null,
            ),
            child: Text(label,
                style: TvTokens.ui(18,
                    weight: FontWeight.w600,
                    color: focused
                        ? const Color(0xFF1A1206)
                        : (enabled ? TvTokens.text : TvTokens.mutedDim))),
          );
        },
      ),
    );
  }
}

// =========================================================
//  Touche à RÉPÉTITION (⌫, ◀, ▶) : OK maintenu = frappes répétées.
//  TvFocusable avale volontairement les répétitions clavier (pour ne pas
//  ouvrir 10 fiches) — ici c'est l'inverse qu'on veut, donc cette touche
//  gère ses KeyEvent elle-même : un Timer périodique démarre après un
//  court délai à l'enfoncement d'OK et s'arrête au relâchement.
//  Déterministe sur TOUTES les télécommandes (on n'attend pas les
//  KeyRepeatEvent, que certaines box n'envoient pas).
// =========================================================
class _RepeatKey extends StatefulWidget {
  const _RepeatKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_RepeatKey> createState() => _RepeatKeyState();
}

class _RepeatKeyState extends State<_RepeatKey> {
  bool _focused = false;
  Timer? _delay;
  Timer? _repeat;

  static const Duration _kDelay = Duration(milliseconds: 380);
  static const Duration _kInterval = Duration(milliseconds: 90);

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    widget.onTap(); // première frappe immédiate
    _delay = Timer(_kDelay, () {
      _repeat = Timer.periodic(_kInterval, (_) => widget.onTap());
    });
  }

  void _stop() {
    _delay?.cancel();
    _delay = null;
    _repeat?.cancel();
    _repeat = null;
  }

  bool _isSelect(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isSelect(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _start();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Notre Timer cadence déjà la répétition : on absorbe pour ne pas
      // doubler la vitesse sur les box qui envoient AUSSI des repeats.
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _stop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Tactile : appui simple = une frappe ; appui long = répétition.
    return SizedBox(
      height: 46,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: Focus(
          onKeyEvent: _onKey,
          onFocusChange: (bool f) {
            if (!f) _stop(); // le focus part OK enfoncé → on coupe net
            setState(() => _focused = f);
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _focused ? TvTokens.gold : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvTokens.rSmall),
              border:
                  _focused ? Border.all(color: TvTokens.goldBright) : null,
            ),
            child: Text(widget.label,
                style: TvTokens.ui(18,
                    weight: FontWeight.w600,
                    color: _focused
                        ? const Color(0xFF1A1206)
                        : TvTokens.text)),
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  TvKeyboardField — champ de formulaire relié au clavier intégré.
//  • OK sur le champ = il devient la CIBLE du clavier (bordure or).
//  • Il contient un VRAI TextField : IME / clavier physique / coller
//    fonctionnent toujours — mais il est HORS du parcours D-pad
//    (skipTraversal) pour que naviguer ne déclenche jamais l'IME de la
//    box. Le bouton ⌨ à côté du champ le focalise volontairement.
// • Mot de passe : bouton afficher/masquer, focusable lui aussi.
// =========================================================
class TvKeyboardField extends StatefulWidget {
  const TvKeyboardField({
    super.key,
    required this.controller,
    required this.label,
    required this.active,
    required this.onActivate,
    this.hint,
    this.obscured = false,
    this.onToggleObscure,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  /// `true` = ce champ est la cible actuelle du clavier intégré.
  final bool active;

  /// OK sur le champ → l'écran fait de ce champ la cible du clavier.
  final VoidCallback onActivate;

  /// Mot de passe masqué. [onToggleObscure] non-null = bouton affiché.
  final bool obscured;
  final VoidCallback? onToggleObscure;
  final bool autofocus;

  @override
  State<TvKeyboardField> createState() => _TvKeyboardFieldState();
}

class _TvKeyboardFieldState extends State<TvKeyboardField> {
  // HORS du parcours D-pad : naviguer aux flèches ne pose JAMAIS le focus
  // sur l'EditableText (sinon l'IME de la box surgirait à chaque passage).
  final FocusNode _imeNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _imeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: TvFocusBuilder(
            autofocus: widget.autofocus,
            scale: TvFocusScale.small,
            onSelect: widget.onActivate,
            builder: (BuildContext context, bool focused) {
              final Color border = focused
                  ? TvTokens.goldBright
                  : (widget.active ? TvTokens.gold : TvTokens.line);
              return Container(
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  border: Border.all(
                      color: border, width: focused || widget.active ? 2 : 1),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _imeNode,
                  obscureText: widget.obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  cursorColor: TvTokens.gold,
                  style: TvTokens.ui(17,
                      weight: FontWeight.w500, color: TvTokens.text),
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.hint,
                    labelStyle: TvTokens.ui(13,
                        color: widget.active ? TvTokens.gold : TvTokens.muted),
                    hintStyle: TvTokens.ui(14, color: TvTokens.mutedDim),
                    floatingLabelStyle:
                        TvTokens.ui(13, color: TvTokens.goldBright),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.onToggleObscure != null) ...<Widget>[
          const SizedBox(width: 8),
          _FieldIconButton(
            icon: widget.obscured
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            tooltip: widget.obscured
                ? context.l10n.tvSourceShowValue
                : context.l10n.tvSourceHideValue,
            onSelect: widget.onToggleObscure!,
          ),
        ],
        const SizedBox(width: 8),
        // Opt-in EXPLICITE au clavier système (IME / physique) : le client
        // qui a une appli télécommande-clavier ou un clavier USB l'ouvre
        // ici — les autres ne le croisent jamais par accident.
        _FieldIconButton(
          icon: Icons.keyboard_alt_outlined,
          tooltip: context.l10n.tvSourceSystemKeyboard,
          onSelect: () => _imeNode.requestFocus(),
        ),
      ],
    );
  }
}

class _FieldIconButton extends StatelessWidget {
  const _FieldIconButton(
      {required this.icon, required this.onSelect, this.tooltip});
  final IconData icon;
  final VoidCallback onSelect;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rSmall),
            border: Border.all(color: focused ? TvTokens.gold : TvTokens.line),
          ),
          child: Icon(icon,
              size: 22,
              color: focused ? const Color(0xFF1A1206) : TvTokens.muted),
        );
      },
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
