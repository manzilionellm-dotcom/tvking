package com.manzilionellm.native_video_player.ai

import android.opengl.GLES20
import androidx.media3.common.GlTextureInfo
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Petits objets GLES2. Aucun changement du contexte Media3, aucun calcul CPU par pixel. */
internal object AiGl {
    const val HALF_FLOAT_OES = 0x8D61
    const val HALF_FLOAT = 0x140B
    const val RGBA16F = 0x881A
    private val quad = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        .apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }

    fun check() {
        val error = GLES20.glGetError()
        check(error == GLES20.GL_NO_ERROR) { "GL_ERROR:$error" }
    }

    fun texture(width: Int, height: Int, halfFloat: Boolean, es3: Boolean): GlTextureInfo {
        val id = IntArray(1)
        val fbo = IntArray(1)
        GLES20.glGenTextures(1, id, 0)
        try {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id[0])
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            val type = if (!halfFloat) GLES20.GL_UNSIGNED_BYTE else if (es3) HALF_FLOAT else HALF_FLOAT_OES
            val format = if (halfFloat && es3) RGBA16F else GLES20.GL_RGBA
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, format, width, height, 0, GLES20.GL_RGBA, type, null)
            GLES20.glGenFramebuffers(1, fbo, 0)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
            GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D, id[0], 0)
            check(GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) == GLES20.GL_FRAMEBUFFER_COMPLETE) {
                "FLOAT_FRAMEBUFFER_UNSUPPORTED"
            }
            check()
            return GlTextureInfo(id[0], fbo[0], -1, width, height)
        } catch (error: Throwable) {
            if (fbo[0] != 0) GLES20.glDeleteFramebuffers(1, fbo, 0)
            if (id[0] != 0) GLES20.glDeleteTextures(1, id, 0)
            throw error
        }
    }

    fun upload(texture: GlTextureInfo, bytes: ByteArray) {
        check(bytes.size == texture.width * texture.height * 4)
        val buffer = ByteBuffer.allocateDirect(bytes.size).put(bytes).apply { position(0) }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture.texId)
        GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, texture.width, texture.height,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        check()
    }

    fun read(texture: GlTextureInfo): ByteArray {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, texture.fboId)
        val buffer = ByteBuffer.allocateDirect(texture.width * texture.height * 4)
        GLES20.glReadPixels(0, 0, texture.width, texture.height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        check()
        return ByteArray(buffer.capacity()).also { buffer.position(0); buffer.get(it) }
    }

    class Program(vertex: String, fragment: String, private val cancelled: () -> Boolean = { false }) : AutoCloseable {
        private var id = 0
        private val uniforms = HashMap<String, Int>()
        init {
            val vs = compile(GLES20.GL_VERTEX_SHADER, vertex)
            var fs = 0
            try {
                if (cancelled()) throw AiWorkCancelled()
                fs = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
                if (cancelled()) throw AiWorkCancelled()
                id = GLES20.glCreateProgram()
                GLES20.glAttachShader(id, vs)
                GLES20.glAttachShader(id, fs)
                GLES20.glBindAttribLocation(id, 0, "aPosition")
                if (cancelled()) throw AiWorkCancelled()
                GLES20.glLinkProgram(id)
                val status = IntArray(1)
                GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, status, 0)
                check(status[0] == GLES20.GL_TRUE) { "SHADER_LINK:${GLES20.glGetProgramInfoLog(id)}" }
            } catch (error: Throwable) {
                close()
                throw error
            } finally {
                GLES20.glDeleteShader(vs)
                if (fs != 0) GLES20.glDeleteShader(fs)
            }
        }

        fun draw(target: GlTextureInfo, width: Int, height: Int, input: Int, second: Int = 0, secondName: String = "uSkip") {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, target.fboId)
            GLES20.glViewport(0, 0, target.width, target.height)
            GLES20.glUseProgram(id)
            GLES20.glUniform2f(location("uSize"), width.toFloat(), height.toFloat())
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, input)
            GLES20.glUniform1i(location("uInput"), 0)
            if (second != 0) {
                GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, second)
                GLES20.glUniform1i(location(secondName), 1)
            }
            GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0)
            quad.position(0)
            GLES20.glVertexAttribPointer(0, 2, GLES20.GL_FLOAT, false, 0, quad)
            GLES20.glEnableVertexAttribArray(0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(0)
            check()
        }

        private fun location(name: String): Int = uniforms.getOrPut(name) { GLES20.glGetUniformLocation(id, name) }
        override fun close() { if (id != 0) GLES20.glDeleteProgram(id); id = 0 }
        private fun compile(type: Int, source: String): Int {
            if (cancelled()) throw AiWorkCancelled()
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] != GLES20.GL_TRUE) {
                val message = GLES20.glGetShaderInfoLog(shader)
                GLES20.glDeleteShader(shader)
                error("SHADER_COMPILE:$message")
            }
            return shader
        }
    }

    /** Le processeur est un invité dans le contexte Media3 : restaurer ses états. */
    class State : AutoCloseable {
        private fun value(name: Int) = IntArray(1).also { GLES20.glGetIntegerv(name, it, 0) }[0]
        private val fbo = value(GLES20.GL_FRAMEBUFFER_BINDING)
        private val program = value(GLES20.GL_CURRENT_PROGRAM)
        private val active = value(GLES20.GL_ACTIVE_TEXTURE)
        private val buffer = value(GLES20.GL_ARRAY_BUFFER_BINDING)
        private val viewport = IntArray(4).also { GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, it, 0) }
        private val flags = intArrayOf(GLES20.GL_BLEND, GLES20.GL_DEPTH_TEST, GLES20.GL_SCISSOR_TEST, GLES20.GL_CULL_FACE)
        private val enabled = flags.map { GLES20.glIsEnabled(it) }
        init { flags.forEach { GLES20.glDisable(it) } }
        override fun close() {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo)
            GLES20.glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
            GLES20.glUseProgram(program)
            GLES20.glActiveTexture(active)
            GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, buffer)
            flags.forEachIndexed { i, flag -> if (enabled[i]) GLES20.glEnable(flag) else GLES20.glDisable(flag) }
        }
    }
}

