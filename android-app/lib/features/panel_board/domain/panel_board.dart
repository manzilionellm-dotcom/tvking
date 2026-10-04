// =========================================================
//  panel_board.dart — Ce que le PANEL a le droit de montrer sur l'accueil
// =========================================================
//  Fonctions PURES (pas de réseau, pas de disque, pas de widget).
//  Trois choses viennent du panel du revendeur et arrivent sur la box
//  par le canal « signal » déjà en place (voir box_signal.dart) :
//
//    1. l'ANNONCE (« Annonces & Notifications » du panel) : un titre, un
//       texte, parfois un lien. Sur une télé il n'y a pas de notification
//       système : l'annonce est une carte sur l'accueil, jamais sur l'image.
//    2. le FAVORI DU JOUR (« Favori du jour » du panel) : le NOM d'une
//       chaîne + une note (« Mondial ce soir ⚽ »). On ne l'affiche que si
//       la chaîne existe VRAIMENT dans la liste de cette box.
//    3. les BANNIÈRES (module « Bannières » du panel, pas encore codé côté
//       panel) : des images avec un libellé, parfois une chaîne ou un lien.
//       La box lit `/api/banners` ; tant que le Worker ne le sert pas,
//       la liste est vide et rien ne change à l'écran.
//
//  Règles d'or (elles protègent le client de nous) :
//    - UNE carte panel à la fois sur l'accueil, et l'émission suivie par
//      la personne passe toujours devant (c'est SON émission) ;
//    - une bannière porte toujours son libellé (« Publicité ») ;
//    - plafond par jour et par bannière, fermable pour la journée ;
//    - rien ne se lance tout seul ; en mode enfants, pas de promo.
// =========================================================

import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../voice/domain/voice_query.dart';

// ---------------------------------------------------------------------------
//  Favori du jour : retrouver la chaîne par son NOM
// ---------------------------------------------------------------------------

/// Projection légère d'une chaîne : ce qu'il faut pour la retrouver par
/// son nom, et rien d'autre (pas d'adresse de flux). C'est ce qui part
/// dans l'isolate quand la liste est grosse.
typedef NameRow = ({String id, String name, bool live});

/// Au-delà de ce nombre de chaînes, le repli des noms (regex sur chaque
/// nom) quitte le fil UI (voir [findChannelByName]).
const int kNameMatchInlineMax = 2000;

/// Retrouve l'id de la chaîne nommée par le panel.
///
/// 1. nom replié identique (accents, casse, tirets ignorés) ;
/// 2. sinon la première chaîne EN DIRECT dont le nom replié commence par
///    le nom cherché suivi d'un espace (« tf1 » → « TF1 HD ») ;
/// 3. sinon rien : on n'invente pas de favori.
///
/// Le direct passe avant une entrée VOD du même nom.
String? matchChannelIdByName(String name, List<NameRow> rows) {
  final String want = voiceFold(name);
  if (want.isEmpty || rows.isEmpty) return null;
  // Filtre pas cher avant le repli (regex) : le nom doit au moins
  // contenir le premier caractère ASCII du nom cherché, en minuscules.
  final String probe = want.isNotEmpty ? want[0] : '';
  String? exact;
  String? prefix;
  for (final NameRow r in rows) {
    if (probe.isNotEmpty && !r.name.toLowerCase().contains(probe)) continue;
    final String have = voiceFold(r.name);
    if (have == want) {
      if (r.live) return r.id;
      exact ??= r.id;
      continue;
    }
    if (prefix == null && r.live && have.startsWith('$want ')) {
      prefix = r.id;
    }
  }
  return exact ?? prefix;
}

/// Même chose sur des [Channel] (listes courtes, tests).
Channel? matchChannelByName(String name, List<Channel> channels) {
  final String? id = matchChannelIdByName(name, nameRows(channels));
  if (id == null) return null;
  for (final Channel c in channels) {
    if (c.id == id) return c;
  }
  return null;
}

List<NameRow> nameRows(List<Channel> channels) => <NameRow>[
      for (final Channel c in channels)
        (id: c.id, name: c.name, live: c.isLive),
    ];

