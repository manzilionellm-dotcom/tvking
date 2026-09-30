// =========================================================
//  tv_remote_screen.dart — QR « le téléphone pilote la box »
// =========================================================
//  Écran 10-foot. Le QR pointe vers la box (réseau local), pas vers
//  un site. Le jeton est dans l'adresse : toute personne qui voit
//  cet écran peut s'appairer jusqu'à expiration — le texte sous le
//  QR le dit. Un seul téléphone : le suivant est refusé tant qu'on
//  n'a pas demandé un nouveau code.
//
//  OK au centre, au départ, ne fait RIEN : on évite qu'un essai de
//  la télécommande du téléphone régénère le QR (et coupe le
//  téléphone qu'on vient d'appairer). Il faut descendre jusqu'aux
//  boutons pour « Nouveau code » ou « Couper ».
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../../tv/presentation/tv_components.dart';
import 'remote_control.dart';

class TvRemoteScreen extends StatefulWidget {
  const TvRemoteScreen({super.key});

  @override
  State<TvRemoteScreen> createState() => _TvRemoteScreenState();
}

class _TvRemoteScreenState extends State<TvRemoteScreen> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      RemoteControl.instance.poll();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    // On NE coupe PAS le serveur : le téléphone doit continuer
    // après qu'on a quitté cet écran (Retour).
    super.dispose();
  }

  Future<void> _open() async {
    await RemoteControl.instance.onScreenOpened();
    if (mounted) setState(() {});
  }

  Future<void> _restart() async {
    if (_busy) return;
    setState(() => _busy = true);
    await RemoteControl.instance.restart();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    await RemoteControl.instance.userStop();
    if (mounted) setState(() => _busy = false);
  }

  String _clock(int seconds) {
    final int m = seconds ~/ 60;
    final String s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  KeyEventResult _swallowOk(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    final bool ok = k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space;
    if (ok) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final RemoteView view = RemoteControl.instance.view;
    final bool showQr = view.phase == RemotePhase.ready &&
        view.url != null &&
        view.secondsLeft > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Focus(
            autofocus: true,
            onKeyEvent: _swallowOk,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.l10n.tvRemoteTitle,
                    style: const TextStyle(
                      fontSize: TvDimens.displayS,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text,
                    )),
                const SizedBox(height: 12),
                Text(context.l10n.tvRemoteLead,
                    style: const TextStyle(
                      fontSize: TvDimens.body,
                      color: TvTokens.muted,
                      height: 1.35,
                    )),
                const SizedBox(height: 8),
                Text(context.l10n.tvRemoteWarn,
                    style: const TextStyle(
                      fontSize: TvDimens.caption,
                      color: TvTokens.mutedDim,
                      height: 1.35,
                    )),
                const SizedBox(height: 18),
                Text(_status(context, view),
                    style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w700,
                      color:
                          view.paired ? TvTokens.accentBright : TvTokens.text,
                    )),
                if (showQr) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(context.l10n.tvRemoteLeft(_clock(view.secondsLeft)),
                      style: const TextStyle(
                        fontSize: TvDimens.body,
                        color: TvTokens.accentBright,
                      )),
                ],
                const Spacer(),
                Text(context.l10n.tvRemoteKeep,
                    style: const TextStyle(
                      fontSize: TvDimens.caption,
                      color: TvTokens.mutedDim,
                      height: 1.35,
                    )),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TvCtaButton(
                        label: view.phase == RemotePhase.stopped ||
                                view.phase == RemotePhase.noLan ||
                                view.phase == RemotePhase.error
                            ? context.l10n.tvRemoteStart
                            : context.l10n.tvRemoteNewCode,
                        onSelect: _busy ? null : _restart,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TvCtaButton(
                        label: context.l10n.tvRemoteStop,
                        onSelect: _busy ||
                                view.phase == RemotePhase.stopped ||
                                view.phase == RemotePhase.starting
                            ? null
                            : _stop,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showQr) ...<Widget>[
          const SizedBox(width: TvDimens.gutter),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Un QR ne se scanne qu'en sombre sur fond clair : même
              // traitement que le QR d'activation (TvWhatsAppQr).
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                  border: Border.all(color: TvTokens.accent, width: 2),
                ),
                child: QrImageView(
                  data: view.url!,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  size: 240,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: TvTokens.bg,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: TvTokens.bg,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: Text(context.l10n.tvRemoteUrlHelp,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TvDimens.caption,
                      color: TvTokens.mutedDim,
                    )),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 300,
                child: Text(view.url!,
                    textAlign: TextAlign.center,
                    style:
                        TvTokens.mono(TvDimens.caption, color: TvTokens.text)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _status(BuildContext context, RemoteView view) {
    switch (view.phase) {
      case RemotePhase.starting:
        return context.l10n.tvRemoteStarting;
      case RemotePhase.ready:
        return view.paired
            ? context.l10n.tvRemotePaired
            : context.l10n.tvRemoteWaiting;
      case RemotePhase.expired:
        return context.l10n.tvRemoteExpired;
      case RemotePhase.stopped:
        return context.l10n.tvRemoteStopped;
      case RemotePhase.noLan:
        return context.l10n.tvRemoteNoLan;
      case RemotePhase.error:
        return context.l10n.tvRemoteError;
    }
  }
}
