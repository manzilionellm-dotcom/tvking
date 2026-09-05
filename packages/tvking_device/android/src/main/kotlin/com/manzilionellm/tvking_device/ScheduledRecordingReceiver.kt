package com.manzilionellm.tvking_device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Réveil par alarme (START / STOP) et après redémarrage (BOOT_COMPLETED).
 *
 * Tourne SANS Flutter : il lit le carnet natif ([ScheduledRecordingStore])
 * et pilote le service au premier plan. C'est ce qui permet à une box en
 * veille, ou à une app fermée, d'enregistrer quand même à l'heure dite.
 */
class ScheduledRecordingReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "RecReceiver"
        const val ACTION_START = "com.manzilionellm.tvking.schedrec.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.schedrec.STOP"
        const val EXTRA_ID = "id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: return
                Log.i(TAG, "START $id")
                startService(context, id)
            }
            ACTION_STOP -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: return
                Log.i(TAG, "STOP $id")
                val stop = Intent(context, ScheduledRecordingService::class.java).apply {
                    action = ScheduledRecordingService.ACTION_STOP
                    putExtra(ScheduledRecordingService.EXTRA_ID, id)
                }
                try {
                    context.startService(stop)
                } catch (e: Exception) {
                    // Service pas lancé (enregistrement jamais parti) : rien à
                    // arrêter, mais on note l'échec dans le carnet.
                    Log.w(TAG, "stop sans service : $e")
                    ScheduledRecordingStore(context).update(id) { e2 ->
                        if (e2.optString("state") == "planned") {
                            e2.put("state", "failed")
                            e2.put("error", "neverStarted")
                        }
                    }
                }
            }
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // Les alarmes ne survivent ni au redémarrage ni à la mise à
                // jour de l'app : on les re-pose depuis le carnet natif.
                Log.i(TAG, "re-armement après ${intent.action}")
                ScheduledRecordingAlarms.rearmAll(context)
            }
        }
    }

    private fun startService(context: Context, id: String) {
        val svc = Intent(context, ScheduledRecordingService::class.java).apply {
            action = ScheduledRecordingService.ACTION_START
            putExtra(ScheduledRecordingService.EXTRA_ID, id)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, svc)
            } else {
                context.startService(svc)
            }
        } catch (e: Exception) {
            // Android 12+ peut REFUSER un service au premier plan lancé
            // depuis l'arrière-plan si l'alarme n'était pas exacte. On le
            // consigne : le Dart, s'il tourne, rattrapera le créneau
            // lui-même (RecordingScheduler.tick) ; sinon l'écran « Prévus »
            // montrera l'échec plutôt que de mentir.
            Log.e(TAG, "startForegroundService refusé : $e")
            ScheduledRecordingStore(context).update(id) { e2 ->
                e2.put("state", "failed")
                e2.put("error", "fgsDenied:${e.javaClass.simpleName}")
            }
        }
    }
}
