// =========================================================
//  trial_block_screen.dart — Écran quand l'essai de 7 jours est fini
// =========================================================
//  Affiché SEULEMENT si le serveur a allumé l'interrupteur et dit
//  « expiré ». Titre, texte court, MAC bien visible, WhatsApp et
//  téléphone déjà dans le projet. Le lien de paiement du panel
//  n'apparaît que s'il est rempli.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/support/vip_support.dart';
import '../../device/data/device_identity.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/subscription_state.dart';
import '../data/trial_block_copy.dart';

class TrialBlockScreen extends StatefulWidget {
  const TrialBlockScreen({
    super.key,
    required this.mac,
    required this.text,
    this.onRefresh,
    this.onWhatsApp,
    this.onCall,
    this.onPay,
  });

  final String mac;
  final TrialBlockText text;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;
  final VoidCallback? onPay;

  @override
  State<TrialBlockScreen> createState() => _TrialBlockScreenState();
}

class _TrialBlockScreenState extends State<TrialBlockScreen> {
  bool _copied = false;
  late String _mac = widget.mac;

  @override
  void initState() {
    super.initState();
    if (widget.mac.contains('?')) {
      DeviceIdentity.instance.mac.then((String m) {
        if (mounted) setState(() => _mac = m);
      });
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _mac));
    setState(() => _copied = true);
  }

  /// Ouvre le lien https du panel, ou le site déjà dans le projet
  /// (kPurchaseUrl) quand le panel n'a rien rempli.
  Future<void> _openPay(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) { /* le bouton reste là, rien à inventer */ }
  }

  @override
  Widget build(BuildContext context) {
    final TrialBlockText t = widget.text;
    final String pay = t.payUrl.isNotEmpty ? t.payUrl : kPurchaseUrl;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
          children: <Widget>[
            Text(
              t.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge,
            ),
            const SizedBox(height: 14),
            Text(
              t.body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              t.macLabel,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentMuted),
              ),
              child: Column(
                children: <Widget>[
                  SelectableText(
                    _mac,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.numeric.copyWith(
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _copy,
                    child: Text(
                      _copied
                          ? (t.french ? 'Copié' : 'Copied')
                          : (t.french ? 'Copier' : 'Copy'),
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              VipSupport.displayNumber,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.onWhatsApp ??
                  () {
                    VipSupport.openWhatsApp(
                      customMessage: t.french
                          ? 'Bonjour, mon essai est terminé. Mon identifiant : $_mac'
                          : 'Hello, my trial has ended. My device ID: $_mac',
                    );
                  },
              child: Text(t.whatsAppLabel, style: AppTextStyles.button),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: widget.onCall ?? VipSupport.openPhoneCall,
              child: Text(
                '${t.phoneLabel} · ${VipSupport.displayNumber}',
                style: AppTextStyles.button.copyWith(color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onPay ?? () => _openPay(pay),
              child: Text(
                t.payLabel,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (t.payUrl.isNotEmpty)
              Text(
                t.payUrl,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: widget.onRefresh == null
                  ? null
                  : () {
                      widget.onRefresh!();
                    },
              child: Text(
                t.french ? 'J’ai activé — vérifier' : 'I’ve activated — check',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau discret pendant l'essai. Invisible si l'interrupteur est
/// coupé ou si l'essai n'est pas en cours.
class TrialDaysHint extends StatelessWidget {
  const TrialDaysHint({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionState.instance,
      builder: (BuildContext context, _) {
        final SubscriptionState s = SubscriptionState.instance;
        if (!s.trialEnforced || s.status != SubscriptionStatus.trialActive) {
          return const SizedBox.shrink();
        }
        final String code = Localizations.localeOf(context).languageCode;
        final TrialBlockText t = resolveTrialBlock(
          languageCode: code,
          titleFr: s.blockTitleFr,
          bodyFr: s.blockBodyFr,
          titleEn: s.blockTitleEn,
          bodyEn: s.blockBodyEn,
          payUrl: s.payUrl,
          daysLeft: s.trialDaysRemaining,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            t.daysLabel,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        );
      },
    );
  }
}
