"""Partage les lecteurs de réglages et garde les particularités du téléphone."""
from pathlib import Path
import re
import sys

mission = Path(sys.argv[1])
for name in [
    'theme/data/remote_theme_repository.dart',
    'simple_home/data/home_layout_repository.dart',
    'country_home/data/featured_repository.dart',
    'ads/data/startup_ad_repository.dart',
    'feedback/data/feedback_repository.dart',
    'pricing/data/pricing_repository.dart',
    'about/data/force_update_checker.dart',
]:
    relative = Path('lib/features') / name
    old = relative.read_text()
    source = (mission / relative).read_text()
    if name.startswith('pricing/'):
        # Les prix hors ligne sont propres au téléphone, jamais remplacés par
        # les valeurs Zuno lors du partage de la lecture HTTP stricte.
        pattern = r'static const PricingConfig fallback = PricingConfig\(.*?\);'
        original = re.search(pattern, old, re.S)
        assert original
        source = re.sub(pattern, lambda _: original.group(0), source, flags=re.S)
    if name.startswith('about/'):
        start = old.index('  /// Signal « le panel')
        end = old.index('  /// `true`', start)
        source = source.replace('  /// `true`', old[start:end] + '  /// `true`', 1)
    relative.write_text(source)

# Le catalogue mobile a des helpers différents : partager seulement les deux
# méthodes réseau, sans modifier ses modèles ou son interface de connexion.
def method(text, prefix):
    start = text.index(prefix)
    pos = text.index(' async {', start) + len(' async {')
    level = 1
    while level:
        if text[pos] == '{': level += 1
        elif text[pos] == '}': level -= 1
        pos += 1
    return text[start:pos]

relative = Path('lib/features/playlists/data/default_servers.dart')
text = relative.read_text()
source = (mission / relative).read_text()
for prefix in ['static Future<List<DefaultServer>> fetch(', 'static Future<List<DefaultServer>?> _fetchFromNetwork(']:
    text = text.replace(method(text, prefix), method(source, prefix), 1)
relative.write_text(text)

path = Path('lib/core/app/panel_live_wait.dart')
text = path.read_text()
imports = """import '../../features/theme/data/remote_theme_repository.dart';
import '../../features/pricing/data/pricing_repository.dart';
import '../../features/simple_home/data/home_layout_repository.dart';
import '../../features/country_home/data/featured_repository.dart';
import '../../features/ads/data/startup_ad_repository.dart';
import '../../features/feedback/data/feedback_repository.dart';
import '../../features/playlists/data/default_servers.dart';
import '../../features/about/data/force_update_checker.dart';
"""
text = text.replace("import '../../features/simple_home/data/announcement_repository.dart';", "import '../../features/simple_home/data/announcement_repository.dart';\n" + imports)
old = "if (commands.any((dynamic item) => item is Map && item['kind'] != 'message')) await trigger();"
assert text.count(old) == 1
text = text.replace(old, """final Set<String> kinds = commands.whereType<Map>().map((item) => '${item['kind'] ?? ''}').toSet();
      const statusKinds = <String>{'activate','renew','expire','suspend','resume','block','transfer','device_delete','license','source','source_clear','reset'};
      if (kinds.any(statusKinds.contains)) await trigger();
      // Chaque accusé attend la relecture de SON réglage. Un serveur en
      // erreur ne transforme jamais un ancien cache en succès appliqué.
      for (final String kind in kinds) {
        switch (kind) {
          case 'theme': await RemoteThemeRepository.fetchAndApply(strict: true); break;
          case 'pricing': await PricingRepository.fetch(strict: true); break;
          case 'home': await HomeLayoutRepository.instance.refresh(strict: true); break;
          case 'featured': await FeaturedRepository.instance.refresh(strict: true); break;
          case 'ad': await StartupAdRepository.instance.fetch(strict: true); break;
          case 'feedback': await FeedbackRepository.instance.reload(strict: true); break;
          case 'servers': await DefaultServersApi.fetch(forceRefresh: true, strict: true); break;
          case 'force_update':
            await ForceUpdateChecker.instance.mustUpdate(strict: true);
            ForceUpdateChecker.instance.requestRecheck();
            break;
        }
      }""")
path.write_text(text)
