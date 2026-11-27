package com.genesis.app.journal

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.activity.result.IntentSenderRequest
import com.genesis.core.domain.journal.AttachmentStorage
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.original.PremiumTeaser
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.journal.Attachment
import com.genesis.core.domain.journal.AttachmentKind
import com.genesis.core.domain.journal.AttachmentLimits
import com.genesis.core.domain.journal.AttachmentOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import com.genesis.core.domain.study.InkPage
import androidx.compose.foundation.layout.systemBarsPadding

/**
 * The attachments on a prayer or sermon notes (Premium journal extras), as
 * AttachmentsSection on iOS: a strip of photos and PDFs, the recordings
 * below it, and an Add Attachment menu. Without Premium, anything already
 * attached still shows, with a teaser in place of the menu. Files are saved
 * on this device and, once the person turns it on, copied to their own
 * Google Drive (AttachmentTransfers); a synced attachment whose file isn't
 * here yet comes down from Drive when shown.
 */
@Composable
internal fun AttachmentsSection(owner: AttachmentOwner, ownerId: String) {
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val store = app.userData.attachments
    val colors = LocalReaderColors.current
    val all by store.all.collectAsStateWithLifecycle()
    val attachments = remember(all, ownerId) { AttachmentLimits.sorted(all.filter { it.owner == owner && it.ownerId == ownerId }) }
    val pictures = attachments.filter { it.kind == AttachmentKind.PHOTO || it.kind == AttachmentKind.PDF || it.kind == AttachmentKind.DRAWING }
    val recordings = attachments.filter { it.kind == AttachmentKind.AUDIO }
    val unlocked = Entitlements.isPremium
    val scope = rememberCoroutineScope()
    val player = remember { VoiceNotePlayer(context) }
    DisposableEffect(Unit) { onDispose { player.stop() } }

    var problem by remember { mutableStateOf<AttachmentFiles.Problem?>(null) }
    var busy by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<Attachment?>(null) }
    var deleting by remember { mutableStateOf<Attachment?>(null) }
    var recording by remember { mutableStateOf(false) }
    // A Pencil page being written: a new one (no attachment yet) or one already attached.
    var drawingNew by remember { mutableStateOf(false) }
    var drawingOpen by remember { mutableStateOf<Pair<Attachment, InkPage>?>(null) }
    var drawingElsewhere by remember { mutableStateOf(false) }

    val transfers = app.attachmentTransfers
    val backup by transfers.enabled.collectAsStateWithLifecycle()
    val driveProblem by transfers.problem.collectAsStateWithLifecycle()
    val waiting by transfers.pending.collectAsStateWithLifecycle()
    var driveUnavailable by remember { mutableStateOf(false) }
    // Bumped when a file comes down from Drive, so its thumbnail loads.
    var downloads by remember { mutableIntStateOf(0) }
    var missing by remember { mutableStateOf<Set<AttachmentStorage.Place>>(emptySet()) }
    LaunchedEffect(attachments) {
        transfers.kick()
        val gone = attachments.filter { !AttachmentFiles.file(context, it).exists() }
        var still = gone.map { AttachmentStorage.place(it.storagePath) }.toSet()
        if (gone.any { AttachmentStorage.place(it.storagePath) == AttachmentStorage.Place.GOOGLE_DRIVE }) {
            var failed = false
            for (attachment in gone.filter { AttachmentStorage.place(it.storagePath) == AttachmentStorage.Place.GOOGLE_DRIVE }) {
                if (transfers.download(attachment)) downloads++ else failed = true
            }
            if (!failed) still = still - AttachmentStorage.Place.GOOGLE_DRIVE
        }
        missing = still
    }
    val consent = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        transfers.finishAccess(result.data)
    }
    fun backUp() {
        driveUnavailable = false
        scope.launch {
            when (val access = transfers.requestAccess()) {
                is AttachmentTransfers.Access.Granted -> transfers.turnOn()
                is AttachmentTransfers.Access.Ask -> runCatching { consent.launch(IntentSenderRequest.Builder(access.intent).build()) }
                AttachmentTransfers.Access.Unavailable -> driveUnavailable = true
            }
        }
    }

    fun adding(block: suspend () -> Unit) {
        problem = null
        busy = true
        scope.launch {
            try {
                block()
            } catch (failure: AttachmentFiles.Failure) {
                problem = failure.problem
            } finally {
                busy = false
                transfers.kick()
            }
        }
    }

    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris: List<Uri> ->
        if (uris.isNotEmpty()) adding { uris.forEach { AttachmentFiles.addPhoto(context, store, owner, ownerId, it) } }
    }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        val uri = cameraUri
        if (taken && uri != null) adding { AttachmentFiles.addPhoto(context, store, owner, ownerId, uri) }
    }
    val pdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) adding { AttachmentFiles.addPdf(context, store, ownerId, uri) }
    }

    Header(stringResource(R.string.attachments))
    Group {
        if (pictures.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pictures.forEach { attachment -> Thumbnail(attachment, downloads) { viewing = attachment } }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
        }
        val playing by player.playing.collectAsStateWithLifecycle()
        recordings.forEach { attachment ->
            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { player.toggle(attachment.id, AttachmentFiles.file(context, attachment)) }) {
                    Text(if (playing == attachment.id) "❚❚" else "▶", color = colors.accent)
                }
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.voice_recording), style = MaterialTheme.typography.bodyLarge, color = colors.text)
                    attachment.durationSeconds?.let {
                        Text(AttachmentLimits.durationLabel(it), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    }
                }
                TextButton(onClick = { deleting = attachment }) { Text(stringResource(R.string.delete), color = colors.secondaryText) }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
        }
        if (unlocked) {
            var menu by remember { mutableStateOf(false) }
            Box {
                Row(
                    Modifier.fillMaxWidth().clickable(enabled = !busy) { menu = true }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("📎  " + stringResource(R.string.add_attachment), style = MaterialTheme.typography.bodyLarge, color = colors.accent, modifier = Modifier.weight(1f))
                    if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.accent)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.choose_photos)) }, onClick = {
                        menu = false
                        photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.take_photo)) }, onClick = {
                        menu = false
                        val target = AttachmentFiles.cameraTarget(context)
                        cameraUri = target
                        runCatching { camera.launch(target) }
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.record_voice)) }, onClick = {
                        menu = false
                        recording = true
                    })
                    if (owner.allows(AttachmentKind.DRAWING)) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.attachment_drawing)) }, onClick = {
                            menu = false
                            drawingNew = true
                        })
                    }
                    if (owner.allows(AttachmentKind.PDF)) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.import_pdf)) }, onClick = {
                            menu = false
                            pdf.launch(arrayOf("application/pdf"))
                        })
                    }
                }
            }
            if (!backup || driveProblem == AttachmentTransfers.Problem.ACCESS_NEEDED) {
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                Text(
                    stringResource(R.string.back_up_to_google_drive),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.accent,
                    modifier = Modifier.fillMaxWidth().clickable(onClick = ::backUp).padding(16.dp),
                )
            }
        } else {
            PremiumTeaser(stringResource(R.string.attachments_premium_teaser), Modifier.padding(4.dp))
        }
    }
    val notes = buildList {
        problem?.let { add(stringResource(it.message)) }
        if (driveUnavailable) add(stringResource(R.string.drive_unavailable))
        if (backup) when (driveProblem) {
            AttachmentTransfers.Problem.ACCESS_NEEDED -> add(stringResource(R.string.drive_access_needed))
            AttachmentTransfers.Problem.DRIVE_FULL -> add(stringResource(R.string.drive_full))
            null -> if (waiting > 0 && attachments.isNotEmpty()) add(stringResource(R.string.drive_waiting, waiting))
        }
        if (drawingElsewhere) add(stringResource(R.string.attachment_drawing_on_iphone))
        if (AttachmentStorage.Place.ICLOUD in missing) add(stringResource(R.string.attachment_in_icloud))
        if (AttachmentStorage.Place.GOOGLE_DRIVE in missing) add(stringResource(R.string.attachment_not_downloaded))
    }
    notes.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = Color(0xFFC77700), modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp)) }
    Footer(stringResource(if (backup) R.string.attachments_drive_footer else R.string.attachments_drive_off_footer))
    if (backup && unlocked) {
        TextButton(onClick = { transfers.turnOff() }, modifier = Modifier.padding(start = 4.dp)) {
            Text(stringResource(R.string.stop_google_drive_backup), color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
        }
    }

    viewing?.let { attachment ->
        if (attachment.kind == AttachmentKind.DRAWING) {
            LaunchedEffect(attachment.id) {
                val page = AttachmentFiles.drawing(context, attachment)
                if (page != null) drawingOpen = attachment to page else drawingElsewhere = true
                viewing = null
            }
        } else if (attachment.kind == AttachmentKind.PDF) {
            LaunchedEffect(attachment.id) {
                if (!AttachmentFiles.open(context, attachment)) problem = AttachmentFiles.Problem.PDF
                viewing = null
            }
        } else {
            PhotoViewer(attachment, onDelete = { viewing = null; deleting = attachment }, onClose = { viewing = null })
        }
    }
    deleting?.let { attachment ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.delete_attachment_question)) },
            confirmButton = {
                TextButton(onClick = {
                    if (player.playing.value == attachment.id) player.stop()
                    store.delete(attachment.id)?.let { AttachmentFiles.remove(context, listOf(it)) }
                    deleting = null
                }) { Text(stringResource(R.string.delete), color = Color(0xFFC0392B)) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
        )
    }
    if (drawingNew) {
        DrawingDialog(InkPage(), onDelete = null, onDone = { page ->
            drawingNew = false
            if (!page.isEmpty) adding { AttachmentFiles.addDrawing(context, store, ownerId, page) }
        })
    }
    drawingOpen?.let { (attachment, original) ->
        DrawingDialog(original, onDelete = { drawingOpen = null; deleting = attachment }, onDone = { page ->
            drawingOpen = null
            if (page != original) adding { AttachmentFiles.updateDrawing(context, store, attachment, page) }
        })
    }
    if (recording) {
        RecorderDialog(
            sermon = owner == AttachmentOwner.SERMON,
            player = player,
            onSave = { file, seconds ->
                recording = false
                adding { AttachmentFiles.addRecording(context, store, owner, ownerId, file, seconds) }
            },
            onCancel = { recording = false },
        )
    }
}

