import 'package:flutter/material.dart';

import '../../playlists/data/import_progress.dart';
import '../../playlists/data/remote_source_repository.dart';
import 'tv_channel_loading_status.dart';
import 'tv_source_entry_form.dart';
import 'tv_whatsapp_support_button.dart';

export 'tv_whatsapp_support_button.dart';

/// Première ouverture : la saisie est le premier élément à l'écran.
/// Le même arbre est conservé en portrait/paysage : changer la largeur ou
/// recevoir un statut du panel ne perd ni les champs ni le focus du clavier.
class TvSourceSetup extends StatelessWidget {
  const TvSourceSetup({
    required this.details,
    this.externalBusy = false,
    this.onAdded,
    super.key,
  });

  final Widget details;
  final bool externalBusy;
  final VoidCallback? onAdded;

  @override
  Widget build(BuildContext context) => Padding(
        // TvShell n'utilise pas Scaffold : réserver explicitement la hauteur
        // du clavier pour que les champs et le bouton restent défilables.
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 980;
            final double formWidth = wide ? 600 : constraints.maxWidth;
            final double detailWidth = wide ? 320 : constraints.maxWidth;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.hasBoundedHeight ? constraints.maxHeight : 0,
                ),
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: 32,
                    runSpacing: 24,
                    children: <Widget>[
                      SizedBox(
                        width: formWidth,
                        child: ListenableBuilder(
                          listenable: Listenable.merge(<Listenable>[
                            RemoteSourceRepository.importing,
                            RemoteSourceRepository.manualImporting,
                          ]),
                          builder: (context, _) => Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TvSourceEntryForm(
                                key: const ValueKey<String>(
                                    'inline-source-entry'),
                                externalBusy: externalBusy ||
                                    RemoteSourceRepository.importing.value ||
                                    RemoteSourceRepository
                                        .manualImporting.value,
                                onAdded: onAdded,
                              ),
                              if (RemoteSourceRepository
                                  .importing.value) ...<Widget>[
                                const SizedBox(height: 16),
                                ValueListenableBuilder<ImportProgress?>(
                                  valueListenable: ImportProgressBus.current,
                                  builder: (context, progress, _) =>
                                      TvChannelLoadingStatus(
                                    checking: false,
                                    importing: true,
                                    progress: progress,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              const TvWhatsAppSupportButton(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: detailWidth, child: details),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}
