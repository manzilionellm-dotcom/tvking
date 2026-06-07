// =========================================================
//  MainActivity.kt — Activity unique de 7 MOTION TV (wrapper)
// =========================================================
//  Ouvre une WebView plein ecran qui charge les assets statiques
//  embarques sous `/assets/web/`. Le React tv-web s'occupe du
//  reste (lecteur, navigation, EPG, etc.).
//
//  Pourquoi WebViewAssetLoader plutot que file:///android_asset/ ?
//    - Les flux IPTV (XHR vers serveur Xtream HTTP) sont bloques
//      par la SOP (Same Origin Policy) si la page est sur le
//      scheme `file:`. WebViewAssetLoader sert les memes assets
//      sous `https://appassets.androidplatform.net/` -> la SOP
//      voit du HTTPS et n'interfere pas avec les XHR cross-origin
//      (controlees par les en-tetes CORS du serveur IPTV).
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

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "TvKingTV"
        /**
         * URL de boot servie par WebViewAssetLoader. Pointe vers
         * `assets/web/index.html` que le build CI vient d'y deposer
         * depuis tv-web/dist/.
         */
        private const val APP_URL = "https://appassets.androidplatform.net/assets/web/index.html"
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

            // Intercepter les requetes pour servir /assets/web/ via
            // l'AssetLoader (sinon WebView fait du 404 sur l'URL HTTPS
            // synthetique). Toute autre requete (XHR vers IPTV) passe
            // a travers normalement.
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    return assetLoader.shouldInterceptRequest(request.url)
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
