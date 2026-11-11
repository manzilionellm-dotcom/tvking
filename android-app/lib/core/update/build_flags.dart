import '../app/novatube_play_policy.dart';

/// NOVATUBE reçoit ses mises à jour uniquement par Google Play.
/// Cette décision ne peut pas être changée par un paramètre du build.
const bool kIsPlayBuild = NovatubePlayPolicy.isPlay;
