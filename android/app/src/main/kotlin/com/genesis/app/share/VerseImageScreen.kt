package com.genesis.app.share

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.genesis.app.R
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.reader.ReaderFont
import com.genesis.core.domain.share.VerseCard
import com.genesis.core.domain.share.VerseImageInk
import com.genesis.core.domain.share.VerseImageShape
import com.genesis.core.domain.share.VerseImageStyle
import com.genesis.core.domain.theme.ReaderTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private enum class SaveOutcome { SAVED, FAILED }

/**
 * Make an image of the selected verses to share or save, as VerseImageView
 * on iOS: Square, Story or Lock Screen; paper, a season, night or one of the
 * person's photos; the face, colour, size and alignment to taste.
 */
@Composable
fun VerseImageScreen(card: VerseCard, readingTheme: ReaderTheme, readingFont: ReaderFont, onDone: () -> Unit, offersLiveWallpaper: Boolean = true) {
    Dialog(onDismissRequest = onDone, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        VerseImageContent(card, readingTheme, readingFont, onDone, offersLiveWallpaper)
    }
}

@Composable
private fun VerseImageContent(card: VerseCard, readingTheme: ReaderTheme, readingFont: ReaderFont, onDone: () -> Unit, offersLiveWallpaper: Boolean) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val premium = Entitlements.isPremium
    var style by remember { mutableStateOf(VerseImageStyle.PAPER) }
    var shape by remember { mutableStateOf(VerseImageShape.SQUARE) }
    var options by remember { mutableStateOf(VerseImageOptions(font = readingFont.available(premium))) }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    var rendered by remember { mutableStateOf<Bitmap?>(null) }
    var outcome by remember { mutableStateOf<SaveOutcome?>(null) }

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            val image = withContext(Dispatchers.IO) { runCatching { loadPhoto(context, uri) }.getOrNull() } ?: return@launch
            photo = image
            style = VerseImageStyle.PHOTO
            if (options.ink == VerseImageInk.AUTOMATIC) options = options.copy(ink = VerseImageInk.WHITE)
        }
    }

    LaunchedEffect(style, shape, options, photo) {
        outcome = null
        rendered = withContext(Dispatchers.Default) {
            runCatching { VerseImageRenderer.render(context, card, style, shape, options, readingTheme, photo) }.getOrNull()
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text(stringResource(R.string.cancel), color = colors.accent) }
            Text(stringResource(R.string.verse_image), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextButton(onClick = { rendered?.let { share(context, it, card.reference) } }, enabled = rendered != null) {
                Text(stringResource(R.string.share), color = colors.accent, fontWeight = FontWeight.SemiBold)
            }
        }

        // The preview, the whole image fitted to the space.
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 20.dp), contentAlignment = Alignment.Center) {
            val ratio = shape.width.toFloat() / shape.height
            val preview = stringResource(R.string.preview_of, card.reference)
            val fitsWidth = maxWidth / maxHeight < ratio
            Box(
                Modifier
                    .aspectRatio(ratio, matchHeightConstraintsFirst = !fitsWidth)
                    .shadow(10.dp, RoundedCornerShape(14.dp))
                    .clip(RoundedCornerShape(14.dp))
                    .background(colors.surface)
                    .semantics { contentDescription = preview },
                contentAlignment = Alignment.Center,
            ) {
                val image = rendered
                if (image != null) Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                else CircularProgressIndicator(color = colors.accent)
                if (shape == VerseImageShape.LOCK_SCREEN) LockScreenGuide()
            }
        }

        // Save, and on the lock screen shape, set it as the wallpaper.
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = {
                    val image = rendered ?: return@Button
                    scope.launch { outcome = if (withContext(Dispatchers.IO) { saveToPhotos(context, image) } != null) SaveOutcome.SAVED else SaveOutcome.FAILED }
                },
                enabled = rendered != null,
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            ) {
                Text(
                    when (outcome) {
                        SaveOutcome.SAVED -> "✓ " + stringResource(R.string.saved_to_photos)
                        SaveOutcome.FAILED -> stringResource(R.string.couldnt_save_try_again)
                        null -> stringResource(R.string.save_to_photos)
                    },
                    fontWeight = FontWeight.SemiBold,
                )
            }
            if (shape == VerseImageShape.LOCK_SCREEN) {
                OutlinedButton(
                    onClick = { rendered?.let { setAsWallpaper(context, it) } },
                    enabled = rendered != null,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                ) { Text(stringResource(R.string.set_as_wallpaper), color = colors.accent) }
            }
        }

        // Premium: the same wallpaper with its season drifting (never a YouVersion Bible's text, as on iOS).
        val season = style.season
        if (shape == VerseImageShape.LOCK_SCREEN && season != null && offersLiveWallpaper) {
            OutlinedButton(
                onClick = {
                    scope.launch {
                        val moving = withContext(Dispatchers.Default) {
                            runCatching { VerseImageRenderer.render(context, card, style, shape, options, readingTheme, photo, seasonStill = false) }.getOrNull()
                        } ?: return@launch
                        LiveWallpaper.set(context, moving, season)
                    }
                },
                enabled = premium,
                modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 12.dp).heightIn(min = 48.dp),
            ) {
                Text(stringResource(R.string.set_as_live_wallpaper), color = if (premium) colors.accent else colors.secondaryText)
                if (!premium) {
                    androidx.compose.foundation.layout.Spacer(Modifier.width(8.dp))
                    com.genesis.app.reader.PremiumTag()
                }
            }
        }

        Column(Modifier.heightIn(max = 280.dp).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // Shape.
            Row(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(10.dp)).padding(3.dp)) {
                for (item in VerseImageShape.entries) {
                    val selected = item == shape
                    Text(
                        stringResource(item.titleRes),
                        color = if (selected) colors.background else colors.text,
                        style = MaterialTheme.typography.labelLarge,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (selected) colors.accent else Color.Transparent)
                            .clickable {
                                shape = item
                                // A wallpaper reads best centred under the clock.
                                if (item == VerseImageShape.LOCK_SCREEN) options = options.copy(centered = true)
                            }
                            .semantics { this.selected = selected; role = Role.Tab }
                            .padding(vertical = 8.dp),
                    )
                }
            }

            // Backgrounds.
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                for (item in VerseImageStyle.entries.filter { it != VerseImageStyle.PHOTO }) {
                    Swatch(stringResource(item.titleRes), selected = style == item, fill = Color(0xFF000000 or item.theme(readingTheme).palette.background.toLong())) { style = item }
                }
                if (photo != null) {
                    Swatch(stringResource(R.string.your_photo), selected = style == VerseImageStyle.PHOTO, fill = Color(0xFF3A3A3A)) { style = VerseImageStyle.PHOTO }
                }
                Swatch(stringResource(R.string.style_photo), selected = false, fill = colors.surface, mark = "+", label = stringResource(R.string.choose_a_photo)) {
                    pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
            }

            // Faces.
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (font in ReaderFont.entries.filter { it.isOffered && (!it.isPremium || premium) }) {
                    val selected = options.font == font
                    val family = rememberFontFamily(font)
                    Text(
                        "Aa",
                        fontFamily = family,
                        fontSize = 20.sp,
                        color = if (selected) colors.background else colors.text,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        modifier = Modifier
                            .width(52.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (selected) colors.accent else colors.surface)
                            .clickable { options = options.copy(font = font) }
                            .semantics { this.selected = selected; role = Role.RadioButton }
                            .padding(vertical = 8.dp),
                    )
                }
            }

            // Colours.
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                val paper = style.theme(readingTheme).palette
                for (ink in VerseImageInk.entries) {
                    val shown = Color(0xFF000000 or (ink.hex ?: paper.text.toLong()))
                    Swatch(stringResource(ink.titleRes), selected = options.ink == ink, fill = Color(0xFF000000 or paper.background.toLong()), mark = "A", markColor = shown) {
                        options = options.copy(ink = ink)
                    }
                }
            }

            // Size and alignment.
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("A", fontSize = 13.sp, color = colors.secondaryText)
                val sizeLabel = stringResource(R.string.text_size)
                Slider(
                    value = options.size.toFloat(),
                    onValueChange = { options = options.copy(size = it.toDouble()) },
                    valueRange = 0.7f..1.4f,
                    colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent),
                    modifier = Modifier.weight(1f).semantics { contentDescription = sizeLabel },
                )
                Text("A", fontSize = 20.sp, color = colors.secondaryText)
                Row(Modifier.background(colors.surface, RoundedCornerShape(10.dp)).padding(3.dp)) {
                    for ((centered, title) in listOf(false to R.string.align_left, true to R.string.align_center)) {
                        val selected = options.centered == centered
                        val label = stringResource(title)
                        Text(
                            if (centered) "≡" else "☰",
                            color = if (selected) colors.background else colors.text,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (selected) colors.accent else Color.Transparent)
                                .clickable { options = options.copy(centered = centered) }
                                .semantics { contentDescription = label; this.selected = selected; role = Role.RadioButton }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Swatch(title: String, selected: Boolean, fill: Color, mark: String? = null, markColor: Color? = null, label: String = title, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Column(
        Modifier.clickable(onClick = onClick).semantics(mergeDescendants = true) { contentDescription = label; this.selected = selected; role = Role.RadioButton },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.size(44.dp).background(fill, CircleShape).border(if (selected) 2.5.dp else 1.dp, if (selected) colors.accent else colors.separator, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (mark != null) Text(mark, color = markColor ?: colors.accent, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(title, style = MaterialTheme.typography.labelSmall, color = if (selected) colors.accent else colors.secondaryText)
    }
}

/** Where the lock screen's date and clock will be, drawn faintly over the preview only. */
@Composable
private fun LockScreenGuide() {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val now = java.util.Date()
        val date = android.text.format.DateFormat.format("EEEE, MMMM d", now).toString()
        val time = android.text.format.DateFormat.getTimeFormat(LocalContext.current).format(now).substringBefore(' ')
        val width = maxWidth.value
        Column(Modifier.fillMaxWidth().padding(top = maxHeight * 0.08f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(date, color = Color.White.copy(alpha = 0.75f), fontSize = (width * 0.045f).sp)
            Text(time, color = Color.White.copy(alpha = 0.75f), fontSize = (width * 0.2f).sp, fontWeight = FontWeight.Bold)
        }
    }
}

private val VerseImageShape.titleRes: Int
    get() = when (this) {
        VerseImageShape.SQUARE -> R.string.shape_square
        VerseImageShape.STORY -> R.string.shape_story
        VerseImageShape.LOCK_SCREEN -> R.string.shape_lock_screen
    }

private val VerseImageStyle.titleRes: Int
    get() = when (this) {
        VerseImageStyle.PAPER -> R.string.theme_paper
        VerseImageStyle.AUTUMN -> R.string.theme_autumn
        VerseImageStyle.WINTER -> R.string.theme_winter
        VerseImageStyle.SPRING -> R.string.theme_spring
        VerseImageStyle.SUMMER -> R.string.theme_summer
        VerseImageStyle.NIGHT -> R.string.theme_night
        VerseImageStyle.PHOTO -> R.string.style_photo
    }

private val VerseImageInk.titleRes: Int
    get() = when (this) {
        VerseImageInk.AUTOMATIC -> R.string.theme_automatic
        VerseImageInk.INK -> R.string.ink_ink
        VerseImageInk.WHITE -> R.string.ink_white
        VerseImageInk.CREAM -> R.string.theme_cream
        VerseImageInk.GOLD -> R.string.ink_gold
        VerseImageInk.NAVY -> R.string.ink_navy
    }

/** A chosen photo, at most 2160 pixels on its longer side. */
private fun loadPhoto(context: Context, uri: Uri): Bitmap {
    val source = ImageDecoder.createSource(context.contentResolver, uri)
    return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
        val longest = maxOf(info.size.width, info.size.height)
        if (longest > 2160) {
            val scale = 2160f / longest
            decoder.setTargetSize((info.size.width * scale).toInt(), (info.size.height * scale).toInt())
        }
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
}

/** Adds the image to the phone's photos (Pictures/Versely); no permission needed for Versely's own pictures. */
private fun saveToPhotos(context: Context, image: Bitmap): Uri? = runCatching {
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "Versely-${System.currentTimeMillis()}.png")
        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Versely")
        put(MediaStore.Images.Media.IS_PENDING, 1)
    }
    val resolver = context.contentResolver
    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
    resolver.openOutputStream(uri)?.use { image.compress(Bitmap.CompressFormat.PNG, 100, it) } ?: return null
    values.clear()
    values.put(MediaStore.Images.Media.IS_PENDING, 0)
    resolver.update(uri, values, null, null)
    uri
}.getOrNull()

/** The image as a file other apps can read, through Versely's file provider. */
private fun shareable(context: Context, image: Bitmap): Uri {
    val folder = File(context.cacheDir, "images").apply { mkdirs() }
    val file = File(folder, "verse.png")
    file.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
    return FileProvider.getUriForFile(context, context.packageName + ".files", file)
}

private fun share(context: Context, image: Bitmap, reference: String) {
    val uri = shareable(context, image)
    val send = Intent(Intent.ACTION_SEND).setType("image/png")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_TITLE, reference)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null))
}

/** Hands the image to the phone's own wallpaper screen, where the person picks the lock screen. */
private fun setAsWallpaper(context: Context, image: Bitmap) {
    val uri = shareable(context, image)
    val attach = Intent(Intent.ACTION_ATTACH_DATA).setDataAndType(uri, "image/png")
        .putExtra("mimeType", "image/png")
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(attach, null))
}
