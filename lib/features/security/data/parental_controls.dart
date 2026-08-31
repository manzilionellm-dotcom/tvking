// =========================================================
//  parental_controls.dart — Contrôle parental & Mode Enfants
// =========================================================
//  Fonctionnalité « premium famille » (comme Netflix Kids / Disney+ Junior) :
//  un MODE ENFANTS qui masque automatiquement tout le contenu Adulte, protégé
//  par le code PIN à 4 chiffres de l'app (AppPinSettings). Un enfant ne peut
//  donc pas le désactiver lui-même.
//
//  Tout est LOCAL (SharedPreferences) — aucune dépendance réseau, aucun impact
//  sur le lecteur vidéo. Par défaut TOUT est désactivé : le comportement de
//  l'app ne change pour personne tant que le parent n'active pas le mode.
//
//  ---------------------------------------------------------
//  VAGUE 2 (30/08) — LE MODE ENFANTS SUIT LE PROFIL
//  ---------------------------------------------------------
//  Demande du propriétaire : « contrôle parental PAR PROFIL ». Un profil
//  d'enfant doit être bridé même si l'interrupteur global de la box est
//  éteint, et l'interrupteur global doit continuer de valoir pour tout le
//  monde quand il est allumé.
//
//  D'où la règle, en une phrase :
//
//      MODE ENFANTS EFFECTIF = interrupteur de l'appareil  OU
//                              profil actif marqué « enfant »
//
//  Le OU (et non le ET) est délibéré : sur un contrôle parental, la
//  position la plus SÛRE des deux gagne toujours. Se tromper dans ce sens
//  ferme trop de contenu à un adulte — l'inverse en ouvrirait trop à un
//  enfant.
//
//  IMPLÉMENTATION : `kidsMode` reste le MÊME ValueNotifier<bool> qu'avant.
//  Une dizaine d'écrans l'écoutent déjà ; en changer le type aurait obligé
//  à toucher chacun d'eux — donc dix occasions d'oublier un filtre. On ne
//  change que ce qu'on MET DEDANS.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

class ParentalControls {
  ParentalControls._();
  static final ParentalControls instance = ParentalControls._();

  static const String _kKidsMode = 'security.kids_mode.v1';

  /// Mode Enfants EFFECTIF, OBSERVABLE : les écrans (ex. Direct) écoutent ce
  /// notifier pour se re-filtrer instantanément quand le parent bascule —
  /// ou quand on change pour un profil d'enfant.
  /// Défaut : false (rien de masqué).
  final ValueNotifier<bool> kidsMode = ValueNotifier<bool>(false);

  /// L'interrupteur de l'APPAREIL, tel que réglé dans « Contrôle parental ».
  /// Distinct de [kidsMode], qui y ajoute la règle du profil : sans cette
  /// séparation, l'écran de réglages afficherait « activé » simplement
  /// parce qu'un enfant est connecté, et le parent croirait avoir mis
  /// l'interrupteur alors qu'il ne l'a pas fait.
  bool _deviceKidsMode = false;
  bool get deviceKidsMode => _deviceKidsMode;

  bool _loaded = false;
  bool _listening = false;

  /// Charge l'état mémorisé. Idempotent, best-effort (ne plante jamais).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _deviceKidsMode = prefs.getBool(_kKidsMode) ?? false;
    } catch (_) {
      // best-effort : en cas de souci, on reste sur les défauts (désactivé).
    }
    _loaded = true;
    // On s'abonne UNE fois au dépôt de profils : changer de profil, ou
    // recevoir du panel un profil re-marqué « enfant », doit re-filtrer les
    // écrans sans que personne n'ait à y penser.
    if (!_listening) {
      _listening = true;
      ProfilesRepository.instance.addListener(_recompute);
    }
    _recompute();
  }

  /// Active / désactive le Mode Enfants de l'APPAREIL et persiste le choix.
  Future<void> setKidsMode(bool value) async {
    _deviceKidsMode = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKidsMode, value);
    } catch (_) {
      // best-effort
    }
    _recompute();
  }

  /// Applique la règle « appareil OU profil ». Ne notifie que si la valeur
  /// CHANGE (ValueNotifier le fait déjà) : les écrans qui rebuild sur ce
  /// notifier ne repartent pas pour rien à chaque synchro de profils.
  void _recompute() {
    kidsMode.value = _deviceKidsMode || ProfilesRepository.instance.activeIsKids;
  }

  @visibleForTesting
  void debugRecompute() => _recompute();
}
