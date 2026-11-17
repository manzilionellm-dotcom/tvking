import 'dart:async';
import 'dart:io';

import '../domain/source_import_problem.dart';
import 'playlist_import_limits.dart';
import 'xtream_client.dart';

/// Code stable et sans identifiants, même avec un APK obfusqué.
String sourceFailureCode(Object error) {
  if (error is PlaylistImportTooLarge) return 'local_too_big';
  if (error is SourceImportProblem) return error.name;
  if (error is TimeoutException) return SourceImportProblem.timeout.name;
  if (error is XtreamAuthException) return SourceImportProblem.denied.name;
  if (error is SocketException || error is HandshakeException) {
    return SourceImportProblem.network.name;
  }
  return 'connect_failed';
}
