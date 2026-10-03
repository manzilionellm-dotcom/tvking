// =========================================================
//  sound_full_report_test.dart — le verdict, sans oreille
// =========================================================
//  On ne prétend pas avoir entendu. On vérifie que les phrases
//  déjà écrites par le lecteur donnent le bon mot, le bon niveau
//  de confiance, et un texte sans doublon ni secret.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/sound_full_report.dart';

void main() {
  setUp(SoundReportExtensions.debugReset);

  test('le plan tient en moins de 30 secondes', () {
    final SoundReportPlan live = SoundReportPlan.forCapture(channelLive: true);
    expect(live.channelListen, const Duration(seconds: 10));
    expect(live.witnessPlay, const Duration(seconds: 10));
    expect(live.total.inSeconds, 20);
    expect(live.withinBudget, isTrue);

    final SoundReportPlan idle = SoundReportPlan.forCapture(channelLive: false);
    expect(idle.channelListen, Duration.zero);
    expect(idle.total.inSeconds, 10);
    expect(idle.withinBudget, isTrue);
  });

  test("chemin d'appel : verdict haute, prioritaire sur la phase", () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_callPath\n$_opposed\n$_lowSpectrum',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, SoundVerdict.callPath);
    expect(r.confidence, SoundConfidence.high);
    expect(r.text, contains("Verdict : chemin d'appel détecté"));
    expect(r.text, contains('Confiance : haute'));
    expect(r.text, contains('Aussi noté : phase inversée'));
    expect(r.text, contains("chemin d'un appel"));
    expect(r.text.contains('source étroite'), isFalse);
  });

  test('une phrase négative ne crée pas un chemin d\'appel', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\nNote : pas de chemin d\'appel ici.\n$_wideSpectrum\n$_together',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.text.contains("chemin d'appel détecté"), isFalse);
  });

  test('Bluetooth dit oui, sans mesure, ne crée pas le verdict', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_wideSpectrum\n$_together',
        witness: _wideWitness,
        answers: const SoundAnswers(bluetooth: SoundYes.oui),
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.text, contains("La box ne montre pas un chemin d'appel"));
  });

  test('Bluetooth non contredit par la box : confiance baissée', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_callPath\n$_together\n$_wideSpectrum',
        witness: _wideWitness,
        answers: const SoundAnswers(bluetooth: SoundYes.non),
      ),
    );
    expect(r.verdict, SoundVerdict.callPath);
    expect(r.confidence, SoundConfidence.mid);
  });

  test('corrélation −0,70 : phase inversée', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\n$_wideSpectrum\nCorrélation gauche/droite (1 s, copie) : -0,70',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, SoundVerdict.invertedPhase);
    expect(r.confidence, SoundConfidence.high);
    expect(r.text, contains('Verdict : phase inversée'));
    expect(r.text, contains("s'opposent"));
  });

  test('corrélation −0,69 : pas une phase inversée', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\n$_wideSpectrum\nCorrélation gauche/droite (1 s, copie) : -0,69',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, isNot(SoundVerdict.invertedPhase));
  });

  test('voies opposées même avec un son large', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_wideSpectrum\n$_opposed',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, SoundVerdict.invertedPhase);
  });

  test('chaîne basse et témoin large : source étroite', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_lowSpectrum\n$_together',
        witness: _wideWitness,
        answers: const SoundAnswers(ear: SoundEar.sourd),
      ),
    );
    expect(r.verdict, SoundVerdict.narrowSource);
    expect(r.confidence, SoundConfidence.high);
    expect(r.text, contains('Verdict : source étroite'));
    expect(r.text, contains('le son étroit vient de la chaîne'));
    expect(r.text, contains('son : sourd'));
  });

  test('oreille « clair » baisse la confiance de la source étroite', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_lowSpectrum\n$_together',
        witness: _wideWitness,
        answers: const SoundAnswers(ear: SoundEar.clair),
      ),
    );
    expect(r.verdict, SoundVerdict.narrowSource);
    expect(r.confidence, SoundConfidence.mid);
  });

  test('les deux étroits : pas la source, confiance basse', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_lowSpectrum\n$_together',
        witness: '$_normalPath\n$_lowSpectrum\n$_together',
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.confidence, SoundConfidence.low);
    expect(r.text, contains('la chaîne et le témoin sont étroits'));
    expect(r.text, contains("Verdict : rien d'anormal côté app"));
  });

  test('son large, chemin normal, voies ensemble : rien côté app', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\n$_wideSpectrum\n$_together\nEffets dans l\'app : voix claire coupée.',
        witness: _wideWitness,
        live: true,
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.confidence, SoundConfidence.high);
    expect(r.text, contains('écoutée 10 secondes'));
    expect(r.text, contains('Chemin : mode normal'));
    expect('Chemin : mode normal'.allMatches(r.text).length, 1);
  });

  test('oreille sourd alors que l\'app est large : confiance baissée', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$_wideSpectrum\n$_together',
        witness: _wideWitness,
        answers: const SoundAnswers(
          ear: SoundEar.sourd,
          otherApp: SoundYes.oui,
        ),
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.confidence, SoundConfidence.low);
    expect(r.text, contains('une autre application'));
    expect(r.text, contains('Vous entendez sourd'));
  });

  test('fiche vide : rien côté app, confiance basse, chaîne pas ouverte', () {
    final SoundFullReport r = SoundFullReport.build(
      const SoundReportFacts(
        channelName: '',
        channelBody: '',
        witnessBody: '',
        answers: SoundAnswers.unanswered,
        channelWasLive: false,
      ),
    );
    expect(r.verdict, SoundVerdict.appClear);
    expect(r.confidence, SoundConfidence.low);
    expect(r.text, contains('pas encore lu'));
    expect(r.text, contains('pas ouverte pendant ce rapport'));
    expect(r.text, contains("n'ont pas été mesurés"));
  });

  test('mono annoncé et témoin large : source étroite', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\n[HAUTE · CAUSE] source_mono\nCause : la piste est mono.',
        witness: _wideWitness,
      ),
    );
    expect(r.verdict, SoundVerdict.narrowSource);
    expect(r.confidence, SoundConfidence.mid);
  });

  test('le texte est dédupliqué, le témoin ne recopie pas la chaîne', () {
    const String twice =
        'Ligne unique AAA\nLigne unique AAA\nSpectre > 4 kHz : présent (70,0 %)';
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel: '$_normalPath\n$twice\n$_together',
        witness: '$_normalPath\nLigne unique AAA\nSeulement témoin\n$_wideTail',
      ),
    );
    expect('Ligne unique AAA'.allMatches(r.text).length, 1);
    expect(r.text, contains('Seulement témoin'));
    expect(r.text, contains('non recopiées'));
  });

  test('url et mot de passe ne sortent pas', () {
    final SoundFullReport r = SoundFullReport.build(
      _facts(
        channel:
            '$_normalPath\nnote password=abc token=zzz '
            'http://alice:s3cret@exemple.test/live/a.ts\n$_wideSpectrum\n$_together',
        witness: _wideWitness,
        name: 'http://user:secret@exemple.test/live',
      ),
    );
    expect(r.text.contains('s3cret'), isFalse);
    expect(r.text.contains('http'), isFalse);
    expect(r.text.contains('password=abc'), isFalse);
    expect(r.text, contains('[url]'));
    expect(r.text, contains('password=[secret]'));
    expect(r.text.contains('user:secret'), isFalse);
  });

  test(
    'les ajouts s\'agrègent une fois, triés, sans bloquer si l\'un casse',
    () {
      SoundReportExtensions.register(
        SoundReportExtension(
          id: 'son-b',
          lines: (SoundReportFacts _) => <String>[
            'Mesure B : 2',
            'Mesure B : 2',
          ],
        ),
      );
      SoundReportExtensions.register(
        SoundReportExtension(
          id: 'son-a',
          lines: (SoundReportFacts _) => <String>['Mesure A : 1'],
        ),
      );
      SoundReportExtensions.register(
        SoundReportExtension(
          id: 'son-casse',
          lines: (SoundReportFacts _) => throw StateError('non'),
        ),
      );
      // Le même id remplace : on ne doit voir que la deuxième phrase.
      SoundReportExtensions.register(
        SoundReportExtension(
          id: 'son-a',
          lines: (SoundReportFacts _) => <String>['Mesure A : remplacée'],
        ),
      );
      final SoundFullReport r = SoundFullReport.build(
        _facts(
          channel: '$_normalPath\n$_wideSpectrum\n$_together',
          witness: _wideWitness,
        ),
      );
      expect(r.text, contains('Ajouts :'));
      expect(r.text, contains('Mesure A : remplacée'));
      expect(r.text.contains('Mesure A : 1'), isFalse);
      expect('Mesure B : 2'.allMatches(r.text).length, 1);
      expect(r.text.indexOf('Mesure A'), lessThan(r.text.indexOf('Mesure B')));
      expect(r.verdict, SoundVerdict.appClear);
    },
  );

  test(
    'un ajout « voies opposées » change le verdict sans éditer la fiche',
    () {
      SoundReportExtensions.register(
        SoundReportExtension(
          id: 'son-phase',
          lines: (SoundReportFacts _) => <String>[
            'Relevé : voies opposées sur 1 s.',
          ],
        ),
      );
      final SoundFullReport r = SoundFullReport.build(
        _facts(
          channel: '$_normalPath\n$_wideSpectrum\n$_together',
          witness: _wideWitness,
        ),
      );
      expect(r.verdict, SoundVerdict.invertedPhase);
      expect(r.confidence, SoundConfidence.mid);
      expect(r.text, contains('voies opposées sur 1 s'));
    },
  );

  test('la capture garde le journal et ne laisse pas une phrase courte effacer la fiche', () {
    final SoundReportCapture c = SoundReportCapture();
    c.seedChannel('Codec : AAC-LC\nConclusion : aucune cause sûre.');
    c.add('Seconde 1 : volume lecteur 1,0', witness: false);
    c.add('Seconde 1 : volume lecteur 1,0', witness: false);
    c.add('Angle libre : 4', witness: false);
    c.add(
      'Codec : AAC-LC\nSpectre > 4 kHz : bas (3,6 %)\nConclusion : x',
      witness: false,
    );
    c.add('Codec : témoin\nConclusion : t', witness: true);
    expect(c.channelBody, contains('Spectre > 4 kHz'));
    expect(c.channelBody, contains('Seconde 1'));
    expect('Seconde 1'.allMatches(c.channelBody).length, 1);
    expect(c.channelBody.contains('aucune cause sûre'), isFalse);
    expect(c.loose, <String>['Angle libre : 4']);
    expect(c.witnessBody, contains('témoin'));
    expect(c.channelBody.contains('témoin'), isFalse);
  });

  test(
    'écouteur d\'appel et Bluetooth appel allumé comptent, le coupé non',
    () {
      final SoundFullReport ear = SoundFullReport.build(
        _facts(
          channel: 'Chemin : mode normal, sortie écouteur d\'appel, Bluetooth appel coupé.',
          witness: _wideWitness,
        ),
      );
      expect(ear.verdict, SoundVerdict.callPath);
      final SoundFullReport music = SoundFullReport.build(
        _facts(
          channel: '$_normalPath\n$_wideSpectrum\n$_together',
          witness: _wideWitness,
        ),
      );
      expect(music.verdict, isNot(SoundVerdict.callPath));
    },
  );

  test('les angles tiennent dans le même texte, sans doubler Chemin', () {
    const String sheet = '''
Chemin : mode normal, haut-parleur d'appel coupé, Bluetooth appel coupé.
Garde mode : coupée. Mode lu « normal ». Aucune écriture.
Attributs : essai coupé, usage média, contenu film.
Chaîne : Zuno (défaut). FFmpeg pour l'AAC.
Effets système (lecture seule, aucun effet créé par l'app) :
Tampon : underruns AudioTrack 0 · rappel Media3 0
Format : 16 bits · piste 48 kHz · mélangeur 48 kHz
Corrélation gauche/droite (1 s, copie) : +0,92
Signalisation : AAC-LC (AOT 2), 48 kHz.
Sources : plein écran 1 (son) · Sons en même temps : 1.
Forme (copie, le son n'est pas modifié) : grave/milieu 1,70, aigu/milieu 0,20, profil large
Écho 18–40 ms (copie) : 4
Chute entre secondes actives : 0,6 dB
''';
    final SoundFullReport r = SoundFullReport.build(
      _facts(channel: sheet, witness: _wideWitness),
    );
    expect(r.text, contains('Angles :'));
    expect(r.text, contains('Garde mode : coupée'));
    expect(r.text, contains('Attributs : essai coupé'));
    expect(r.text, contains('Chemin : déjà dans Système'));
    expect(r.text, contains('Effets système (lecture seule'));
    expect(r.text, contains('Tampon : underruns AudioTrack 0'));
    expect(r.text, contains('Format : 16 bits'));
    expect(r.text, contains('Corrélation gauche/droite (1 s, copie) : +0,92'));
    expect(r.text, contains('Signalisation : AAC-LC'));
    expect(r.text, contains('Sources : plein écran'));
    expect(r.text, contains('Forme (copie, le son n\'est pas modifié)'));
    expect(r.text, contains('Écho 18–40 ms'));
    expect(r.text, contains('Chute entre secondes actives'));
    expect(
      'Chemin : mode normal'.allMatches(r.text).length,
      1,
    );
  });
}

