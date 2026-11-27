package com.genesis.app

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/** The tab bar's line icons, drawn so the app needs no icon library. */
@Composable
internal fun TabIcon(tab: AppTab, color: Color) {
    Canvas(Modifier.size(24.dp)) {
        val w = size.width
        val h = size.height
        val stroke = Stroke(width = w * 0.075f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        when (tab) {
            AppTab.HOME -> {
                val house = Path().apply {
                    moveTo(w * 0.14f, h * 0.46f)
                    lineTo(w * 0.5f, h * 0.14f)
                    lineTo(w * 0.86f, h * 0.46f)
                    moveTo(w * 0.24f, h * 0.38f)
                    lineTo(w * 0.24f, h * 0.86f)
                    lineTo(w * 0.76f, h * 0.86f)
                    lineTo(w * 0.76f, h * 0.38f)
                    moveTo(w * 0.42f, h * 0.86f)
                    lineTo(w * 0.42f, h * 0.62f)
                    lineTo(w * 0.58f, h * 0.62f)
                    lineTo(w * 0.58f, h * 0.86f)
                }
                drawPath(house, color, style = stroke)
            }
            AppTab.READ -> {
                // An open book.
                val book = Path().apply {
                    moveTo(w * 0.5f, h * 0.28f)
                    cubicTo(w * 0.38f, h * 0.2f, w * 0.22f, h * 0.2f, w * 0.1f, h * 0.24f)
                    lineTo(w * 0.1f, h * 0.8f)
                    cubicTo(w * 0.22f, h * 0.76f, w * 0.38f, h * 0.76f, w * 0.5f, h * 0.84f)
                    cubicTo(w * 0.62f, h * 0.76f, w * 0.78f, h * 0.76f, w * 0.9f, h * 0.8f)
                    lineTo(w * 0.9f, h * 0.24f)
                    cubicTo(w * 0.78f, h * 0.2f, w * 0.62f, h * 0.2f, w * 0.5f, h * 0.28f)
                    lineTo(w * 0.5f, h * 0.84f)
                }
                drawPath(book, color, style = stroke)
            }
            AppTab.LIBRARY -> {
                // Three books on a shelf, one leaning.
                val radius = CornerRadius(w * 0.03f)
                drawRoundRect(color, Offset(w * 0.14f, h * 0.18f), Size(w * 0.16f, h * 0.66f), radius, style = stroke)
                drawRoundRect(color, Offset(w * 0.36f, h * 0.26f), Size(w * 0.16f, h * 0.58f), radius, style = stroke)
                val leaning = Path().apply {
                    moveTo(w * 0.6f, h * 0.3f)
                    lineTo(w * 0.73f, h * 0.24f)
                    lineTo(w * 0.9f, h * 0.78f)
                    lineTo(w * 0.77f, h * 0.84f)
                    close()
                }
                drawPath(leaning, color, style = stroke)
            }
        }
    }
}
