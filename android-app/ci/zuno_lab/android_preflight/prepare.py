"""Modifie exclusivement une copie du diagnostic .lab.catalog, dans la CI."""
from pathlib import Path

android = Path("android/app")
if 'applicationId = "com.sevenmotion.tv.seven_tv.lab.catalog"' not in (android / "build.gradle.kts").read_text():
    raise RuntimeError("Identité du diagnostic requise")


def insert(path, anchor, lines):
    original = path.read_text()
    if original.count(anchor) != 1:
        raise RuntimeError(f"Vérifier le point de mesure dans {path}")
    path.write_text(original.replace(anchor, anchor + "\n" + lines))


activity = android / "src/main/kotlin/com/example/tv_king/MainActivity.kt"
insert(activity, "    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {", '''        val skipLabPreflight = intent.getBooleanExtra("disable_lab_gl_preflight", false)
        System.setProperty("zuno.lab.skipPreflight", skipLabPreflight.toString())
        Log.i("ZunoStartup", "lab.ai.skip=" + skipLabPreflight)''')
engine = Path("packages/native_video_player/android/src/main/kotlin/com/manzilionellm/native_video_player/ai/AiPictureEngine.kt")
insert(engine, "    fun startPreflight() {", '''        if (java.lang.Boolean.getBoolean("zuno.lab.skipPreflight")) {
            Log.i("ZunoStartup", "lab.ai.preflight.skipped")
            return
        }''')