const String _normalPath =
    'Chemin : mode normal, haut-parleur d\'appel coupé, Bluetooth appel coupé, '
    'sortie HDMI, appareils prévus HDMI, flux musique (contenu film).';

const String _callPath =
    'Chemin : mode communication ⚠ chemin d\'appel, haut-parleur d\'appel coupé, '
    'Bluetooth appel allumé, sortie Bluetooth appel, appareils prévus Bluetooth appel, '
    'flux appel (contenu parole).';

const String _lowSpectrum =
    'Spectre > 4 kHz : bas (3,6 %) — compatible passe-bas, cause non tranchée seule';

const String _wideSpectrum =
    'Spectre > 4 kHz : présent (72,0 %) — pas un son radio';

const String _together = 'Corrélation gauche/droite (1 s, copie) : +0,92';

const String _opposed =
    'Corrélation gauche/droite (1 s, copie) : -0,95 → voies opposées (voix centrale annulée)';

const String _wideTail =
    'Spectre > 4 kHz : intermédiaire (22,0 %) — ne tranche pas\n'
    'Dernière seconde > 4 kHz : 75,0 %\n'
    'Corrélation gauche/droite (1 s, copie) : +0,95';

const String _wideWitness = '$_normalPath\n$_wideTail';

SoundReportFacts _facts({
  required String channel,
  required String witness,
  SoundAnswers answers = const SoundAnswers(),
  bool live = false,
  String name = 'France 24',
}) {
  return SoundReportFacts(
    channelName: name,
    channelBody: channel,
    witnessBody: witness,
    answers: answers,
    channelWasLive: live,
  );
}
