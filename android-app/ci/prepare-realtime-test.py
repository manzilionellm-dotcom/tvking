"""Préparer uniquement le paquet Android de recette, jamais une publication."""
from pathlib import Path
import sys

variant, mission = sys.argv[1], Path(sys.argv[2])
source = (mission / 'android-app/ci/realtime_device_test.dart.template').read_text()
if variant == 'zuno':
    imports = "import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';"
    start = 'RemoteActivationWatch.instance.start();'
    stop = 'RemoteActivationWatch.instance.stop();'
else:
    imports = "import 'package:tv_king/core/realtime/realtime_sync_service.dart';\nimport 'package:tv_king/core/app/panel_live_wait.dart';"
    start = "await RealtimeSyncService.instance.start(platform: 'mobile');"
    stop = 'PanelLiveWait.instance.stop();'
source = source.replace('// ADAPTER_IMPORTS', imports).replace('// ADAPTER_START', start).replace('// ADAPTER_STOP', stop)
Path('integration_test').mkdir(exist_ok=True)
Path('integration_test/realtime_device_test.dart').write_text(source)
pubspec = Path('pubspec.yaml')
text = pubspec.read_text()
if '  integration_test:' not in text:
    text = text.replace('dev_dependencies:', 'dev_dependencies:\n  integration_test:\n    sdk: flutter', 1)
pubspec.write_text(text)
