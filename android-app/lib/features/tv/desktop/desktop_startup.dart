import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../core/tv_tokens.dart';

/// Écran transitoire dans la palette EXISTANTE. Une erreur ne peut plus être
/// avalée avant runApp en laissant simplement le fond noir du runner.
class DesktopStartupScreen extends StatelessWidget {
  const DesktopStartupScreen({super.key, required this.failed});
  final ValueListenable<bool> failed;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: TvTokens.bg,
          body: Center(
              child: ValueListenableBuilder<bool>(
            valueListenable: failed,
            builder: (BuildContext context, bool error, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('ZUNO', style: TextStyle(color: TvTokens.text)),
                if (error)
                  const Text('Démarrage impossible. Fermez puis relancez ZUNO.',
                      style: TextStyle(color: TvTokens.muted))
                else
                  const CircularProgressIndicator(color: TvTokens.accent),
              ],
            ),
          )),
        ),
      );
}

/// Le smoke test utilise le vrai bootstrap mais ne peut ni contacter ni
/// enregistrer un appareil sur le panel. Aucun secret/service factice requis.
class DesktopSmokeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) =>
            Future<ConnectionTask<Socket>>.error(const SocketException(
                'Network disabled for Windows CI smoke test'));
}
