import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/blackbox/black_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('les anciens réglages de journal brut respectent la confidentialité NovaTube', () async {
    SharedPreferences.setMockInitialValues({RepairFlags.blackBoxRawKey: true});
    await RepairFlags.load();
    final marker = List.generate(18, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    final original = debugPrint;
    var leaked = 0;
    final url = Uri.http('localhost','/test',{'username':marker,'password':marker});
    try {
      debugPrint = (String? line,{int? wrapWidth}) { if (line?.contains(marker) == true) leaked++; };
      BlackBox.instance.info('SOURCE','Test du filtre $url');
    } finally {
      debugPrint = original;
      RepairFlags.debugReset();
    }
    debugPrint('JOURNAL_BRUT lignes_avec_marqueur=$leaked');
    expect(leaked,kNovatubeTv ? 0 : 1);
  });
}
