// Entrée NOVATUBE pour téléphones et tablettes. Le chemin validé est conservé :
// même une tablette large garde son bouton Cast. Le lecteur Android reste
// le lecteur natif ZUNO ; le pont Google Cast est fourni par son packaging.
import 'core/app/guarded_main.dart';
import 'core/app/zuno_edition.dart';
import 'main_tv.dart';

void main() => runGuarded(
      () => bootstrapZunoTv(edition: ZunoEdition.touch),
    );
