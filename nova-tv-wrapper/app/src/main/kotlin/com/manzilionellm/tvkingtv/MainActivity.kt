// =========================================================
//  MainActivity.kt — Activity unique de 7 MOTION TV (wrapper)
// =========================================================
//  Ouvre une WebView plein ecran qui charge les assets statiques
//  embarques sous `/assets/web/`. Le React tv-web s'occupe du
//  reste (lecteur, navigation, EPG, etc.).
//
//  Pourquoi WebViewAssetLoader plutot que file:///android_asset/ ?
//    - Une page sur le scheme `file:` est traitee en origine "null",
//      ce qui casse localStorage / modules / fetch. WebViewAssetLoader
//      sert les memes assets sous `https://appassets.androidplatform.net/`
//      -> origine HTTPS stable, tout le web standard fonctionne.
//
//  Pourquoi un PROXY natif dans shouldInterceptRequest ? (CRITIQUE)
//    - Les serveurs Xtream/M3U ne renvoient JAMAIS d'en-tetes CORS
//      (Access-Control-Allow-Origin). Un `fetch()` du WebView (origine
//      https://appassets...) vers `http://serveur-iptv/get.php` est donc
//      BLOQUE par la Same-Origin Policy -> "Failed to fetch", 0 chaine.
//    - La couche reseau NATIVE (HttpURLConnection) n'a pas de SOP. On
//      intercepte donc chaque requete externe, on la rejoue nativement,
//      et on RENVOIE la reponse en y AJOUTANT `Access-Control-Allow-Origin: *`.
//      Le WebView voit alors une reponse "CORS-autorisee" -> playlist, EPG
//      ET segments video (hls.js) passent. C'est LE correctif du chargement.
//
//  Pourquoi onKeyDown override ?
//    - La telecommande Android TV envoie KEYCODE_BACK = bouton
//      "Retour" rouge. Par defaut, ca quitte l'Activity. On veut
//      d'abord essayer webView.goBack() si on a un historique de
//      navigation interne (utile quand on aura plusieurs vues
//      React).
// =========================================================

package com.manzilionellm.tvkingtv

