// =========================================================
//  removed_list_prompt.dart — Message, puis écran d'ajout
// =========================================================
//  La chaîne en cours n'est pas coupée au moment du message :
//  le lecteur reste monté derrière la boîte. Quand la personne
//  confirme, on referme le lecteur (il s'arrête à ce moment-là)
//  et, s'il ne reste plus de liste, on ouvre « Ajouter ma liste ».
// =========================================================

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

import '../../playlists/data/removed_list_notice.dart';
import 'tv_add_source_screen.dart';
import 'tv_shell.dart';

class RemovedListPrompt extends StatefulWidget {
  const RemovedListPrompt({super.key, required this.child});

  final Widget child;

  @override
  State<RemovedListPrompt> createState() => _RemovedListPromptState();
}

class _RemovedListPromptState extends State<RemovedListPrompt> {
  int _shown = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RemovedListNotice.instance.event.addListener(_onEvent);
  }

  @override
  void dispose() {
    RemovedListNotice.instance.event.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() {
    final RemovedListEvent? ev = RemovedListNotice.instance.event.value;
    if (ev == null || ev.token == _shown || _busy) return;
    _shown = ev.token;
    _busy = true;
    // Pendant un build, on attend la fin de la frame. Sinon
    // (réponse réseau, test) on ouvre tout de suite.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _present(ev);
      });
    } else {
      _present(ev);
    }
  }

  Future<void> _present(RemovedListEvent ev) async {
    if (!mounted) return;
    final NavigatorState nav = Navigator.of(context, rootNavigator: true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Liste retirée'),
          content: const Text(
            'Ton revendeur a retiré cette liste. '
            'Les chaînes de cette liste ne sont plus là.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                nav.popUntil((Route<dynamic> route) => route.isFirst);
                if (!ev.noneLeft) return;
                nav.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const TvShell(child: TvAddSourceScreen()),
                  ),
                );
              },
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );
    _busy = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
