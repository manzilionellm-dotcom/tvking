import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/support/vip_support.dart';
import '../../playlists/data/import_progress.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_channel_loading_status.dart';
import 'tv_source_entry_form.dart';

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
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        final double formWidth = wide ? 600 : constraints.maxWidth;
        final double detailWidth = wide ? 320 : constraints.maxWidth;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
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
                            key: const ValueKey<String>('inline-source-entry'),
                            externalBusy: externalBusy ||
                                RemoteSourceRepository.importing.value ||
                                RemoteSourceRepository.manualImporting.value,
                            onAdded: onAdded,
                          ),
                          if (RemoteSourceRepository.importing.value) ...<Widget>[
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

/// Un contact discret, sans QR ni transfert des identifiants saisis.
/// Le clic ouvre la conversation ; il n'envoie aucun message à la place
/// de l'utilisateur. Le numéro déjà configuré reste la seule destination.
class TvWhatsAppSupportButton extends StatefulWidget {
  const TvWhatsAppSupportButton({super.key, this.openForTesting});

  final Future<bool> Function(String message)? openForTesting;

  @override
  State<TvWhatsAppSupportButton> createState() => _TvWhatsAppSupportButtonState();
}

class _TvWhatsAppSupportButtonState extends State<TvWhatsAppSupportButton> {
  bool _opening = false;
  bool _unavailable = false;

  Future<void> _open() async {
    if (_opening) return;
    final String message = context.l10n.tvSupportHello;
    setState(() {
      _opening = true;
      _unavailable = false;
    });
    bool opened = false;
    try {
      opened = await (widget.openForTesting?.call(message) ??
          VipSupport.openWhatsApp(customMessage: message));
    } catch (_) {
      // Aucun détail technique ni URL privée dans le texte ou le journal.
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _unavailable = !opened;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      TextButton.icon(
        key: const ValueKey<String>('source-whatsapp-support'),
        onPressed: _opening ? null : _open,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: TvDimens.icon),
        label: Text(context.l10n.tvSupportWhatsApp, textAlign: TextAlign.center),
        style: TextButton.styleFrom(
          foregroundColor: TvTokens.accentBright,
          textStyle: TvTokens.ui(TvDimens.caption, weight: FontWeight.w600),
          minimumSize: const Size(48, 48),
        ),
      ),
      if (_unavailable) ...<Widget>[
        Text(context.l10n.tvSupportUnavailable,
            textAlign: TextAlign.center,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted)),
        const SizedBox(height: 6),
        SelectableText(VipSupport.displayNumber,
            textDirection: TextDirection.ltr,
            style: TvTokens.ui(TvDimens.label, color: TvTokens.accentBright)),
      ],
    ],
  );
}
