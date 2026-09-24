// =========================================================
//  xtream_login_sheet.dart — Connexion Xtream (bottom sheet)
// =========================================================
//  Coquille (chrome de feuille) autour de [XtreamLoginForm]. Toute la
//  logique de connexion vit désormais dans le formulaire réutilisable
//  `widgets/xtream_login_form.dart`, partagé avec l'écran d'accueil
//  vide. Ici on ne fait que présenter ce formulaire dans une feuille
//  glissante, gérer l'inset clavier et fermer la feuille au succès.
//
//  Conforme AGENTS.md règle n°2 : aucune URL de flux en dur (les
//  serveurs viennent du Worker). Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'widgets/xtream_login_form.dart';

Future<void> showXtreamLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _XtreamLoginSheet(),
  );
}

class _XtreamLoginSheet extends StatelessWidget {
  const _XtreamLoginSheet();

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tout le formulaire (serveur + identifiant + mot de
                // passe). `onConnected` ferme la feuille au succès.
                XtreamLoginForm(
                  showCancel: true,
                  onConnected: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
