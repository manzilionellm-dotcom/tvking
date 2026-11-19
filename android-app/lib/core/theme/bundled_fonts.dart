import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

bool _licensesRegistered = false;

/// La TV doit afficher ses textes dès la première ouverture, même sans réseau.
/// À appeler avant toute construction de thème ; les styles existants restent
/// inchangés et google_fonts charge les fichiers exacts inclus dans les assets.
/// Le mobile conserve sa configuration réseau, car seul le bootstrap TV/PC
/// appelle cette fonction. Aucun téléchargement ni préchargement n'est lancé.
void configureTvFontLoading() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// Les assets sont communs aux variantes TV/mobile. On expose donc leurs
/// licences dans le registre commun, sans lire de fichier pendant le boot :
/// ce générateur ne s'exécute que si l'écran des licences est consulté.
void registerBundledFontLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    const families = <String, String>{
      'Inter': 'Inter',
      'Oswald': 'Oswald',
      'JetBrains Mono': 'JetBrainsMono',
      'Bricolage Grotesque': 'BricolageGrotesque',
      'Manrope': 'Manrope',
    };
    for (final family in families.entries) {
      final license = await rootBundle.loadString(
        'assets/fonts/licenses/${family.value}-OFL.txt',
      );
      // Le fichier OFL officiel Manrope conserve sa mention 2018. Les TTF
      // distribués portent aussi cette mention 2019 dans leur table `name`.
      // On affiche les deux sans modifier la licence ou les fontes d'origine.
      final notice = family.key == 'Manrope'
          ? 'Copyright 2019 The Manrope Project Authors '
              '(https://github.com/sharanda/manrope)\n\n'
          : '';
      yield LicenseEntryWithLineBreaks(<String>[family.key], '$notice$license');
    }
  });
}
