package com.sevenmotion.zuno_cast

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.content.pm.PackageManager
import com.manzilionellm.tvking.GoogleCastApi
import com.manzilionellm.tvking.MulticastLockBridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/** Le téléphone émet ; une box reste un lecteur. Aucun scan au démarrage. */
class ZunoCastPlugin : FlutterPlugin, ActivityAware {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var capability: MethodChannel? = null
    private var cast: GoogleCastApi? = null
    private var multicast: MulticastLockBridge? = null
    private var handset = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        val context = binding.applicationContext
        val mode = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        handset = mode.currentModeType != Configuration.UI_MODE_TYPE_TELEVISION &&
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        capability = MethodChannel(binding.binaryMessenger, "com.sevenmotion.zuno/cast-capability").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "isHandset") result.success(handset) else result.notImplemented()
            }
        }
    }
    override fun onAttachedToActivity(activity: ActivityPluginBinding) {
        val engine = binding ?: return
        if (!handset) return
        // Le bridge gère lui-même les téléphones sans Google Play Services.
        cast = GoogleCastApi(engine.binaryMessenger, activity.activity)
        multicast = MulticastLockBridge(engine.binaryMessenger, engine.applicationContext)
    }
    private fun detachActivity() {
        cast?.dispose(); cast = null
        multicast?.dispose(); multicast = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        capability?.setMethodCallHandler(null); capability = null
        this.binding = null
    }
}
