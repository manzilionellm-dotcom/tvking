// =========================================================
//  crash_device_label.dart — Modèle de la box, rien d'autre
// =========================================================
//  Une ligne de plantage doit dire SUR QUOI ça a cassé
//  (fabricant, modèle, niveau d'API). Elle ne doit pas dire
//  QUI regarde : pas d'adresse MAC, pas d'identifiants de
//  flux, pas d'e-mail. Ces trois champs viennent de
//  Build.MANUFACTURER / MODEL / SDK_INT, déjà lus par le
//  plugin tvking_device (getDeviceInfo).
//
//  Sous Android 10 (API 29), ActivityManager ne donne pas
//  encore la raison de la mort (ça commence à Android 11).
//  Le modèle, lui, est là. On l'écrit quand même.
// =========================================================

import '../blackbox/black_box_redaction.dart';

/// « NVIDIA SHIELD Android TV · API 35 », ou une chaîne vide
/// si le modèle est inconnu. On n'invente pas un nom.
String crashDeviceLabel({
  required String manufacturer,
  required String model,
  required String sdk,
}) {
  final String device = model.trim();
  if (device.isEmpty) return '';
  final String maker = manufacturer.trim();
  final String api = sdk.trim();
  final bool makerAlreadyInModel = maker.isNotEmpty &&
      device.toLowerCase().startsWith(maker.toLowerCase());
  final String who =
      maker.isEmpty || makerAlreadyInModel ? device : '$maker $device';
  final String line = api.isEmpty ? who : '$who · API $api';
  // Filet : un modèle exotique qui contiendrait une URL ou un
  // identifiant ne doit pas sortir tel quel.
  return redactBlackBox(line);
}
