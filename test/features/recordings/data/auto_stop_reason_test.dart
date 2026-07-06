// =========================================================
//  auto_stop_reason_test.dart — Stabilite de l'enum
// =========================================================
//  Phase 1 / F-03 — `AutoStopReason.name` est ECRIT en base SQLite
//  (colonne `auto_stop_reason`), donc renommer un des valeurs casse
//  les fiches existantes a la lecture.
//
//  Ces tests verrouillent les noms canoniques. Si un futur dev
//  renomme `serverUnreachable` en `serverDead`, ces tests sautent
//  et le rappellent qu'il faut prevoir une migration SQL.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/recordings/data/http_recording_downloader.dart';

void main() {
  group('AutoStopReason persistance', () {
    test('noms canoniques (utilises comme cle DB)', () {
      // Si l'un de ces asserts casse, les fiches deja en base ne
      // pourront plus etre relues correctement. Prevoir une
      // migration SQL avant tout rename.
      expect(AutoStopReason.maxDurationReached.name, 'maxDurationReached');
      expect(AutoStopReason.serverUnreachable.name, 'serverUnreachable');
      expect(AutoStopReason.diskError.name, 'diskError');
    });

    test('couvre exactement les 3 causes documentees', () {
      // Si on ajoute une 4e cause, prevoir aussi le mapping UX dans
      // `video_player_screen.dart _autoStopMessage(...)`.
      expect(AutoStopReason.values.length, 3);
      expect(
        AutoStopReason.values.map((AutoStopReason r) => r.name).toSet(),
        <String>{
          'maxDurationReached',
          'serverUnreachable',
          'diskError',
        },
      );
    });
  });

  test('kMaxRecordingDuration = 30 jours (plafond anti-fuite)', () {
    // CONFIRMÉ (2026-06-29) : la demande produit est « enregistrements
    // ILLIMITÉS » ; 30 jours est un garde-fou anti-fuite (si l'utilisateur
    // oublie d'arrêter), PAS une durée cible. Les anciennes mentions « 6 h »
    // étaient un design antérieur et ne subsistaient que dans des debugPrint
    // (jamais affichées à l'utilisateur). Test verrouillé sur la vraie valeur :
    // un changement (ex. cap storage-aware) doit être conscient.
    expect(kMaxRecordingDuration, const Duration(days: 30));
  });
}
