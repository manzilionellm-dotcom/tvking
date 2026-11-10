#!/usr/bin/env python3
"""Rejoue les courses du vrai bridge Kotlin avec un SDK Cast déterministe.

Ce test ne simule pas une télévision physique. Il compile GoogleCastApi.kt
inchangé, puis contrôle l'ordre des callbacks et des messages de son canal.
Les doubles n'ouvrent aucun réseau et ne possèdent aucune playlist réelle.

Usage : python3 test_native_bridge.py --compiler-dir /chemin/jars-kotlin
Le dossier doit contenir kotlin-compiler-embeddable et ses dépendances Maven.
Il est fourni explicitement : ce test ne télécharge ni n'installe rien.
"""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


STUBS = {
    "Context.kt": """
package android.content
open class Context
""",
    "Activity.kt": """
package android.app
open class Activity : android.content.Context()
""",
    "FragmentActivity.kt": """
package androidx.fragment.app
open class FragmentActivity : android.app.Activity()
""",
    "Handler.kt": """
package android.os
class Looper { companion object { fun getMainLooper() = Looper() } }
class Handler(looper: Looper) {
    data class Task(val owner: Handler, val delay: Long, val action: () -> Unit)
    companion object {
        val tasks = mutableListOf<Task>()
        fun take(delay: Long): Task {
            val task = tasks.first { it.delay == delay }
            tasks.remove(task)
            return task
        }
    }
    fun postDelayed(action: () -> Unit, delay: Long): Boolean {
        tasks.add(Task(this, delay, action)); return true
    }
    fun removeCallbacksAndMessages(token: Any?) { tasks.removeAll { it.owner === this } }
}
""",
    "Log.kt": """
package android.util
object Log {
    val lines = mutableListOf<String>()
    fun i(tag: String, message: String) { lines.add(message) }
    fun w(tag: String, message: String) { lines.add(message) }
    fun e(tag: String, message: String) { lines.add(message) }
}
""",
    "Uri.kt": """
package android.net
class Uri { companion object { fun parse(value: String) = Uri() } }
""",
    "AppCompat.kt": """
package androidx.appcompat
object R { object style { const val Theme_AppCompat_Light_Dialog_Alert = 1 } }
""",
    "ContextThemeWrapper.kt": """
package androidx.appcompat.view
class ContextThemeWrapper(context: android.content.Context, theme: Int) : android.content.Context()
""",
    "MediaRouter.kt": """
package androidx.mediarouter.media
class MediaRouter {
    class RouteInfo(val id: String, val isDefault: Boolean = false)
    var selectedRoute = RouteInfo("salon")
    val selected = mutableListOf<RouteInfo>()
    fun selectRoute(route: RouteInfo) { selectedRoute = route; selected.add(route) }
    companion object {
        var instance = MediaRouter()
        fun getInstance(context: android.content.Context) = instance
    }
}
""",
    "MediaRouteChooserDialog.kt": """
package androidx.mediarouter.app
class MediaRouteChooserDialog(context: android.content.Context) {
    var routeSelector: Any = Any()
    fun show() {}
}
""",
    "MediaModels.kt": """
package com.google.android.gms.cast
class MediaMetadata(type: Int) {
    fun putString(key: String, value: String) {}
    fun addImage(image: com.google.android.gms.common.images.WebImage) {}
    companion object {
        const val MEDIA_TYPE_TV_SHOW = 1
        const val KEY_TITLE = "title"
        const val KEY_SUBTITLE = "subtitle"
    }
}
class MediaStatus(var idleReason: Int = 0) {
    companion object {
        const val PLAYER_STATE_PLAYING = 1
        const val PLAYER_STATE_PAUSED = 2
        const val PLAYER_STATE_BUFFERING = 3
        const val PLAYER_STATE_IDLE = 4
        const val PLAYER_STATE_LOADING = 5
        const val IDLE_REASON_FINISHED = 1
        const val IDLE_REASON_CANCELED = 2
        const val IDLE_REASON_INTERRUPTED = 3
        const val IDLE_REASON_ERROR = 4
    }
}
class MediaInfo(val contentId: String) {
    class Builder(private val url: String) {
        fun setStreamType(value: Int) = this
        fun setContentType(value: String) = this
        fun setMetadata(value: MediaMetadata) = this
        fun setCustomData(value: org.json.JSONObject) = this
        fun build() = MediaInfo(url)
    }
    companion object { const val STREAM_TYPE_LIVE = 1; const val STREAM_TYPE_BUFFERED = 2 }
}
class MediaLoadRequestData(val mediaInfo: MediaInfo) {
    class Builder {
        private lateinit var media: MediaInfo
        fun setMediaInfo(value: MediaInfo): Builder { media = value; return this }
        fun setAutoplay(value: Boolean) = this
        fun build() = MediaLoadRequestData(media)
    }
}
""",
    "Framework.kt": """
package com.google.android.gms.cast.framework
import com.google.android.gms.cast.framework.media.RemoteMediaClient
class ApplicationMetadata(val applicationId: String)
class CastSession(val remoteMediaClient: RemoteMediaClient = RemoteMediaClient(),
                  val applicationMetadata: ApplicationMetadata = ApplicationMetadata("custom")) {
    var isConnected = true
}
interface SessionManagerListener<T> {
    fun onSessionStarted(session: T, sessionId: String)
    fun onSessionResumed(session: T, wasSuspended: Boolean)
    fun onSessionEnded(session: T, error: Int)
    fun onSessionSuspended(session: T, reason: Int)
    fun onSessionStarting(session: T)
    fun onSessionResuming(session: T, sessionId: String)
    fun onSessionEnding(session: T)
    fun onSessionStartFailed(session: T, error: Int)
    fun onSessionResumeFailed(session: T, error: Int)
}
class SessionManager {
    var currentCastSession: CastSession? = null
    val listeners = mutableListOf<SessionManagerListener<CastSession>>()
    var disconnects = 0
    fun addSessionManagerListener(listener: SessionManagerListener<CastSession>, type: Class<CastSession>) {
        listeners.add(listener)
    }
    fun removeSessionManagerListener(listener: SessionManagerListener<CastSession>, type: Class<CastSession>) {
        listeners.remove(listener)
    }
    fun endCurrentSession(stop: Boolean) {
        disconnects++
        val old = currentCastSession ?: return
        currentCastSession = null
        old.isConnected = false
        listeners.toList().forEach { it.onSessionEnded(old, 0) }
    }
    fun start(session: CastSession) {
        currentCastSession = session
        listeners.toList().forEach { it.onSessionStarted(session, "session") }
    }
}
class CastContext {
    val sessionManager = SessionManager()
    val mergedSelector: Any? = Any()
    fun setReceiverApplicationId(id: String) { sessionManager.endCurrentSession(true) }
    companion object {
        var instance = CastContext()
        fun getSharedInstance(context: android.content.Context) = instance
    }
}
""",
    "RemoteMediaClient.kt": """
package com.google.android.gms.cast.framework.media
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaStatus
class RemoteMediaClient {
    open class Callback { open fun onStatusUpdated() {} }
    class Status(val isSuccess: Boolean, val statusCode: Int, val statusMessage: String?)
    class MediaChannelResult(val status: Status)
    class Pending {
        var callback: ((MediaChannelResult) -> Unit)? = null
        fun setResultCallback(value: (MediaChannelResult) -> Unit) { callback = value }
        fun complete(ok: Boolean, message: String? = null) {
            callback?.invoke(MediaChannelResult(Status(ok, if (ok) 0 else 2100, message)))
        }
    }
    val callbacks = mutableListOf<Callback>()
    val loads = mutableListOf<Pending>()
    val stopResults = mutableListOf<Pending>()
    var playerState = MediaStatus.PLAYER_STATE_IDLE
    var mediaStatus: MediaStatus? = MediaStatus()
    var mediaInfo: MediaInfo? = null
    val isPlaying get() = playerState == MediaStatus.PLAYER_STATE_PLAYING
    val isPaused get() = playerState == MediaStatus.PLAYER_STATE_PAUSED
    val isBuffering get() = playerState == MediaStatus.PLAYER_STATE_BUFFERING
    var stops = 0
    var loadException: RuntimeException? = null
    fun registerCallback(callback: Callback) { callbacks.add(callback) }
    fun unregisterCallback(callback: Callback) { callbacks.remove(callback) }
    fun notifyState() { callbacks.toList().forEach { it.onStatusUpdated() } }
    fun load(request: MediaLoadRequestData): Pending {
        loadException?.let { throw it }
        return Pending().also { loads.add(it) }
    }
    fun play() { playerState = MediaStatus.PLAYER_STATE_PLAYING }
    fun pause() { playerState = MediaStatus.PLAYER_STATE_PAUSED }
    fun stop(): Pending {
        stops++; playerState = MediaStatus.PLAYER_STATE_IDLE
        return Pending().also { stopResults.add(it) }
    }
}
""",
    "GoogleCommon.kt": """
package com.google.android.gms.common
object ConnectionResult { const val SUCCESS = 0 }
class GoogleApiAvailability {
    fun isGooglePlayServicesAvailable(context: android.content.Context) = 0
    companion object { fun getInstance() = GoogleApiAvailability() }
}
""",
    "WebImage.kt": """
package com.google.android.gms.common.images
class WebImage(uri: android.net.Uri)
""",
    "JSONObject.kt": """
package org.json
class JSONObject { fun put(key: String, value: Any) = this }
""",
    "FlutterChannel.kt": """
package io.flutter.plugin.common
interface BinaryMessenger
class MethodCall(val method: String, val arguments: Any?)
class MethodChannel(messenger: BinaryMessenger, name: String) {
    interface MethodCallHandler { fun onMethodCall(call: MethodCall, result: Result) }
    interface Result {
        fun success(value: Any?)
        fun error(code: String, message: String?, details: Any?)
        fun notImplemented()
    }
    fun setMethodCallHandler(handler: MethodCallHandler?) {}
    fun invokeMethod(method: String, args: Any?) { events.add(method to args) }
    companion object { val events = mutableListOf<Pair<String, Any?>>() }
}
""",
}


