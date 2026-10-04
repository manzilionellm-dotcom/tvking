// =========================================================
//  panel_board_flags.dart — Interrupteurs des cartes venues du panel
// =========================================================
//  Trois interrupteurs, un par carte (voir BoxFlag : défaut allumé,
//  coupé = la carte n'apparaît plus, rien d'autre ne change).
//  Réglages → En plus. Le direct n'est jamais concerné.
// =========================================================

import '../../box_extras/box_flag.dart';

/// Annonce du revendeur (« Annonces & Notifications » du panel).
final BoxFlag panelNoticeFlag = BoxFlag('zuno.flag.panel_notice');

/// Favori du jour (« Favori du jour » du panel).
final BoxFlag featuredFlag = BoxFlag('zuno.flag.featured');

/// Bannières images (module « Bannières » du panel).
final BoxFlag promoBannerFlag = BoxFlag('zuno.flag.promo_banner');
