"""Ajoute un chronomètre et un flux de mesure à la copie CI du vrai lecteur."""
from pathlib import Path
from shutil import copyfile


def insert(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f"Point de mesure absent ou ambigu dans {path}")
    path.write_text(text.replace(old, new))


app = Path("lib/main.dart")
player = Path("packages/novatube_video/lib/novatube_video.dart")
copyfile(Path(__file__).with_name("benchmark_home.dart.fixture"), "lib/benchmark_home.dart")
insert(app, "import 'dart:async';", "import 'dart:async';\nimport 'benchmark_home.dart';")
insert(app, "home: const _AppEntry(),", "home: const BenchmarkHome(_AppEntry()),")
insert(player, "class PhoneVideoPlayer", "final Stopwatch qaFirstImage = Stopwatch();\n\nclass PhoneVideoPlayer")
insert(player, "case 'firstFrame':", """case 'firstFrame':
        if (qaFirstImage.isRunning) {
          qaFirstImage.stop();
          debugPrint('SEVEN_PERF_TTFF_US ${qaFirstImage.elapsedMicroseconds}');
        }""")
