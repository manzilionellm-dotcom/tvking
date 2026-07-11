// =========================================================
//  mini_epg_now_next.dart — Mini-guide « En ce moment / Ensuite »
// =========================================================
//  Petit bandeau affiché dans l'overlay du lecteur en LIVE : il
//  montre le programme EN COURS (titre + horaires + barre de
//  progression) et, s'il existe, le programme SUIVANT. C'est le
//  « must-have » des apps IPTV premium (façon TiviMate) : savoir ce
//  qui passe maintenant sans quitter la chaîne.
//
//  Robuste : si la chaîne n'a AUCUNE donnée EPG (cas fréquent selon
//  les fournisseurs), le widget se masque tout seul (SizedBox.shrink)
//  — il n'occupe alors aucune place et ne gêne pas l'image.
//
//  Auto-rafraîchi toutes les 30 s (la barre de progression avance,
//  et on bascule sur le programme suivant à la fin du courant) et à
//  chaque changement de chaîne (zapping).
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/epg_repository.dart';
import '../../domain/epg_program.dart';
import '../epg_format.dart';

class MiniEpgNowNext extends StatefulWidget {
  const MiniEpgNowNext({required this.channelId, super.key});

  /// Id de la chaîne en cours de lecture. Quand il change (zapping),
  /// on recharge le now/next pour la nouvelle chaîne.
  final String channelId;

  @override
  State<MiniEpgNowNext> createState() => _MiniEpgNowNextState();
}

class _MiniEpgNowNextState extends State<MiniEpgNowNext> {
  EpgProgram? _now;
  EpgProgram? _next;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Rafraîchit la barre de progression et la bascule now→next.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant MiniEpgNowNext oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changement de chaîne → on recharge le programme.
    if (oldWidget.channelId != widget.channelId) _load();
  }

  Future<void> _load() async {
    final EpgProgram? now =
        await EpgRepository.instance.currentProgram(widget.channelId);
    final EpgProgram? next =
        await EpgRepository.instance.nextProgram(widget.channelId);
    if (!mounted) return;
    setState(() {
      _now = now;
      _next = next;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EpgProgram? now = _now;
    // Pas de donnée EPG → invisible, zéro encombrement.
    if (now == null) return const SizedBox.shrink();

    // Fraction écoulée du programme en cours (pour la barre).
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int span = now.stopTime - now.startTime;
    final double progress = span <= 0
        ? 0.0
        : ((nowMs - now.startTime) / span).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Ligne « en ce moment » : titre + horaires.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  now.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                // Plage horaire localisée (12h/24h selon la locale).
                epgTimeRange(context, now),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Barre de progression du programme en cours.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          // Ligne « ensuite » : flèche + titre du programme suivant.
          if (_next != null) ...<Widget>[
            const SizedBox(height: 5),
            Row(
              children: <Widget>[
                Icon(
                  Icons.skip_next_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _next!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
