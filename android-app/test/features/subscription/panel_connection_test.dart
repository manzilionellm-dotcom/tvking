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
    bool paid=false,frozen=false, finalSaved=false;
    int statusReads=0, finalAttempts=0;
    SharedPreferences.setMockInitialValues(<String,Object>{
      'device.virtual_mac.v1':'MK:11:22:33:44:55',
      'zuno.signal.box_after.v1':900, // Ancienne MAC : ne masque pas le nouveau n°1.
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    RepairFlags.realtimeLegacy=true;
    server.listen((request) async {
      request.response.headers.contentType=ContentType.json;
      if(request.uri.path.startsWith('/api/box/wait/')) {
        await click.future;
        if((int.tryParse(request.uri.queryParameters['after'] ?? '') ?? 0)<1) {
          request.response.write('{"box":[{"id":1,"kind":"activate","order_id":"ord_connection123"}],"fleet":[]}');
        } else {
          expect(finalSaved,isTrue,reason:'curseur avancé avant confirmation du serveur');
          request.response.statusCode=404;request.response.write('{}');
        }
      } else if(request.uri.path.startsWith('/api/box/ack/')) {
        final Map<String,dynamic> body=jsonDecode(await utf8.decoder.bind(request).join()) as Map<String,dynamic>;
        final List<dynamic> orders=body['orders'] is List ? body['orders'] as List<dynamic> : <Object>[];
        final results=<Map<String,Object?>>[];
        for(final order in orders) {
          final bool finalAck=order['state']=='applied';
          final bool refused=finalAck && ++finalAttempts==1;
          if(finalAck && !refused)finalSaved=true;
          results.add(<String,Object?>{'order_id':order['order_id'],'status':refused?500:200,
            'state':refused?'received':order['state'],'error':refused?'temporary':null});
        }
        request.response.write(jsonEncode(<String,Object>{'ok':true,'results':results}));
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
      await _until(()=>finalSaved);
      expect(finalAttempts,2);
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
