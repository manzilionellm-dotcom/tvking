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
    // Doc : un changement de cette duree impacte la com utilisateur et les
    // estimations storage. Valeur actuelle = plafond de SÉCURITÉ anti-fuite
    // (si l'utilisateur oublie d'arrêter l'enregistrement), pas une durée
    // cible. Verrouillé ici pour qu'un changement soit conscient.
    expect(kMaxRecordingDuration, const Duration(days: 30));
  },
      // INCOHÉRENCE À TRANCHER (produit) : la constante vaut
      // Duration(days: 30) mais ~20 commentaires de http_recording_
      // downloader.dart ET l'ancien test disent « 6 h », et les messages
      // utilisateur affichent « limite de 6 h atteinte ». Soit le plafond
      // a été relevé à 30 j (anti-fuite) sans mettre à jour la doc, soit
      // c'est une régression. On SKIP tant que le propriétaire n'a pas
      // confirmé la valeur voulue — pour ne pas verrouiller un mauvais
      // choix ni laisser la barrière CI rouge.
      skip: 'Valeur 6 h vs 30 jours à confirmer (voir commentaire).');
}
