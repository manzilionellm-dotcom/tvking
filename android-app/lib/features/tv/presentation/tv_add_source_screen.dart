// =========================================================
//  Écran dédié à l'ajout d'une source personnelle.
// =========================================================
//  Le même formulaire est disponible directement sur l'accueil sans liste.
//  Ici seulement, un ajout réussi ferme la route et revient à l'appelant.
import 'package:flutter/material.dart';

import '../../playlists/domain/open_source_input.dart';
import 'tv_source_entry_form.dart';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key, this.initialMode = OpenEntryMode.xtream});

  /// Le raccourci historique player reste accepté et ouvre maintenant M3U.
  final OpenEntryMode initialMode;

  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  @override
  Widget build(BuildContext context) => Padding(
    // Le shell TV ne redimensionne pas son contenu quand le clavier mobile
    // s'ouvre. L'inset garde la validation accessible dans cette route aussi.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: TvSourceEntryForm(
            initialMode: widget.initialMode,
            autofocus: true,
            onAdded: () {
              // Un dialogue peut s'être ouvert pendant l'import. Ne pas le
              // fermer à la place de la route qui a lancé cet ajout.
              if (ModalRoute.of(context)?.isCurrent == true &&
                  Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      ),
    ),
  );
}
