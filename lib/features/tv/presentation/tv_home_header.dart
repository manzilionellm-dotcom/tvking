// =========================================================
//  tv_home_header.dart — Bloc contexte de l'accueil The Few
// =========================================================
//  Ville · météo · jour · heure (+ « mot du cœur »), en haut de
//  l'accueil. Extrait de tv_app.dart après un bug TERRAIN (photo
//  box 2026-08-01) : le bloc vivait dans un Expanded coincé entre
//  le logo et 8 puces — quand il ne restait que quelques pixels de
//  large, le texte SANS maxLines se repliait LETTRE PAR LETTRE en
//  colonne, étirait la barre en hauteur et cassait tout l'accueil.
//  Règles d'or désormais testées (tv_home_header_test) :
//    • UNE seule ligne, ellipsis — jamais de pliage vertical ;
//    • ville COURTE (« Tierp », pas « Tierp (Comté d'Uppsala) »).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../data/greeting_repository.dart';

/// Nom de ville AFFICHABLE : le géocodage renvoie souvent
/// « Ville (Région administrative) » — la parenthèse est précieuse dans le
/// SÉLECTEUR (désambiguïser deux « Tierp ») mais trop longue pour la barre
/// d'accueil. On n'affiche que la ville.
String shortCityLabel(String city) =>
    city.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();

/// En-tête personnalisé : ville courte · météo · jour · heure locale.
class TvHomeHeader extends StatefulWidget {
  const TvHomeHeader({super.key, this.initialGreeting});

  /// Semence de test : évite le fetch réseau (mocké à 400 en widget test)
  /// pour exercer le rendu avec une vraie ville/température.
  final Greeting? initialGreeting;

  @override
  State<TvHomeHeader> createState() => _TvHomeHeaderState();
}

class _TvHomeHeaderState extends State<TvHomeHeader> {
  Greeting? _g;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _g = widget.initialGreeting;
    if (_g == null) {
      GreetingRepository.instance.fetch().then((Greeting? g) {
        if (mounted) setState(() => _g = g);
      });
    }
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _time =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final Greeting? g = _g;
    // Jour de la semaine traduit dans la langue active (intl), p. ex.
    // « Lunes » en espagnol, « måndag » en suédois, « الاثنين » en arabe.
    final String localeName = Localizations.localeOf(context).toString();
    final String weekday =
        toBeginningOfSentenceCase(DateFormat.EEEE(localeName).format(_now)) ??
            '';
    final String temp =
        (g != null && g.tempC != null) ? '${g.tempC!.round()}° ${g.emoji}' : '';
    final String dayTime = '$weekday · $_time';
    // LE MOT DU CŒUR : un chiffre de météo, c'est froid — on y ajoute ce
    // qu'une grand-mère dirait. Tard le soir, on le murmure aussi. Un seul
    // mot à la fois, discret, dans le même gris que le reste.
    String heart = '';
    final int hh = _now.hour;
    final int wd = _now.weekday;
    if (hh >= 23 || hh < 5) {
      heart = context.l10n.tvHeartLate;
    } else if (g != null && g.tempC != null && g.tempC! <= 8) {
      heart = context.l10n.tvHeartCoverUp;
    } else if (g != null && g.tempC != null && g.tempC! >= 30) {
      heart = context.l10n.tvHeartDrink;
    } else if (hh >= 5 && hh < 10) {
      // SALUTATION VIVANTE : l'accueil sent le moment de la semaine.
      heart = context.l10n.tvHeartCoffee;
    } else if (wd == DateTime.friday && hh >= 18) {
      heart = context.l10n.tvHeartWeekend;
    } else if (wd == DateTime.sunday && hh >= 10 && hh < 20) {
      heart = context.l10n.tvHeartSunday;
    } else if (wd == DateTime.monday && hh < 12) {
      heart = context.l10n.tvHeartMonday;
    }
    final String city = g == null ? '' : shortCityLabel(g.city);
    return Align(
      alignment: Alignment.centerRight,
      child: Text.rich(
        TextSpan(
          style: TvTokens.ui(18, color: TvTokens.mutedDim),
          children: <InlineSpan>[
            if (city.isNotEmpty) ...<InlineSpan>[
              TextSpan(
                  text: city,
                  style: TvTokens.ui(18,
                      weight: FontWeight.w600, color: TvTokens.muted)),
              const TextSpan(text: '   ·   '),
            ],
            if (temp.isNotEmpty) TextSpan(text: '$temp   ·   '),
            TextSpan(text: dayTime),
            // Le mot du cœur (« couvre-toi bien », « il est tard »…),
            // légèrement doré pour qu'on le sente sans qu'il crie.
            if (heart.isNotEmpty)
              TextSpan(
                  text: '   ·   $heart',
                  style: TvTokens.ui(18,
                      weight: FontWeight.w600, color: TvTokens.goldDeep)),
          ],
        ),
        // BUG TERRAIN (photo box) : sans ces bornes, un Expanded étroit
        // repliait le texte lettre par lettre en colonne et cassait toute
        // la barre. UNE ligne, coupée proprement — quoi qu'il arrive.
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
