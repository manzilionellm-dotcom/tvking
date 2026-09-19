package com.manzilionellm.tvking_miroir

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Capture d'écran SYSTÈME (MediaProjection) pour l'assistance à distance.
 *
 * Channel : `com.manzilionellm.tvking/miroir`
 *   disponible  -> Boolean   : l'appareil sait-il projeter son écran ?
 *   demander    -> Boolean   : affiche la boîte de dialogue d'Android ;
 *                              répond `true` quand le client a accepté,
 *                              `false` s'il a refusé ou si ça a échoué.
 *   capturer    -> ByteArray : un JPEG de l'écran, ou null si rien de
 *                              nouveau / pas de projection.
 *   arreter     -> null      : libère tout (fin de session).
 *
 * LE FIL DE LA CAPTURE, dans l'ordre imposé par Android :
 *   1. démarrer le service au premier plan typé mediaProjection
 *      ([MiroirService]) — obligatoire sur Android 10+, sinon
 *      SecurityException à l'étape 3 ;
 *   2. lancer l'intent de consentement du système ; le client accepte
 *      à la télécommande ;
 *   3. dans onActivityResult, fabriquer la MediaProjection, un
 *      ImageReader (RGBA) et un VirtualDisplay RÉDUIT (≈ 420 px de
 *      large) : Android compose directement à cette taille, pas de
 *      redimensionnement à faire côté app ;
 *   4. `capturer` prend la dernière image, la met dans un Bitmap et la
 *      compresse en JPEG (natif : quelques millisecondes).
 *
 * TOUT EST FAIL-SOFT. Rien ici ne doit jamais faire tomber l'app du
 * client pendant qu'on l'aide : chaque étape rend `false` / `null` et
 * un log, jamais une exception qui remonte.
 */
class TvkingMiroirPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val TAG = "TvkingMiroir"
        private const val CHANNEL = "com.manzilionellm.tvking/miroir"
        private const val REQ_PROJECTION = 7318

        /** Plus grand côté de l'image envoyée au panel.
         *
         *  960 px, et pas 420 comme le miroir Flutter : le propriétaire a
         *  vu son écran arriver (19/09 au soir) et a tranché — « l'écran
         *  doit être géant et lisible ». À 420 px, agrandi dans le panel,
         *  le texte des menus devient de la bouillie. À 960 px on lit un
         *  menu TV comme sur la télé.
         *
         *  On borne le PLUS GRAND côté, pas la largeur : une box (paysage)
         *  donne 960×540, un téléphone (portrait) 432×960. Borner la
         *  largeur ferait un téléphone en 960×2133 — inutile et lourd.
         *
         *  Le JPEG est natif (Bitmap.compress), donc la taille ne coûte
         *  presque rien au processeur ; elle coûte des octets sur la ligne
         *  du client : ~60 à 120 Ko toutes les 2 s. Accepté pour une
         *  session de dépannage. */
        private const val COTE_MAX = 960

        /** Qualité JPEG. 50 : texte parfaitement lisible à 960 px, et
         *  assez léger pour tenir ~3 images/s (« l'écran doit être
         *  fluide ») ; on n'envoie pas une photo, on envoie un menu. */
        private const val QUALITE_JPEG = 50
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var largeur = 0
    private var hauteur = 0

    /** La réponse Dart en attente pendant que la boîte de dialogue est
     *  affichée. Une seule à la fois : une seconde demande pendant la
     *  première est refusée tout de suite. */
    private var demandeEnAttente: MethodChannel.Result? = null

    private val main = Handler(Looper.getMainLooper())
    private val encodeur = Executors.newSingleThreadExecutor()

    // ---------------------------------------------------------------
    //  Cycle de vie plugin / activité
    // ---------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        liberer()
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // ---------------------------------------------------------------
    //  Appels Dart
    // ---------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "disponible" -> result.success(disponible())
            "demander" -> demander(result)
            "capturer" -> capturer(result)
            "arreter" -> {
                liberer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun disponible(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val ctx = appContext ?: return false
        val mgr = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as? MediaProjectionManager
        if (mgr == null) return false
        // LE SERVICE EST-IL DÉCLARÉ ? Le build Play Store (AAB) le retire
        // du manifeste, avec la permission FOREGROUND_SERVICE_MEDIA_PROJECTION,
        // pour ne pas avoir à déclarer la capture d'écran à Google (voir
        // build-android.yml, « (b ter) »). Sans service typé, une projection
        // est impossible depuis Android 10 : on le dit TOUT DE SUITE, et le
        // Dart passe à la capture Flutter — plutôt que d'afficher au client
        // une boîte de dialogue système qui n'aboutirait à rien.
        return try {
            ctx.packageManager.getServiceInfo(
                ComponentName(ctx, MiroirService::class.java), 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            Log.i(TAG, "MiroirService absent du manifeste (build Play) → capture native indisponible")
            false
        } catch (e: Throwable) {
            Log.w(TAG, "getServiceInfo : $e")
            false
        }
    }

    /**
     * Étapes 1 et 2 : le service, puis la boîte de dialogue du système.
     * La réponse à Dart part depuis [onActivityResult].
     */
    private fun demander(result: MethodChannel.Result) {
        val activity: Activity? = activityBinding?.activity
        val ctx = appContext
        if (activity == null || ctx == null) {
            result.success(false)
            return
        }
        if (demandeEnAttente != null) {
            // Une boîte de dialogue est déjà à l'écran : on ne l'empile
            // pas, le client ne saurait plus à quoi il répond.
            result.success(false)
            return
        }
        if (projection != null) {
            // Déjà autorisé pour cette session : inutile de redemander.
            result.success(true)
            return
        }
        val mgr = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as? MediaProjectionManager
        if (mgr == null) {
            result.success(false)
            return
        }
        // Étape 1 — le service typé, AVANT la projection (Android 10+).
        if (!MiroirService.start(ctx)) {
            result.success(false)
            return
        }
        // Étape 2 — la question, posée par Android lui-même.
        try {
            demandeEnAttente = result
            activity.startActivityForResult(mgr.createScreenCaptureIntent(), REQ_PROJECTION)
        } catch (e: Throwable) {
            Log.w(TAG, "createScreenCaptureIntent : $e")
            demandeEnAttente = null
            MiroirService.stop(ctx)
            result.success(false)
        }
    }

    /** Étape 3 : la réponse du client. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PROJECTION) return false
        val attente = demandeEnAttente
        demandeEnAttente = null
        val ctx = appContext
        if (resultCode != Activity.RESULT_OK || data == null || ctx == null) {
            // Le client a dit non (ou a fermé la boîte) : on range tout,
            // et le panel le saura par le `false`.
            if (ctx != null) MiroirService.stop(ctx)
            attente?.success(false)
            return true
        }
        val ok = try {
            ouvrirProjection(ctx, resultCode, data)
        } catch (e: Throwable) {
            Log.e(TAG, "ouvrirProjection : $e")
            false
        }
        if (!ok) {
            liberer()
        }
        attente?.success(ok)
        return true
    }

    private fun ouvrirProjection(ctx: Context, code: Int, data: Intent): Boolean {
        val mgr = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as? MediaProjectionManager ?: return false
        val p = mgr.getMediaProjection(code, data) ?: return false

        // Android 14 exige un callback enregistré AVANT createVirtualDisplay,
        // sinon IllegalStateException. Il sert aussi à ranger proprement si
        // le système coupe la projection (l'utilisateur l'arrête depuis la
        // barre système, par exemple).
        p.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.i(TAG, "projection arrêtée par le système")
                main.post { liberer() }
            }
        }, main)

        // Taille RÉDUITE dès la source : Android compose directement à la
        // taille demandée. Pas de redimensionnement à faire côté app.
        // On borne le PLUS GRAND côté à COTE_MAX (voir la constante) ; on
        // ne grossit jamais un écran plus petit que ça.
        val dm: DisplayMetrics = ctx.resources.displayMetrics
        val plusGrand = maxOf(dm.widthPixels, dm.heightPixels).coerceAtLeast(1)
        val ratio = (COTE_MAX.toFloat() / plusGrand.toFloat()).coerceAtMost(1f)
        largeur = (dm.widthPixels * ratio).toInt().coerceAtLeast(2)
        hauteur = (dm.heightPixels * ratio).toInt().coerceAtLeast(2)
        // Certains encodeurs veulent des dimensions paires.
        if (largeur % 2 != 0) largeur -= 1
        if (hauteur % 2 != 0) hauteur -= 1

        val reader = ImageReader.newInstance(largeur, hauteur, PixelFormat.RGBA_8888, 2)
        val vd = p.createVirtualDisplay(
            "7motion_miroir",
            largeur,
            hauteur,
            dm.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            main,
        ) ?: return false

        projection = p
        imageReader = reader
        virtualDisplay = vd
        Log.i(TAG, "projection ouverte ${largeur}x${hauteur}")
        return true
    }

    /**
     * Étape 4 : la dernière image, en JPEG. Répond `null` s'il n'y a pas
     * de projection ou pas d'image neuve — jamais une exception.
     *
     * L'encodage tourne sur un thread à part : quelques millisecondes,
     * mais on ne bloque pas le thread UI de la box pour ça.
     */
    private fun capturer(result: MethodChannel.Result) {
        val reader = imageReader
        if (reader == null || projection == null) {
            result.success(null)
            return
        }
        val image = try {
            reader.acquireLatestImage()
        } catch (e: Throwable) {
            Log.w(TAG, "acquireLatestImage : $e")
            null
        }
        if (image == null) {
            result.success(null)
            return
        }
        // On copie les pixels MAINTENANT (sur le thread appelant) puis on
        // libère l'image : l'ImageReader n'en a que 2 en réserve, la garder
        // pendant l'encodage bloquerait la suivante.
        val w = image.width
        val h = image.height
        val plane = image.planes[0]
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * w
        val bmp = try {
            // Le buffer peut être plus large que l'image (padding de ligne) :
            // on crée le bitmap à la largeur « stride » puis on recadre.
            val large = Bitmap.createBitmap(w + rowPadding / pixelStride, h, Bitmap.Config.ARGB_8888)
            large.copyPixelsFromBuffer(plane.buffer)
            if (rowPadding == 0) large else Bitmap.createBitmap(large, 0, 0, w, h).also { large.recycle() }
        } catch (e: Throwable) {
            Log.w(TAG, "bitmap : $e")
            null
        } finally {
            try { image.close() } catch (_: Throwable) {}
        }
        if (bmp == null) {
            result.success(null)
            return
        }
        encodeur.execute {
            val octets = try {
                ByteArrayOutputStream().use { out ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, QUALITE_JPEG, out)
                    out.toByteArray()
                }
            } catch (e: Throwable) {
                Log.w(TAG, "jpeg : $e")
                null
            } finally {
                bmp.recycle()
            }
            main.post { result.success(octets) }
        }
    }

    /** Fin de session : on rend TOUT, dans l'ordre inverse de l'ouverture. */
    private fun liberer() {
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (_: Throwable) {}
        imageReader = null
        try { projection?.stop() } catch (_: Throwable) {}
        projection = null
        appContext?.let { MiroirService.stop(it) }
        // Une demande restée sans réponse (activité détruite pendant la
        // boîte de dialogue) : on répond `false` plutôt que de laisser
        // Dart attendre pour toujours.
        demandeEnAttente?.let { r ->
            demandeEnAttente = null
            try { r.success(false) } catch (_: Throwable) {}
        }
    }
}
