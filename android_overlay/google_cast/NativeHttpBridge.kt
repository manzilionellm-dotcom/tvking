// =========================================================
//  NativeHttpBridge.kt — Pont réseau natif (correctif « HTTP 884 »)
// =========================================================
//  POURQUOI CE FICHIER EXISTE
//  --------------------------
//  Certains serveurs / CDN IPTV protégés par un front « anti-bot »
//  rejettent notre app avec un code maison « HTTP 884 » AVANT même de
//  regarder l'URL ou les en-têtes — alors que la MÊME URL marche dans un
//  navigateur ET dans IBO Player, sur la même TV / le même réseau.
//
//  La cause : notre app Flutter télécharge les playlists via `dart:io
//  HttpClient`, qui embarque SA PROPRE pile TLS (BoringSSL livré avec
//  Dart). Son empreinte TLS (JA3/JA4) est atypique. Le front la classe
//  « cliente inconnue » et la bloque. Le navigateur et IBO, eux, utilisent
//  la pile TLS SYSTÈME d'Android (Conscrypt) → empreinte ultra-répandue,
//  donc acceptée. (Détails : docs/DIAGNOSTIC_HTTP_884.md.)
//
//  CE QUE FAIT CE PONT
//  -------------------
//  Il refait la requête GET avec `java.net.HttpURLConnection`, qui repose
//  sur la pile TLS SYSTÈME (Conscrypt) — EXACTEMENT la même que le
//  navigateur et IBO. L'empreinte TLS redevient « normale » → le front
//  laisse passer. Côté Dart, `M3uFetcher` / `XtreamClient` tentent ce pont
//  EN PREMIER, puis retombent sur `dart:io` si le pont est indisponible
//  (iOS, vieil APK…) ou échoue — donc AUCUNE régression possible.
//
//  POURQUOI HttpURLConnection ET PAS cronet_http / OkHttp ajouté ?
//    - HttpURLConnection est DANS le framework Android : zéro dépendance
//      ajoutée, zéro patch Gradle, rien à télécharger au build.
//    - Aucune réflexion / JNI → compatible avec l'obfuscation R8 du build
//      release (contrairement à cronet_http qui a un crash JNI documenté
//      en release obfusqué).
//
//  Channel : "com.manzilionellm.tvking/native_http" — chaîne FIXE (comme
//  le canal /pip), indépendante du package du flavor (7motion / TV /
//  redroom). Le script apply_cast_patch.sh réécrit la ligne `package`
//  pour matcher le package réellement généré par `flutter create`.
//
//  Méthode "get" — arguments Dart :
//    url     : String
//    headers : Map<String,String>  (User-Agent, Accept, Accept-Language…)
//  Retour (Map) :
//    status      : Int       (code HTTP final ; -1 si exception réseau)
//    body        : ByteArray (→ Uint8List côté Dart)
//    finalUrl    : String    (URL après redirections)
//    contentType : String?   (en-tête Content-Type de la réponse)
//    error       : String?   (message si exception réseau)
// =========================================================

package com.manzilionellm.tvking

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class NativeHttpBridge(messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "NativeHttpBridge"
        private const val CHANNEL = "com.manzilionellm.tvking/native_http"
        private const val MAX_REDIRECTS = 8
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 90_000
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    // Le réseau ne doit JAMAIS tourner sur le thread UI
    // (NetworkOnMainThreadException). On exécute la requête sur un pool
    // de threads dédié, puis on répond sur le main thread (exigence des
    // MethodChannel.Result).
    private val executor = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> {
                    val url = call.argument<String>("url")
                    val headers: Map<String, String> =
                        call.argument<Map<String, String>>("headers") ?: emptyMap()
                    if (url.isNullOrEmpty()) {
                        result.error("bad_args", "url manquante", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        val map = doGet(url, headers)
                        main.post { result.success(map) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.i(TAG, "NativeHttp channel registered ($CHANNEL)")
    }

    /// Effectue le GET en suivant manuellement les redirections (y compris
    /// cross-protocole http<->https, que HttpURLConnection ne suit pas tout
    /// seul — or les serveurs Xtream en font systématiquement).
    private fun doGet(initialUrl: String, headers: Map<String, String>): Map<String, Any?> {
        var current = initialUrl
        var redirects = 0
        var conn: HttpURLConnection? = null
        try {
            while (true) {
                val url = URL(current)
                conn = (url.openConnection() as HttpURLConnection).apply {
                    // On gère NOUS-MÊMES les redirections (cross-protocole).
                    instanceFollowRedirects = false
                    connectTimeout = CONNECT_TIMEOUT_MS
                    readTimeout = READ_TIMEOUT_MS
                    requestMethod = "GET"
                    // En-têtes fournis par Dart (User-Agent, Accept…). On NE
                    // touche PAS à Accept-Encoding : sans override,
                    // HttpURLConnection ajoute gzip ET décompresse de façon
                    // transparente → on lit des octets en clair.
                    for ((k, v) in headers) {
                        try {
                            setRequestProperty(k, v)
                        } catch (_: Throwable) {
                            // Certains en-têtes « réservés » (Connection,
                            // Host…) peuvent être ignorés par la pile : sans
                            // gravité, on continue.
                        }
                    }
                }

                val code = conn.responseCode

                // 3xx → on suit le Location à la main (conserve le contrôle
                // sur le cross-protocole et le nombre de sauts).
                if (code in 300..399 && redirects < MAX_REDIRECTS) {
                    val loc = conn.getHeaderField("Location")
                    conn.disconnect()
                    conn = null
                    if (loc.isNullOrEmpty()) break
                    // Résout les Location relatives par rapport à l'URL courante.
                    current = URL(URL(current), loc).toString()
                    redirects++
                    continue
                }

                // Lecture du corps (errorStream si code >= 400, ex. 884).
                val stream: InputStream? =
                    if (code >= 400) conn.errorStream else conn.inputStream
                val body = stream?.use { readAll(it) } ?: ByteArray(0)
                val ct = conn.contentType
                return mapOf(
                    "status" to code,
                    "body" to body,
                    "finalUrl" to current,
                    "contentType" to ct,
                    "error" to null,
                )
            }
            return mapOf(
                "status" to -1,
                "body" to ByteArray(0),
                "finalUrl" to current,
                "contentType" to null,
                "error" to "too_many_redirects",
            )
        } catch (e: Throwable) {
            Log.w(TAG, "doGet KO ($current): $e")
            return mapOf(
                "status" to -1,
                "body" to ByteArray(0),
                "finalUrl" to current,
                "contentType" to null,
                "error" to (e.message ?: e.toString()),
            )
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Throwable) {
            }
        }
    }

    private fun readAll(input: InputStream): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(16 * 1024)
        while (true) {
            val n = input.read(chunk)
            if (n < 0) break
            buffer.write(chunk, 0, n)
        }
        return buffer.toByteArray()
    }
}
