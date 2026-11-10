import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/domain/activation_pace.dart';

void main() {
  test('rythme : 1 s en attente, 2 s ensuite, sous 2 s', () {
    expect(ActivationPace.fast, const Duration(seconds: 1));
    expect(ActivationPace.calm, const Duration(seconds: 2));
    expect(ActivationPace.fast.inMilliseconds, lessThanOrEqualTo(2000));
    expect(ActivationPace.calm.inMilliseconds, lessThanOrEqualTo(2000));
    expect(
      ActivationPace.next(waiting: true, failures: 0),
      const Duration(seconds: 1),
    );
    expect(
      ActivationPace.next(waiting: false, failures: 0),
      const Duration(seconds: 2),
    );
    expect(
      ActivationPace.next(waiting: false, failures: 1),
      const Duration(seconds: 4),
    );
    // Quatre échecs : ×16, encore sous le plafond de 45 s.
    // Le plafond reste dans le calcul pour un rythme de base plus long.
    expect(
      ActivationPace.next(waiting: true, failures: 8),
      const Duration(seconds: 16),
    );
    expect(
      ActivationPace.next(waiting: false, failures: 4),
      const Duration(seconds: 32),
    );
    expect(ActivationPace.ceiling, const Duration(seconds: 45));
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

  test('un ordre du panel importe tout de suite, même pendant la lecture', () {
    // Cause mesurée le 05/10/2026 : la v106 attendait le retour à
    // l'accueil (lecteur ou Direct ouvert = occupé) avant d'importer la
    // liste envoyée par le panel. Un ordre explicite passe devant.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: true,
        ordered: true,
      ),
      isTrue,
    );
    // Sans ordre (relecture de routine), la règle d'avant reste.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: true,
      ),
      isFalse,
    );
    // Repli allumé : l'ordre attend le retour à l'accueil (ancien
    // comportement), mais une box sans chaîne importe quand même.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: true,
        ordered: true,
        orderWaitsIdle: true,
      ),
      isFalse,
    );
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: true,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: false,
        ordered: true,
        orderWaitsIdle: true,
      ),
      isTrue,
    );
    // Un ordre passe aussi devant « même numéro de source » : le Worker
    // de production ne publie pas source_rev, et un ordre veut dire
    // qu'il y a du neuf.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: true,
        playbackBusy: false,
        sourceRevKnown: true,
        sourceRev: 7,
        lastFetchedRev: 7,
        hasChannels: true,
        ordered: true,
      ),
      isTrue,
    );
    // Réseau coupé : rien, ordre ou pas.
    expect(
      SourceFetchDecision.shouldFetch(
        networkOk: false,
        playbackBusy: false,
        sourceRevKnown: false,
        sourceRev: null,
        lastFetchedRev: null,
        hasChannels: false,
        ordered: true,
      ),
      isFalse,
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
    expect(
      SourceFingerprint.m3u(' http://liste.test/a.m3u '),
      'm3u|http://liste.test/a.m3u',
    );
    final Set<String> drop = fingerprintsToDrop(
      remembered: <String>{'xtream|a|u', 'm3u|b'},
      current: <String>{'m3u|b'},
      revoked: <String>{'xtream|c|v', 'm3u|b'},
    );
    expect(drop, <String>{'xtream|a|u', 'xtream|c|v'});
    expect(drop.contains('m3u|b'), isFalse);
  });

  test('source_rev absent, zéro, ou un nombre', () {
    final RemoteSubscriptionStatus absent = RemoteSubscriptionStatus.fromJson(
      const <String, dynamic>{'paid': true},
    );
    expect(absent.sourceRev, isNull);
    expect(absent.revoked, isEmpty);

    final RemoteSubscriptionStatus zero = RemoteSubscriptionStatus.fromJson(
      const <String, dynamic>{
        'source_rev': null,
        'revoked': <Map<String, String>>[
          <String, String>{
            'type': 'xtream',
            'server_url': 'http://Hote.test/',
            'username': 'ada',
          },
        ],
      },
    );
    expect(zero.sourceRev, 0);
    expect(zero.revoked, <String>['xtream|http://hote.test|ada']);

    final RemoteSubscriptionStatus n = RemoteSubscriptionStatus.fromJson(
      const <String, dynamic>{'source_rev': 42},
    );
    expect(n.sourceRev, 42);
  });
}
