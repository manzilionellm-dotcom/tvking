// Éprouve le contrat de lecture et d'accusé ZUNO avec ses vrais composants.
// HTTP boucle locale et SQLite fichier. Le répartiteur d'ordres et le rendu
// physique restent des mesures séparées. Aucun appareil client n'est utilisé.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/subscription/data/order_ack_client.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/domain/order_ack.dart';

class _LoopbackHttp extends HttpOverrides {}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('révisions du panel et accusé après écriture sur une base persistante', () async {
    final base = Uri.parse(kSubscriptionBaseUrl);
    expect(base.host,'127.0.0.1');
    HttpOverrides.global = _LoopbackHttp();
    const mac = 'MK:00:00:00:00:01'; // Identité synthétique du test.
    SharedPreferences.setMockInitialValues({'device.virtual_mac.v1':mac});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('zuno-panel-local-');
    PlaylistDatabase.debugFilePath = '${temp.path}/essai.db';
    final store = PlaylistDatabase.instance;
    final repo = PlaylistRepository.instance;
    PlaylistRepository.mergeAllPlaylists = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4,base.port);
    final timeline = <Map<String,Object?>>[];
    final ledgers = <int,int>{};
    var rev = 0;
    var count = 0;
    var disconnect = false;
    final timer = Stopwatch()..start();
    void log(String event,[Map<String,Object?> fields = const {}]) =>
        timeline.add({'event':event,'rev':rev,'ms':timer.elapsedMilliseconds,...fields});
    Future<int> rows() async {
      final db = await store.database;
      return (await db.rawQuery('SELECT COUNT(*) AS n FROM channels')).single['n'] as int;
    }
    server.listen((r) async {
      if(r.uri.path.startsWith('/api/device-source/')) {
        log('configuration');
        r.response.write(jsonEncode({'rev':rev,'sources':[{'type':'m3u','label':'Mire $rev','m3u_url':'$base/media-$rev'}]}));
      } else if(r.uri.path.startsWith('/media-')) {
        if(count==0){r.response.statusCode=404;}else{
          final m=StringBuffer('#EXTM3U\n');
          for(int i=0;i<count;i++){
            m.writeln('#EXTINF:-1 tvg-id="s$i" group-title="Groupe ${i%4}",Mire $i');
            m.writeln('$base/flux/$i.ts');
          }
          r.response.write(m);
        }
      } else if(r.uri.path.startsWith('/api/box/ack/')){
        final body=jsonDecode(await utf8.decoder.bind(r).join());
        final item=body['orders'].single;
        final written=await rows();
        log('ack',{'state':item['state'],'config_rev':item['config_rev'],'result':item['result'],'rows':written});
        if(disconnect){
          disconnect=false;
          r.response.statusCode=503;
        }else{
          ledgers[rev]=(ledgers[rev]??0)+1;
          r.response.write('{"ok":true}');
        }
      }else{r.response.write('{}');}
      await r.response.close();
    });
    try {
      await repo.initialize();
      for(final step in [(101,5000),(102,20000),(102,20000),(103,0)]){
        rev=step.$1;count=step.$2;
        final started=DateTime.now().millisecondsSinceEpoch;
        final previous=await rows();
        await RemoteSourceRepository.sync();
        final report=RemoteSourceRepository.lastReport!;
        final n=await rows();
        final outcome=orderOutcome(kind:'source',receivedAtMs:started,statusRead:true,sideEffectOk:true,report:report);
        expect(report.configRev,rev);
        expect(outcome.applied,count>0);
        expect(n,count>0 ? count:previous);
        log('apres_import',{'rows':n,'loaded':report.result,'in_memory':repo.currentChannels.length,'kept_previous':report.keptPrevious});
        expect(repo.currentChannels.length,n);
        if(rev==101)disconnect=true;
        expect(await OrderAckClient.send(mac,[ackPayload(orderId:'ord_zunolab$rev',state:outcome.state,traceId:'',appVersion:'119',outcome:outcome)],delays:[const Duration(milliseconds:20)]),isTrue);
      }
      expect(ledgers,{101:1,102:2,103:1});
      await store.closeForTesting();
      expect(await rows(),20000);
      log('reouverture_sqlite',{'rows':await rows()});
    } finally {
      final path=Platform.environment['ZUNO_PANEL_RESULT'];
      if(path!=null) await File(path).writeAsString(jsonEncode(timeline));
      await server.close(force:true);
      await store.closeForTesting();
      PlaylistDatabase.debugFilePath=null;
      await temp.delete(recursive:true);
    }
  }, timeout:const Timeout(Duration(minutes:5)));
}
