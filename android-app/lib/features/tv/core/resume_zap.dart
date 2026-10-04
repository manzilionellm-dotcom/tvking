// =========================================================
//  resume_zap.dart — Reprise au démarrage : zapper dans TOUTE la liste
// =========================================================
//  Avant (4 octobre 2026) : la reprise automatique ouvrait la dernière
//  chaîne avec, comme liste de zap, les 8 chaînes « Reprendre ». Haut/Bas
//  ne parcouraient donc pas la liste du client. Ici on ouvre la même
//  chaîne, positionnée dans la liste complète des chaînes en direct.
//  Si elle n'y est plus (liste changée), on garde l'ancien comportement.
//  Fonction pure, testée sans écran.
// =========================================================

import '../../channels/domain/channel.dart';

class ResumeZap {
  const ResumeZap(this.channels, this.startIndex);
  final List<Channel> channels;
  final int startIndex;
}

/// [all] = toutes les chaînes connues ; [recent] = rangée « Reprendre »
/// (la première est la dernière vue). `null` = rien à reprendre.
ResumeZap? resumeZapList(List<Channel> all, List<Channel> recent) {
  if (recent.isEmpty) return null;
  final Channel last = recent.first;
  final List<Channel> live = <Channel>[
    for (final Channel c in all)
      if (c.isLive) c,
  ];
  final int at = live.indexWhere((Channel c) => c.id == last.id);
  if (at < 0) return ResumeZap(List<Channel>.of(recent), 0);
  return ResumeZap(live, at);
}
