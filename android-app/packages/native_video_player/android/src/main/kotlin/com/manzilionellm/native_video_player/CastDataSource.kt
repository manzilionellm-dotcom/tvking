package com.manzilionellm.native_video_player

import android.net.Uri
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import com.manzilionellm.native_video_player.logic.CastNetworkHandoff
import java.io.IOException

/** Suit aussi les ouvertures encore en cours, pas seulement les transferts réussis. */
@UnstableApi
internal class CastDataSource(
    private val delegate: DataSource,
    private val handoff: CastNetworkHandoff,
) : DataSource {
    private var source: Int? = null

    override fun addTransferListener(transferListener: TransferListener) =
        delegate.addTransferListener(transferListener)

    override fun open(dataSpec: DataSpec): Long {
        check(source == null) { "Une source doit être fermée avant sa réouverture." }
        source = handoff.acquireSource()
            ?: throw IOException("Lecture locale suspendue pour le Cast.")
        // Le contrat DataSource impose close(), même si open() a échoué.
        // Garder la source comptée jusque-là est essentiel pour le transfert.
        return delegate.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        delegate.read(buffer, offset, length)

    override fun getUri(): Uri? = delegate.uri

    override fun getResponseHeaders(): Map<String, List<String>> = delegate.responseHeaders

    override fun close() {
        val closing = source ?: return
        try {
            delegate.close()
            handoff.sourceClosed(closing, success = true)
            source = null
        } catch (error: Exception) {
            handoff.sourceClosed(closing, success = false)
            throw error
        }
    }
}
