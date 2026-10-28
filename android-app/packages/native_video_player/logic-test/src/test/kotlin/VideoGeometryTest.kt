import com.manzilionellm.native_video_player.logic.VideoBounds
import com.manzilionellm.native_video_player.logic.VideoGeometry
import kotlin.test.Test
import kotlin.test.assertEquals

class VideoGeometryTest {
    @Test fun uneTv4kAvecInterface1080NePlafonnePasLaVideo() {
        assertEquals(2160, VideoGeometry.screenHeight(3840, 2160, 1080))
        assertEquals(1080, VideoGeometry.screenHeight(1080, 2400, 2400))
        assertEquals(720, VideoGeometry.screenHeight(0, 0, 720))
    }

    @Test fun leQuatreTiersGardeSesProportions() {
        assertEquals(VideoBounds(1440, 1080), VideoGeometry.fit(1920, 1080, 640, 480))
    }

    @Test fun leCinemaLargeNeSeFaitPasRogner() {
        assertEquals(VideoBounds(1920, 800), VideoGeometry.fit(1920, 1080, 1920, 800))
        assertEquals(VideoBounds(1080, 608), VideoGeometry.fit(1080, 2400, 1920, 1080))
    }

    @Test fun lesPixelsAnamorphiquesSontRespectes() {
        assertEquals(VideoBounds(1920, 1080), VideoGeometry.fit(1920, 1080, 720, 576, 64f / 45f))
    }

    @Test fun lesMetadonneesIncompletesNeCassentPasLaSurface() {
        assertEquals(VideoBounds(0, 0), VideoGeometry.fit(0, 0, 1920, 1080))
        assertEquals(VideoBounds(1920, 1080), VideoGeometry.fit(1920, 1080, 0, 0))
        assertEquals(VideoBounds(1440, 1080), VideoGeometry.fit(1920, 1080, 640, 480, Float.NaN))
    }
}
