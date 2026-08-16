// =========================================================
//  tv_pair_screen.dart — Appairage « ZÉRO FRAPPE » (QR + téléphone)
// =========================================================
//  Le client scanne un QR avec son téléphone, saisit ses identifiants
//  sur un VRAI clavier, et la TV se connecte seule. Plus jamais de
//  serveur Xtream tapé à la télécommande (20 min et des fautes de frappe).
//
//  Garde-fous « salon » :
//   • jamais de cul-de-sac : backend injoignable ou code expiré → message
//     clair + « Nouveau code », et la saisie manuelle reste accessible
//     par Retour ;
//   • le jeton de relève est SECRET — seul le code à 6 chiffres est
//     affiché (cf. pairing_service.dart pour le modèle de sécurité) ;
//   • la relève s'arrête net quand l'écran est démonté (pas de timer
//     fantôme qui frappe le backend en boucle sur une box allumée 24/7).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/pairing_service.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

enum _PairPhase { opening, waiting, importing, expired, unavailable }

class TvPairScreen extends StatefulWidget {
  const TvPairScreen({super.key});

  @override
  State<TvPairScreen> createState() => _TvPairScreenState();
}

class _TvPairScreenState extends State<TvPairScreen> {
  static const Duration _pollEvery = Duration(seconds: 2);

  _PairPhase _phase = _PairPhase.opening;
  PairingSession? _session;
  Timer? _poll;
  String? _error;

  /// Anti-empilement : sur un Wi-Fi lent, une relève peut durer jusqu'au
  /// timeout (12 s) alors que le timer retombe toutes les 2 s — sans ce
  /// verrou, six requêtes se chevauchaient et la box saturait sa file.
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() {
      _phase = _PairPhase.opening;
      _error = null;
    });
    final PairingSession? s = await PairingService.instance.open();
    if (!mounted) return;
    if (s == null) {
      setState(() => _phase = _PairPhase.unavailable);
      return;
    }
    setState(() {
      _session = s;
      _phase = _PairPhase.waiting;
    });
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  Future<void> _tick() async {
    final PairingSession? s = _session;
    if (s == null || _phase != _PairPhase.waiting || _polling) return;
    _polling = true;
    final PairingPoll r;
    try {
      r = await PairingService.instance.poll(s.token);
    } finally {
      _polling = false;
    }
    if (!mounted || _phase != _PairPhase.waiting) return;
    if (r.status == PairingStatus.expired) {
      _poll?.cancel();
      setState(() => _phase = _PairPhase.expired);
      return;
    }
    if (r.status == PairingStatus.ready && r.source != null) {
      _poll?.cancel();
      await _import(r.source!);
    }
  }

  /// Import via les MÊMES points d'entrée que la saisie manuelle
  /// (normalisation des liens, extraction d'identifiants, EPG…) — zéro
  /// chemin parallèle à maintenir.
  Future<void> _import(PairedSource src) async {
    setState(() => _phase = _PairPhase.importing);
    try {
      if (src.isXtream) {
        await PlaylistRepository.instance.addXtreamPlaylist(
          name: src.name,
          serverUrl: src.server!,
          username: src.username!,
          password: src.password!,
        );
      } else {
        await PlaylistRepository.instance.addM3uPlaylistSmart(
          name: src.name,
          url: src.m3uUrl!,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true); // succès → l'aiguillage se referme
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PairPhase.expired;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(context.l10n.tvPairTitle,
                  style: TvTokens.display(34, color: TvTokens.text)),
              const SizedBox(height: 8),
              Text(context.l10n.tvPairSubtitle,
                  style: TvTokens.ui(16, color: TvTokens.mutedDim)),
              const SizedBox(height: 26),
              ..._leftColumn(context),
            ],
          ),
        ),
        const SizedBox(width: 34),
        Expanded(flex: 4, child: Center(child: _qrPane(context))),
      ],
    );
  }

  List<Widget> _leftColumn(BuildContext context) {
    switch (_phase) {
      case _PairPhase.opening:
        return <Widget>[
          Text(context.l10n.tvPairConnecting,
              style: TvTokens.ui(17, color: TvTokens.muted)),
        ];
      case _PairPhase.unavailable:
        return <Widget>[
          Text(context.l10n.tvPairUnavailable,
              style: TvTokens.ui(17, color: const Color(0xFFE0746A))),
          const SizedBox(height: 18),
          TvCtaButton(
              label: context.l10n.tvPairNewCode, onSelect: _start),
        ];
      case _PairPhase.expired:
        return <Widget>[
          Text(_error ?? context.l10n.tvPairExpired,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(17, color: const Color(0xFFE0746A))),
          const SizedBox(height: 18),
          TvCtaButton(
              label: context.l10n.tvPairNewCode, onSelect: _start),
        ];
      case _PairPhase.importing:
        return <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: TvTokens.gold),
              ),
              const SizedBox(width: 14),
              Text(context.l10n.tvPairConnecting,
                  style: TvTokens.ui(18,
                      weight: FontWeight.w700, color: TvTokens.text)),
            ],
          ),
        ];
      case _PairPhase.waiting:
        final PairingSession s = _session!;
        return <Widget>[
          Text(context.l10n.tvPairOrGoTo,
              style: TvTokens.ui(15, color: TvTokens.muted)),
          const SizedBox(height: 8),
          SelectableText(
            s.url.replaceFirst(RegExp(r'^https?://'), ''),
            style: TvTokens.mono(22, color: TvTokens.goldBright),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text('${context.l10n.tvPairCodeIs}  ',
                  style: TvTokens.ui(15, color: TvTokens.muted)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: TvTokens.sel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TvTokens.gold),
                ),
                child: Text(s.code,
                    style: TvTokens.mono(30, color: TvTokens.goldBright)
                        .copyWith(letterSpacing: 6)),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: TvTokens.mutedDim),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.tvPairWaiting,
                  style: TvTokens.ui(15, color: TvTokens.mutedDim)),
            ],
          ),
        ];
    }
  }

  Widget _qrPane(BuildContext context) {
    final PairingSession? s = _session;
    if (s == null || _phase != _PairPhase.waiting) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.gold, width: 2),
      ),
      child: QrImageView(
        data: s.url,
        version: QrVersions.auto,
        size: 300,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
        dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF0B0B0B)),
      ),
    );
  }
}