/// Version qui respecte le fil UI : jusqu'à [kNameMatchInlineMax]
/// chaînes, on cherche sur place ; au-delà, dans un isolate (une box
/// peut avoir 50 000 chaînes, et une regex par nom, ça se voit).
Future<Channel?> findChannelByName(String name, List<Channel> channels) async {
  if (name.trim().isEmpty || channels.isEmpty) return null;
  if (channels.length <= kNameMatchInlineMax) {
    return matchChannelByName(name, channels);
  }
  final List<NameRow> rows = nameRows(channels);
  final String? id = await Isolate.run(() => matchChannelIdByName(name, rows));
  if (id == null) return null;
  for (final Channel c in channels) {
    if (c.id == id) return c;
  }
  return null;
}

// ---------------------------------------------------------------------------
//  Bannières : modèle + lecture du JSON du Worker
// ---------------------------------------------------------------------------

/// Nombre maximal de bannières gardées (au-delà, le panel s'est trompé).
const int kPromoMaxItems = 20;

/// Au plus N affichages d'une même bannière par jour.
const int kPromoMaxPerDay = 6;

/// Libellé par défaut quand le panel n'en donne pas. Une bannière sans
/// libellé n'existe pas : la loi (et le bon sens) veut qu'une publicité
/// se présente comme telle.
const String kPromoDefaultLabel = 'Publicité';

