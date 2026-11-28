// Écran dédié à l'ajout d'une source personnelle.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/app/novatube_tv_edition.dart';
import '../../playlists/domain/open_source_input.dart';
import 'tv_source_entry_form.dart';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key, this.initialMode = OpenEntryMode.xtream});

  final OpenEntryMode initialMode;

  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  late final bool _phone = kNovatubeTv && !AppPlatform.isTv;
  BuildContext? _activeField;

  @override
  void initState() {
    super.initState();
    if (_phone) {
      // L'utilisateur choisit sa position de saisie. Le lecteur reste en paysage.
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
      FocusManager.instance.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    if (_phone) {
      FocusManager.instance.removeListener(_focusChanged);
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    super.dispose();
  }

  void _focusChanged() {
    final at = FocusManager.instance.primaryFocus?.context;
    BuildContext? field;
    if (at != null && at.findAncestorStateOfType<_TvAddSourceScreenState>() == this) {
      at.visitAncestorElements((element) {
        if (element.widget is! TextField) return true;
        field = element;
        return false;
      });
    }
    if (_activeField == field) return;
    setState(() => _activeField = field);
    _revealField();
  }

  void _revealField() {
    final field = _activeField;
    if (field == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || field != _activeField || !field.mounted) return;
      // Un clavier flottant peut annoncer un inset de zéro. Le focus suffit
      // à placer le champ en haut et laisse le reste du formulaire défilable.
      Scrollable.ensureVisible(field);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Après rotation ou redimensionnement par le clavier ancré, la position
    // précédente dans le scroll ne correspond plus au même endroit de l'écran.
    _revealField();
  }

  @override
  Widget build(BuildContext context) {
    final form = TvSourceEntryForm(
      initialMode: widget.initialMode,
      autofocus: true, // Route dédiée : le choix M3U/Xtream est déjà fait.
      touchInput: _phone,
      onAdded: () {
        if (ModalRoute.of(context)?.isCurrent == true && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final canvas = MediaQuery.of(context);
    if (!_phone) {
      return Padding(
        padding: EdgeInsets.only(bottom: canvas.viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: form),
          ),
        ),
      );
    }

    // Le shell parent affiche toute la TV sur un canevas de 1280 unités.
    // Cette page tactile rend les champs et les zones de toucher en vrais dp,
    // y compris quand le téléphone pivote. Aucun second formulaire n'est créé.
    final native = MediaQueryData.fromView(View.of(context));
    final scale = native.size.width / canvas.size.width;
    return LayoutBuilder(builder: (context, bounds) {
      final height = bounds.maxHeight * scale;
      final width = bounds.maxWidth * scale;
      // Le shell applique déjà des marges symétriques. Ne pas les ajouter
      // deux fois aux barres système ou au clavier, surtout en paysage.
      final marginX = (native.size.width - width) / 2;
      final marginY = (native.size.height - height) / 2;
      final safe = EdgeInsets.fromLTRB(
        math.max(0.0, native.padding.left - marginX),
        math.max(0.0, native.padding.top - marginY),
        math.max(0.0, native.padding.right - marginX),
        math.max(0.0, math.max(native.padding.bottom, native.viewInsets.bottom) - marginY),
      );
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: width,
          height: height,
          child: MediaQuery(
            data: native,
            child: Padding(
              padding: safe,
              child: LayoutBuilder(builder: (context, viewport) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          8, 4, 8, _activeField == null ? 12 : viewport.maxHeight * .85,
                        ),
                        child: form,
                      ),
                    ),
                  );
              }),
            ),
          ),
        ),
      );
    });
  }
}
