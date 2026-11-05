// Invitation visible sur l'accueil seulement. Le panel ne peut ni ouvrir le
// clavier ni envoyer un avis à la place du client. Le formulaire TV reste
// accessible au D-pad et se décale avec le clavier Android.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../tv/core/tv_app_tokens.dart';
import '../../tv/core/tv_field_keys.dart';
import '../../tv/core/tv_dimens.dart';
import '../data/feedback_repository.dart';

class TvFeedbackCard extends StatelessWidget {
  const TvFeedbackCard({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = TvAppTokens.of(context);
    return Container(
      key: const ValueKey<String>('tv-feedback-card'),
      padding: const EdgeInsets.all(TvDimens.gutter),
      decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message, style: palette.ui(TvDimens.body)),
            const SizedBox(height: TvDimens.rowGap),
            Wrap(spacing: TvDimens.gutter, children: <Widget>[
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _TvFeedbackDialog(message: message)),
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(context.l10n.buttonSend),
              ),
              TextButton(
                  onPressed: () =>
                      FeedbackRepository.instance.markDone(prompt: message),
                  child: Text(context.l10n.tvLater)),
            ]),
          ]),
    );
  }
}

class _TvFeedbackDialog extends StatefulWidget {
  const _TvFeedbackDialog({required this.message});
  final String message;
  @override
  State<_TvFeedbackDialog> createState() => _TvFeedbackDialogState();
}

class _TvFeedbackDialogState extends State<_TvFeedbackDialog> {
  final _text = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  bool _failed = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final sent = await FeedbackRepository.instance
        .submit(text: _text.text, rating: _rating, prompt: widget.message);
    if (!mounted) return;
    if (sent) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvAppTokens.of(context);
    return Dialog(
      backgroundColor: palette.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TvDimens.railCardW * 3),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TvDimens.gutter),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(widget.message, style: palette.ui(TvDimens.titleS)),
            const SizedBox(height: TvDimens.gutter),
            Wrap(children: <Widget>[
              for (int i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i / 5',
                  onPressed: _busy ? null : () => setState(() => _rating = i),
                  icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: palette.accentBright),
                ),
            ]),
            TvFieldKeys(
              child: TextField(
              key: const ValueKey<String>('tv-feedback-text'),
              autofocus: true,
              enabled: !_busy,
              controller: _text,
              maxLines: 3,
              maxLength: 800,
              style: palette.ui(TvDimens.body),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: widget.message,
                  errorText: _failed ? context.l10n.buttonRetry : null),
              ),
            ),
            const SizedBox(height: TvDimens.gutter),
            Wrap(spacing: TvDimens.gutter, children: <Widget>[
              FilledButton(
                  onPressed: _busy || _text.text.trim().isEmpty ? null : _send,
                  child: Text(_failed
                      ? context.l10n.buttonRetry
                      : context.l10n.buttonSend)),
              TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(context.l10n.buttonCancel)),
            ]),
          ]),
        ),
      ),
    );
  }
}
