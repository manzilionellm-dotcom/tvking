// =========================================================
//  display_settings.dart — Réglages d'affichage TV (confort)
// =========================================================
//  Deux réglages 100 % « présentation », SANS aucun rapport avec le lecteur
//  vidéo ni le décodage (zéro impact sur la stabilité de l'image) :
//
//    • OVERSCAN : certaines TV (surtout anciennes) « rognent » les bords de
//      l'image. On ajoute une marge réglable (0 à 8 %) tout autour de l'app
//      pour que rien ne soit coupé.
//
//      LA MARGE EST AUTOMATIQUE SUR LES BOX (19/09/2026). Photo du
//      propriétaire à l'appui : sur une Sony Bravia d'ancienne génération,
//      la carte du haut à droite et le bouton « J'en profite » sortaient
//      de l'écran. Le réglage existait déjà… à 0 %, caché dans Réglages →
//      Affichage. Un client qui voit son image coupée ne va pas chercher
//      un réglage : il appelle, ou il change d'app. « Il faut que l'app
//      s'adapte partout. »
//
//      Android TV a une règle pour ça, que Netflix, YouTube et le Play
//      Store appliquent tous : garder 5 % de marge de chaque côté, parce
//      qu'on ne peut PAS savoir depuis l'app ce que la télé rogne (le
//      signal HDMI ne le dit pas). C'est donc le défaut, uniquement sur
//      une BOX ANDROID derrière un câble HDMI — un PC Windows ou une
//      Samsung affichent tout, eux, et n'ont rien à masquer.
//
//      Le client garde la main : le réglage descend à 0 % (télé qui
//      affiche tout) ou monte jusqu'à 8 % (télé qui rogne beaucoup). Une
//      valeur qu'il a CHOISIE n'est jamais écrasée par le défaut.
//
//    • VIDÉO PLEIN ÉCRAN : la marge vaut pour l'interface, pas pour
//      l'image. Netflix ne met pas de cadre noir autour d'un film : sur
//      une télé qui ne rogne rien, ce serait 10 % d'image perdue pour
//      rien ; sur une télé qui rogne, perdre 5 % de bord d'image est
//      invisible. Le lecteur se déclare donc « plein écran » : la racine
//      retire la marge physique et la PUBLIE dans MediaQuery.padding, où
//      le lecteur la lit pour placer ses habillages (barre, pastilles,
//      panneau des pistes) hors de la zone rognée. Voir `videoPleinEcran`.
//    • GRAND TEXTE : agrandit légèrement le texte (confort de lecture, utile
//      pour les seniors). Volontairement MODÉRÉ (+8 %) pour ne pas casser les
//      mises en page.
//
//    • ZOOM DE L'INTERFACE (20/09/2026) : agrandit TOUT — menus, affiches,
//      textes — de 10 ou 20 %. Demande du propriétaire, écran de 128
//      pouces : « le menu est devenu petit… il va détecter la TV et
//      s'adapter ». Ce qu'il faut savoir : une box ne PEUT PAS connaître
//      la taille de la télé. Le câble HDMI transmet la résolution (1080p,
//      4K), jamais la diagonale ; et de toute façon c'est la DISTANCE du
//      canapé qui compte, pas les pouces — un 128" vu de 6 m et un 55" vu
//      de 2,5 m demandent la même taille de lettres. Netflix, YouTube,
//      Disney n'ont pas ce réglage automatique non plus : ils ont UNE
//      taille, pensée pour 3 m, et c'est tout. Nous, on laisse le client
//      choisir en trois crans, et la box s'en souvient.
//
//      À NE PAS CONFONDRE avec la marge (overscan). Le 19/09, la marge
//      de 5 % RÉTRÉCISSAIT tout le canevas de 10 % : c'est ça que le
//      propriétaire a vu comme « le menu est devenu petit ». Depuis le
//      20/09, la marge ne rétrécit plus rien : elle RECULE le contenu du
//      bord (voir tv_app.dart). La taille des lettres ne dépend que du
//      zoom, jamais de la marge.
//
//  Ces réglages sont appliqués UNE SEULE FOIS à la racine (MaterialApp.builder)
//  et mémorisés en local (SharedPreferences).
// =========================================================
import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/app_platform.dart';

/// « NUIT ROYALE » — filtre de confort nocturne. Un voile CHAUD très léger
/// (moins de lumière bleue) + une pointe de tamisage, appliqué par-dessus
/// toute l'app le soir. Zéro contact avec le décodage vidéo : c'est une
/// simple couche de couleur GPU (IgnorePointer) à la racine.
enum NightComfortMode {
  /// Jamais de filtre.
  off,

  /// Filtre actif automatiquement le soir (21 h → 7 h). Défaut.
  auto,

  /// Filtre actif en permanence.
  always,
}

