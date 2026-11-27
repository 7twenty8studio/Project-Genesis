package com.genesis.app.widget

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Row_
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.widgets.PhotoFraming
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Settings › Widget Photo, as WidgetPhotoSettingsView on iOS: choose, adjust
 * or remove the photo the Your Photo widget style shows. It stays on this phone.
 */
@Composable
fun WidgetPhotoScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val version by WidgetPhoto.version.collectAsStateWithLifecycle()
    var adjusting by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    val has = remember(version) { WidgetPhoto.exists(context) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            working = true
            scope.launch {
                // Chosen for a widget: the widgets follow it once the style is Your Photo.
                if (WidgetPhoto.save(context, uri)) WidgetStylePreference.set(context, WidgetArtStyle.PHOTO)
                working = false
            }
        }
    }
    if (adjusting) {
        PhotoFramingScreen(onDone = { adjusting = false }, modifier = modifier)
        return
    }
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.widget_photo),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            val picture by produceState<Bitmap?>(null, version) { value = WidgetArtLoad.load(context, WidgetArtShape.MEDIUM) }
            Box(
                Modifier.widthIn(max = 360.dp).fillMaxWidth().aspectRatio(WidgetArtShape.MEDIUM.width.toFloat() / WidgetArtShape.MEDIUM.height)
                    .clip(RoundedCornerShape(20.dp)).background(colors.surface),
                contentAlignment = Alignment.Center,
            ) {
                val current = picture
                if (current != null) {
                    Image(current.asImageBitmap(), contentDescription = stringResource(R.string.widget_photo_preview), contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    Text(
                        stringResource(R.string.verse_of_the_day).uppercase(),
                        color = Color(0xFFEBC08F), fontSize = 10.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.align(Alignment.TopStart).padding(18.dp),
                    )
                } else if (working) {
                    CircularProgressIndicator(color = colors.accent)
                } else {
                    Text(stringResource(R.string.no_photo_chosen), color = colors.secondaryText)
                }
            }
            Spacer(Modifier.size(16.dp))
            Group {
                Row_(stringResource(if (has) R.string.change_photo else R.string.choose_photo), onClick = { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, trailing = "›", icon = "🖼")
                if (has) {
                    Row_(stringResource(R.string.adjust_photo), onClick = { adjusting = true }, trailing = "›", icon = "✥")
                    Row_(stringResource(R.string.remove_photo), onClick = { scope.launch { WidgetPhoto.remove(context) } }, icon = "✕")
                }
            }
            Footer(stringResource(R.string.widget_photo_footer))
        }
    }
}

/** The framed photo for one shape, if there is one. */
private object WidgetArtLoad {
    suspend fun load(context: android.content.Context, shape: WidgetArtShape): Bitmap? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { WidgetArt.load(context, WidgetArtStyle.PHOTO, shape) }
}

/**
 * Adjust Photo, as WidgetPhotoFramingView on iOS: drag to move the photo and
 * pinch to zoom; each widget size keeps its own framing (`PhotoFraming`).
 */
@Composable
private fun PhotoFramingScreen(onDone: () -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val photo by produceState<Bitmap?>(null) { value = WidgetPhoto.photo(context) }
    var shape by remember { mutableStateOf(WidgetArtShape.MEDIUM) }
    val framings = remember { mutableStateMapOf<WidgetArtShape, PhotoFraming>().apply { WidgetArtShape.entries.forEach { put(it, WidgetPhoto.framing(context, it)) } } }
    androidx.activity.compose.BackHandler { onDone() }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 8.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text(stringResource(R.string.cancel), color = colors.accent) }
            Text(
                stringResource(R.string.adjust_photo),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = {
                scope.launch {
                    WidgetPhoto.saveFramings(context, framings.toMap())
                    onDone()
                }
            }) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.surface).padding(3.dp)) {
                WidgetArtShape.entries.forEach { option ->
                    val selected = option == shape
                    Text(
                        stringResource(
                            when (option) {
                                WidgetArtShape.SMALL -> R.string.widget_size_small
                                WidgetArtShape.MEDIUM -> R.string.widget_size_medium
                                WidgetArtShape.LARGE -> R.string.widget_size_large
                            },
                        ),
                        color = if (selected) colors.text else colors.secondaryText,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                            .background(if (selected) colors.background else Color.Transparent)
                            .semantics { this.selected = selected }
                            .clickable(role = Role.Tab) { shape = option }
                            .padding(vertical = 8.dp),
                    )
                }
            }
            val image = photo
            if (image == null) {
                CircularProgressIndicator(color = colors.accent)
            } else {
                Frame(image, shape, framings[shape] ?: PhotoFraming()) { framings[shape] = it }
            }
            Text(stringResource(R.string.adjust_photo_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            TextButton(onClick = { framings[shape] = PhotoFraming() }) { Text(stringResource(R.string.reset), color = colors.accent) }
        }
    }
}

/** The photo in the widget's shape, cut exactly as it will be saved, following drags and pinches. */
@Composable
private fun Frame(photo: Bitmap, shape: WidgetArtShape, framing: PhotoFraming, onChange: (PhotoFraming) -> Unit) {
    val image = remember(photo) { photo.asImageBitmap() }
    val description = stringResource(R.string.widget_photo_in_widget)
    val current by androidx.compose.runtime.rememberUpdatedState(framing)
    BoxWithConstraints(
        Modifier.widthIn(max = if (shape == WidgetArtShape.SMALL) 220.dp else 420.dp).fillMaxWidth()
            .aspectRatio(shape.width.toFloat() / shape.height)
            .clip(RoundedCornerShape(20.dp))
            .semantics { contentDescription = description },
    ) {
        val density = LocalDensity.current
        val frameW = with(density) { maxWidth.toPx() }.toDouble()
        val frameH = with(density) { maxHeight.toPx() }.toDouble()
        val w = photo.width.toDouble()
        val h = photo.height.toDouble()
        Canvas(
            Modifier.fillMaxSize().pointerInput(shape, photo) {
                detectTransformGestures { _, pan, zoom, _ ->
                    var next = current
                    if (zoom != 1f) next = next.zoomed(zoom.toDouble(), w, h, frameW / frameH)
                    next = next.panned(pan.x.toDouble(), pan.y.toDouble(), frameW, frameH, w, h)
                    onChange(next)
                }
            },
        ) {
            val crop = framing.crop(w, h, frameW / frameH)
            drawImage(
                image,
                srcOffset = IntOffset(crop.x.roundToInt(), crop.y.roundToInt()),
                srcSize = IntSize(crop.width.roundToInt().coerceIn(1, photo.width), crop.height.roundToInt().coerceIn(1, photo.height)),
                dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
            )
            drawRect(Color.Black.copy(alpha = 0.22f), topLeft = Offset.Zero, size = size)
        }
    }
}
