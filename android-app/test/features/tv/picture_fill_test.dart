// =========================================================
//  picture_fill_test.dart — « Remplir l'écran » sur téléphone
// =========================================================
//  L'image n'est jamais déformée : le cadre reste en 16:9.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/picture_fill.dart';

void main() {
  test('image entière : la plus grande image 16:9 qui tient', () {
    // Téléphone 20:9 en paysage : bandes sur les côtés.
    final wide = pictureBox(width: 2000, height: 900, fill: false);
    expect(wide.height, 900);
    expect(wide.width, closeTo(1600, 0.01));
    // Portrait : bandes en haut et en bas.
    final tall = pictureBox(width: 900, height: 2000, fill: false);
    expect(tall.width, 900);
    expect(tall.height, closeTo(506.25, 0.01));
  });

  test('remplir : l\'image couvre la largeur et garde son rapport', () {
    final box = pictureBox(width: 2000, height: 900, fill: true);
    expect(box.width, closeTo(2000, 0.01));
    expect(box.width / box.height, closeTo(16 / 9, 0.0001));
    expect(box.height, greaterThan(900));
  });

  test('écran très allongé : on ne coupe pas plus d\'un quart', () {
    final box = pictureBox(width: 3000, height: 900, fill: true);
    expect(box.width, closeTo(1600 * kMaxFillZoom, 0.01));
    expect(box.width / box.height, closeTo(16 / 9, 0.0001));
  });

  test('écran 16:9 ou portrait : le bouton ne sert à rien', () {
    expect(pictureFillUseful(width: 1920, height: 1080), isFalse);
    expect(pictureFillUseful(width: 900, height: 2000), isFalse);
    expect(pictureFillUseful(width: 2000, height: 900), isTrue);
    expect(pictureFillUseful(width: 0, height: 0), isFalse);
    final same = pictureBox(width: 1920, height: 1080, fill: true);
    expect(same.width, closeTo(1920, 0.01));
    expect(same.height, closeTo(1080, 0.01));
  });
}
