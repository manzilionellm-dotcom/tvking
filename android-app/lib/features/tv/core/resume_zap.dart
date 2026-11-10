// =========================================================
//  resume_zap.dart — Reprise au démarrage : zapper dans TOUTE la liste
// =========================================================
//  Avant (4 octobre 2026) : la reprise automatique ouvrait la dernière
//  chaîne avec, comme liste de zap, les 8 chaînes « Reprendre ». Haut/Bas
//  ne parcouraient donc pas la liste du client. Ici on ouvre la même
//  chaîne, positionnée dans la liste complète des chaînes en direct.
//  Une chaîne retirée/masquée n'est jamais réintroduite depuis l'historique.
//  Fonction pure, testée sans écran.
// =========================================================

import '../../channels/domain/channel.dart';

class ResumeZap {
  const ResumeZap(this.channels, this.startIndex);
  final List<Channel> channels;
  final int startIndex;
}

/// [all] = toutes les chaînes connues ; [recent] = rangée « Reprendre »
/// (la première est la dernière vue). [selectedIndex] conserve la carte
/// choisie manuellement. [hide] applique le filtre parental du même écran.
/// `null` = cible absente du catalogue accessible, donc aucune reprise.
ResumeZap? resumeZapList(
  List<Channel> all,
  List<Channel> recent, {
  int selectedIndex = 0,
  bool Function(Channel)? hide,
}) {
  if (selectedIndex < 0 || selectedIndex >= recent.length) return null;
  final Channel last = recent[selectedIndex];
  final List<Channel> live = <Channel>[
    for (final Channel c in all)
      if (c.isLive && !(hide?.call(c) ?? false)) c,
  ];
  final int at = live.indexWhere(
      (Channel c) => c.id == last.id && c.playlistId == last.playlistId);
  if (at < 0) return null;
  return ResumeZap(live, at);
}

/// Une reprise différée conserve son intention, pas son ancien catalogue.
/// Un changement de portée l'annule ; une actualisation de la même source
/// utilise ses nouvelles chaînes et son URL actuelle au prochain cadre.
ResumeZap? refreshResumeZap(
  ResumeZap captured,
  List<Channel> current, {
  required int requestedScope,
  required int currentScope,
  bool Function(Channel)? hide,
}) {
  if (requestedScope != currentScope ||
      captured.startIndex < 0 ||
      captured.startIndex >= captured.channels.length) return null;
  return resumeZapList(
      current, <Channel>[captured.channels[captured.startIndex]],
      hide: hide);
}
