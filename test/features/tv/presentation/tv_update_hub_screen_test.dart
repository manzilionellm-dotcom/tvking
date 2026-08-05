// =========================================================
//  tv_update_hub_screen_test.dart — le choix derrière « Mise à jour »
// =========================================================
//  CONTRAT CLIENT, mot pour mot : « si tu appuies, il te demande : tu veux
//  la mise à jour des applications, des mots de passe ou des listes de
//  chaînes ? »
//
//  Ces tests gardent les TROIS choix et leurs noms. Ils sont là contre une
//  régression précise : quelqu'un qui « simplifierait » l'écran en
//  retirant une entrée casserait la promesse faite au client, et rien
//  d'autre ne le signalerait — le bouton continuerait de s'ouvrir.
//
//  Les libellés sont vérifiés tels qu'ils s'affichent : c'est ce que le
//  client lit à 3 mètres, pas un identifiant interne.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_update_hub_screen.dart';

void main() {
  testWidgets('les trois mises à jour sont proposées, et nommées en clair',
      (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: TvUpdateHubScreen()));
    await t.pump();

    // La question posée au client, telle qu'il l'a demandée.
    expect(find.text('Que voulez-vous mettre à jour ?'), findsOneWidget);

    // Les trois choix. Nommés par leur EFFET : « listes de chaînes », pas
    // « playlists » — le client ne parle pas ce vocabulaire.
    expect(find.text('L\'application'), findsOneWidget);
    expect(find.text('Les listes de chaînes'), findsOneWidget);
    expect(find.text('Les mots de passe'), findsOneWidget);
  });

  testWidgets('le sous-menu distingue les DEUX mots de passe de l\'app',
      (WidgetTester t) async {
    // Confondre le mot de passe du FOURNISSEUR (chaînes en 401/403) et le
    // CODE PARENTAL de la box coûte cher au support : les deux entrées
    // doivent rester distinctes et explicites.
    await t.pumpWidget(const MaterialApp(home: TvPasswordsHubScreen()));
    await t.pump();

    expect(find.text('Identifiants du fournisseur'), findsOneWidget);
    expect(find.text('Code parental'), findsOneWidget);
  });

  testWidgets('une ligne occupée ne peut plus être re-déclenchée',
      (WidgetTester t) async {
    // Un rafraîchissement de chaînes dure. Si la ligne restait cliquable,
    // le client la martèlerait — et chaque appui relancerait un import.
    int presses = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvUpdateChoiceRow(
          icon: Icons.live_tv_rounded,
          title: 'Les listes de chaînes',
          subtitle: 'Re-télécharger toutes vos sources.',
          busy: true,
          busyLabel: 'Mise à jour des chaînes en cours…',
          onSelect: () => presses++,
        ),
      ),
    ));
    await t.pump();

    // L'état occupé est ANNONCÉ (un bouton qui ne réagit pas sans rien
    // dire est un bouton qu'on croit cassé).
    expect(find.text('Mise à jour des chaînes en cours…'), findsOneWidget);

    await t.tap(find.text('Les listes de chaînes'), warnIfMissed: false);
    await t.pump();
    expect(presses, 0, reason: 'occupée, la ligne ne doit rien relancer');
  });

  testWidgets('le compte rendu reste affiché sous la ligne',
      (WidgetTester t) async {
    // Une box n'a pas de barre de notification : un SnackBar qui passe en
    // 3 s se rate à 3 mètres. Le résultat doit PERSISTER à l'écran.
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TvUpdateChoiceRow(
          icon: Icons.live_tv_rounded,
          title: 'Les listes de chaînes',
          subtitle: 'Re-télécharger toutes vos sources.',
          report: 'Mise à jour partielle : 2 source(s) sur 3.',
          reportIsError: true,
          onSelect: _noop,
        ),
      ),
    ));
    await t.pump();

    expect(
      find.text('Mise à jour partielle : 2 source(s) sur 3.'),
      findsOneWidget,
    );
  });
}

void _noop() {}
