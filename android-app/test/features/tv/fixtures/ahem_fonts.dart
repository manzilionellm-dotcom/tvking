// =========================================================
//  Polices de test déterministes (même méthode que mac_rtl_test.dart).
// =========================================================
//  En production, les polices de l'interface TV (Inter, Oswald,
//  JetBrains Mono) sont des fichiers embarqués lus par google_fonts. Dans un
//  test hors réseau, une police qui arrive PENDANT une image fait échouer
//  l'assertion « debugSize » du moteur de texte. On sert donc la police Ahem
//  du SDK Flutter sous leurs noms : géométrie stable, aucun téléchargement.
// =========================================================
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void installAhemFonts() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final Uint8List bytes =
      File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync();
  final ByteData font = ByteData.sublistView(bytes);
  final Map<String, List<Map<String, String>>> assets =
      <String, List<Map<String, String>>>{
    for (final String family in <String>['Inter', 'Oswald', 'JetBrainsMono'])
      for (final String weight in <String>[
        'Thin',
        'ExtraLight',
        'Light',
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Black',
      ])
        'fonts/$family-$weight.ttf': <Map<String, String>>[
          <String, String>{'asset': 'fonts/$family-$weight.ttf'},
        ],
  };
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final String key = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(assets);
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(jsonEncode(<String, List<String>>{
          for (final String k in assets.keys) k: <String>[k],
        }))),
      );
    }
    if (assets.containsKey(key)) return font;
    return messenger.delegate.send('flutter/assets', message);
  });
}

void removeAhemFonts() => TestDefaultBinaryMessengerBinding
    .instance.defaultBinaryMessenger
    .setMockMessageHandler('flutter/assets', null);
