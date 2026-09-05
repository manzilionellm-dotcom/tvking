package com.manzilionellm.tvking_device

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Pose / retire les alarmes système d'un enregistrement programmé.
 *
 * Deux alarmes par programmation : START (à `startMs`) et STOP (à
 * `stopMs`). Chacune réveille [ScheduledRecordingReceiver], qui
 * démarre ou arrête [ScheduledRecordingService].
 *
 * EXACTITUDE : une émission qui commence à 20 h 00 doit être captée à
 * 20 h 00, pas « entre 20 h 00 et 20 h 10 ». On utilise donc
 * `setExactAndAllowWhileIdle` (précis, passe le mode Doze) quand
 * l'application y est autorisée (`canScheduleExactAlarms`, Android 12+ ;
 * accordé d'office avec USE_EXACT_ALARM sur Android 13+). À défaut, on
 * retombe sur `setAndAllowWhileIdle` : l'alarme peut glisser de
 * quelques minutes — c'est pour ça que le Dart ajoute une MARGE avant le
 * début (2 min par défaut) et après la fin.
 *
 * Le pending intent est identifié par (id, action) : reposer une alarme
 * pour le même id la REMPLACE (FLAG_UPDATE_CURRENT), annuler retire
 * exactement celle-là.
 */
object ScheduledRecordingAlarms {

    private const val TAG = "RecAlarms"

    fun canScheduleExact(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun arm(context: Context, id: String, startMs: Long, stopMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        val now = System.currentTimeMillis()
        // START : si l'heure est déjà passée (programmation « tout de
        // suite » ou re-armement après reboot en plein créneau), on
        // déclenche dans 2 s plutôt que de laisser AlarmManager le faire
        // « immédiatement » de façon non garantie.
        val startAt = if (startMs <= now) now + 2000L else startMs
        if (stopMs <= now) {
            Log.w(TAG, "arm($id) : fin déjà passée, rien à poser")
            return
        }
        schedule(am, context, pending(context, id, ScheduledRecordingReceiver.ACTION_START), startAt)
        schedule(am, context, pending(context, id, ScheduledRecordingReceiver.ACTION_STOP), stopMs)
        Log.i(TAG, "arm($id) start=${startAt - now}ms stop=${stopMs - now}ms exact=${canScheduleExact(context)}")
    }

    fun cancel(context: Context, id: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        try {
            am.cancel(pending(context, id, ScheduledRecordingReceiver.ACTION_START))
            am.cancel(pending(context, id, ScheduledRecordingReceiver.ACTION_STOP))
        } catch (e: Exception) {
            Log.w(TAG, "cancel($id) : $e")
        }
    }

    /** Re-pose toutes les alarmes encore à venir (après un redémarrage). */
    fun rearmAll(context: Context) {
        val store = ScheduledRecordingStore(context)
        val now = System.currentTimeMillis()
        store.pruneOld(now)
        for (e in store.all()) {
            val state = e.optString("state", "planned")
            if (state == "done" || state == "failed") continue
            val stop = e.optLong("stopMs", 0L)
            if (stop <= now) continue
            arm(context, e.optString("id"), e.optLong("startMs", now), stop)
        }
    }

    private fun schedule(am: AlarmManager, context: Context, pi: PendingIntent, at: Long) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (canScheduleExact(context)) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                } else {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                }
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            // Permission d'alarme exacte retirée entre-temps : on retombe
            // sur l'inexact plutôt que de ne rien poser du tout.
            Log.w(TAG, "alarme exacte refusée, repli inexact : $e")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            }
        }
    }

    private fun pending(context: Context, id: String, action: String): PendingIntent {
        val intent = Intent(context, ScheduledRecordingReceiver::class.java).apply {
            this.action = action
            putExtra(ScheduledRecordingReceiver.EXTRA_ID, id)
            // Data unique par (id, action) : sans ça, deux PendingIntent de
            // même action ne diffèrent que par leurs extras — qu'Android
            // IGNORE pour la comparaison → une seule alarme survivrait.
            data = android.net.Uri.parse("tvking://rec/$id/$action")
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(context, (id + action).hashCode(), intent, flags)
    }
}
