// =========================================================
//  missed_flag.dart — Interrupteur du résumé « en retard »
// =========================================================
//  Une seule instance : l'écran En plus et le lecteur lisent
//  la même valeur. Coupé, le lecteur ne demande même pas le guide.
// =========================================================

import '../../box_extras/box_flag.dart';

final BoxFlag missedShowFlag = BoxFlag('zuno.flag.missed_show');
