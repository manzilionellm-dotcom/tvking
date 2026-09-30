// =========================================================
//  box_signal.dart — Décisions pures « panel → box »
// =========================================================
//  Pas de réseau ici. On décide seulement :
//    - quels ordres sont nouveaux (un numéro déjà vu ne se rejoue pas) ;
//    - quels rafraîchissements lancer pour chaque nom d'ordre ;
//    - à quel rythme retomber si le canal long est coupé.
// =========================================================

import 'activation_pace.dart';

/// Nom d'ordre → ce que la box doit relire.
///
/// `status` : licence, gel, ban, expiration (GET /api/status).
/// `source` : listes IPTV (empreintes + fichier des codes).
/// Le reste : une lecture du réglage déjà servi par le Worker.
enum SignalRefresh {
  status,
  source,
  announcement,
  theme,
  home,
  forceUpdate,
  featured,
  ad,
  pricing,
  feedback,
  servers,
}

/// Ordres déjà connus : on ne les rejoue pas.
List<Map<String, Object?>> freshCommands(
  List<Map<String, Object?>> incoming,
  Set<int> seen,
) {
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  final Set<int> local = <int>{};
  for (final Map<String, Object?> item in incoming) {
    final int? id = (item['id'] as num?)?.toInt();
    if (id == null || seen.contains(id) || local.contains(id)) continue;
    local.add(id);
    out.add(item);
  }
  return out;
}

/// Ce qu'il faut relire pour ce nom. Inconnu → on relit le statut,
/// sans inventer un autre effet.
Set<SignalRefresh> refreshesFor(String kind) {
  switch (kind) {
    case 'activate':
    case 'renew':
    case 'expire':
    case 'suspend':
    case 'resume':
    case 'block':
    case 'transfer':
    case 'device_delete':
    case 'license':
      return <SignalRefresh>{SignalRefresh.status};
    case 'source':
    case 'source_clear':
      return <SignalRefresh>{SignalRefresh.status, SignalRefresh.source};
    case 'message':
      return <SignalRefresh>{SignalRefresh.announcement};
    case 'theme':
      return <SignalRefresh>{SignalRefresh.theme};
    case 'home':
      return <SignalRefresh>{SignalRefresh.home};
    case 'force_update':
      return <SignalRefresh>{SignalRefresh.forceUpdate};
    case 'featured':
      return <SignalRefresh>{SignalRefresh.featured};
    case 'ad':
      return <SignalRefresh>{SignalRefresh.ad};
    case 'pricing':
      return <SignalRefresh>{SignalRefresh.pricing};
    case 'feedback':
      return <SignalRefresh>{SignalRefresh.feedback};
    case 'servers':
      return <SignalRefresh>{SignalRefresh.servers};
    default:
      return <SignalRefresh>{SignalRefresh.status};
  }
}

/// Vrai si l'ordre change la licence ou la liste : on n'accuse
/// réception qu'après une lecture de statut réussie. Un message ou
/// un thème peut être accusé même si cette lecture-là échoue,
/// parce qu'elle a son propre appel.
bool kindNeedsStatus(String kind) {
  final Set<SignalRefresh> set = refreshesFor(kind);
  return set.contains(SignalRefresh.status) ||
      set.contains(SignalRefresh.source);
}

/// Canal ouvert : on ne relit le statut que toutes les 25 s
/// (filet). Canal coupé : on revient au rythme 3 s / 4 s de la 103.
Duration signalPace({
  required bool channelUp,
  required bool waiting,
  required int failures,
}) {
  if (channelUp && failures <= 0) return ActivationPace.parked;
  return ActivationPace.next(waiting: waiting, failures: failures);
}
