import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Revalide aussi le cache : la taille seule ne prouve pas son intégrité.
/// Lecture en flux pour garder une consommation mémoire bornée sur les box.
Future<bool> updateFileMatches(
  File file, {
  required int sizeBytes,
  required String sha256,
}) async {
  try {
    if (sizeBytes <= 0 ||
        !await file.exists() ||
        await file.length() != sizeBytes) {
      return false;
    }
    final HashSink hasher = Sha256().newHashSink();
    await for (final List<int> chunk in file.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    final Hash hash = await hasher.hash();
    return hash.bytes
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join() ==
        sha256;
  } catch (_) {
    return false;
  }
}