/// RAPPELS D'ÉMISSIONS (21/09/2026) — « des petites notifications dans
/// 5 min : le journal et d'autres matchs importants… que ce soit pas
/// gênant ». Une bannière non demandée est gênante par nature ; la seule
/// façon de ne pas l'être, c'est de laisser le client décider de ce qu'il
/// veut recevoir. Trois positions, pas une dizaine de cases.
enum ModeRappels {
  /// Tout : matchs, journaux, et le rappel ordinaire des chaînes suivies.
  /// C'est le comportement historique, donc le défaut.
  tous,

  /// Seulement ce qui compte : matchs et journaux (avec dernier appel).
  importants,

  /// Aucune bannière, jamais.
  aucun,
}

class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();
  static final DisplaySettings instance = DisplaySettings._();

  static const String _kOverscan = 'tv_overscan_pct';
  static const String _kBigText = 'tv_big_text';
  static const String _kNight = 'tv_night_comfort';
  static const String _kNavSounds = 'tv_nav_sounds';
  static const String _kZoom = 'tv_ui_zoom_pct';
  static const String _kRappels = 'tv_reminders_mode';
  static const int maxOverscan = 8;

  /// Les crans de zoom autorisés, en pour cent. Trois, pas un curseur :
  /// un client âgé choisit entre « normal, grand, très grand », pas entre
  /// 100 et 137. Plafond à 120 % : au-delà, avec la marge de 5 %, le
  /// canevas passerait sous 960 px logiques (le 720p d'Android TV) et des
  /// écrans faits pour 1280 commenceraient à déborder.
  static const List<int> zoomsPossibles = <int>[100, 110, 120];

  /// La « zone sûre » Android TV : 5 % de marge de chaque côté. C'est le
  /// chiffre de la règle officielle (48 dp sur 960 dp de large), celui que
  /// Netflix et YouTube appliquent — pas une estimation maison.
  static const int overscanAuto = 5;

  /// Marge par défaut, tant que le client n'a rien choisi.
  ///
  /// 5 % sur une BOX ANDROID (`AppPlatform.isTv` + plateforme Android) :
  /// elle est derrière un câble HDMI, et une télé au bout d'un câble HDMI
  /// peut rogner sans prévenir. 0 % partout ailleurs : un PC Windows
  /// affiche tout, une Samsung (app native, `TargetPlatform.linux` sous
  /// Tizen) aussi — leur mettre un cadre noir serait une régression.
  ///
  /// `defaultTargetPlatform` et non `Platform.isAndroid` : les tests
  /// peuvent le forcer (`debugDefaultTargetPlatformOverride`), et c'est
  /// déjà « android » sous `flutter test`.
  static int get defautOverscanPct =>
      AppPlatform.isTv && defaultTargetPlatform == TargetPlatform.android
          ? overscanAuto
          : 0;

  /// null = jamais réglé par le client → on applique le défaut. Un 0 %
  /// EXPLICITE reste un 0 % (télé qui affiche tout, le client l'a dit).
  int? _overscanPct;
  int _zoomPct = 100;
  bool _bigText = false;
  bool _navSounds = true; // clic discret à chaque cran de D-pad (défaut ON)
  NightComfortMode _night = NightComfortMode.auto;
  ModeRappels _rappels = ModeRappels.tous;

  /// Compteur, pas un booléen : un lecteur peut en ouvrir un autre par-
  /// dessus (multivue, épisode suivant). Chaque entrée compte, chaque
  /// sortie décompte ; la marge revient quand le DERNIER a fermé.
  int _pleinEcran = 0;

  int get overscanPct => _overscanPct ?? defautOverscanPct;

  /// `true` = le client a réglé la marge lui-même (le défaut ne s'applique
  /// plus). Sert à l'écran Réglages pour dire d'où vient le chiffre.
  bool get overscanChoisi => _overscanPct != null;

  /// `true` tant qu'un lecteur vidéo est ouvert : la racine retire alors la
  /// marge physique (image plein écran) et la publie dans
  /// `MediaQuery.padding` pour que le lecteur recule ses habillages.
  bool get videoPleinEcran => _pleinEcran > 0;
  bool get bigText => _bigText;

  /// Sons de navigation (ancrage sensoriel) : petit clic système à chaque
  /// déplacement du focus D-pad, comme Apple TV / TiviMate. Désactivable.
  bool get navSounds => _navSounds;

  /// « NUIT ROYALE » — filtre de confort nocturne (voir NightComfortMode).
  NightComfortMode get nightComfort => _night;

  /// Quels rappels d'émissions le client accepte (voir ModeRappels).
  ModeRappels get rappels => _rappels;

  /// Fraction de marge à appliquer de chaque côté (0.0 → 0.08).
  double get overscanFraction => overscanPct.clamp(0, maxOverscan) / 100.0;

  /// Le CANEVAS LOGIQUE à dessiner pour un écran physique [ecran], à
  /// partir d'une largeur de référence (1280, le 720p « 10-foot »).
  ///
  ///  • le ZOOM divise la largeur : 1280 → 1164 (110 %) → 1067 (120 %).
  ///    Moins de pixels logiques sur le même écran = tout plus grand ;
  ///  • la MARGE ampute ensuite le canevas de la même fraction que l'écran
  ///    (5 % de chaque côté → 90 % en largeur ET en hauteur). L'échelle
  ///    écran/canevas est alors la même qu'à 0 % : la marge RECULE le
  ///    contenu, elle ne le rétrécit plus (décision du 20/09/2026) ;
  ///  • pendant la VIDÉO, le canevas reprend toute sa taille : l'image
  ///    prend tout l'écran, la marge est publiée au lecteur à part.
  ///
  /// Fonction pure (pas de widget) : elle se teste à la virgule près.
  Size canevas({required Size ecran, double largeurReference = 1280}) {
    final double w = largeurReference / zoomFactor;
    final double h = w * ecran.height / ecran.width;
    if (videoPleinEcran) return Size(w, h);
    final double ov = overscanFraction;
    return Size(w * (1 - 2 * ov), h * (1 - 2 * ov));
  }

  /// Un lecteur vidéo s'ouvre : l'image prend tout l'écran.
  ///
  /// La notification est DIFFÉRÉE (microtâche) : ces deux méthodes sont
  /// appelées depuis `initState` / `dispose` d'un écran, c'est-à-dire en
  /// plein `build` d'une frame. Prévenir la racine à ce moment-là, c'est
  /// « setState() called during build » — l'erreur classique. Une
  /// microtâche part une fois la frame finie : la racine se redessine à
  /// la suivante, sans jamais interrompre celle en cours.
  void entrerPleinEcran() {
    _pleinEcran++;
    scheduleMicrotask(notifyListeners);
  }

  /// Le lecteur se ferme : la marge revient (si c'était le dernier).
  void quitterPleinEcran() {
    if (_pleinEcran == 0) return; // une sortie de trop ne casse rien
    _pleinEcran--;
    scheduleMicrotask(notifyListeners);
  }

  /// Facteur de taille du texte (1.0 = normal, 1.08 = grand).
  double get textScale => _bigText ? 1.08 : 1.0;

  /// Zoom de l'interface en pour cent (100, 110 ou 120).
  int get zoomPct => _zoomPct;

  /// Le même zoom en facteur (1.0, 1.1, 1.2). La racine DIVISE la largeur
  /// du canevas par ce facteur : moins de pixels logiques sur le même
  /// écran, donc tout paraît plus grand — menus, affiches et textes, dans
  /// les mêmes proportions. Rien à changer dans les écrans.
  double get zoomFactor => _zoomPct / 100.0;

  /// Ramène une valeur quelconque au cran autorisé le plus proche : une
  /// préférence corrompue ou un futur cran retiré ne peuvent pas laisser
  /// la box avec un zoom impossible.
  static int _cranDeZoom(int pct) {
    int meilleur = zoomsPossibles.first;
    for (final int z in zoomsPossibles) {
      if ((z - pct).abs() < (meilleur - pct).abs()) meilleur = z;
    }
    return meilleur;
  }

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Pas de `?? 0` : sans valeur mémorisée, on reste sur le défaut de la
    // plateforme (5 % sur une box). Un 0 mémorisé, lui, est un choix.
    _overscanPct = prefs.getInt(_kOverscan)?.clamp(0, maxOverscan);
    _bigText = prefs.getBool(_kBigText) ?? false;
    _zoomPct = _cranDeZoom(prefs.getInt(_kZoom) ?? 100);
    _navSounds = prefs.getBool(_kNavSounds) ?? true;
    final int n = prefs.getInt(_kNight) ?? NightComfortMode.auto.index;
    _night = NightComfortMode
        .values[n.clamp(0, NightComfortMode.values.length - 1)];
    final int r = prefs.getInt(_kRappels) ?? ModeRappels.tous.index;
    _rappels = ModeRappels.values[r.clamp(0, ModeRappels.values.length - 1)];
    notifyListeners();
  }

  Future<void> setRappels(ModeRappels mode) async {
    _rappels = mode;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRappels, mode.index);
  }

  Future<void> setNightComfort(NightComfortMode mode) async {
    _night = mode;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNight, mode.index);
  }

  Future<void> setOverscan(int pct) async {
    final int v = pct.clamp(0, maxOverscan);
    _overscanPct = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOverscan, v);
  }

  Future<void> setZoom(int pct) async {
    final int v = _cranDeZoom(pct);
    _zoomPct = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kZoom, v);
  }

  /// Tests uniquement : revient à l'état « rien de mémorisé, aucun lecteur
  /// ouvert », comme au premier lancement.
  @visibleForTesting
  void reinitialiser() {
    _overscanPct = null;
    _zoomPct = 100;
    _rappels = ModeRappels.tous;
    _pleinEcran = 0;
  }

  Future<void> setNavSounds(bool value) async {
    _navSounds = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNavSounds, value);
  }

  Future<void> setBigText(bool value) async {
    _bigText = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBigText, value);
  }
}
