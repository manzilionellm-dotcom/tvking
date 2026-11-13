// Tarifs de Zuno : affichage réactif des valeurs du panel, sans décision de
// licence. Un lien externe n'existe que dans l'APK hors Play et après une
// configuration HTTPS valide ; aucune navigation automatique.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/update/build_flags.dart';
import '../../tv/core/tv_app_tokens.dart';
import '../data/pricing_repository.dart';

class TvPricingCard extends StatefulWidget {
  const TvPricingCard({super.key, this.showBlockCopy = false, this.showStatus = false});
  final bool showBlockCopy;
  final bool showStatus;

  @override
  State<TvPricingCard> createState() => _TvPricingCardState();
}

class _TvPricingCardState extends State<TvPricingCard> {
  bool _loading = true;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (!kIsPlayBuild) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _failed = false; });
    try { await PricingRepository.fetch(strict: true); }
    catch (_) { if (mounted) setState(() => _failed = true); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _open(String value) async {
    if (kIsPlayBuild || _opening) return;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
    setState(() => _opening = true);
    bool opened = false;
    try { opened = await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) { /* Le navigateur peut manquer sur une box. */ }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.l10n.subCantOpenUrl(uri.host)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ne pas introduire de parcours commercial externe dans le build Store.
    if (kIsPlayBuild) return const SizedBox.shrink();
    return ValueListenableBuilder<PricingConfig>(
      valueListenable: PricingRepository.notifier,
      builder: (context, config, _) {
        final palette = TvAppTokens.of(context);
        final String language = Localizations.localeOf(context).languageCode;
        final String title = widget.showBlockCopy ? config.blockTitle(language) : '';
        final String body = widget.showBlockCopy ? config.blockBody(language) : '';
        final bool promo = config.promoEnabled && config.promoMessage.isNotEmpty;
        if (!config.confirmed || (!config.hasOffers && title.isEmpty && body.isEmpty && !promo && config.payUrl.isEmpty)) {
          if (!widget.showStatus) return const SizedBox.shrink();
          return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(_loading ? context.l10n.subLoading : _failed ? context.l10n.tvCheckUnavailable : context.l10n.tvNoData,
              style: palette.ui(18, color: palette.muted)),
            const SizedBox(height: 12),
            TextButton(onPressed: _loading ? null : _refresh, child: Text(context.l10n.buttonRetry)),
          ]);
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.line)),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (title.isNotEmpty) ...<Widget>[
              Text(title, textAlign: TextAlign.center, style: palette.ui(20, color: palette.text)),
              const SizedBox(height: 8),
            ],
            if (body.isNotEmpty) ...<Widget>[
              Text(body, textAlign: TextAlign.center, style: palette.ui(16, color: palette.muted)),
              const SizedBox(height: 12),
            ],
            if (config.hasOffers) ...<Widget>[
              Text(context.l10n.pricingOffersTitle, style: palette.ui(16, color: palette.muted)),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 10, children: <Widget>[
                if (config.lifetime.isNotEmpty) _offer(context.l10n.pricingLifetime, config.lifetimeLabel, palette),
                if (config.yearly.isNotEmpty) _offer(context.l10n.pricingYearly, config.yearlyLabel, palette),
              ]),
            ],
            if (promo) ...<Widget>[
              const SizedBox(height: 12),
              Text(config.promoMessage, textAlign: TextAlign.center, style: palette.ui(16, color: palette.accentBright)),
            ],
            if (config.payUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey<String>('panel-pricing-pay'),
                onPressed: _opening ? null : () => _open(config.payUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text('${context.l10n.pricingOffersTitle} · ${Uri.parse(config.payUrl).host}'),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _offer(String label, String value, TvAppTokens palette) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label, style: palette.ui(15, color: palette.muted)),
      const SizedBox(height: 4),
      Text(value, style: palette.ui(22, color: palette.accentBright, weight: FontWeight.w600)),
    ],
  );
}

class TvPricingScreen extends StatelessWidget {
  const TvPricingScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TvAppTokens.of(context).bg,
    appBar: AppBar(title: Text(context.l10n.pricingOffersTitle)),
    body: const Center(child: SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: SizedBox(width: 640, child: TvPricingCard(showStatus: true)),
    )),
  );
}
