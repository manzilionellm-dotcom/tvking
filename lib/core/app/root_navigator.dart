// =========================================================
//  root_navigator.dart — Clé du Navigator racine
// =========================================================
//  Permet aux surfaces montées AU-DESSUS du Navigator (comme le
//  mini-lecteur flottant posé dans MaterialApp.builder) de pousser
//  des routes — p. ex. « Agrandir » qui rouvre le plein écran.
//  Posée sur le MaterialApp dans main.dart.
// =========================================================

import 'package:flutter/widgets.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
