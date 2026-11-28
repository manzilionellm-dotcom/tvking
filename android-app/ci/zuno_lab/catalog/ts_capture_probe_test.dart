// Capture d'un programme TS HD entier sur l'API de relais. Le fournisseur de
// mire envoie le fichier aussi vite que le réseau local peut l'accepter. La
// durée décodable est indépendante du temps de transfert.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  final input = Platform.environment['ZUNO_TS_FIXTURE'];
  final folder = Platform.environment['ZUNO_TS_RESULT_DIR'];
  test('une session MPEG-TS HD alimente le lecteur et le fichier', () async {
    final expected = File(input!).lengthSync();
    final outDir=Directory(folder!)..createSync(recursive:true);
    final rec=File('${outDir.path}/enregistrement.ts');
    final playerFile=File('${outDir.path}/lecteur.ts');
    final client=HttpClient();
    final reqSeen=Completer<void>();
    final start=Completer<void>();
    final sent=Completer<void>();
    final done=Completer<void>();
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    final relay=LocalStreamRelay.instance;
    final real='http://127.0.0.1:${server.port}/programme.ts';
    var requests=0;
    final clock=Stopwatch()..start();
    server.listen((r) async {
      requests++;
      if(!reqSeen.isCompleted) reqSeen.complete();
      await start.future;
      try {
        await r.response.addStream(File(input).openRead());
        await r.response.flush();
        if(!sent.isCompleted) sent.complete();
        await done.future;
        await r.response.close();
      } on IOException { /* Le lecteur peut fermer après le dernier octet. */ }
    });
    try {
      final local=await relay.playUrlFor(real);
      final req=await client.getUrl(Uri.parse(local));
      var seen=0;
      final playback=req.close().then<void>((res) async {
        final file=playerFile.openWrite();
        try {
          await for(final block in res) {
            file.add(block);
            seen+=block.length;
            if(seen>=expected) break;
          }
        } finally {await file.close();}
      });
      await reqSeen.future.timeout(const Duration(seconds:10));
      expect(await relay.startRecording(realUrl:real,filePath:rec.path),isTrue);
      start.complete();
      await sent.future.timeout(const Duration(minutes:2));
      await playback.timeout(const Duration(minutes:2));
      final bytes=await relay.stopRecording(real);
      if(!done.isCompleted)done.complete();
      expect(bytes,expected); expect(seen,expected); expect(requests,1);
      await File('${outDir.path}/capture.json').writeAsString(jsonEncode({'source_requests':requests,'source_bytes':expected,'file_bytes':rec.lengthSync(),'player_bytes':playerFile.lengthSync(),'transfer_ms':clock.elapsedMilliseconds,'protocol':'HTTP MPEG-TS local, transfert sans limitation de débit'}));
    } finally {
      if(!start.isCompleted)start.complete();
      if(!done.isCompleted)done.complete();
      client.close(force:true);
      await relay.stopRecording(real);
      await server.close(force:true);
    }
  }, skip:input==null || folder==null, timeout:const Timeout(Duration(minutes:4)));
}
