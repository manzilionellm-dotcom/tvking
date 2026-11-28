"""Installe le diagnostic dans une copie jetable déjà préparée en ZUNO LAB."""
from pathlib import Path
import shutil

app = Path.cwd()
tv = app / "lib/features/tv/presentation"
here = Path(__file__).resolve().parent

def replace(path, old, new):
    data = path.read_text()
    if data.count(old) != 1:
        raise ValueError(f"Relire le point d'instrumentation dans {path}")
    path.write_text(data.replace(old, new))

gradle = app / "android/app/build.gradle.kts"
replace(gradle, 'applicationId = "com.sevenmotion.tv.seven_tv.lab"',
        'applicationId = "com.sevenmotion.tv.seven_tv.lab.catalog"')
for name in ("catalog_probe", "catalog_counts"):
    shutil.copy(here / f"{name}.dart.src", tv / f"{name}.dart")
replace(tv / "tv_app.dart", "? const RestartWidget(child: RemovedListPrompt(child: TvGate()))", "? const CatalogProbe()")
for name, dependency in [('tv_app','catalog_probe'), ('tv_live_screen','catalog_counts'), ('tv_player_screen','catalog_counts')]:
    path = tv / f"{name}.dart"
    path.write_text(f"import '{dependency}.dart';\n" + path.read_text())
replace(tv / "tv_live_screen.dart", "void _setPreview(Channel c) {", "void _setPreview(Channel c) {\n    CatalogCounts.focus.add(c.id);\n    CatalogCounts.selections++;")
replace(tv / "tv_player_screen.dart", "    TvActivity.enter();", "    CatalogCounts.opens++;\n    TvActivity.enter();")
replace(tv / "tv_player_screen.dart", "void _zap(int delta) {", "void _zap(int delta) {\n    CatalogCounts.zapIntents++;")

replace(tv / "tv_player_screen.dart", "    TvActivity.leave();", "    CatalogCounts.closes++;\n    TvActivity.leave();")
