"""Ajoute uniquement sur la copie CI de diagnostic des marqueurs sans URL."""
from pathlib import Path


def replace(file, before, after):
    p=Path(file)
    text=p.read_text()
    if text.count(before)!=1: raise RuntimeError('Point de mesure absent ou ambigu dans '+file)
    p.write_text(text.replace(before,after))


def main():
    gradle='android/app/build.gradle.kts'
    replace(gradle,'applicationId = "com.sevenmotion.tv.seven_tv.lab"','applicationId = "com.sevenmotion.tv.seven_tv.lab.tracediag"')
    app='lib/features/tv/presentation/tv_app.dart'
    replace(app,"                      id: 'probe',","                      id: 'A',")
    replace(app,'                      streamUrl: kZunoPlayerProbeUrl,','''                      streamUrl: kZunoPlayerProbeUrl,
                      isLive: true,
                    ),
                    Channel(
                      id: 'B',
                      name: 'Mire B',
                      category: 'Essai',
                      streamUrl: kZunoPlayerProbeUrl.replaceFirst('/A/', '/B/'),''')
    player='lib/features/tv/presentation/tv_player_screen.dart'
    replace(player,"import 'dart:async';","import 'dart:async';\nimport 'dart:developer' as trace_time;")
    for point, phase in [('  void _zap(int delta) {','dart_zap'),('  void _open({bool reuse = false}) {','dart_open')]:
        replace(player,point,point+f"\n    print('ZUNO_PHASE {phase} ticks=\u0024{{trace_time.Timeline.now}}');")
    kt='packages/native_video_player/android/src/main/kotlin/com/manzilionellm/native_video_player/NativeVideoView.kt'
    marker='    private fun openCurrent('
    replace(kt,marker,'''    private fun tracePhase(phase: String, sourceTimeMs: Long = -1L) {
        val channel = when {
            currentUrl?.contains("/A/") == true -> "A"
            currentUrl?.contains("/B/") == true -> "B"
            else -> "unknown"
        }
        android.util.Log.i("ZunoLabPhase", "ZUNO_PHASE $phase ticks=${SystemClock.elapsedRealtimeNanos()} channel=$channel gen=${sessions.generation} event_ms=$sourceTimeMs")
    }

'''+marker)
    for point, tag in [
        ('        if (currentUrl == null || released || disposeStarted) return\n        // Dehors','        if (currentUrl == null || released || disposeStarted) return\n        tracePhase("native_open")\n        // Dehors'),
        ('        player.prepare()','        tracePhase("prepare")\n        player.prepare()'),
        ('        decoderReadyAtMs = SystemClock.elapsedRealtime()','        tracePhase("decoder_ready", initializedTimestampMs)\n        decoderReadyAtMs = SystemClock.elapsedRealtime()'),
        ('        reconnect.onRecovered()\n        behindLiveCount = 0\n        sawFrame = true',
         '        tracePhase("native_first_render", renderTimeMs)\n        reconnect.onRecovered()\n        behindLiveCount = 0\n        sawFrame = true')]:
        replace(kt,point,tag)

if __name__=='__main__': main()
