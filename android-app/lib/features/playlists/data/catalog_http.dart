// Délais par requête : une liste lente ne doit pas fermer le client partagé
// par les autres catégories Xtream.
import 'dart:async';

import 'package:http/http.dart' as http;

Future<http.StreamedResponse> sendCatalogGet(http.Client client, Uri uri,
    Map<String, String> headers, Duration timeout) {
  final abort = Completer<void>();
  final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
    ..headers.addAll(headers);
  return client.send(request).then((response) async {
    // Un client injecté peut ignorer l'annulation avant les en-têtes.
    if (abort.isCompleted) {
      await response.stream.listen(null).cancel();
      throw TimeoutException('En-têtes du catalogue', timeout);
    }
    return response;
  }).timeout(timeout, onTimeout: () {
    abort.complete();
    throw TimeoutException('En-têtes du catalogue', timeout);
  });
}

/// Le plafond total interrompt la souscription même quand les octets
/// arrivent régulièrement. Les pauses du consommateur remontent à la source.
Stream<List<int>> catalogBody(http.ByteStream body, Duration total) {
  final output = StreamController<List<int>>(sync: true);
  late StreamSubscription<List<int>> subscription;
  late Timer deadline;
  output.onListen = () {
    deadline = Timer(total, () {
      output.addError(TimeoutException('Corps du catalogue', total));
      unawaited(output.close());
      unawaited(subscription.cancel());
    });
    subscription =
        body.listen(output.add, onError: output.addError, onDone: () {
      deadline.cancel();
      unawaited(output.close());
    });
  };
  output.onPause = () => subscription.pause();
  output.onResume = () => subscription.resume();
  output.onCancel = () {
    deadline.cancel();
    return subscription.cancel();
  };
  return output.stream;
}
