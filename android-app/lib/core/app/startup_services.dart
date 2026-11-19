import 'dart:async';

import 'package:flutter/widgets.dart';

import '../crash/crash_reporting.dart';
import '../crash/crash_reporting_firebase.dart';
import 'startup_trace.dart';

/// Le collecteur local précède toujours l'UI. Le backend Firebase reste
/// facultatif : même une initialisation qui ne répond jamais ne doit empêcher
/// ni le bootstrap, ni la première image. Les gestionnaires globaux d'erreurs
/// restent installés par runGuarded avant cet appel.
///
/// Les deux paramètres optionnels rendent ce contrat testable sans Firebase :
/// en production, le signal vient du moteur après sa première rasterisation
/// (pas seulement d'un callback de fin de build) et l'attachement est inchangé.
Future<void> startWithLocalCrashReporting(
  Future<void> Function() body, {
  Future<void>? firstFrameRasterized,
  Future<bool> Function()? attachRemoteCrashReporting,
}) async {
  await StartupTrace.step('crashReporting', CrashReporting.instance.initialize);

  StartupTrace.mark('crashlytics.deferred');
  unawaited(_attachAfterFirstFrame(
    firstFrameRasterized ?? WidgetsBinding.instance.waitUntilFirstFrameRasterized,
    attachRemoteCrashReporting ?? attachCrashlytics,
  ));

  // Ce Future se termine avec le bootstrap, indépendamment du backend distant.
  await StartupTrace.step('bootstrap', body);
}

Future<void> _attachAfterFirstFrame(
  Future<void> firstFrameRasterized,
  Future<bool> Function() attach,
) async {
  try {
    await firstFrameRasterized;
    StartupTrace.mark('crashlytics.afterFirstFrame');
    await StartupTrace.step('crashlytics', attach);
  } catch (error, stack) {
    // Une erreur tardive de cette tâche détachée reste dans le journal local,
    // sans devenir une exception async non traitée ou interrompre l'interface.
    CrashReporting.instance.recordError(
      error,
      stack,
      context: 'Crashlytics différé',
    );
  }
}
