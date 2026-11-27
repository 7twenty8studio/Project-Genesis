package com.genesis.core.domain.journal

/** What an attachment belongs to, as AttachmentOwner on iOS. */
enum class AttachmentOwner(val id: String) {
    PRAYER("prayer"),
    SERMON("sermon"),
    ;

    /** Prayers hold photos and recordings; sermon notes also PDFs (and, on iPhone, Pencil pages). */
    fun allows(kind: AttachmentKind): Boolean = when (kind) {
        AttachmentKind.PHOTO, AttachmentKind.AUDIO -> true
        AttachmentKind.PDF, AttachmentKind.DRAWING -> this == SERMON
    }

    companion object {
        fun of(id: String): AttachmentOwner? = entries.firstOrNull { it.id == id }
    }
}

enum class AttachmentKind(val id: String, val fileExtension: String) {
    PHOTO("photo", "jpg"),
    AUDIO("audio", "m4a"),
    PDF("pdf", "pdf"),
    DRAWING("drawing", "drawing"),
    ;

    companion object {
        fun of(id: String): AttachmentKind? = entries.firstOrNull { it.id == id }
    }
}

/**
 * A photo, recording or PDF on a prayer or sermon notes (Premium journal
 * extras). The row holds what it is; the file lives on the device as
 * "<id>.<ext>" (`fileName`), never in the database.
 */
data class Attachment(
    val id: String,
    val owner: AttachmentOwner,
    val ownerId: String,
    val kind: AttachmentKind,
    val byteSize: Long,
    val durationSeconds: Double? = null,
    val pageCount: Int? = null,
    val caption: String? = null,
    val sortOrder: Int = 0,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    /** Where the file is kept beyond this device (AttachmentStorage); null until it's copied. */
    val storagePath: String? = null,
) {
    val fileName: String get() = "${id.lowercase()}.${kind.fileExtension}"
}

/** The limits iOS keeps (AttachmentLimits, AttachmentMedia, VoiceRecorder). */
object AttachmentLimits {
    /** One file at most 250 MB, CloudKit's asset limit, so a file can follow the person to iPhone later. */
    const val MAX_FILE_BYTES: Long = 250L * 1024 * 1024

    /** Photos are scaled so the long side is at most this many pixels. */
    const val PHOTO_LONG_SIDE = 1600

    /** JPEG quality for photos (0.7 on iOS). */
    const val PHOTO_QUALITY = 70

    /** A recording stops itself after four hours. */
    const val MAX_RECORDING_SECONDS = 4 * 60 * 60

    /** AAC mono at 32 kbps, as on iOS. */
    const val RECORDING_BIT_RATE = 32_000

    fun fits(bytes: Long): Boolean = bytes in 1..MAX_FILE_BYTES

    /** The size a photo is scaled to: the long side at most [PHOTO_LONG_SIDE], never enlarged. */
    fun photoSize(width: Int, height: Int): Pair<Int, Int> {
        val long = maxOf(width, height)
        if (long <= PHOTO_LONG_SIDE || long <= 0) return width to height
        val scale = PHOTO_LONG_SIDE.toDouble() / long
        return maxOf(1, Math.round(width * scale).toInt()) to maxOf(1, Math.round(height * scale).toInt())
    }

    /** "0:42", "12:05", "1:02:09". */
    fun durationLabel(seconds: Double): String {
        val total = maxOf(0, seconds.toInt())
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    /** Attachments in the order they were placed, then added. */
    fun sorted(attachments: List<Attachment>): List<Attachment> =
        attachments.sortedWith(compareBy<Attachment> { it.sortOrder }.thenBy { it.createdAt })
}

/**
 * Where an attachment's file is kept, from the row's storage_path. iPhone
 * files are in the person's iCloud ("<user>/<file>"); Android files in a
 * hidden Versely folder in the person's own Google Drive ("gdrive:<file>").
 * Neither is Versely's storage.
 */
object AttachmentStorage {
    const val DRIVE_PREFIX = "gdrive:"

    /** The server keeps rows for files up to 25 MB and recordings up to about two hours. */
    const val SERVER_MAX_BYTES: Long = 25L * 1024 * 1024
    const val SERVER_MAX_SECONDS = 7_300.0

    enum class Place { THIS_DEVICE, GOOGLE_DRIVE, ICLOUD }

    fun drivePath(fileName: String): String = DRIVE_PREFIX + fileName

    /** How long to wait after [failures] failed transfers in a row: 30 s, doubling, at most 6 hours (as iOS). */
    fun retryDelayMillis(failures: Int): Long {
        if (failures <= 0) return 0
        val doubled = 30_000L shl (failures - 1).coerceAtMost(20)
        return doubled.coerceAtMost(6L * 60 * 60 * 1000)
    }

    /** The file's type, for Drive. */
    fun mimeType(kind: AttachmentKind): String = when (kind) {
        AttachmentKind.PHOTO -> "image/jpeg"
        AttachmentKind.AUDIO -> "audio/mp4"
        AttachmentKind.PDF -> "application/pdf"
        AttachmentKind.DRAWING -> "application/octet-stream"
    }

    fun place(storagePath: String?): Place = when {
        storagePath.isNullOrEmpty() -> Place.THIS_DEVICE
        storagePath.startsWith(DRIVE_PREFIX) -> Place.GOOGLE_DRIVE
        else -> Place.ICLOUD
    }

    /** The Drive file's name, or null for a file that isn't in Drive. */
    fun driveName(storagePath: String?): String? =
        storagePath?.takeIf { it.startsWith(DRIVE_PREFIX) }?.removePrefix(DRIVE_PREFIX)?.takeIf { it.isNotEmpty() && '/' !in it }

    /** Whether the row fits the server's limits, so it can sync. */
    fun syncs(attachment: Attachment): Boolean =
        attachment.byteSize in 0..SERVER_MAX_BYTES && (attachment.durationSeconds ?: 0.0) <= SERVER_MAX_SECONDS
}
