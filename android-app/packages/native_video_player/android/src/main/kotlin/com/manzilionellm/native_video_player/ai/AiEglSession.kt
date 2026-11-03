package com.manzilionellm.native_video_player.ai

import android.opengl.EGL14
import android.opengl.EGLConfig

/** Même choix que Media3 1.5.1 : GLES3 si possible, sinon GLES2. Contexte privé. */
internal class AiEglSession : AutoCloseable {
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private var surface = EGL14.EGL_NO_SURFACE
    private var context = EGL14.EGL_NO_CONTEXT
    private var initialized = false
    private var closed = false
    init {
        try {
            check(display != EGL14.EGL_NO_DISPLAY)
            check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 0))
            initialized = true
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            check(EGL14.eglChooseConfig(display, intArrayOf(
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_NONE), 0, configs, 0, 1, count, 0))
            check(count[0] > 0)
            fun tryVersion(version: Int): Boolean {
                val candidateContext = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
                    intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, version, EGL14.EGL_NONE), 0)
                if (candidateContext == EGL14.EGL_NO_CONTEXT) { EGL14.eglGetError(); return false }
                val candidateSurface = EGL14.eglCreatePbufferSurface(display, configs[0],
                    intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
                // Certains pilotes acceptent createContext(3), mais refusent son
                // placeholder avec EGL_BAD_MATCH. Media3 retente alors TOUT en2.
                if (candidateSurface == EGL14.EGL_NO_SURFACE ||
                    !EGL14.eglMakeCurrent(display, candidateSurface, candidateSurface, candidateContext)) {
                    if (candidateSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, candidateSurface)
                    EGL14.eglDestroyContext(display, candidateContext)
                    EGL14.eglGetError()
                    return false
                }
                context = candidateContext
                surface = candidateSurface
                return true
            }
            check(tryVersion(3) || tryVersion(2))
        } catch (error: Throwable) { close(); throw error }
    }
    override fun close() {
        if (closed) return
        closed = true
        if (display == EGL14.EGL_NO_DISPLAY || !initialized) return
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
        if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
        surface = EGL14.EGL_NO_SURFACE
        context = EGL14.EGL_NO_CONTEXT
    }
}
