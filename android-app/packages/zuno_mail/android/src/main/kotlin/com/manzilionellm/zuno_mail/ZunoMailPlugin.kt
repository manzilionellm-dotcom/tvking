// =========================================================
//  ZunoMailPlugin.kt — intent e-mail, rien d'autre
// =========================================================
//  Ouvre l'application e-mail déjà installée :
//    • ACTION_SENDTO mailto: si le corps tient dans l'intent ;
//    • ACTION_SEND + FileProvider si Dart a préparé un .txt.
//
//  L'adresse est fixe. On n'accepte pas une autre en argument :
//  le canal ne doit pas pouvoir rediriger le rapport.
//  Aucun identifiant, aucun serveur de courrier.
//
//  Toute exception est avalée. Une box sans application e-mail
//  répond « no_app ». Zuno reste ouvert.
// =========================================================

package com.manzilionellm.zuno_mail

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.TransactionTooLargeException
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ZunoMailPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "open") {
            result.notImplemented()
            return
        }
        // On répond toujours une chaîne. Dart ne doit pas recevoir une exception.
        val status = try {
            openMail(
                subject = call.argument<String>("subject"),
                body = call.argument<String>("body"),
                filePath = call.argument<String>("filePath"),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "ouverture e-mail interrompue : ${t.javaClass.simpleName}")
            "error"
        }
        result.success(status)
    }

    private fun openMail(subject: String?, body: String?, filePath: String?): String {
        val act = activity ?: return "error"
        if (act.isFinishing || act.isDestroyed) return "error"
        val text = body ?: ""
        val title = oneLine(subject)
        val file = reportFile(act, filePath)
        if (file == null && text.length > HARD_BODY_CHARS) return "too_large"
        val handlers = emailHandlers(act)
        if (handlers.isEmpty()) return "no_app"
        val intent = if (file != null) {
            sendWithFile(act, title, text, file) ?: return "error"
        } else {
            sendBody(title, text)
        }
        return launch(act, intent, handlers)
    }

    private fun sendBody(subject: String, body: String): Intent {
        val encodedSubject = Uri.encode(subject)
        val encodedBody = Uri.encode(body)
        val withQuery = "mailto:$RECIPIENT?subject=$encodedSubject&body=$encodedBody"
        val intent = Intent(Intent.ACTION_SENDTO)
        if (withQuery.length <= MAX_MAILTO_URI) {
            intent.data = Uri.parse(withQuery)
        } else {
            // Le corps reste dans les extras. L'adresse, elle, reste dans le mailto
            // pour que seules les applications e-mail se proposent.
            intent.data = Uri.parse("mailto:$RECIPIENT")
            intent.putExtra(Intent.EXTRA_SUBJECT, subject)
            intent.putExtra(Intent.EXTRA_TEXT, body)
        }
        intent.putExtra(Intent.EXTRA_EMAIL, arrayOf(RECIPIENT))
        return intent
    }

    private fun sendWithFile(context: Context, subject: String, body: String, file: File): Intent? {
        val uri = try {
            FileProvider.getUriForFile(context, "${context.packageName}.zuno.soundreport", file)
        } catch (t: Throwable) {
            Log.w(TAG, "FileProvider a refusé le fichier : ${t.javaClass.simpleName}")
            return null
        }
        val send = Intent(Intent.ACTION_SEND)
        send.type = "text/plain"
        send.putExtra(Intent.EXTRA_EMAIL, arrayOf(RECIPIENT))
        send.putExtra(Intent.EXTRA_SUBJECT, subject)
        send.putExtra(Intent.EXTRA_TEXT, body)
        send.putExtra(Intent.EXTRA_STREAM, uri)
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newUri(context.contentResolver, "Rapport son", uri)
        // Le sélecteur ne montre que les applications mailto, pas toutes
        // les applications qui savent partager un texte.
        send.selector = Intent(Intent.ACTION_SENDTO).setData(Uri.parse("mailto:"))
        return send
    }

    private fun launch(act: Activity, intent: Intent, handlers: List<ResolveInfo>): String {
        grantRead(act, intent, handlers)
        if (handlers.size == 1) {
            // Une seule application : on l'ouvre directement. Le sélecteur
            // gênerait setPackage, on le retire.
            intent.selector = null
            val pkg = handlers[0].activityInfo?.packageName
            if (!pkg.isNullOrEmpty()) intent.setPackage(pkg)
            return start(act, intent)
        }
        return try {
            val chooser = Intent.createChooser(intent, "Envoyer le rapport son")
            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (intent.clipData != null) chooser.clipData = intent.clipData
            act.startActivity(chooser)
            "opened"
        } catch (t: Throwable) {
            if (isTooLarge(t)) return "too_large"
            // Le sélecteur est refusé par quelques versions d'Android.
            // On réessaie sans lui : les applications e-mail sont déjà
            // les seules qu'on a listées, et le corps part quand même.
            intent.selector = null
            start(act, intent)
        }
    }

    private fun start(act: Activity, intent: Intent): String {
        return try {
            act.startActivity(intent)
            "opened"
        } catch (e: ActivityNotFoundException) {
            "no_app"
        } catch (e: TransactionTooLargeException) {
            "too_large"
        } catch (t: Throwable) {
            if (isTooLarge(t)) "too_large"
            else {
                Log.w(TAG, "startActivity : ${t.javaClass.simpleName}")
                "error"
            }
        }
    }

    private fun grantRead(act: Activity, intent: Intent, handlers: List<ResolveInfo>) {
        val uri = streamUri(intent) ?: return
        for (info in handlers) {
            val pkg = info.activityInfo?.packageName ?: continue
            try {
                act.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (t: Throwable) {
                Log.w(TAG, "partage du fichier refusé pour $pkg")
            }
        }
    }

    private fun streamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }

    /**
     * Le fichier doit être le .txt du cache sound-report. On ne donne
     * pas un URI pour un autre chemin, même si Dart le demandait.
     */
    private fun reportFile(context: Context, path: String?): File? {
        if (path.isNullOrBlank()) return null
        return try {
            val cache = File(context.cacheDir, "sound-report").canonicalFile
            val file = File(path).canonicalFile
            if (file.parentFile?.canonicalFile != cache) null
            else if (file.name != "rapport-son.txt") null
            else if (!file.isFile) null
            else file
        } catch (t: Throwable) {
            null
        }
    }

    private fun emailHandlers(context: Context): List<ResolveInfo> {
        val probe = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val pm = context.packageManager
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(probe, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(probe, 0)
            }
        } catch (t: Throwable) {
            emptyList()
        }
    }

    private fun oneLine(raw: String?): String {
        if (raw.isNullOrBlank()) return "Rapport son Zuno"
        val cleaned = raw.replace(Regex("[\\r\\n]"), " ").trim()
        return if (cleaned.length > 180) cleaned.substring(0, 180) else cleaned
    }

    private fun isTooLarge(t: Throwable): Boolean {
        var cur: Throwable? = t
        while (cur != null) {
            if (cur is TransactionTooLargeException) return true
            if (cur.javaClass.name.contains("TransactionTooLarge")) return true
            cur = cur.cause
        }
        return false
    }

    companion object {
        private const val TAG = "ZunoMail"
        const val CHANNEL = "com.manzilionellm.zuno/mail"
        const val RECIPIENT = "manzilionel.lm@gmail.com"

        /** Corps au-delà : on ne tente même pas l'intent sans fichier. */
        private const val HARD_BODY_CHARS = 120_000

        /** mailto: trop long pour certaines box. On bascule sur les extras. */
        private const val MAX_MAILTO_URI = 60_000
    }
}
