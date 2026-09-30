// =========================================================
//  phone_remote_session.dart — Mini-serveur sur le Wi-Fi
// =========================================================
//  Démarre seulement quand on ouvre l'écran « Téléphone »,
//  et seulement si l'interrupteur est allumé. Il reste en
//  vie quand on revient au direct, pour que les touches
//  agissent. On l'arrête depuis cet écran, ou en coupant
//  l'interrupteur.
//
//  Si le port ne s'ouvre pas, ou s'il n'y a pas d'adresse
//  locale : on le dit, et on ne touche pas au lecteur.
//
//  Le jeton change à chaque démarrage. Il n'est pas écrit
//  dans le code : un voisin qui devine l'adresse sans le
//  jeton reçoit une page vide.
// =========================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../box_extras/box_flag.dart';
import '../domain/remote_command.dart';
import '../domain/remote_page.dart';
import 'phone_remote_bus.dart';

class PhoneRemoteSession {
  PhoneRemoteSession._();
  static final PhoneRemoteSession instance = PhoneRemoteSession._();

  static final BoxFlag flag = BoxFlag('zuno.flag.phone_remote');

  HttpServer? _server;
  String? _token;
  String? url;
  String? error;

  bool get running => _server != null;

  Future<void> ensureStarted() async {
    await flag.load();
    if (!flag.value) {
      await stop();
      error = 'off';
      return;
    }
    if (_server != null && url != null) {
      error = null;
      return;
    }
    try {
      _token = _newToken();
      final HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      final List<String> ips = await _lanIps();
      if (ips.isEmpty) {
        await stop();
        error = 'no-ip';
        return;
      }
      url = 'http://${ips.first}:${server.port}/?t=$_token';
      error = null;
      server.listen((HttpRequest req) {
        unawaited(_handle(req));
      }, onError: (Object _) {});
    } catch (_) {
      await stop();
      error = 'bind';
    }
  }

  Future<void> stop() async {
    final HttpServer? server = _server;
    _server = null;
    url = null;
    _token = null;
    if (server == null) return;
    try {
      await server.close(force: true);
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final String? token = req.uri.queryParameters['t'];
      if (token == null || token.isEmpty || token != _token) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && (req.uri.path == '/' || req.uri.path.isEmpty)) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(remoteControlPage(token));
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/cmd') {
        final RemoteCommand? command =
            RemoteCommands.parse(req.uri.queryParameters['c']);
        if (command == null) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
          return;
        }
        PhoneRemoteBus.instance.add(command);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}

String _newToken() {
  final Random random = Random.secure();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 9; i++) {
    out.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Adresses IPv4 du réseau local, privées d'abord.
/// 127.0.0.1 est ignorée : le téléphone n'est pas dans la box.
Future<List<String>> _lanIps() async {
  final List<String> privateOnes = <String>[];
  final List<String> others = <String>[];
  try {
    final List<NetworkInterface> ifs =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final NetworkInterface iface in ifs) {
      for (final InternetAddress addr in iface.addresses) {
        if (addr.isLoopback) continue;
        final String ip = addr.address;
        if (_isPrivate(ip)) {
          privateOnes.add(ip);
        } else {
          others.add(ip);
        }
      }
    }
  } catch (_) {}
  return <String>[...privateOnes, ...others];
}

bool _isPrivate(String ip) {
  if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
  final RegExp box = RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.');
  return box.hasMatch(ip);
}
