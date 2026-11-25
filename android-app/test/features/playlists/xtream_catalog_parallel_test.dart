// Le catalogue live commence sans attendre les catégories. Deux réponses
// contrôlées remplacent le réseau : la preuve porte sur l'ordre des requêtes,
// sans seuil de performance fragile ni fournisseur réel.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_import_limits.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

const String _categories =
    '[{"category_id":"7","category_name":"Sport"}]';
const String _channels =
    '[{"stream_id":42,"name":"Test","category_id":"7",'
    '"epg_channel_id":"guide-test"}]';

http.StreamedResponse _response(String body) => http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)), 200,
    );

class _CatalogServer extends http.BaseClient {
  final Completer<http.StreamedResponse> categories =
      Completer<http.StreamedResponse>();
  final Completer<http.StreamedResponse> channels =
      Completer<http.StreamedResponse>();
  final Completer<void> bothStarted = Completer<void>();
  final List<String> actions = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final String action = request.url.queryParameters['action']!;
    actions.add(action);
    if (actions.length == 2 && !bothStarted.isCompleted) bothStarted.complete();
    return switch (action) {
      'get_live_categories' => categories.future,
      'get_live_streams' => channels.future,
      _ => throw StateError('Appel imprévu : $action'),
    };
  }

  void finish() {
    if (!categories.isCompleted) categories.complete(_response(_categories));
    if (!channels.isCompleted) channels.complete(_response(_channels));
  }
}

XtreamClient _client(http.Client httpClient) => XtreamClient(
      serverUrl: 'https://catalog.invalid',
      username: 'viewer',
      password: 'test',
      httpClient: httpClient,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ImportProgressBus.clear);
  tearDown(ImportProgressBus.clear);

  test('les chaînes partent avant la réponse des catégories, deux appels seuls',
      () async {
    final _CatalogServer server = _CatalogServer();
    final XtreamClient client = _client(server);
    final Future<List<Channel>> pending = client.fetchLiveChannels(playlistId: 9);
    try {
      // Avec l'ancien chargement en série, cette attente échoue : la réponse
      // catégories est volontairement retenue et la requête live ne part pas.
      await server.bothStarted.future.timeout(const Duration(seconds: 2));
      expect(server.categories.isCompleted, isFalse);
      expect(server.channels.isCompleted, isFalse);
      expect(server.actions,
          <String>['get_live_categories', 'get_live_streams']);
    } finally {
      server.finish();
    }
    final List<Channel> result = await pending;
    expect(result.single.id, 'xtream-42');
    expect(result.single.playlistId, 9);
    expect(result.single.category, 'Sport');
    expect(client.epgChannelIds, <String, String>{'xtream-42': 'guide-test'});
    expect(ImportProgressBus.current.value?.count, 1);
    client.dispose();
  });

  test('catégories fournies : aucun second téléchargement des catégories',
      () async {
    final List<String?> actions = <String?>[];
    final XtreamClient client = _client(MockClient((http.Request request) async {
      actions.add(request.url.queryParameters['action']);
      return http.Response(_channels, 200);
    }));
    final List<Channel> result = await client.fetchLiveChannels(
      playlistId: 1, categories: <String, String>{'7': 'Déjà chargé'},
    );
    expect(actions, <String>['get_live_streams']);
    expect(result.single.category, 'Déjà chargé');
    client.dispose();
  });

  test('catégories vides : les chaînes restent disponibles dans Autres',
      () async {
    final XtreamClient client = _client(MockClient((http.Request request) async {
      return http.Response(
          request.url.queryParameters['action'] == 'get_live_categories'
              ? '[]' : _channels, 200);
    }));
    final List<Channel> result = await client.fetchLiveChannels(playlistId: 1);
    expect(result.single.category, 'Autres');
    client.dispose();
  });

  test('une catégorie en cours ne compte pas comme déjà reçue', () async {
    final Completer<void> categoryStarted = Completer<void>();
    final Completer<http.Response> categoryResponse = Completer<http.Response>();
    final XtreamClient client = _client(MockClient((http.Request request) async {
      if (request.url.queryParameters['action'] == 'get_live_categories') {
        return http.Response(_categories, 200);
      }
      if (request.url.queryParameters['category_id'] == null) {
        // Dépasse le seuil existant, sans décoder un grand arbre JSON :
        // le client coupe le bloc puis demande cette catégorie séparément.
        return http.Response(' ' * (kXtreamSingleShotBytes + 1), 200);
      }
      categoryStarted.complete();
      return categoryResponse.future;
    }));
    final Future<List<Channel>> pending = client.fetchLiveChannels(playlistId: 1);
    try {
      await categoryStarted.future.timeout(const Duration(seconds: 2));
      final ImportProgress? progress = ImportProgressBus.current.value;
      expect(progress?.stage, ImportStage.category);
      expect(progress?.index, 0,
          reason: 'aucune catégorie reçue tant que la réponse est retenue');
      expect(progress?.total, 1);
      expect(progress?.count, 0);
    } finally {
      categoryResponse.complete(http.Response(_channels, 200));
    }
    expect(await pending, hasLength(1));
    expect(ImportProgressBus.current.value?.count, 1);
    client.dispose();
  });

  test('catégories refusées : une réponse live tardive ne réanime pas le progrès',
      () async {
    final _CatalogServer server = _CatalogServer();
    final XtreamClient client = _client(server);
    final Future<void> failed = expectLater(
      client.fetchLiveChannels(playlistId: 1), throwsA(isA<XtreamException>()),
    );
    await server.bothStarted.future.timeout(const Duration(seconds: 2));
    server.categories.complete(_response('réponse invalide'));
    await failed;
    ImportProgressBus.clear();

    final Completer<void> consumed = Completer<void>();
    Stream<List<int>> lateBody() async* {
      yield utf8.encode(_channels);
      consumed.complete();
    }
    server.channels.complete(http.StreamedResponse(lateBody(), 200));
    await consumed.future;
    expect(ImportProgressBus.current.value, isNull,
        reason: 'la recherche a déjà échoué, les octets tardifs sont ignorés');
    client.dispose();
  });

  test('deux échecs : la seconde erreur HTTP est elle aussi consommée', () async {
    final _CatalogServer server = _CatalogServer();
    final XtreamClient client = _client(server);
    final Future<void> failed = expectLater(
      client.fetchLiveChannels(playlistId: 1), throwsA(isA<XtreamException>()),
    );
    await server.bothStarted.future.timeout(const Duration(seconds: 2));
    server.categories.complete(_response('réponse invalide'));
    await failed;
    server.channels.completeError(TimeoutException('serveur simulé'));
    // Laisse passer la seconde réponse dans _getBytes puis Future.wait.
    // Une erreur non consommée ferait échouer le test dans la zone courante.
    await Future<void>.delayed(Duration.zero);
    client.dispose();
  });
}