/// Une bannière telle que le panel la décrit. Immuable.
///
/// Contrat JSON (`GET /api/banners` → `{items:[…], version}`), chaque item :
///   id        chaîne non vide (identité pour le plafond et la fermeture)
///   image     URL https de l'image (16:5 conseillé, ≥ 1280 px de large)
///   title     titre court (optionnel)
///   subtitle  sous-titre (optionnel)
///   label     « Publicité » / « Sponsorisé » / « Info » (défaut : Publicité)
///   cta       libellé du bouton (optionnel, défaut selon l'action)
///   channel   NOM d'une chaîne à ouvrir (optionnel)
///   url       lien pour le téléphone, montré en QR (optionnel)
///   from      début de diffusion, epoch ms (optionnel)
///   until     fin de diffusion, epoch ms (optionnel)
///   kids      true = visible aussi en mode enfants (défaut : false)
@immutable
class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.image,
    this.title = '',
    this.subtitle = '',
    this.label = kPromoDefaultLabel,
    this.cta = '',
    this.channel = '',
    this.url = '',
    this.fromMs = 0,
    this.untilMs = 0,
    this.kids = false,
  });

  final String id;
  final String image;
  final String title;
  final String subtitle;
  final String label;
  final String cta;
  final String channel;
  final String url;
  final int fromMs;
  final int untilMs;
  final bool kids;

  /// Un item du Worker. `null` si inutilisable (pas d'id, image absente ou
  /// pas en https : la box n'affiche pas d'image en clair).
  static PromoBanner? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = (raw['id'] ?? '').toString().trim();
    final String image = (raw['image'] ?? '').toString().trim();
    if (id.isEmpty || id.length > 64) return null;
    final Uri? uri = Uri.tryParse(image);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    String label = (raw['label'] ?? '').toString().trim();
    if (label.isEmpty) label = kPromoDefaultLabel;
    return PromoBanner(
      id: id,
      image: image,
      title: _text(raw['title'], 80),
      subtitle: _text(raw['subtitle'], 120),
      label: label.length > 24 ? label.substring(0, 24) : label,
      cta: _text(raw['cta'], 24),
      channel: _text(raw['channel'], 80),
      url: _httpsOrEmpty(raw['url']),
      fromMs: _ms(raw['from']),
      untilMs: _ms(raw['until']),
      kids: raw['kids'] == true,
    );
  }

  static String _text(Object? v, int max) {
    final String s = (v ?? '').toString().trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  static String _httpsOrEmpty(Object? v) {
    final String s = (v ?? '').toString().trim();
    final Uri? u = Uri.tryParse(s);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return '';
    return s;
  }

  static int _ms(Object? v) {
    if (v is int) return v < 0 ? 0 : v;
    if (v is num) return v < 0 ? 0 : v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  /// Vrai si la bannière a une action (chaîne ou lien). Sans action, elle
  /// reste une image : on la montre, mais il n'y a que « Fermer ».
  bool get hasAction => channel.isNotEmpty || url.isNotEmpty;
}

/// Lit `{items:[…]}` ou directement `[…]`. Items invalides ignorés, ids en
/// double gardés une fois (le premier), liste bornée à [kPromoMaxItems].
List<PromoBanner> parsePromoBanners(Object? decoded) {
  Object? list = decoded;
  if (decoded is Map) list = decoded['items'];
  if (list is! List) return const <PromoBanner>[];
  final List<PromoBanner> out = <PromoBanner>[];
  final Set<String> ids = <String>{};
  for (final Object? item in list) {
    final PromoBanner? b = PromoBanner.fromJson(item);
    if (b == null || !ids.add(b.id)) continue;
    out.add(b);
    if (out.length >= kPromoMaxItems) break;
  }
  return out;
}

/// « Fermer » éloigne une bannière pendant 7 jours : la personne a dit
/// non, on ne revient pas le lendemain avec la même image.
const Duration kPromoDismissFor = Duration(days: 7);

/// Les bannières qu'on a le droit de montrer MAINTENANT :
/// dans leur fenêtre de diffusion, autorisées en mode enfants si besoin,
/// pas fermées (7 jours), pas déjà vues [kPromoMaxPerDay] fois aujourd'hui.
List<PromoBanner> eligiblePromos({
  required List<PromoBanner> banners,
  required int nowMs,
  required bool kidsMode,
  required Map<String, int> shownToday,
  required Set<String> dismissed,
  int maxPerDay = kPromoMaxPerDay,
}) {
  final List<PromoBanner> out = <PromoBanner>[];
  for (final PromoBanner b in banners) {
    if (b.fromMs > 0 && nowMs < b.fromMs) continue;
    if (b.untilMs > 0 && nowMs >= b.untilMs) continue;
    if (kidsMode && !b.kids) continue;
    if (dismissed.contains(b.id)) continue;
    if ((shownToday[b.id] ?? 0) >= maxPerDay) continue;
    out.add(b);
  }
  return out;
}

/// Rotation : la [tick]-ième bannière éligible (le tic vient de l'horloge
/// de l'accueil, 20 s). Liste vide → rien.
PromoBanner? rotatePromo(List<PromoBanner> eligible, int tick) {
  if (eligible.isEmpty) return null;
  final int i = tick % eligible.length;
  return eligible[i < 0 ? i + eligible.length : i];
}

// ---------------------------------------------------------------------------
//  Une seule carte en tête de l'accueil
// ---------------------------------------------------------------------------

/// Ce que la tête de l'accueil montre. Une seule chose à la fois :
/// la télé n'est pas un fil d'actualité.
enum HeaderCard { show, notice, promo, featured, none }

/// Priorité : l'émission suivie par la personne (minutée, c'est la sienne)
/// > l'annonce du revendeur (persistante jusqu'à « Vu ») > les deux cartes
/// « vitrine » qui ALTERNENT d'un tic à l'autre quand les deux existent.
HeaderCard pickHeaderCard({
  required bool hasShow,
  required bool hasNotice,
  required bool hasPromo,
  required bool hasFeatured,
  required int tick,
}) {
  if (hasShow) return HeaderCard.show;
  if (hasNotice) return HeaderCard.notice;
  if (hasPromo && hasFeatured) {
    return tick.isEven ? HeaderCard.promo : HeaderCard.featured;
  }
  if (hasPromo) return HeaderCard.promo;
  if (hasFeatured) return HeaderCard.featured;
  return HeaderCard.none;
}

/// Clé « jour » locale pour les compteurs (AAAA-MM-JJ). Un jour change,
/// les compteurs et les fermetures repartent de zéro.
String promoDayKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// En mode enfants, une annonce « promo » n'a rien à faire à l'écran.
/// Les autres (info, maintenance, nouveauté) restent : elles parlent du
/// service, pas d'une vente.
bool noticeAllowed({required String kind, required bool kidsMode}) =>
    !(kidsMode && kind == 'promo');
