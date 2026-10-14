import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/desktop/desktop_layout.dart';

void main() {
  test('petite fenêtre : contenu entier, proportions intactes', () {
    final Size design = desktopDesignSize(const Size(960, 640));
    expect(design.width, 1280);
    expect(design.aspectRatio, closeTo(1.5, 0.001));
  });
  test('4K : ne grossit pas les textes et exploite la largeur', () {
    expect(desktopDesignSize(const Size(3840, 2160)), const Size(3840, 2160));
  });
}
