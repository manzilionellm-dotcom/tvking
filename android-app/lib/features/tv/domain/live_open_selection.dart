import 'dart:collection';

import '../../channels/domain/channel.dart';

/// Le numéro de catalogue change aussi lorsque ses restrictions changent.
/// L'identité et la portée du profil restent explicites : un index contenant
/// une chaîne n'est jamais, à lui seul, une autorisation de lecture.
typedef LiveOpenContext = ({
  int catalogGeneration,
  String profileId,
  int profileScope,
  bool kidsMode,
});

/// Sélection du Direct retenue pendant la fermeture asynchrone de l'aperçu.
///
/// La file autorisée est préparée une seule fois. Après une attente, on
/// vérifie les générations et les identités des index/snapshots en O(1), puis
/// l'autorisation ACTUELLE de la chaîne choisie. Aucun Set de tout le catalogue
/// n'est alloué pour ouvrir une petite catégorie.
class LiveOpenSelection {
  LiveOpenSelection._({
    required this.channels,
    required this.startIndex,
    required LiveOpenContext context,
    required Object catalogSnapshot,
    required Map<String, Channel> byId,
  }) : _context = context,
       _catalogSnapshot = catalogSnapshot,
       _byId = byId;

  final List<Channel> channels;
  final int startIndex;
  final LiveOpenContext _context;
  final Object _catalogSnapshot;
  final Map<String, Channel> _byId;

  Channel get selected => channels[startIndex];

  /// Une chaîne remplacée portant le même identifiant n'est pas celle sur
  /// laquelle l'utilisateur a appuyé. Les objets doivent correspondre au lot.
  static LiveOpenSelection? capture({
    required List<Channel> list,
    required int index,
    required Map<String, Channel> byId,
    required LiveOpenContext context,
    required Object catalogSnapshot,
    required bool Function(Channel) allowsChannel,
    bool legacy = false,
  }) {
    if (index < 0 || index >= list.length) return null;
    final Channel selected = list[index];
    if (!identical(byId[selected.id], selected) || !allowsChannel(selected)) {
      return null;
    }

    final List<Channel> allowed;
    int selectedIndex = -1;
    if (legacy) {
      // Retour au calcul historique de la file, sans retirer les gardes de
      // génération ni d'autorisation ajoutées autour des attentes.
      allowed = list.where(allowsChannel).toList(growable: false);
      selectedIndex = allowed.indexOf(selected);
      if (selectedIndex < 0 ||
          !allowed.every((c) => identical(byId[c.id], c))) {
        return null;
      }
    } else {
      allowed = <Channel>[];
      for (final Channel channel in list) {
        if (!allowsChannel(channel)) continue;
        // Une ancienne entrée dans la file invalide l'ouverture entière,
        // comme auparavant ; elle n'est pas remplacée silencieusement.
        if (!identical(byId[channel.id], channel)) return null;
        if (selectedIndex < 0 && identical(channel, selected)) {
          selectedIndex = allowed.length;
        }
        allowed.add(channel);
      }
      if (selectedIndex < 0) return null;
    }

    return LiveOpenSelection._(
      channels: UnmodifiableListView<Channel>(allowed),
      startIndex: selectedIndex,
      context: context,
      catalogSnapshot: catalogSnapshot,
      byId: byId,
    );
  }

  /// La comparaison du snapshot ferme aussi la fenêtre entre sa publication
  /// par le dépôt et la livraison de son événement au Direct. Les restrictions
  /// restent vérifiées même si une génération a été oubliée par l'appelant.
  bool isCurrent({
    required LiveOpenContext context,
    required Object catalogSnapshot,
    required Map<String, Channel> byId,
    required bool Function(Channel) allowsChannel,
  }) =>
      context == _context &&
      identical(catalogSnapshot, _catalogSnapshot) &&
      identical(byId, _byId) &&
      identical(byId[selected.id], selected) &&
      allowsChannel(selected);
}
