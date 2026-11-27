package com.genesis.app.widget

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontStyle
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.genesis.app.R
import com.genesis.core.domain.home.TextFit
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import java.time.LocalDate

/**
 * A keepsake verse widget (KeepsakeWidgets.swift on iOS): linen behind a
 * cream text card and a picture card, side by side in the medium widget,
 * the picture above in the large one, one card in the small one. The verse
 * is written over the text card verbatim; the pictures hold no words.
 */
@Composable
internal fun KeepsakeContent(
    style: WidgetArtStyle,
    title: String,
    text: String,
    citation: String,
    premiumTag: Boolean,
    photo: Bitmap?,
    open: Action,
) {
    val context = LocalContext.current
    val size = LocalSize.current
    val shape = WidgetArtShape.of(size.width.value, size.height.value)
    val date = LocalDate.now()
    val reference = citation.substringBefore(" · ")
    val inset = 10.dp
    val gap = 8.dp
    val inner = androidx.compose.ui.unit.DpSize(size.width - inset * 2, size.height - inset * 2)

    @Composable
    fun Picture(width: Dp, height: Dp, caption: String? = null) {
        val bitmap = Keepsakes.pictureCard(context, style, width.value, height.value, shape, photo, date, caption)
        Image(ImageProvider(bitmap), contentDescription = null, contentScale = ContentScale.FillBounds, modifier = GlanceModifier.size(width, height))
    }

    Box(GlanceModifier.fillMaxSize().cornerRadius(20.dp).clickable(open)) {
        Image(ImageProvider(R.drawable.keepsake_linen), contentDescription = null, contentScale = ContentScale.Crop, modifier = GlanceModifier.fillMaxSize())
        Box(GlanceModifier.fillMaxSize().padding(inset)) {
            when (shape) {
                WidgetArtShape.MEDIUM -> Row(GlanceModifier.fillMaxSize()) {
                    val pictureWidth = 118.dp
                    TextCard(style, title, text, citation, premiumTag, inner.width - gap - pictureWidth, inner.height, small = false)
                    Spacer(GlanceModifier.width(gap))
                    Picture(pictureWidth, inner.height)
                }
                WidgetArtShape.LARGE -> Column(GlanceModifier.fillMaxSize()) {
                    val pictureHeight = 168.dp
                    Picture(inner.width, pictureHeight)
                    Spacer(GlanceModifier.height(gap))
                    TextCard(style, title, text, citation, premiumTag, inner.width, inner.height - gap - pictureHeight, small = false)
                }
                WidgetArtShape.SMALL -> when {
                    // The instant print with the reference written on its border.
                    style == WidgetArtStyle.INSTANT_PHOTO -> Picture(inner.width, inner.height, caption = reference)
                    // The picture with its reference, when the picture is the point or the verse won't fit.
                    style == WidgetArtStyle.PRESSED_FLOWERS || style == WidgetArtStyle.FILM_STRIP || text.length > 110 ->
                        Box(GlanceModifier.size(inner.width, inner.height), contentAlignment = Alignment.BottomCenter) {
                            Picture(inner.width, inner.height)
                            Text(
                                reference,
                                maxLines = 1,
                                style = TextStyle(color = fixed(Keepsakes.INK), fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 12.sp),
                                modifier = GlanceModifier.padding(bottom = 6.dp).background(ColorProvider(Color(0xF2F7F2E9))).cornerRadius(10.dp).padding(horizontal = 10.dp, vertical = 4.dp),
                            )
                        }
                    else -> TextCard(style, title, text, citation, premiumTag, inner.width, inner.height, small = true)
                }
            }
        }
    }
}

private fun fixed(hex: Long) = ColorProvider(Color(hex))

/** The cream card the verse is written on, in each keepsake's own hand. */
@Composable
private fun TextCard(style: WidgetArtStyle, title: String, text: String, citation: String, premiumTag: Boolean, width: Dp, height: Dp, small: Boolean) {
    val context = LocalContext.current
    val card = Keepsakes.textCard(context, style, width.value, height.value, small)
    val typewriter = style == WidgetArtStyle.TYPEWRITER
    val library = style == WidgetArtStyle.LIBRARY_CARD
    val top = when {
        style == WidgetArtStyle.FILM_STRIP -> 20.dp
        library -> 9.dp
        else -> if (small) 12.dp else 14.dp
    }
    val side = if (library) 22.dp else if (small) 12.dp else 14.dp
    val bottom = if (style == WidgetArtStyle.FILM_STRIP) 18.dp else if (small) 10.dp else 12.dp
    val header = 30.dp
    val fit = TextFit.fit(
        characters = text.length,
        widthDp = (width - side * 2).value.toDouble() * (if (typewriter) 0.85 else 1.0),
        heightDp = (height - top - bottom - header - 20.dp).value.toDouble(),
        largest = if (small) 14 else if (height > 160.dp) 18 else 15,
        smallest = 10,
    )
    Box(GlanceModifier.size(width, height)) {
        Image(ImageProvider(card), contentDescription = null, contentScale = ContentScale.FillBounds, modifier = GlanceModifier.fillMaxSize())
        Column(GlanceModifier.fillMaxSize().padding(start = side, end = side, top = top, bottom = bottom)) {
            Row(GlanceModifier.fillMaxWidth().height(if (library) 22.dp else 16.dp), verticalAlignment = Alignment.CenterVertically) {
                if (library) {
                    Text(
                        context.getString(R.string.due_for_today).uppercase(),
                        maxLines = 1,
                        style = TextStyle(color = fixed(Keepsakes.TERRACOTTA), fontWeight = FontWeight.Bold, fontSize = 10.sp),
                    )
                } else {
                    Eyebrow(title, fixed(Keepsakes.SAGE))
                }
                if (premiumTag) {
                    Spacer(GlanceModifier.defaultWeight())
                    Text(context.getString(R.string.premium), style = TextStyle(color = fixed(Keepsakes.TERRACOTTA), fontWeight = FontWeight.Bold, fontSize = 9.sp))
                }
            }
            Spacer(GlanceModifier.height(if (library) 8.dp else 6.dp))
            Text(
                text,
                maxLines = fit.maxLines,
                style = TextStyle(
                    color = fixed(if (typewriter) Keepsakes.INK else Keepsakes.BODY),
                    fontFamily = if (typewriter) FontFamily.Monospace else FontFamily.Serif,
                    fontSize = fit.fontSizeSp.sp,
                ),
                modifier = GlanceModifier.defaultWeight(),
            )
            Spacer(GlanceModifier.height(4.dp))
            Text(
                citation.replace(" · ", " — "),
                maxLines = 1,
                style = TextStyle(
                    color = fixed(if (typewriter) Keepsakes.FADED_RED else Keepsakes.SAGE),
                    fontFamily = if (typewriter) FontFamily.Monospace else FontFamily.Serif,
                    fontStyle = if (typewriter) FontStyle.Normal else FontStyle.Italic,
                    fontSize = 11.sp,
                ),
            )
        }
    }
}
