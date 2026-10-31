import 'package:flutter/material.dart';

/// Le panneau garde des textes lisibles à distance. Avant, le FittedBox
/// comprimait TOUTE la hauteur des formulaires et de l'essai dans l'écran :
/// ajouter un message rendait jusqu'au code MAC plus petit. Ici, les colonnes
/// ont une hauteur stable et défilent au focus si leur contenu est plus long.
class TvActivationFrame extends StatelessWidget {
  const TvActivationFrame({super.key, required this.activation, required this.help});

  final Widget activation;
  final Widget help;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Une tablette tenue debout reste utilisable au toucher.
      if (constraints.maxWidth < constraints.maxHeight) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: <Widget>[
            activation,
            const SizedBox(height: 24),
            FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: 612, child: help)),
          ]),
        );
      }
      return Center(child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 1200,
          height: 640,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: 552, child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: activation,
              )),
              const SizedBox(width: 36),
              SizedBox(width: 612, child: Center(child: SingleChildScrollView(
                primary: false,
                child: help,
              ))),
            ],
          ),
        ),
      ));
    },
  );
}
