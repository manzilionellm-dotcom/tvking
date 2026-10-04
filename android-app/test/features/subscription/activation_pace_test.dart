import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/domain/activation_pace.dart';

void main() {
  test('rythme : 3 s en attente, 4 s ensuite, plafond 45 s', () {
    expect(
      ActivationPace.next(waiting: true, failures: 0),
      const Duration(seconds: 3),
    );
    expect(
      ActivationPace.next(waiting: false, failures: 0),
      const Duration(seconds: 4),
    );
    expect(
      ActivationPace.next(waiting: false, failures: 1),
      const Duration(seconds: 8),
    );
    expect(
      ActivationPace.next(waiting: true, failures: 8),
      const Duration(seconds: 45),
    );
  });

  test('on ne télécharge les codes que si le numéro change', () {
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: false,
        playbackBusy: false,
        sourceRevKnown: true,
        sourceRev: 5,
        lastFetchedRev: 4,
        hasChannels: true,
      ),
      isFalse,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: true,
        sourceRev: 5,
        lastFetchedRev: 4,
        hasChannels: true,
      ),
      isFalse,
    );
    // Box SANS chaîne sur l'écran Direct vide (compté « occupé ») :
    // rien ne joue, la source poussée arrive tout de suite.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: true,
        sourceRev: 5,
        lastFetchedRev: 4,
        hasChannels: false,
      ),
      isTrue,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: false,
        sourceRevKnown: true,
        sourceRev: 5,
        lastFetchedRev: 5,
        hasChannels: true,
      ),
      isFalse,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: false,
        sourceRevKnown: true,
        sourceRev: 6,
        lastFetchedRev: 5,
        hasChannels: true,
      ),
      isTrue,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: false,
        sourceRevKnown: true,
        sourceRev: 0,
        lastFetchedRev: 9,
        hasChannels: true,
      ),
      isTrue,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: false,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: true,
      ),
      isTrue,
    );
  });

  test('une lecture ratée ne remplace pas le dernier statut', () {
    expect(keepLastStatusOnFailure(reached: false), isTrue);
    expect(keepLastStatusOnFailure(reached: true), isFalse);
  });

  test('empreinte et listes à retirer', () {
    expect(
      SourceFingerprint.xtream('http://Exemple.test/', ' user '),
      'xtream|http://exemple.test|user',
    );
    expect(SourceFingerprint.m3u(' http://liste.test/a.m3u '),
        'm3u|http://liste.test/a.m3u');
    final Set<String> drop = fingerprintsToDrop(
      remembered: <String>{'xtream|a|u', 'm3u|b'},
      current: <String>{'m3u|b'},
      revoked: <String>{'xtream|c|v', 'm3u|b'},
    );
    expect(drop, <String>{'xtream|a|u', 'xtream|c|v'});
    expect(drop.contains('m3u|b'), isFalse);
  });

  test('source_rev absent, zéro, ou un nombre', () {
    final RemoteSubscriptionStatus absent =
        RemoteSubscriptionStatus.fromJson(
            const <String, dynamic>{'paid': true});
    expect(absent.sourceRev, isNull);
    expect(absent.revoked, isEmpty);

    final RemoteSubscriptionStatus zero =
        RemoteSubscriptionStatus.fromJson(const <String, dynamic>{
      'source_rev': null,
      'revoked': <Map<String, String>>[
        <String, String>{
          'type': 'xtream',
          'server_url': 'http://Hote.test/',
          'username': 'ada',
        },
      ],
    });
    expect(zero.sourceRev, 0);
    expect(zero.revoked, <String>['xtream|http://hote.test|ada']);

    final RemoteSubscriptionStatus n =
        RemoteSubscriptionStatus.fromJson(const <String, dynamic>{
      'source_rev': 42,
    });
    expect(n.sourceRev, 42);
  });
}
