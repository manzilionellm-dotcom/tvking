// =========================================================
//  feedback_sheet.dart — Feuille « Donne ton avis »
// =========================================================
//  Invitation douce (message piloté par le panel) à laisser un avis :
//  étoiles optionnelles + texte libre. Envoi → POST /api/feedback, lisible
//  côté panel. Refermable sans rien envoyer. Zéro cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/feedback_repository.dart';

/// Affiche la feuille d'avis si le panel l'a activée et que le client n'a
/// pas déjà répondu à ce message. Sans effet sinon.
Future<void> maybeShowFeedbackSheet(BuildContext context) async {
  if (!await FeedbackRepository.instance.shouldPrompt()) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _FeedbackSheet(),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final TextEditingController _ctrl = TextEditingController();
  int _rating = 0;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _ctrl.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await FeedbackRepository.instance.submit(text: text, rating: _rating);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Merci pour ton avis 🙏'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  FeedbackRepository.instance.message,
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 14),
                // Étoiles (optionnel).
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 1; i <= 5; i++)
                      IconButton(
                        onPressed: () => setState(() => _rating = i),
                        icon: Icon(
                          i <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: AppColors.warning,
                          size: 32,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl,
                  maxLines: 4,
                  maxLength: 800,
                  decoration: const InputDecoration(
                    hintText: 'Écris ton avis ou comment améliorer l\'app…',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Envoyer'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            FeedbackRepository.instance.markDone();
                            Navigator.of(context).pop();
                          },
                    child: const Text('Plus tard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
