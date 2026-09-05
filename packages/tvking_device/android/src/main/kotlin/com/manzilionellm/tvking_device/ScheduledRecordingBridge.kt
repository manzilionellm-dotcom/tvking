package com.manzilionellm.tvking_device

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Pont Dart ↔ enregistrement programmé (canal
 * `com.manzilionellm.tvking/recording_scheduler`).
 *
 * Méthodes :
 *   schedule({id,url,file,title,startMs,stopMs,notifTitle,channelName,
 *             channelDesc})            → true
 *   cancel({id})                       → true (annule alarmes + arrête si en cours)
 *   status({id})                       → {state,bytes,startedAt,endedAt,error} ou null
 *   statusAll()                        → liste des mêmes maps
 *   canScheduleExact()                 → Boolean
 *   openExactAlarmSettings()           → ouvre l'écran système (Android 12+)
 *   freeSpace({path})                  → octets libres (Long) ou null
 *   isRecording()                      → id en cours ou null
 *
 * Tout est best-effort : aucune méthode ne lève vers Flutter, les erreurs
 * remontent en `result.error` avec un code lisible.
 */
class ScheduledRecordingBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val store = ScheduledRecordingStore(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "schedule" -> {
                    val id = call.argument<String>("id") ?: return result.error("ARG", "id", null)
                    val entry = JSONObject().apply {
                        put("id", id)
                        put("url", call.argument<String>("url") ?: "")
                        put("file", call.argument<String>("file") ?: "")
                        put("title", call.argument<String>("title") ?: "7 MOTION")
                        put("startMs", call.argument<Number>("startMs")?.toLong() ?: 0L)
                        put("stopMs", call.argument<Number>("stopMs")?.toLong() ?: 0L)
                        put("notifTitle", call.argument<String>("notifTitle") ?: "")
                        put("channelName", call.argument<String>("channelName") ?: "")
                        put("channelDesc", call.argument<String>("channelDesc") ?: "")
                        put("state", "planned")
                        put("bytes", 0L)
                    }
                    store.put(entry)
                    ScheduledRecordingAlarms.arm(
                        context, id, entry.getLong("startMs"), entry.getLong("stopMs"),
                    )
                    result.success(true)
                }
                "cancel" -> {
                    val id = call.argument<String>("id") ?: return result.error("ARG", "id", null)
                    ScheduledRecordingAlarms.cancel(context, id)
                    if (ScheduledRecordingService.activeId == id) {
                        val stop = Intent(context, ScheduledRecordingService::class.java).apply {
                            action = ScheduledRecordingService.ACTION_STOP
                            putExtra(ScheduledRecordingService.EXTRA_ID, id)
                        }
                        try { context.startService(stop) } catch (_: Exception) {}
                    } else {
                        store.remove(id)
                    }
                    result.success(true)
                }
                "status" -> {
                    val id = call.argument<String>("id") ?: return result.error("ARG", "id", null)
                    result.success(store.get(id)?.let { toMap(it) })
                }
                "statusAll" -> result.success(store.all().map { toMap(it) })
                "forget" -> {
                    // Le Dart a intégré le résultat : on retire l'entrée du carnet.
                    val id = call.argument<String>("id") ?: return result.error("ARG", "id", null)
                    if (ScheduledRecordingService.activeId != id) store.remove(id)
                    result.success(true)
                }
                "canScheduleExact" -> result.success(ScheduledRecordingAlarms.canScheduleExact(context))
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val i = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = android.net.Uri.parse("package:" + context.packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "freeSpace" -> {
                    val path = call.argument<String>("path") ?: return result.success(null)
                    result.success(
                        try {
                            val fs = StatFs(path)
                            fs.availableBytes
                        } catch (e: Exception) {
                            null
                        },
                    )
                }
                "isRecording" -> result.success(ScheduledRecordingService.activeId)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("SCHED_REC", e.message, null)
        }
    }

    private fun toMap(e: JSONObject): HashMap<String, Any?> {
        val id = e.optString("id")
        // Si le service tourne pour cet id, les octets vivent en mémoire
        // (le carnet n'est écrit qu'à la fin) → on renvoie la valeur vive.
        val live = ScheduledRecordingService.activeId == id
        return hashMapOf(
            "id" to id,
            "state" to (if (live) "recording" else e.optString("state", "planned")),
            "bytes" to (if (live) ScheduledRecordingService.bytesWritten else e.optLong("bytes", 0L)),
            "file" to e.optString("file"),
            "startedAt" to (if (e.has("startedAt")) e.optLong("startedAt") else null),
            "endedAt" to (if (e.has("endedAt")) e.optLong("endedAt") else null),
            "error" to (if (e.has("error")) e.optString("error") else null),
        )
    }
}
