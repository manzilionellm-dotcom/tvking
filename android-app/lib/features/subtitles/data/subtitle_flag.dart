// =========================================================
//  subtitle_flag.dart — Interrupteur des sous-titres du direct
// =========================================================
//  Coupé : le lecteur n'appelle ni selectTrack ni disableSubtitles
//  pour cette fonction. Le film, lui, garde son réglage à part.
// =========================================================

import '../../box_extras/box_flag.dart';

final BoxFlag subtitlesFlag = BoxFlag('zuno.flag.subtitles');