internal class AiWorkCancelled : RuntimeException()

/** Compiler une seule fois par contexte, pas à chaque géométrie ou chaque zap. */
internal class ArtCnnPrograms(assets: ArtCnnAssets, cancelled: () -> Boolean = { false }) : AutoCloseable {
    val items = ArrayList<AiGl.Program>()
    init {
        try {
            val vertex = assets.text.getValue("vertex.glsl")
            (listOf("denoise.glsl") + (0..6).map { "conv$it.glsl" } + "composite.glsl").forEach {
                if (cancelled()) throw AiWorkCancelled()
                items.add(AiGl.Program(vertex, assets.text.getValue(it), cancelled))
            }
        } catch (error: Throwable) { close(); throw error }
    }
    override fun close() { items.forEach { runCatching { it.close() } }; items.clear() }
}

/** 9 passes réelles : débruitage, 7 convolutions et composition Y'/chroma x2. */
internal class ArtCnnPipeline(
    assets: ArtCnnAssets,
    val width: Int,
    val height: Int,
    es3: Boolean,
    sharedPrograms: ArtCnnPrograms? = null,
    cancelled: () -> Boolean = { false },
) : AutoCloseable {
    private val textures = ArrayList<GlTextureInfo>()
    private val ownPrograms = sharedPrograms == null
    private val programs = sharedPrograms ?: ArtCnnPrograms(assets, cancelled)
    val output: GlTextureInfo

    init {
        try {
            fun allocate(w: Int, h: Int, half: Boolean): GlTextureInfo {
                if (cancelled()) throw AiWorkCancelled()
                return AiGl.texture(w, h, half, es3).also { textures.add(it) }
            }
            // Features signées RGBA16F : jamais de cible RGBA8 qui les tronquerait.
            allocate(width, height, true) // gamma + luma
            repeat(3) { allocate(width * 2, height * 2, true) } // skip, ping, pong
            allocate(width, height, true) // 4 sous-pixels
            output = allocate(width * 2, height * 2, false)
        } catch (error: Throwable) { close(); throw error }
    }

    fun render(input: Int, cancelled: () -> Boolean = { false }): Boolean {
        AiGl.State().use {
            fun pass(program: Int, target: Int, source: Int, second: Int = 0, name: String = "uSkip"): Boolean {
                if (cancelled()) return false
                programs.items[program].draw(textures[target], width, height, source, second, name)
                return true
            }
            if (!pass(0, 0, input)) return false
            if (!pass(1, 1, textures[0].texId)) return false
            if (!pass(2, 2, textures[1].texId)) return false
            if (!pass(3, 3, textures[2].texId)) return false
            if (!pass(4, 2, textures[3].texId)) return false
            if (!pass(5, 3, textures[2].texId)) return false
            if (!pass(6, 2, textures[3].texId, textures[1].texId)) return false
            if (!pass(7, 4, textures[2].texId)) return false
            if (!pass(8, 5, textures[4].texId, textures[0].texId, "uColor")) return false
            // Les temps de simple soumission GPU ne qualifient jamais l'IA.
            GLES20.glFinish()
            AiGl.check()
            return !cancelled()
        }
    }

    override fun close() {
        textures.forEach { runCatching { it.release() } }; textures.clear()
        if (ownPrograms) programs.close()
    }

    companion object {
        // 128 octets/pixel pour les textures réellement créées + marge programme/pilote.
        fun workingBytes(width: Int, height: Int): Long = width.toLong() * height * 128 + 64L * 1024 * 1024
    }
}
