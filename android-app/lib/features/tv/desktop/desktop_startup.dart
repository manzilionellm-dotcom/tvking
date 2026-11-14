import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_tokens.dart';

/// Échec de démarrage montré à l'écran (détail technique lisible, sans secret).
class DesktopStartupFailure {
  const DesktopStartupFailure(this.detail);
  final String detail;
}

/// Journal de démarrage PC : %LOCALAPPDATA%\Zuno\logs\startup.log.
/// Noms d'étapes, durées et erreurs ; jamais de MAC, URL de source ni code.
abstract final class DesktopStartupLog {
  static File? _file;

  static String? get path => _file?.path;

  static String? defaultPath() {
    final String? base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) return null;
    return '$base${Platform.pathSeparator}Zuno${Platform.pathSeparator}logs'
        '${Platform.pathSeparator}startup.log';
  }

  /// Ouvre le journal (rotation à 512 Ko). Ne lance jamais.
  static void open({String? path, List<String> header = const <String>[]}) {
    try {
      final String? target = path ?? defaultPath();
      if (target == null) return;
      final File file = File(target);
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > 512 * 1024) {
        final File old = File('${file.path}.1');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
      _file = File(target);
      write('===== ZUNO démarrage ${DateTime.now().toIso8601String()} =====');
      for (final String line in header) {
        write(line);
      }
    } catch (_) {
      _file = null;
    }
  }

  static void write(String line) {
    final File? file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync('${DateTime.now().toIso8601String()} $line\r\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static void error(String context, Object error, StackTrace? stack) {
    final String trace = (stack?.toString() ?? '')
        .split('\n')
        .where((String l) => l.trim().isNotEmpty)
        .take(12)
        .join('\r\n    ');
    write('[ERREUR $context] ${error.runtimeType}: $error'
        '${trace.isEmpty ? '' : '\r\n    $trace'}');
  }
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _RetryIntent extends Intent {
  const _RetryIntent();
}

/// Écran transitoire dans la palette EXISTANTE. En cas d'échec : fenêtre
/// quittée du plein écran par l'appelant, boutons Réessayer / Fermer,
/// Échap = Fermer, détail de l'erreur et chemin du journal.
class DesktopStartupScreen extends StatelessWidget {
  const DesktopStartupScreen({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onClose,
    this.logPath,
  });

  final ValueListenable<DesktopStartupFailure?> failure;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final String? logPath;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
            SingleActivator(LogicalKeyboardKey.f5): _RetryIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _CloseIntent:
                  CallbackAction<_CloseIntent>(onInvoke: (_) => onClose()),
              _RetryIntent:
                  CallbackAction<_RetryIntent>(onInvoke: (_) => onRetry()),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: TvTokens.bg,
                body: Center(
                  child: ValueListenableBuilder<DesktopStartupFailure?>(
                    valueListenable: failure,
                    builder: (BuildContext context,
                            DesktopStartupFailure? error, _) =>
                        error == null
                            ? const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text('ZUNO',
                                      style: TextStyle(color: TvTokens.text)),
                                  SizedBox(height: 16),
                                  CircularProgressIndicator(
                                      color: TvTokens.accent),
                                ],
                              )
                            : _FailurePanel(
                                detail: error.detail,
                                logPath: logPath,
                                onRetry: onRetry,
                                onClose: onClose,
                              ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.detail,
    required this.logPath,
    required this.onRetry,
    required this.onClose,
  });
  final String detail;
  final String? logPath;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('ZUNO — Démarrage impossible',
                  style: TextStyle(color: TvTokens.text, fontSize: 22)),
              const SizedBox(height: 12),
              const Text('Réessayez, ou fermez ZUNO (touche Échap).',
                  style: TextStyle(color: TvTokens.muted)),
              const SizedBox(height: 16),
              SelectableText(detail,
                  key: const Key('startup-error-detail'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TvTokens.muted, fontSize: 13)),
              if (logPath != null) ...<Widget>[
                const SizedBox(height: 8),
                SelectableText('Journal : $logPath',
                    style:
                        const TextStyle(color: TvTokens.muted, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FilledButton(
                    key: const Key('startup-retry'),
                    autofocus: true,
                    style: FilledButton.styleFrom(
                        backgroundColor: TvTokens.accent),
                    onPressed: onRetry,
                    child: const Text('Réessayer',
                        style: TextStyle(color: TvTokens.onAccent)),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    key: const Key('startup-close'),
                    onPressed: onClose,
                    child: const Text('Fermer',
                        style: TextStyle(color: TvTokens.text)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// Le smoke hors réseau utilise le vrai bootstrap mais ne peut ni contacter
/// ni enregistrer un appareil sur le panel. Aucun secret/service factice requis.
class DesktopSmokeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) =>
            Future<ConnectionTask<Socket>>.error(const SocketException(
                'Network disabled for Windows CI smoke test'));
}
