import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../subscription/data/novatube_atlas.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import 'tv_components.dart';

/// Saisie volontaire d'un code remis au client. Même parcours pour tous,
/// au clavier tactile ou à la télécommande ; aucun code n'est fourni ici.
/// Le dialogue renvoie `true` après acceptation serveur. L'appelant relit
/// ensuite sa licence : ce dialogue ne modifie jamais l'accès lui-même.
class TvNovatubeAccessCodeDialog extends StatefulWidget {
  const TvNovatubeAccessCodeDialog({super.key});

  @override
  State<TvNovatubeAccessCodeDialog> createState() =>
      _TvNovatubeAccessCodeDialogState();
}

class _TvNovatubeAccessCodeDialogState
    extends State<TvNovatubeAccessCodeDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  NovatubeRedemption? _failure;

  @override
  void dispose() {
    // Le contrôleur est éphémère : aucune préférence ni restauration d'état
    // ne conserve le code après fermeture du dialogue.
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy || _form.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final NovatubeRedemption result =
        await NovatubeAtlas.instance.redeemAccessCode(_code.text);
    if (!mounted) return;
    if (result == NovatubeRedemption.accepted) {
      _code.clear();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _failure = result;
    });
  }

  String _failureText(AppLocalizations l10n, NovatubeRedemption result) =>
      switch (result) {
        NovatubeRedemption.invalidCode => l10n.novatubeCodeInvalid,
        NovatubeRedemption.deviceAuthRequired => l10n.novatubeCodeDeviceAuth,
        NovatubeRedemption.conflict => l10n.novatubeCodeConflict,
        NovatubeRedemption.rateLimited => l10n.novatubeCodeRateLimited,
        _ => l10n.novatubeCodeUnavailable,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TvAppTokens t = TvAppTokens.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: t.panel,
        title: Text(l10n.novatubeAccessCode,
            style: t.ui(TvDimens.title, color: t.text)),
        content: SizedBox(
          width: TvDimens.columnWidth * 10,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(l10n.novatubeAccessCodeHelp,
                      style: t.body(TvDimens.body, color: t.muted)),
                  const SizedBox(height: TvDimens.gutter),
                  TextFormField(
                    key: const ValueKey<String>('novatube-access-code-input'),
                    controller: _code,
                    autofocus: true,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    style: t.mono(TvDimens.body, color: t.text),
                    decoration: InputDecoration(
                      labelText: l10n.novatubeAccessCode,
                      labelStyle: t.ui(TvDimens.label, color: t.muted),
                      hintText: 'NVMAX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX',
                      hintStyle: t.mono(TvDimens.caption, color: t.mutedDim),
                      errorMaxLines: 3,
                    ),
                    validator: (String? value) =>
                        NovatubeAtlas.normalizeAccessCode(value ?? '') == null
                            ? l10n.novatubeCodeInvalid
                            : null,
                    onFieldSubmitted: (_) => _redeem(),
                    onChanged: (_) {
                      if (_failure != null) setState(() => _failure = null);
                    },
                  ),
                  if (_failure != null) ...<Widget>[
                    const SizedBox(height: TvDimens.gutter),
                    Semantics(
                      liveRegion: true,
                      child: Text(_failureText(l10n, _failure!),
                          style: t.ui(TvDimens.body, color: t.text)),
                    ),
                  ],
                  const SizedBox(height: TvDimens.gutter),
                  TvCtaButton(
                    key: const ValueKey<String>('novatube-access-code-submit'),
                    label: _busy ? l10n.tvChecking : l10n.novatubeRedeemCode,
                    onSelect: _busy ? null : _redeem,
                  ),
                  const SizedBox(height: TvDimens.rowGap),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.tvCancel,
                        style: t.ui(TvDimens.label, color: t.muted)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
