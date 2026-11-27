package com.genesis.core.domain.journal

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AttachmentTest {
    @Test fun prayersHoldPhotosAndRecordingsOnly() {
        assertTrue(AttachmentOwner.PRAYER.allows(AttachmentKind.PHOTO))
        assertTrue(AttachmentOwner.PRAYER.allows(AttachmentKind.AUDIO))
        assertFalse(AttachmentOwner.PRAYER.allows(AttachmentKind.PDF))
        assertTrue(AttachmentOwner.SERMON.allows(AttachmentKind.PDF))
    }

    @Test fun fileNameMatchesIOS() {
        val a = Attachment("ABC-1", AttachmentOwner.SERMON, "s", AttachmentKind.AUDIO, 10)
        assertEquals("abc-1.m4a", a.fileName)
    }

    @Test fun photosShrinkToTheLongSideNeverGrow() {
        assertEquals(1600 to 1200, AttachmentLimits.photoSize(4000, 3000))
        assertEquals(900 to 1600, AttachmentLimits.photoSize(1800, 3200))
        assertEquals(800 to 600, AttachmentLimits.photoSize(800, 600))
    }

    @Test fun sizeLimit() {
        assertTrue(AttachmentLimits.fits(AttachmentLimits.MAX_FILE_BYTES))
        assertFalse(AttachmentLimits.fits(AttachmentLimits.MAX_FILE_BYTES + 1))
        assertFalse(AttachmentLimits.fits(0))
    }

    @Test fun durations() {
        assertEquals("0:42", AttachmentLimits.durationLabel(42.7))
        assertEquals("12:05", AttachmentLimits.durationLabel(725.0))
        assertEquals("1:02:09", AttachmentLimits.durationLabel(3729.0))
    }

    @Test fun orderedByPlaceThenAdded() {
        fun a(id: String, order: Int, at: Long) = Attachment(id, AttachmentOwner.PRAYER, "p", AttachmentKind.PHOTO, 1, sortOrder = order, createdAt = at)
        assertEquals(listOf("b", "c", "a"), AttachmentLimits.sorted(listOf(a("a", 1, 1), a("b", 0, 5), a("c", 0, 9))).map { it.id })
    }
}

class AttachmentStorageTest {
    @Test fun retriesBackOffToSixHours() {
        assertEquals(0L, AttachmentStorage.retryDelayMillis(0))
        assertEquals(30_000L, AttachmentStorage.retryDelayMillis(1))
        assertEquals(60_000L, AttachmentStorage.retryDelayMillis(2))
        assertEquals(6L * 60 * 60 * 1000, AttachmentStorage.retryDelayMillis(12))
        assertEquals(6L * 60 * 60 * 1000, AttachmentStorage.retryDelayMillis(400))
    }

    @Test fun places() {
        assertEquals(AttachmentStorage.Place.THIS_DEVICE, AttachmentStorage.place(null))
        assertEquals(AttachmentStorage.Place.GOOGLE_DRIVE, AttachmentStorage.place("gdrive:abc.jpg"))
        assertEquals(AttachmentStorage.Place.ICLOUD, AttachmentStorage.place("0f1e/abc.jpg"))
    }

    @Test fun driveNames() {
        assertEquals("abc.jpg", AttachmentStorage.driveName(AttachmentStorage.drivePath("abc.jpg")))
        assertEquals(null, AttachmentStorage.driveName("0f1e/abc.jpg"))
        assertEquals(null, AttachmentStorage.driveName("gdrive:../x"))
    }

    @Test fun serverLimits() {
        fun a(bytes: Long, seconds: Double? = null) = Attachment("a", AttachmentOwner.PRAYER, "p", AttachmentKind.AUDIO, bytes, durationSeconds = seconds)
        assertTrue(AttachmentStorage.syncs(a(1000, 60.0)))
        assertFalse(AttachmentStorage.syncs(a(AttachmentStorage.SERVER_MAX_BYTES + 1)))
        assertFalse(AttachmentStorage.syncs(a(1000, 4 * 3600.0)))
    }
}
