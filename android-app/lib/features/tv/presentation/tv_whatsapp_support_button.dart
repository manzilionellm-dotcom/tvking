import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/support/vip_support.dart';
import '../core/tv_dimens.dart';
import '../core/tv_app_tokens.dart';

/// Contact direct commun à l'activation et aux réglages ZUNO.
/// Aucun import de liste, achat ou appel au panel n'est déclenché ici.
/// Le diagnostic est préparé au clic ; le client garde le choix de l'envoyer.
class TvWhatsAppSupportButton extends StatefulWidget {
  const TvWhatsAppSupportButton({super.key, this.openForTesting});

  /// Remplace seulement l'ouverture externe dans les tests, jamais les données
  /// d'un fournisseur. Le composant ne reçoit ni URL de liste ni identifiants.
  final Future<bool> Function(String message)? openForTesting;

  @override
  State<TvWhatsAppSupportButton> createState() =>
      _TvWhatsAppSupportButtonState();
}

class _TvWhatsAppSupportButtonState extends State<TvWhatsAppSupportButton> {
  bool _opening = false;
  bool _unavailable = false;

  Future<void> _open() async {
    // Deux appuis avant la prochaine frame ne doivent ouvrir qu'une fois.
    if (_opening) return;
    final String message = context.l10n.tvSupportHello;
    setState(() {
      _opening = true;
      _unavailable = false;
    });
    bool opened = false;
    try {
      opened =
          await (widget.openForTesting?.call(message) ??
              VipSupport.openWhatsApp(customMessage: message));
    } catch (_) {
      // Une erreur d'ouverture ne doit exposer ni message ni URL privée.
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
        icon: const Icon(
          Icons.chat_bubble_outline_rounded,
          size: TvDimens.title,
        ),
        label: Text(
          context.l10n.tvSupportWhatsApp,
          textAlign: TextAlign.center,
        ),
        style: TextButton.styleFrom(
          foregroundColor: TvAppTokens.of(context).accentBright,
          textStyle: TvAppTokens.of(context)
              .ui(TvDimens.caption, weight: FontWeight.w600),
          minimumSize: const Size(48, 48),
        ),
      ),
      if (_unavailable) ...<Widget>[
        Text(
          context.l10n.tvSupportUnavailable,
          textAlign: TextAlign.center,
          style: TvAppTokens.of(context)
              .ui(TvDimens.caption, color: TvAppTokens.of(context).muted),
        ),
        const SizedBox(height: TvDimens.rowGap),
        SelectableText(
          VipSupport.displayNumber,
          textDirection: TextDirection.ltr,
          style: TvAppTokens.of(context)
              .ui(TvDimens.label, color: TvAppTokens.of(context).accentBright),
        ),
      ],
    ],
  );
}
