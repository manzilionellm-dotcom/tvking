package com.example.tv_king

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import android.util.Rational
import android.view.KeyEvent
import com.manzilionellm.native_video_player.logic.AppForeground
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Activité Zuno. Sur téléphone, Home conserve la vidéo dans une petite
 * fenêtre. Sur TV, ou sans vidéo locale, le comportement d'arrêt reste le
 * même : le son s'arrête dans le cycle Android, sans attendre Flutter.
 *
 * La règle (dialogue / overlay / Home) est dans [AppForeground].
 * Ce canal PiP est distinct de celui du service Cast : celui-ci continue
 * de garder sa session distante, sans intervenir dans la vidéo locale.
 */
class MainActivity : FlutterFragmentActivity() {
    private var pipChannel: MethodChannel? = null
    private var playbackActive = false
    private var activityVisible = false
    private var videoRatio = Rational(16, 9)
    private var flutterUiDisplayed = false
    private val startupUiListener = object : FlutterUiDisplayListener {
        override fun onFlutterUiDisplayed() {
            flutterUiDisplayed = true
            Log.i("ZunoStartup", "native.flutterUiDisplayed")
            focusFlutterViewIfNeeded()
        }
        override fun onFlutterUiNoLongerDisplayed() {
            flutterUiDisplayed = false
            Log.i("ZunoStartup", "native.flutterUiHidden")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.i("ZunoStartup", "native.plugins.begin")
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(startupUiListener)
        Log.i("ZunoStartup", "native.plugins.end")
        FieldKeyNav.channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.sevenmotion.zuno/field_keys",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setArmed" -> {
                        FieldKeyNav.armed = call.arguments == true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.sevenmotion.zuno/pip",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPipSupported" -> result.success(supportsPhonePip())
                    "setPlaybackActive" -> {
                        // Flutter n'arme Home que pour la vidéo locale en
                        // lecture. Un Cast actif ou une pause le désarme.
                        playbackActive = call.argument<Boolean>("active") == true
                        result.success(true)
                    }
                    "setAspectRatio" -> {
                        val num = call.argument<Number>("num")?.toDouble() ?: 16.0
                        val den = call.argument<Number>("den")?.toDouble() ?: 9.0
                        val ratio = num / den
                        // Android refuse les proportions extrêmes. On garde
                        // les vidéos verticales sans provoquer d'exception.
                        val bounded = if (ratio.isFinite() && ratio > 0.0) {
                            ratio.coerceIn(0.42, 2.39)
                        } else {
                            16.0 / 9.0
                        }
                        videoRatio = Rational((bounded * 10000).roundToInt(), 10000)
                        result.success(updatePipParams())
                    }
                    "enterPip" -> result.success(enterPhonePip())
                    "isInPipMode" -> result.success(physicalPipMode())
                    // Un seul instantané évite qu'un retour plein écran
                    // mélange le mode d'avant et la visibilité d'après.
                    "getPipState" -> result.success(pipState())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (FieldKeyNav.onKey(event)) return true
        return super.dispatchKeyEvent(event)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        flutterEngine.renderer.removeIsDisplayingFlutterUiListener(startupUiListener)
        flutterUiDisplayed = false
        // Ne jamais retirer le canal historique du service Cast.
        FieldKeyNav.channel?.setMethodCallHandler(null)
        FieldKeyNav.channel = null
        FieldKeyNav.armed = false
        pipChannel?.setMethodCallHandler(null)
        pipChannel = null
        playbackActive = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun focusFlutterViewIfNeeded() {
        // Le focus Dart d'un bouton ne donne pas le focus à sa vue Android.
        // Sans cible native, Android consomme la première flèche pour choisir
        // cette vue : Bas/Bas/OK peut atteindre Redémarrer au lieu de Quitter.
        // Ne jamais prendre le focus d'une autre vue ni pendant une lecture.
        if (!flutterUiDisplayed || !hasWindowFocus() || currentFocus != null ||
            playbackActive || physicalPipMode() || isFinishing || isDestroyed
        ) return
        val flutterView = findViewById<FlutterView>(FlutterFragment.FLUTTER_VIEW_ID)
            ?: return
        if (!flutterView.isAttachedToWindow || !flutterView.isShown) return
        disableNativeFocusHighlight()
        if (flutterView.requestFocus()) {
            Log.i("ZunoStartup", "native.flutterViewFocused")
        }
    }

    // Flutter dessine son propre focus. Sinon, hors mode tactile, Android
    // peint autour de toute l'app le liseré de focus du thème (cadre vert
    // de Theme.Black) dès que la vue Flutter a le focus natif.
    private fun disableNativeFocusHighlight() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        findViewById<FlutterView>(FlutterFragment.FLUTTER_VIEW_ID)
            ?.defaultFocusHighlightEnabled = false
    }

    private fun supportsPhonePip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val mode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val television = mode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        return !television &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun physicalPipMode(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode

    private fun pipState(): Map<String, Boolean> = mapOf(
        "inPip" to physicalPipMode(),
        "visible" to activityVisible,
    )

    private fun publishPipState() {
        pipChannel?.invokeMethod("onPipModeChanged", pipState())
    }

    private fun updatePipParams(): Boolean {
        if (!supportsPhonePip()) return false
        return try {
            setPictureInPictureParams(
                PictureInPictureParams.Builder().setAspectRatio(videoRatio).build(),
            )
            true
        } catch (_: RuntimeException) {
            // PiP peut être désactivé par le système ou le constructeur.
            false
        }
    }

    private fun enterPhonePip(): Boolean {
        if (!playbackActive || !activityVisible || !supportsPhonePip() ||
            isFinishing || isDestroyed
        ) return false
        if (physicalPipMode()) return true
        return try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(videoRatio).build(),
            )
        } catch (_: RuntimeException) {
            // Refus de l'autorisation PiP : Home reste un arrêt normal.
            false
        }
    }

    override fun onUserLeaveHint() {
        // PiP conserve la même surface et le même décodeur. Ne pas annoncer
        // USER_LEAVE dans ce cas : onPause ne doit pas couper l'AudioTrack.
        if (!enterPhonePip()) AppForeground.onUserLeaveHint()
        super.onUserLeaveHint()
    }

    override fun onStart() {
        super.onStart()
        // Avant le premier focus natif : au D-pad, Android le donne à la
        // vue Flutter dès l'ajout de la fenêtre.
        disableNativeFocusHighlight()
        activityVisible = true
        // Après extinction puis rallumage de l'écran, une fenêtre PiP
        // redevient visible sans recevoir forcément onResume.
        if (physicalPipMode()) AppForeground.onResume()
        publishPipState()
    }

    override fun onPause() {
        if (!physicalPipMode()) AppForeground.onPause()
        super.onPause()
    }

    override fun onStop() {
        // Écran éteint ou fenêtre fermée : elle n'est plus visible, même
        // si Android garde momentanément son drapeau PiP à vrai.
        activityVisible = false
        AppForeground.onStop()
        publishPipState()
        super.onStop()
    }

    override fun onResume() {
        // Avant Flutter : une seule reprise, le message « resumed » en
        // retard ne doit pas en lancer une deuxième.
        AppForeground.onResume()
        activityVisible = true
        super.onResume()
        publishPipState()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Ne pas forcer visible=true ici : une fermeture peut annoncer la
        // sortie PiP après onStop, alors que la vidéo doit rester arrêtée.
        publishPipState()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Focus perdu seul = overlay encore sur l'app. On ne coupe pas.
        AppForeground.onWindowFocus(hasFocus)
        // La fenêtre peut obtenir son focus après la première image Flutter.
        if (hasFocus) focusFlutterViewIfNeeded()
    }
}
