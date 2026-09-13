// =========================================================
//  tv_license_lock_screen.dart — Écran 10-foot « abo requis »
// =========================================================
//  Affiché par TvGate dès que canStream == false. Remplace
//  TvWelcomeScreen (QR + collage M3U) qui laissait un expiré
//  AJOUTER une playlist — même s'il ne pouvait plus ouvrir
//  l'accueil, c'était le mauvais message et un trou UX.
//
//  D-pad : un bouton « Revérifier » (le revendeur vient d'activer).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

class TvLicenseLockScreen extends StatefulWidget {
  const TvLicenseLockScreen({super.key});

  @override
  State<TvLicenseLockScreen> createState() => _TvLicenseLockScreenState();
}

class _TvLicenseLockScreenState extends State<TvLicenseLockScreen> {
  String _mac = '…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
  }

  Future<void> _recheck() async {
    if (_busy) return;
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _mac));
  }

  @override
  Widget build(BuildContext context) {
    final SubscriptionStatus s = SubscriptionState.instance.status;
    final bool banned = s == SubscriptionStatus.banned;
    final bool frozen = s == SubscriptionStatus.frozen;
    final String title = banned
        ? context.l10n.subAccountSuspended
        : frozen
            ? context.l10n.subAccountFrozen
            : context.l10n.subUnlockAll;
    final String message = banned
        ? context.l10n.subBannedMsg
        : frozen
            ? context.l10n.subFrozenMsg
            : context.l10n.subTrialExpiredMsg(kTrialDurationDays);

    return MediaQuery.withNoTextScaling(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 980,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const TvLogo(width: 200),
                const SizedBox(height: 28),
                Icon(
                  banned
                      ? Icons.block_rounded
                      : frozen
                          ? Icons.ac_unit_rounded
                          : Icons.lock_clock_rounded,
                  color: TvTokens.gold,
                  size: 64,
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TvTokens.display(36, color: TvTokens.text),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 720,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(18, color: TvTokens.muted),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: 560,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  decoration: BoxDecoration(
                    color: TvTokens.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: TvTokens.gold.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        context.l10n.gateReferenceLabel,
                        style: TvTokens.ui(13,
                            color: TvTokens.gold, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _mac,
                        style: TvTokens.ui(26,
                            color: TvTokens.text, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                TvFocusable(
                  autofocus: true,
                  onSelect: _recheck,
                  child: Container(
                    width: 420,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: TvTokens.gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: TvTokens.bg,
                            ),
                          )
                        : Text(
                            context.l10n.subPullToRefresh,
                            style: TvTokens.ui(18,
                                color: TvTokens.bg, weight: FontWeight.w800),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TvFocusable(
                  onSelect: _copy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    child: Text(
                      context.l10n.buttonCopy,
                      style: TvTokens.ui(16, color: TvTokens.muted),
                    ),
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
