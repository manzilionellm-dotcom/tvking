import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../network/api_config.dart';
import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/subscription_backend.dart';
import '../../features/subscription/data/subscription_state.dart';
import '../../features/playlists/data/playlist_repository.dart';
import '../../features/playlists/data/remote_source_repository.dart';
import '../../features/playlists/data/default_servers.dart';
import '../../features/simple_home/data/announcement_repository.dart';
import '../../features/simple_home/data/home_layout_repository.dart';
import '../../features/country_home/data/featured_repository.dart';
import '../../features/theme/data/remote_theme_repository.dart';
import '../../features/ads/data/startup_ad_repository.dart';
import '../../features/about/data/force_update_checker.dart';
import '../../features/pricing/data/pricing_repository.dart';
import '../../core/app/boot_guard.dart';
import 'device_session.dart';
import 'realtime_service.dart';

class _IoSocket implements RealtimeSocket {
  _IoSocket(this.socket);
  final WebSocket socket;
  @override
  Stream<Object?> get messages => socket;
  @override
  void send(String message) => socket.add(message);
  @override
  Future<void> close() async {
    await socket.close();
  }
}

/// Owns the only connection for both mobile and TV entrypoints.
class PanelRealtime with WidgetsBindingObserver {
  PanelRealtime._();
  static final PanelRealtime instance = PanelRealtime._();
  RealtimeService? _service;
  bool _starting = false;
  Future<void> start() async {
    if (_service != null || _starting) return;
    _starting = true;
    try {
      await PlaylistRepository.instance.initialize();
      await SubscriptionState.instance.initialize();
      final String mac = await DeviceIdentity.instance.mac;
      _service = RealtimeService(
          mac: mac,
          connect: () async {
            // Refreshes/reissues the license-bound token through the existing
            // status flow. No admin credential is ever embedded in the app.
            await SubscriptionBackend.getStatus(mac);
            final String? token = await DeviceSession.token();
            if (token == null) throw StateError('device_session_unavailable');
            final http.Response response = await http.post(
                Uri.parse('$kApiBaseUrl/api/device-rt/ticket'),
                headers: <String, String>{
                  ...kNoCacheHeaders,
                  'Authorization': 'Bearer $token'
                }).timeout(const Duration(seconds: 8));
            if (response.statusCode != 200) {
              throw StateError('device_ticket_unavailable');
            }
            final Object? body = jsonDecode(response.body);
            final Object? ticket = body is Map ? body['ticket'] : null;
            if (ticket is! String ||
                !RegExp(r'^[a-f0-9-]{36}$').hasMatch(ticket)) {
              throw StateError('invalid_ticket');
            }
            final Uri ws = Uri.parse(kApiBaseUrl).replace(
                scheme: Uri.parse(kApiBaseUrl).scheme == 'https' ? 'wss' : 'ws',
                path: '/api/device-rt/ws',
                queryParameters: <String, String>{'ticket': ticket});
            return _IoSocket(await WebSocket.connect(ws.toString()));
          },
          refreshers: <String, Refresh>{
            'status': SubscriptionState.instance.refreshRemote,
            'sources': () async {
              if (!BootGuard.instance.safeMode) {
                await RemoteSourceRepository.sync();
              }
            },
            'announcements': () async {
              await AnnouncementRepository.fetchLatest();
            },
            'theme': RemoteThemeRepository.fetchAndApply,
            'home': HomeLayoutRepository.instance.refresh,
            'featured': FeaturedRepository.instance.refresh,
            'ad': () async {
              await StartupAdRepository.instance.fetch();
            },
            'version': ForceUpdateChecker.instance.refresh,
            'servers': () async {
              await DefaultServersApi.fetch(forceRefresh: true);
            },
            'pricing': () async {
              await PricingRepository.fetch();
            },
          });
      WidgetsBinding.instance.addObserver(this);
      _service!.start();
    } finally {
      _starting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service?.resume();
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    final RealtimeService? service = _service;
    _service = null;
    await service?.dispose();
  }
}
