// Régression du vrai synchroniseur : après un ordre, son filet HTTP reste
// actif même si le canal temps réel disparaît. Serveur local, aucune prod.
// flutter test --dart-define=RUN_PANEL_CONNECTION=true \
//   --dart-define=BACKEND_URL=http://127.0.0.1:18789 test/features/subscription/panel_connection_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');
class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() condition) async {
  final DateTime deadline=DateTime.now().add(const Duration(seconds:7));
  while(!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds:20));
  }
  expect(condition(),isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('activation reçue puis canal indisponible : le statut continue à descendre',() async {
    final previous=HttpOverrides.current;
    HttpOverrides.global=_RealHttp();
    final HttpServer server=await HttpServer.bind(InternetAddress.loopbackIPv4,18789);
    final Completer<void> click=Completer<void>();
    bool paid=false,frozen=false, sent=false;
    int statusReads=0;
    SharedPreferences.setMockInitialValues(<String,Object>{
      'device.virtual_mac.v1':'MK:11:22:33:44:55',
      'zuno.signal.box_after.v1':900, // Ancienne MAC : ne masque pas le nouveau n°1.
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    RepairFlags.realtimeLegacy=true;
    server.listen((request) async {
      request.response.headers.contentType=ContentType.json;
      if(request.uri.path.startsWith('/api/box/wait/')) {
        if(!sent) {
          await click.future; sent=true;
          request.response.write('{"box":[{"id":1,"kind":"activate"}],"fleet":[]}');
        } else {request.response.statusCode=404;request.response.write('{}');}
      } else if(request.uri.path.startsWith('/api/status/') || request.uri.path=='/api/heartbeat') {
        statusReads++;
        request.response.write(jsonEncode(<String,Object>{
          'exists':true,'status':frozen?'frozen':'active','paid':paid,'plan':'lifetime',
          'paid_until':0,'expired':false,'frozen':frozen,'banned':false,'source_rev':0,
          'trial_until':DateTime.now().add(const Duration(days:1)).millisecondsSinceEpoch,
        }));
      } else {request.response.write('{"ok":true}');}
      await request.response.close();
    });
    try {
      await SubscriptionState.instance.initialize();
      RemoteActivationWatch.instance.start(allowSourceImport:false);
      await _until(()=>statusReads>0);
      paid=true;click.complete();
      await _until(()=>SubscriptionState.instance.remote.paid);
      frozen=true; // Aucun second ordre : le filet doit sauver ce changement.
      await _until(()=>SubscriptionState.instance.remote.frozen);
      expect(statusReads,greaterThanOrEqualTo(3));
    } finally {
      if(!click.isCompleted)click.complete();
      RemoteActivationWatch.instance.stopForTesting();
      RepairFlags.realtimeLegacy=false;
      await server.close(force:true);
      HttpOverrides.global=previous;
    }
  },skip:!_run);
}