private val AttachmentFiles.Problem.message: Int
    get() = when (this) {
        AttachmentFiles.Problem.PHOTO -> R.string.attachment_photo_failed
        AttachmentFiles.Problem.PDF -> R.string.attachment_pdf_failed
        AttachmentFiles.Problem.TOO_LARGE -> R.string.attachment_too_large
        AttachmentFiles.Problem.RECORDING -> R.string.attachment_recording_failed
        AttachmentFiles.Problem.SAVING -> R.string.attachment_saving_failed
    }

@Composable
private fun Thumbnail(attachment: Attachment, downloads: Int, onOpen: () -> Unit) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val side = with(LocalDensity.current) { 84.dp.roundToPx() }
    val bitmap by produceState<Bitmap?>(null, attachment.id, downloads) { value = AttachmentFiles.thumbnail(context, attachment, side) }
    val label = if (attachment.kind == AttachmentKind.PDF) {
        attachment.pageCount?.let { stringResource(R.string.pdf_pages, it) } ?: stringResource(R.string.pdf)
    } else if (attachment.kind == AttachmentKind.DRAWING) {
        stringResource(R.string.attachment_drawing)
    } else {
        stringResource(R.string.style_photo)
    }
    Box(
        Modifier.size(84.dp).clip(RoundedCornerShape(10.dp)).background(colors.background).clickable(onClick = onOpen).semantics { contentDescription = label },
        contentAlignment = Alignment.BottomStart,
    ) {
        bitmap?.let { Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
        if (attachment.kind == AttachmentKind.PDF || attachment.kind == AttachmentKind.DRAWING) {
            Text(
                if (attachment.kind == AttachmentKind.PDF) stringResource(R.string.pdf) else "✎",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier.padding(6.dp).background(Color(0xAA000000), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun PhotoViewer(attachment: Attachment, onDelete: () -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val side = with(LocalDensity.current) { 1600.dp.roundToPx().coerceAtMost(2400) }
    val bitmap by produceState<Bitmap?>(null, attachment.id) { value = AttachmentFiles.thumbnail(context, attachment, side) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Color.Black)) {
            Row(Modifier.fillMaxWidth().padding(8.dp)) {
                TextButton(onClick = onDelete) { Text(stringResource(R.string.delete), color = Color(0xFFFF8A7A)) }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onClose) { Text(stringResource(R.string.done), color = Color.White, fontWeight = FontWeight.SemiBold) }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                bitmap?.let { Image(it.asImageBitmap(), contentDescription = stringResource(R.string.style_photo), contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize()) }
            }
        }
    }
}

/** A Pencil page on sermon notes, full screen, as DrawingAttachmentSheet on iOS; Done keeps what was written. */
@Composable
private fun DrawingDialog(initial: InkPage, onDelete: (() -> Unit)?, onDone: (InkPage) -> Unit) {
    val colors = LocalReaderColors.current
    var page by remember { mutableStateOf(initial) }
    Dialog(onDismissRequest = { onDone(page) }, properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false)) {
        Column(Modifier.fillMaxSize().background(colors.background).systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (onDelete != null) TextButton(onClick = onDelete) { Text(stringResource(R.string.delete), color = Color(0xFFC0392B)) }
                Text(
                    stringResource(R.string.attachment_drawing),
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.text,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                TextButton(onClick = { onDone(page) }) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            }
            com.genesis.app.reader.HandwritingPage(page = page, onChange = { page = it }, modifier = Modifier.weight(1f).fillMaxWidth())
        }
    }
}

/** Record, stop, listen back, then save or record again, as VoiceRecorderSheet on iOS. */
@Composable
private fun RecorderDialog(sermon: Boolean, player: VoiceNotePlayer, onSave: (File, Double) -> Unit, onCancel: () -> Unit) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val recorder = remember { VoiceRecorder(context) }
    val phase by recorder.phase.collectAsStateWithLifecycle()
    val playing by player.playing.collectAsStateWithLifecycle()
    var elapsed by remember { mutableDoubleStateOf(0.0) }
    var failed by remember { mutableStateOf(false) }
    var denied by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose {
            if (player.playing.value == TAKE) player.stop()
            if (!saved) recorder.discard()
        }
    }
    LaunchedEffect(phase) {
        while (phase == VoiceRecorder.Phase.RECORDING) {
            elapsed = recorder.elapsed()
            delay(250)
        }
        elapsed = recorder.elapsed()
    }
    fun begin() {
        failed = false
        player.stop()
        (context.applicationContext as VerselyApplication).let {
            it.listening.pause()
            it.ambient.pause()
        }
        if (!recorder.start()) failed = true
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin() else denied = true
    }

    AlertDialog(
        onDismissRequest = {},
        title = { Text(stringResource(R.string.voice_recording)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    AttachmentLimits.durationLabel(elapsed),
                    style = MaterialTheme.typography.displaySmall,
                    color = if (phase == VoiceRecorder.Phase.RECORDING) Color(0xFFC0392B) else colors.text,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    when (phase) {
                        VoiceRecorder.Phase.READY -> TextButton(onClick = {
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) begin()
                            else permission.launch(Manifest.permission.RECORD_AUDIO)
                        }) { Text("● " + stringResource(R.string.record), color = Color(0xFFC0392B), fontWeight = FontWeight.SemiBold) }
                        VoiceRecorder.Phase.RECORDING -> TextButton(onClick = recorder::stop) { Text("■ " + stringResource(R.string.stop), color = colors.accent, fontWeight = FontWeight.SemiBold) }
                        VoiceRecorder.Phase.RECORDED -> {
                            TextButton(onClick = { player.toggle(TAKE, recorder.take) }) {
                                Text(stringResource(if (playing == TAKE) R.string.pause else R.string.play), color = colors.accent)
                            }
                            TextButton(onClick = { player.stop(); recorder.discard() }) { Text(stringResource(R.string.record_again), color = colors.accent) }
                        }
                    }
                }
                if (denied) Text(stringResource(R.string.microphone_denied), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                if (failed) Text(stringResource(R.string.recording_failed_start), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                if (sermon) Text(stringResource(R.string.sermon_recording_reminder), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                Text(stringResource(R.string.recording_saved_on_device), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
        },
        confirmButton = {
            TextButton(enabled = phase == VoiceRecorder.Phase.RECORDED, onClick = {
                player.stop()
                saved = true
                // The take moves into place, so it's copied out of the recorder's cache name first.
                val file = File(context.cacheDir, "recording-${System.currentTimeMillis()}.m4a")
                if (recorder.take.renameTo(file)) onSave(file, recorder.seconds) else onCancel()
            }) { Text(stringResource(R.string.save), color = if (phase == VoiceRecorder.Phase.RECORDED) colors.accent else colors.secondaryText, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.accent) } },
        containerColor = colors.surface,
        titleContentColor = colors.text,
        textContentColor = colors.text,
    )
}

private const val TAKE = "take"
