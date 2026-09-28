// =========================================================
//  cinema_track_labels_test.dart — Noms des pistes audio / sous-titres
// =========================================================
//  Le menu « Audio et sous-titres » du lecteur doit afficher le nom de la
//  langue dans sa propre langue (« Čeština », pas « CS ») et savoir
//  distinguer deux variantes régionales (« es-419 » ≠ « es-ES »).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/domain/cinema_language.dart';

void main() {
  test('langues des pistes : nom natif, codes courts et ISO 639-2', () {
    expect(CinemaLanguage.labelFor('cs'), 'Čeština');
    expect(CinemaLanguage.labelFor('cze'), 'Čeština');
    expect(CinemaLanguage.labelFor('hun'), 'Magyar');
    expect(CinemaLanguage.labelFor('es-419'), 'Español');
    // Inconnu : le code en majuscules plutôt que rien.
    expect(CinemaLanguage.labelFor('xx'), 'XX');
  });

  test('région : distingue les variantes d\'une même langue', () {
    expect(CinemaLanguage.regionLabel('es-419'), 'Latinoamérica');
    expect(CinemaLanguage.regionLabel('es-ES'), 'España');
    expect(CinemaLanguage.regionLabel('pt_BR'), 'Brasil');
    expect(CinemaLanguage.regionLabel('zh-Hant'), '繁體');
    expect(CinemaLanguage.regionLabel('es'), isNull);
    expect(CinemaLanguage.regionLabel(null), isNull);
  });
}
