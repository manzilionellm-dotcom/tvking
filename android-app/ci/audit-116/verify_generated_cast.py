"""Vérifie les quatre sources Kotlin réellement générées après compilation."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
names = ('GoogleCastApi.kt', 'CastOptionsProviderImpl.kt',
         'MulticastLockBridge.kt', 'PlaybackForegroundService.kt')
results = {}
for name in names:
    source = root / 'android_overlay/google_cast' / name
    candidates = [
        root / 'build/zuno_cast/generated/sharedCast' / name,
        root / 'packages/zuno_cast/android/build/generated/sharedCast' / name,
    ]
    generated = [path for path in candidates if path.is_file()]
    if not generated:
        raise SystemExit(f'Source Kotlin générée absente : {name}')
    for path in generated:
        if path.read_bytes() != source.read_bytes():
            raise SystemExit(f'Copie Kotlin différente de la source durable : {name}')
    results[name] = {
        'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'generated': [str(path.relative_to(root)) for path in generated],
    }
print(json.dumps(results, indent=2))