REGRESSION = """
package com.manzilionellm.tvking

import android.os.Handler
import android.util.Log
import androidx.fragment.app.FragmentActivity
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private class Result : MethodChannel.Result {
    var value: Any? = null
    var error: String? = null
    var replies = 0
    override fun success(value: Any?) { replies++; this.value = value }
    override fun error(code: String, message: String?, details: Any?) { replies++; error = "$code:$message" }
    override fun notImplemented() { replies++; error = "notImplemented" }
}

private class Fixture {
    val session: CastSession
    val bridge: GoogleCastApi
    val manager get() = CastContext.instance.sessionManager
    val client get() = session.remoteMediaClient
    val router get() = MediaRouter.instance
    init {
        Handler.tasks.clear()
        MethodChannel.events.clear()
        Log.lines.clear()
        MediaRouter.instance = MediaRouter()
        CastContext.instance = CastContext()
        session = CastSession()
        manager.currentCastSession = session
        bridge = GoogleCastApi(object : BinaryMessenger {}, FragmentActivity())
        MethodChannel.events.clear()
    }
    fun command(name: String, args: Any? = null): Result {
        return Result().also { bridge.onMethodCall(MethodCall(name, args), it) }
    }
    fun load(name: String = "a", url: String = "https://example.invalid/$name.m3u8",
             loadId: String? = null) =
        command("loadMedia", mapOf("streamUrl" to url, "title" to name, "loadId" to loadId))
    fun switch() = command("setReceiverApplicationId", mapOf("appId" to "default"))
    fun events(name: String) = MethodChannel.events.count {
        it.first == "onSessionEvent" && (it.second as Map<*, *>)["event"] == name
    }
    fun mediaEvents() = MethodChannel.events.count { it.first == "onMediaStateChanged" }
}

private fun requireThat(ok: Boolean, message: String) { check(ok) { message } }

fun main() {
    var passed = 0
    fun scenario(name: String, body: () -> Unit) {
        body(); passed++; println("PASS $name")
    }

    scenario("ancien échec après changement de chaîne") {
        val f = Fixture()
        f.load("a"); f.load("b")
        f.client.loads[0].complete(false)
        requireThat(f.events("load_failed") == 0, "l'ancien échec a quitté le bridge")
        f.client.loads[1].complete(true)
        requireThat(f.events("load_ok") == 1, "le nouveau chargement doit réussir")
    }
    scenario("événements déjà envoyés gardent le LOAD et le contenu d'origine") {
        val f = Fixture()
        val firstUrl = "https://example.invalid/a.m3u8"
        f.load("a", loadId = "load-a")
        f.client.mediaInfo = MediaInfo(firstUrl)
        f.client.playerState = MediaStatus.PLAYER_STATE_PLAYING
        f.client.loads[0].complete(true)
        val queued = MethodChannel.events.filter { it.first == "onMediaStateChanged" }
            .map { it.second as Map<*, *> }.single()
        val accepted = MethodChannel.events.filter { it.first == "onSessionEvent" }
            .map { it.second as Map<*, *> }.single()
        f.load("b", loadId = "load-b")
        f.client.loads[1].complete(true)
        val current = MethodChannel.events.last { it.first == "onMediaStateChanged" }.second as Map<*, *>
        requireThat(queued["loadId"] == "load-a" && queued["contentId"] == firstUrl,
            "ancien PLAYING déjà envoyé réattribué au nouveau LOAD")
        requireThat(accepted["loadId"] == "load-a", "load_ok sans identité d'origine")
        requireThat(current["loadId"] == "load-b" && current["contentId"] == firstUrl,
            "l'URL demandée masque l'ancien contenu encore joué par le receiver")
        f.client.mediaInfo = MediaInfo("https://example.invalid/b.m3u8")
        f.client.notifyState()
        val playing = MethodChannel.events.last { it.first == "onMediaStateChanged" }.second as Map<*, *>
        requireThat(playing["loadId"] == "load-b" &&
            playing["contentId"] == "https://example.invalid/b.m3u8",
            "statut courant sans corrélation au bon LOAD")
    }
    scenario("refus identifié et ancien Dart sans LOAD ID restent compatibles") {
        val f = Fixture()
        f.load(loadId = "load-refused")
        f.client.loads[0].complete(false)
        val rejected = MethodChannel.events.last { it.first == "onSessionEvent" }.second as Map<*, *>
        requireThat(rejected["event"] == "load_failed" && rejected["loadId"] == "load-refused",
            "refus SDK non corrélé")
        f.load("legacy")
        f.client.loads[1].complete(true)
        val legacy = MethodChannel.events.last { it.first == "onSessionEvent" }.second as Map<*, *>
        requireThat(legacy["event"] == "load_ok" && legacy["loadId"] == null,
            "ancien appel Dart sans loadId refusé")
    }
    scenario("ancien succès après stop") {
        val f = Fixture(); f.load(); f.command("stop")
        f.client.loads.single().complete(true)
        requireThat(f.events("load_ok") == 0 && f.client.stops == 1, "stop laisse revenir load_ok")
    }
    scenario("STOP attend l'ACK SDK et répond une seule fois") {
        val f = Fixture()
        val result = f.command("stop")
        requireThat(result.replies == 0, "STOP annoncé réussi avant l'ACK receiver")
        val ack = f.client.stopResults.single()
        ack.complete(true); ack.complete(true)
        requireThat(result.replies == 1 && result.error == null, "ACK STOP perdu ou réponse doublée")
        requireThat(Handler.tasks.isEmpty(), "timeout STOP conservé après ACK")
    }
    scenario("STOP refusé interdit le faux succès sans exposer l'URL") {
        val f = Fixture()
        val result = f.command("stop")
        f.client.stopResults.single().complete(false, "https://example.invalid/private-token")
        requireThat(result.replies == 1 && result.error?.startsWith("STOP_FAILED:") == true,
            "STOP refusé annoncé réussi")
        requireThat(result.error?.contains("private-token") != true, "URL SDK divulguée")
    }
    scenario("STOP sans ACK expire et ignore le succès trop tardif") {
        val f = Fixture()
        val result = f.command("stop")
        Handler.take(5_000).action()
        f.client.stopResults.single().complete(true)
        requireThat(result.replies == 1 && result.error?.startsWith("STOP_TIMEOUT:") == true,
            "timeout STOP converti en succès tardif")
    }
    scenario("nouveau LOAD annule l'ancien STOP sans toucher sa lecture") {
        val f = Fixture()
        val result = f.command("stop")
        f.load("next", loadId = "next-load")
        requireThat(result.replies == 1 && result.error?.startsWith("STOP_SUPERSEDED:") == true,
            "ancien STOP non terminé lors du nouveau LOAD")
        f.client.stopResults.single().complete(true)
        f.client.loads.single().complete(true)
        requireThat(result.replies == 1 && f.events("load_ok") == 1,
            "ACK STOP tardif altère le nouveau LOAD")
    }
    scenario("ACK STOP de l'ancienne TV ne valide pas la nouvelle session") {
        val f = Fixture()
        val result = f.command("stop")
        val next = CastSession()
        f.manager.start(next)
        f.client.stopResults.single().complete(true)
        requireThat(result.replies == 1 && result.error?.startsWith("STOP_SUPERSEDED:") == true,
            "ACK d'une autre session accepté")
        requireThat(next.remoteMediaClient.stops == 0, "nouvelle TV arrêtée par l'ancien STOP")
    }
    scenario("STOP déconnecté reste idempotent") {
        val f = Fixture()
        f.manager.currentCastSession = null
        val result = f.command("stop")
        requireThat(result.replies == 1 && result.error == null && f.client.stops == 0,
            "STOP sans lecture distante refusé")
    }
    scenario("ancien échec après déconnexion") {
        val f = Fixture(); f.load(); f.command("disconnect")
        f.client.loads.single().complete(false)
        requireThat(f.events("load_failed") == 0, "déconnexion laisse revenir load_failed")
    }
    scenario("ancien résultat après changement de TV") {
        val f = Fixture(); f.load(); f.manager.start(CastSession())
        f.client.loads.single().complete(true)
        requireThat(f.events("load_ok") == 0, "résultat d'une autre TV accepté")
        requireThat(f.client.callbacks.isEmpty(), "ancien client encore abonné")
    }
    scenario("fin tardive de l'ancienne TV préserve la nouvelle") {
        val f = Fixture()
        val next = CastSession()
        f.manager.start(next)
        MethodChannel.events.clear()
        f.manager.listeners.toList().forEach { it.onSessionEnded(f.session, 0) }
        requireThat(f.events("ended") == 0, "ancienne fin annoncée sur la nouvelle TV")
        requireThat(next.remoteMediaClient.callbacks.size == 1, "nouvelle TV désabonnée")
        next.remoteMediaClient.playerState = MediaStatus.PLAYER_STATE_PLAYING
        next.remoteMediaClient.notifyState()
        requireThat(f.mediaEvents() == 1, "nouveau lecteur ne notifie plus")
        f.manager.endCurrentSession(true)
        requireThat(f.events("ended") == 1, "fin légitime de la nouvelle TV perdue")
    }
    scenario("suspension tardive de l'ancienne TV préserve la nouvelle") {
        val f = Fixture()
        val next = CastSession()
        f.manager.start(next)
        MethodChannel.events.clear()
        f.manager.listeners.toList().forEach { it.onSessionSuspended(f.session, 1) }
        requireThat(f.events("suspended") == 0, "ancienne suspension annoncée sur nouvelle TV")
        requireThat(next.remoteMediaClient.callbacks.size == 1, "nouvelle TV désabonnée")
        f.manager.listeners.toList().forEach { it.onSessionSuspended(next, 1) }
        requireThat(f.events("suspended") == 1, "suspension réelle de la nouvelle TV perdue")
    }
    scenario("échecs tardifs de l'ancienne TV préservent la nouvelle") {
        val f = Fixture()
        val next = CastSession()
        f.manager.start(next)
        MethodChannel.events.clear()
        f.manager.listeners.toList().forEach {
            it.onSessionStartFailed(f.session, 7)
            it.onSessionResumeFailed(f.session, 8)
        }
        requireThat(f.events("start_failed") == 0 && f.events("resume_failed") == 0,
            "échec de l'ancienne TV annoncé sur la nouvelle")
        next.remoteMediaClient.playerState = MediaStatus.PLAYER_STATE_PLAYING
        next.remoteMediaClient.notifyState()
        requireThat(f.mediaEvents() == 1, "nouvelle TV devenue inobservable")
    }
    scenario("échec courant avant started reste observable") {
        val f = Fixture()
        val failing = CastSession()
        f.manager.currentCastSession = failing
        f.manager.listeners.toList().forEach {
            it.onSessionStartFailed(failing, 7)
            it.onSessionResumeFailed(failing, 8)
        }
        requireThat(f.events("start_failed") == 1 && f.events("resume_failed") == 1,
            "échec de la tentative courante perdu avant started")
    }
    scenario("échec sans session courante reste observable") {
        val f = Fixture()
        f.manager.currentCastSession = null
        val failing = CastSession()
        f.manager.listeners.toList().forEach {
            it.onSessionStartFailed(failing, 7)
            it.onSessionResumeFailed(failing, 8)
        }
        requireThat(f.events("start_failed") == 1 && f.events("resume_failed") == 1,
            "absence de session masque l'échec de connexion")
    }
    scenario("résultat SDK après dispose") {
        val f = Fixture(); f.load(); f.bridge.dispose()
        f.client.loads.single().complete(false)
        requireThat(f.events("load_failed") == 0, "dispose laisse notifier l'ancien moteur")
    }
    scenario("repli courant préservé") {
        val f = Fixture()
        requireThat(f.switch().value == "switching", "bascule non annoncée")
        Handler.take(400).action()
        requireThat(f.router.selected.size == 1, "le repli légitime ne resélectionne pas sa TV")
        f.manager.start(CastSession())
        requireThat(Handler.tasks.isEmpty(), "timer de bascule non libéré à la connexion")
    }
    scenario("stop annule une resélection déjà en file") {
        val f = Fixture(); f.switch()
        val queued = Handler.take(400)
        f.command("stop"); queued.action()
        requireThat(f.router.selected.isEmpty() && Handler.tasks.isEmpty(), "stop reconnecte la TV")
    }
    scenario("déconnexion annule la resélection") {
        val f = Fixture(); f.switch()
        val queued = Handler.take(400)
        f.command("disconnect"); queued.action()
        requireThat(f.router.selected.isEmpty(), "déconnexion reconnecte la TV")
    }
    scenario("dispose annule la resélection") {
        val f = Fixture(); f.switch()
        val queued = Handler.take(400)
        f.bridge.dispose(); queued.action()
        requireThat(f.router.selected.isEmpty(), "l'ancienne activité reconnecte la TV")
    }
    scenario("nouveau repli remplace ancienne route et ancien timeout") {
        val f = Fixture(); f.switch()
        val oldRoute = Handler.take(400)
        val oldTimeout = Handler.take(15_000)
        f.manager.currentCastSession = CastSession()
        f.router.selectedRoute = MediaRouter.RouteInfo("chambre")
        f.switch()
        oldTimeout.action(); oldRoute.action()
        requireThat(f.router.selected.isEmpty(), "ancienne route resélectionnée")
        Handler.take(400).action()
        requireThat(f.router.selected.single().id == "chambre", "ancien timeout annule le nouveau repli")
    }
    scenario("callback média ancien ignoré après zap et stop") {
        val f = Fixture(); f.load()
        val oldCallback = f.client.callbacks.single()
        f.load("b")
        MethodChannel.events.clear()
        oldCallback.onStatusUpdated()
        f.client.notifyState()
        requireThat(f.mediaEvents() == 0, "état ancien publié pendant load")
        f.client.playerState = MediaStatus.PLAYER_STATE_PLAYING
        f.client.loads[1].complete(true)
        requireThat(f.mediaEvents() == 1, "état courant perdu après acceptation")
        val activeCallback = f.client.callbacks.single()
        f.command("stop")
        MethodChannel.events.clear()
        activeCallback.onStatusUpdated()
        requireThat(f.mediaEvents() == 0, "état tardif publié après stop")
    }
    scenario("pause et reprise restent observables") {
        val f = Fixture(); f.load(); f.client.loads.single().complete(true)
        MethodChannel.events.clear()
        f.command("pause"); f.client.notifyState()
        f.command("play"); f.client.notifyState()
        val states = MethodChannel.events.filter { it.first == "onMediaStateChanged" }
            .map { (it.second as Map<*, *>)["playerState"] }
        requireThat(states == listOf("paused", "playing"), "commandes pause/reprise désynchronisées")
    }
    scenario("aucun identifiant dans les logs de chargement") {
        val secret = "https://example.invalid/private-user/private-password/live.ts?token=private-token"
        val f = Fixture(); f.load(url = secret)
        f.client.loads.single().complete(false, secret)
        f.client.loadException = IllegalStateException(secret)
        val result = f.load(url = secret)
        requireThat(Log.lines.none { it.contains("private-") }, "URL confidentielle dans logcat")
        requireThat(result.error?.contains("private-") != true, "URL confidentielle dans erreur Flutter")
    }
    println("GoogleCastApi : $passed scénarios de courses validés sur le bridge compilé")
}
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler-dir", required=True, type=Path)
    parser.add_argument("--bridge", type=Path, help="Source alternative pour contre-preuve")
    args = parser.parse_args()
    app = Path(__file__).resolve().parents[3]
    bridge = args.bridge or app / "android_overlay/google_cast/GoogleCastApi.kt"
    jars = sorted(args.compiler_dir.glob("*.jar"))
    if not any("kotlin-compiler-embeddable" in p.name for p in jars):
        parser.error("Le compilateur Kotlin embeddable est absent du dossier donné")
    classpath = os.pathsep.join(str(p.resolve()) for p in jars)
    with tempfile.TemporaryDirectory(prefix="zuno-cast-native-") as directory:
        root = Path(directory)
        for name, content in STUBS.items():
            (root / name).write_text(content, encoding="utf-8")
        (root / "GoogleCastRaceTest.kt").write_text(REGRESSION, encoding="utf-8")
        sources = sorted(str(p) for p in root.glob("*.kt"))
        output = root / "classes"
        subprocess.run([
            "java", "-cp", classpath, "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
            "-no-stdlib", "-no-reflect", "-nowarn", "-jvm-target", "17",
            "-classpath", classpath, "-d", str(output), str(bridge), *sources,
        ], check=True)
        subprocess.run([
            "java", "-cp", os.pathsep.join([str(output), classpath]),
            "com.manzilionellm.tvking.GoogleCastRaceTestKt",
        ], check=True)


if __name__ == "__main__":
    main()
