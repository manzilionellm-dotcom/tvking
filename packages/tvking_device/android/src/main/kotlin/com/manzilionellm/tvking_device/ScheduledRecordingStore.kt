package com.manzilionellm.tvking_device

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Mémoire NATIVE des enregistrements programmés.
 *
 * POURQUOI UNE COPIE NATIVE alors que le Dart a déjà sa table SQLite :
 * une alarme Android réveille un BroadcastReceiver SANS moteur Flutter
 * (la box est en veille, l'app a été tuée, ou l'appareil vient de
 * redémarrer). À cet instant, le receiver doit connaître l'URL du flux,
 * le fichier de destination et l'heure de fin — sans Dart. On garde
 * donc un petit miroir JSON dans les SharedPreferences, écrit par le
 * Dart au moment de la programmation, lu par le receiver au réveil.
 *
 * Le Dart reste la SOURCE DE VÉRITÉ (liste, statuts, fiche « Mes
 * enregistrements ») ; ce store n'est que le carnet de route du natif.
 *
 * Format d'une entrée :
 *   { id, url, file, title, startMs, stopMs, notifTitle, channelName,
 *     channelDesc, state ("planned"|"recording"|"done"|"failed"),
 *     bytes, error }
 */
class ScheduledRecordingStore(context: Context) {

    companion object {
        private const val PREFS = "tvking_scheduled_recordings"
        private const val KEY = "items"
    }

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Toutes les entrées (copie). */
    @Synchronized
    fun all(): List<JSONObject> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun get(id: String): JSONObject? = all().firstOrNull { it.optString("id") == id }

    /** Ajoute ou remplace l'entrée d'identifiant `id`. */
    @Synchronized
    fun put(entry: JSONObject) {
        val id = entry.optString("id")
        val next = all().filter { it.optString("id") != id }.toMutableList()
        next.add(entry)
        save(next)
    }

    @Synchronized
    fun remove(id: String) {
        save(all().filter { it.optString("id") != id })
    }

    /** Met à jour quelques champs d'une entrée existante (no-op si absente). */
    @Synchronized
    fun update(id: String, mutate: (JSONObject) -> Unit) {
        val items = all().toMutableList()
        val idx = items.indexOfFirst { it.optString("id") == id }
        if (idx < 0) return
        mutate(items[idx])
        save(items)
    }

    /** Purge les entrées terminées depuis plus de 7 jours (hygiène). */
    @Synchronized
    fun pruneOld(nowMs: Long) {
        val keep = all().filter { e ->
            val stop = e.optLong("stopMs", 0L)
            val state = e.optString("state", "planned")
            !(stop < nowMs - 7L * 24 * 3600 * 1000 && state != "recording")
        }
        save(keep)
    }

    private fun save(items: List<JSONObject>) {
        val arr = JSONArray()
        items.forEach { arr.put(it) }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }
}
