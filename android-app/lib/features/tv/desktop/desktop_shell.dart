// Fenêtre Windows : taille mémorisée, commandes natives et raccourcis PC.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/blackbox/black_box.dart';
import '../../subscription/data/remote_activation_watch.dart';
import '../../voice/presentation/voice_navigation.dart';
import '../core/tv_tokens.dart';

abstract final class DesktopWindow {
  static final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);
  static bool _changing = false;
  static const Size minimumSize = Size(960, 640);

  static Future<void> prepare() async {
    await windowManager.ensureInitialized();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Pas de position sauvegardée : un écran débranché ne doit jamais
    // rendre la fenêtre inaccessible. Windows la recentre au démarrage.
    final double width = (prefs.getDouble('desktop.width') ?? 1280).clamp(
      960,
      1920,
    );
    final double height = (prefs.getDouble('desktop.height') ?? 800).clamp(
      640,
      1080,
    );
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'Zuno',
        size: Size(width, height),
        minimumSize: minimumSize,
        center: true,
        backgroundColor: TvTokens.bg,
      ),
      () async {
        await windowManager.setPreventClose(true);
        if (prefs.getBool('desktop.maximized') ?? false)
          await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  static Future<void> toggleFullscreen() async {
    if (_changing) return;
    _changing = true;
    try {
      final bool next = !await windowManager.isFullScreen();
      await windowManager.setFullScreen(next);
      fullscreen.value = next;
    } catch (e) {
      BlackBox.instance.warn('PC', 'plein écran indisponible');
    } finally {
      _changing = false;
    }
  }

  static Future<void> save() async {
    try {
      if (await windowManager.isFullScreen() ||
          await windowManager.isMinimized())
        return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool maximized = await windowManager.isMaximized();
      await prefs.setBool('desktop.maximized', maximized);
      if (!maximized) {
        final Size size = await windowManager.getSize();
        await prefs.setDouble('desktop.width', size.width);
        await prefs.setDouble('desktop.height', size.height);
      }
    } catch (_) {
      BlackBox.instance.warn('PC', 'taille non mémorisée');
    }
  }
}

/// Les raccourcis système sont traités avant ceux des écrans TV : Alt+Entrée
/// ne doit pas activer par accident la chaîne qui possède le focus.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with WindowListener {
  Timer? _saveTimer;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_key);
  }

  bool _key(KeyEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final LogicalKeyboardKey key = event.logicalKey;
    final bool full =
        key == LogicalKeyboardKey.f11 ||
        (key == LogicalKeyboardKey.enter && keyboard.isAltPressed);
    final bool search =
        key == LogicalKeyboardKey.keyF && keyboard.isControlPressed;
    if (full || search) {
      if (event is KeyDownEvent) {
        if (search) {
          VoiceNavigation.openSearch();
        } else {
          unawaited(DesktopWindow.toggleFullscreen());
        }
      }
      return true;
    }
    return false;
  }

  // Réveil Windows / retour à l'app : pas d'attente du délai de repli réseau.
  @override
  void onWindowFocus() => RemoteActivationWatch.instance.reconnect();
  @override
  void onWindowEnterFullScreen() => DesktopWindow.fullscreen.value = true;
  @override
  void onWindowLeaveFullScreen() => DesktopWindow.fullscreen.value = false;
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(DesktopWindow.save()),
    );
  }

  @override
  void onWindowResize() => _scheduleSave();
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();
  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    unawaited(() async {
      await DesktopWindow.save();
      RemoteActivationWatch.instance.stop();
      await windowManager.destroy();
    }());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_key);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.escape): _DesktopBackIntent(),
      SingleActivator(LogicalKeyboardKey.browserBack): _DesktopBackIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _DesktopBackIntent: CallbackAction<_DesktopBackIntent>(
          onInvoke: (_) {
            unawaited(VoiceNavigation.navigatorKey.currentState?.maybePop());
            return null;
          },
        ),
      },
      child: widget.child,
    ),
  );
}

class _DesktopBackIntent extends Intent {
  const _DesktopBackIntent();
}

/// Barre PC à l'intérieur du MaterialApp : les boutons ont un Navigator
/// réel et les infobulles suivent la langue du client. Masquée en plein écran.
class DesktopToolbar extends StatelessWidget {
  const DesktopToolbar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations strings = MaterialLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindow.fullscreen,
      builder: (context, full, _) => Column(
        children: <Widget>[
          if (!full)
            Material(
              color: TvTokens.panel,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: strings.backButtonTooltip,
                      onPressed: () =>
                          VoiceNavigation.navigatorKey.currentState?.maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Zuno',
                      style: TvTokens.ui(16, weight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '${strings.searchFieldLabel} · Ctrl+F',
                      onPressed: () => VoiceNavigation.openSearch(),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: 'F11 / Alt+Enter',
                      onPressed: () =>
                          unawaited(DesktopWindow.toggleFullscreen()),
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
