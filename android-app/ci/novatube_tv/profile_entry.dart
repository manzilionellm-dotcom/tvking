// Entrée CI du profil dans le checkout jetable. Le certificat n’existe que
// pendant ce run et ne va dans aucun APK distribué.
import 'dart:convert';
import 'dart:io';

import 'package:tv_king/main_tv.dart' as tv;

void main() {
  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    base64Decode(const String.fromEnvironment('NOVATUBE_CI_ROOT_PEM')),
  );
  tv.main();
}
