package com.genesis.app.journal

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import com.genesis.core.data.UserDatabase
import com.genesis.core.domain.journal.Attachment
import com.genesis.core.domain.journal.AttachmentKind
import com.genesis.core.domain.journal.AttachmentLimits
import com.genesis.core.domain.journal.AttachmentOwner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * The files behind attachments, as AttachmentFiles and AttachmentMedia on
 * iOS: Attachments/<id>.<ext> in the app's own storage. Photos are scaled
 * (long side ≤ 1600 px) and saved again as JPEG, which leaves out every bit
 * of metadata, so no location. Nothing here leaves the device.
 */
internal object AttachmentFiles {
    /** Why an attachment couldn't be added, for the message under the section. */
    enum class Problem { PHOTO, PDF, TOO_LARGE, RECORDING, SAVING }

    class Failure(val problem: Problem) : Exception()

    fun folder(context: Context): File = File(context.filesDir, "Attachments").apply { mkdirs() }

    fun file(context: Context, attachment: Attachment): File = File(folder(context), attachment.fileName)

    /** Scales and saves a photo the person picked or took. */
    suspend fun addPhoto(context: Context, store: UserDatabase.AttachmentStore, owner: AttachmentOwner, ownerId: String, uri: Uri): Attachment =
        withContext(Dispatchers.IO) {
            val bitmap = runCatching { decodeScaled(context, uri) }.getOrNull() ?: throw Failure(Problem.PHOTO)
            val id = UUID.randomUUID().toString()
            val target = File(folder(context), "$id.${AttachmentKind.PHOTO.fileExtension}")
            runCatching { target.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, AttachmentLimits.PHOTO_QUALITY, it) } }
                .onFailure { target.delete(); throw Failure(Problem.SAVING) }
            bitmap.recycle()
            store.add(Attachment(id, owner, ownerId, AttachmentKind.PHOTO, target.length()))
        }

    /** Copies a PDF in as it is, and counts its pages. */
    suspend fun addPdf(context: Context, store: UserDatabase.AttachmentStore, ownerId: String, uri: Uri): Attachment =
        withContext(Dispatchers.IO) {
            val id = UUID.randomUUID().toString()
            val target = File(folder(context), "$id.${AttachmentKind.PDF.fileExtension}")
            val copied = runCatching {
                context.contentResolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
            }
            if (copied.isFailure) { target.delete(); throw Failure(Problem.SAVING) }
            if (!AttachmentLimits.fits(target.length())) { target.delete(); throw Failure(Problem.TOO_LARGE) }
            val pages = runCatching {
                ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY).use { PdfRenderer(it).use { pdf -> pdf.pageCount } }
            }.getOrNull()
            if (pages == null) { target.delete(); throw Failure(Problem.PDF) }
            store.add(Attachment(id, AttachmentOwner.SERMON, ownerId, AttachmentKind.PDF, target.length(), pageCount = pages))
        }

    /** Moves a finished recording into place. */
    suspend fun addRecording(context: Context, store: UserDatabase.AttachmentStore, owner: AttachmentOwner, ownerId: String, recording: File, seconds: Double): Attachment =
        withContext(Dispatchers.IO) {
            val id = UUID.randomUUID().toString()
            val target = File(folder(context), "$id.${AttachmentKind.AUDIO.fileExtension}")
            val moved = recording.renameTo(target) || runCatching { recording.copyTo(target, overwrite = true); recording.delete() }.isSuccess
            if (!moved || target.length() == 0L) { target.delete(); throw Failure(Problem.RECORDING) }
            store.add(Attachment(id, owner, ownerId, AttachmentKind.AUDIO, target.length(), durationSeconds = seconds))
        }

    /** Removes attachments' rows' files (after their rows were marked deleted). */
    fun remove(context: Context, attachments: List<Attachment>) {
        attachments.forEach { file(context, it).delete() }
        (context.applicationContext as? com.genesis.app.VerselyApplication)?.attachmentTransfers?.queueDeletion(attachments)
    }

    /** Deletes everything on a prayer or sermon that's gone. */
    fun removeOwner(context: Context, store: UserDatabase.AttachmentStore, ownerId: String) {
        remove(context, store.deleteOwner(ownerId))
    }

    /** A small picture of a photo, or the first page of a PDF, for the strip. */
    suspend fun thumbnail(context: Context, attachment: Attachment, sidePx: Int): Bitmap? = withContext(Dispatchers.IO) {
        val file = file(context, attachment)
        if (!file.exists()) return@withContext null
        runCatching {
            when (attachment.kind) {
                AttachmentKind.PHOTO -> {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.path, bounds)
                    var sample = 1
                    while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= sidePx) sample *= 2
                    BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
                }
                AttachmentKind.PDF -> ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                    PdfRenderer(fd).use { pdf ->
                        pdf.openPage(0).use { page ->
                            val scale = sidePx.toFloat() / maxOf(page.width, page.height)
                            val bitmap = Bitmap.createBitmap(maxOf(1, (page.width * scale).toInt()), maxOf(1, (page.height * scale).toInt()), Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(android.graphics.Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            bitmap
                        }
                    }
                }
                else -> null
            }
        }.getOrNull()
    }

    /** Opens a PDF in the person's PDF viewer. */
    fun open(context: Context, attachment: Attachment): Boolean {
        val file = file(context, attachment)
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/pdf")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(intent) }.isSuccess
    }

    /** A place for the camera to write a photo before it's scaled and saved. */
    fun cameraTarget(context: Context): Uri {
        val folder = File(context.cacheDir, "camera").apply { mkdirs() }
        val file = File(folder, "photo.jpg").apply { delete() }
        return FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    private fun decodeScaled(context: Context, uri: Uri): Bitmap {
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val (w, h) = AttachmentLimits.photoSize(info.size.width, info.size.height)
            decoder.setTargetSize(w, h)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }
}