import android.annotation.SuppressLint
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.WebViewAssetLoader
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "TvKingTV"
        /**
         * URL de boot servie par WebViewAssetLoader. Pointe vers
         * `assets/web/index.html` que le build CI vient d'y deposer
         * depuis tv-web/dist/.
         */
        private const val APP_URL = "https://appassets.androidplatform.net/assets/web/index.html"

        /**
         * User-Agent "lecteur" pour les requetes IPTV proxifiees. Beaucoup de
         * panels/CDN n'acceptent que des UA de lecteur (et bloquent les UA de
         * navigateur). VLC est le plus universellement accepte.
         */
        private const val PLAYER_UA = "VLC/3.0.20 LibVLC/3.0.20"

        /**
         * En-tetes de reponse a NE PAS reporter au WebView via le proxy :
         *  - content-type : passe separement au constructeur (mime+charset).
         *  - content-encoding/content-length/transfer-encoding : HttpURLConnection
         *    a deja decompresse/normalise le flux ; les reporter ferait attendre
         *    au WebView des octets gzip/une longueur fausse -> flux casse.
         *  - connection : hop-by-hop, sans objet ici.
         *  - access-control-* : on impose les notres (corsHeaders).
         */
        private val DROP_RESPONSE_HEADERS = setOf(
            "content-type", "content-encoding", "content-length",
            "transfer-encoding", "connection",
            "access-control-allow-origin", "access-control-allow-methods",
            "access-control-allow-headers", "access-control-expose-headers",
        )
    }

    private lateinit var webView: WebView
    private lateinit var assetLoader: WebViewAssetLoader

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Plein ecran "lean-back" — pas de barre de statut, pas de
        // navbar systeme. C'est la convention sur Android TV.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
        )
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )

        assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        webView = WebView(this).apply {
            // Necessaire pour React + hls.js
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            // Permet aux flux video <video> de jouer sans interaction
            // utilisateur (= autoplay). Android TV n'a pas la meme
            // contrainte que les navigateurs mobiles.
            settings.mediaPlaybackRequiresUserGesture = false
            // Cache reseau modere — accelere les re-loads de l'app.
            settings.cacheMode = android.webkit.WebSettings.LOAD_DEFAULT
            // Le viewport vient du <meta viewport> de index.html.
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            // CRITIQUE : la page est servie en https:// (appassets) mais les
            // flux IPTV (Xtream/M3U) sont en http://. Sans ceci, la WebView
            // BLOQUE le "contenu mixte" -> "Failed to fetch" sur la playlist
            // et les segments. On autorise le mixte pour que l'IPTV charge.
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW

            // Pont natif : expose à l'app web un identifiant d'appareil STABLE
            // (ANDROID_ID). Il survit à la désinstallation/réinstallation tant
            // que la clé de signature ne change pas -> le MAC virtuel reste le
            // MÊME -> le client ne "rachète" pas l'app après une réinstall.
            addJavascriptInterface(NovaBridge(this@MainActivity), "NovaNative")

            // Intercepter les requetes :
            //  - host appassets -> servir /assets/web/ via l'AssetLoader.
            //  - http(s) externe -> PROXY natif (ajoute le CORS) cf. proxyRequest().
            //  - autre (data:, blob:, ...) -> laisser passer (null).
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    val url = request.url
                    if (url.host == "appassets.androidplatform.net") {
                        return assetLoader.shouldInterceptRequest(url)
                    }
                    val scheme = url.scheme?.lowercase()
                    if (scheme == "http" || scheme == "https") {
                        return proxyRequest(request)
                    }
                    return null
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: android.webkit.WebResourceError?,
                ) {
                    super.onReceivedError(view, request, error)
                    Log.w(TAG, "onReceivedError ${request?.url}: ${error?.description}")
                }
            }

            // Remonte les console.log() / console.error() du JS dans
            // Logcat — indispensable pour debugger sur device sans
            // chrome://inspect.
            webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(msg: ConsoleMessage): Boolean {
                    val level = when (msg.messageLevel()) {
                        ConsoleMessage.MessageLevel.ERROR -> Log.ERROR
                        ConsoleMessage.MessageLevel.WARNING -> Log.WARN
                        ConsoleMessage.MessageLevel.DEBUG -> Log.DEBUG
                        else -> Log.INFO
                    }
                    Log.println(
                        level,
                        TAG,
                        "[web] ${msg.message()} (${msg.sourceId()}:${msg.lineNumber()})",
                    )
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl(APP_URL)
        Log.i(TAG, "Loaded $APP_URL")
    }

    /**
     * Proxy natif d'une requete externe : rejoue la requete via
     * HttpURLConnection (aucune Same-Origin Policy cote natif) et renvoie la
     * reponse au WebView en y AJOUTANT les en-tetes CORS. C'est ce qui debloque
     * playlist / EPG / segments video servis par des serveurs IPTV sans CORS.
     *
     * Tourne sur un thread de travail du WebView (pas l'UI) -> l'I/O bloquante
     * est autorisee ici.
     */
    private fun proxyRequest(request: WebResourceRequest): WebResourceResponse? {
        val method = (request.method ?: "GET").uppercase()

        // Pre-vol CORS : on repond OK sans toucher au reseau.
        if (method == "OPTIONS") {
            return WebResourceResponse(
                "text/plain", "utf-8", 200, "OK",
                corsHeaders(), ByteArrayInputStream(ByteArray(0)),
            )
        }

        return try {
            val conn = (URL(request.url.toString()).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                instanceFollowRedirects = true
                connectTimeout = 20_000
                readTimeout = 30_000
                // CRITIQUE : on se presente comme un LECTEUR, pas un navigateur.
                // Les CDN IPTV (souvent derriere Cloudflare) RESET/refusent les
                // requetes au profil "navigateur" (UA Chrome + en-tetes Origin /
                // Sec-Fetch-* / sec-ch-ua que le WebView ajoute), ce qui remonte
                // en 502 cote app. Une vraie app IPTV envoie un UA de lecteur et
                // des en-tetes minimaux -> on imite ce comportement : UA lecteur,
                // Accept */*, et on ne reporte QUE Range (utile aux segments video).
                setRequestProperty("User-Agent", PLAYER_UA)
                setRequestProperty("Accept", "*/*")
                for ((k, v) in request.requestHeaders) {
                    if (k.equals("Range", true)) setRequestProperty("Range", v)
                }
            }
            conn.connect()

            val status = conn.responseCode
            if (status < 100) return errorResponse("Bad status $status")

            // Content-Type -> mime + charset (le constructeur les veut separes).
            val ct = conn.contentType
            val mime = ct?.substringBefore(";")?.trim()?.ifBlank { null } ?: "application/octet-stream"
            val enc = ct?.substringAfter("charset=", "")?.trim()?.ifBlank { null }

            // En-tetes de reponse : CORS d'abord, puis ceux du serveur — en
            // ECARTANT ceux qui fausseraient la lecture du flux par le WebView.
            val headers = corsHeaders().toMutableMap()
            for ((k, vs) in conn.headerFields) {
                if (k == null || k.lowercase() in DROP_RESPONSE_HEADERS) continue
                headers[k] = vs.joinToString(", ")
            }

            val noBody = status == 204 || status == 304 || method == "HEAD"
            val body: InputStream =
                if (noBody) ByteArrayInputStream(ByteArray(0))
                else if (status >= 400) (conn.errorStream ?: conn.inputStream)
                else conn.inputStream

            WebResourceResponse(mime, enc, status, reasonFor(status, conn.responseMessage), headers, body)
        } catch (e: Exception) {
            // Message detaille (classe + cause) -> remonte dans le corps du 502,
            // que l'app affiche a l'ecran : "Unable to resolve host",
            // "Failed to connect to .../X.X.X.X:80", "timeout", etc.
            val detail = "${e.javaClass.simpleName}: ${e.message ?: "?"}"
            Log.w(TAG, "proxy fail ${request.url}: $detail")
            // 502 (avec CORS) plutot que null : le fetch JS se resout en "HTTP 502"
            // au lieu d'un "Failed to fetch" opaque -> diagnostic plus clair.
            errorResponse(detail)
        }
    }

    private fun corsHeaders(): MutableMap<String, String> = mutableMapOf(
        "Access-Control-Allow-Origin" to "*",
        "Access-Control-Allow-Methods" to "GET, POST, HEAD, OPTIONS",
        "Access-Control-Allow-Headers" to "*",
        "Access-Control-Expose-Headers" to "*",
    )

    private fun errorResponse(msg: String): WebResourceResponse =
        WebResourceResponse(
            "text/plain", "utf-8", 502, "Proxy Error",
            corsHeaders(), ByteArrayInputStream(msg.toByteArray()),
        )

    /** Reason phrase non vide et sans retour ligne (exige par WebResourceResponse). */
    private fun reasonFor(status: Int, raw: String?): String {
        val clean = raw?.replace(Regex("[\\r\\n]"), " ")?.trim()
        return if (!clean.isNullOrBlank()) clean else "Status $status"
    }

    /**
     * Telecommande Android TV : on intercepte BACK pour permettre
     * une navigation interne React. Si la WebView n'a pas
     * d'historique, on laisse le BACK quitter l'Activity (comportement
     * standard attendu par l'utilisateur).
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        // Nettoie la WebView pour ne pas garder une session live audio
        // si l'utilisateur a coupe l'app brutalement.
        webView.stopLoading()
        webView.removeAllViews()
        webView.destroy()
        super.onDestroy()
    }
}

/**
 * Pont JS exposé sous `window.NovaNative`. Fournit l'identifiant matériel
 * STABLE de l'appareil (ANDROID_ID) dont l'app web dérive son MAC virtuel.
 * ANDROID_ID est constant pour un (appareil + clé de signature) donné : il
 * survit à la désinstallation/réinstallation, donc le code d'activation ne
 * change pas et le client n'a pas à réactiver / racheter.
 */
class NovaBridge(private val ctx: Context) {
    @JavascriptInterface
    fun getDeviceId(): String {
        return try {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (_: Exception) {
            ""
        }
    }
}
