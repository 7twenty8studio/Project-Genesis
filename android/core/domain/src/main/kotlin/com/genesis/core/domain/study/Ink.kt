package com.genesis.core.domain.study

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToLong

/**
 * Versely Ink: a handwritten page that iPhone, iPad and Android all read and
 * write (docs/HANDWRITING_FORMAT.md). iOS converts it to and from PencilKit;
 * Android draws it itself. Pure, so both apps test the same cases
 * (supabase/functions/_shared/fixtures/ink.json).
 */
enum class InkType(val id: String) {
    PEN("pen"), PENCIL("pencil"), MARKER("marker"), MONOLINE("monoline"),
    FOUNTAIN_PEN("fountainPen"), WATERCOLOR("watercolor"), CRAYON("crayon");

    companion object {
        /** An unknown type is drawn as a pen. */
        fun of(id: String?): InkType = entries.firstOrNull { it.id == id } ?: PEN
    }
}

/** A control point: position in page points, the nib's width there, and its opacity. */
data class InkPoint(val x: Double, val y: Double, val size: Double, val opacity: Double = 1.0)

/** One stroke; [color] is sRGB 0xRRGGBBAA. */
data class InkStroke(val ink: InkType, val color: Long, val points: List<InkPoint>)

data class InkPage(val strokes: List<InkStroke> = emptyList(), val width: Double = PAGE_WIDTH) {
    val isEmpty get() = strokes.isEmpty()

    /** How far down the writing goes, in page points (0 for an empty page). */
    val bottom: Double get() = strokes.maxOfOrNull { s -> s.points.maxOf { it.y + it.size / 2 } } ?: 0.0

    companion object {
        /** HandwritingLayout.pageWidth on iOS. */
        const val PAGE_WIDTH = 768.0
        /** Ruled lines' spacing, in page points (HandwritingLayout.lineSpacing). */
        const val LINE_SPACING = 44.0
        /** Room below the writing (HandwritingLayout.overscroll). */
        const val OVERSCROLL = 400.0
    }
}

object InkFormat {
    const val FORMAT = "versely-ink"
    const val VERSION = 1

    /** The database's limit on notes.ink, in bytes (as notes.drawing). */
    const val MAX_SYNCED_BYTES = 2_097_152

    /**
     * Whether pages sync (notes.ink, migration 20261129000000). Off until
     * that migration has run: pages then stay on the device, kept through
     * pulls, and go up once it's turned on (they stay marked as edited).
     */
    const val SYNCS = false

    private val json = Json { ignoreUnknownKeys = true }

    /** The page as JSON text; null for an empty page (a note without one). */
    fun encode(page: InkPage): String? {
        if (page.isEmpty) return null
        val root = buildJsonObject {
            put("format", FORMAT)
            put("version", VERSION)
            put("width", number(page.width))
            put("strokes", JsonArray(page.strokes.map { stroke ->
                buildJsonObject {
                    put("ink", stroke.ink.id)
                    put("color", hex(stroke.color))
                    put("points", JsonArray(stroke.points.map { p ->
                        JsonArray(listOf(number(p.x), number(p.y), number(p.size), number(p.opacity)))
                    }))
                }
            }))
        }
        return root.toString()
    }

    /** Reads a page; null when the text isn't Versely Ink (or is a newer version this app can't read). */
    fun decode(text: String?): InkPage? {
        if (text.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return null
        if (root["format"]?.jsonPrimitive?.content != FORMAT) return null
        val version = root["version"]?.jsonPrimitive?.intOrNull ?: return null
        if (version > VERSION) return null
        val width = root["width"]?.jsonPrimitive?.doubleOrNull?.takeIf { it > 0 } ?: InkPage.PAGE_WIDTH
        val strokes = runCatching { root["strokes"]?.jsonArray }.getOrNull().orEmpty().mapNotNull { element ->
            val stroke = element as? JsonObject ?: return@mapNotNull null
            val color = stroke["color"]?.jsonPrimitive?.content?.let(::parseHex) ?: 0x000000FFL
            val points = runCatching { stroke["points"]?.jsonArray }.getOrNull().orEmpty().mapNotNull { point ->
                val values = (point as? JsonArray)?.map { it.jsonPrimitive.doubleOrNull } ?: return@mapNotNull null
                val x = values.getOrNull(0) ?: return@mapNotNull null
                val y = values.getOrNull(1) ?: return@mapNotNull null
                InkPoint(x, y, values.getOrNull(2)?.takeIf { it > 0 } ?: 2.0, (values.getOrNull(3) ?: 1.0).coerceIn(0.0, 1.0))
            }
            if (points.isEmpty()) null else InkStroke(InkType.of(stroke["ink"]?.jsonPrimitive?.content), color, points)
        }
        return InkPage(strokes, width)
    }

    /** True when the page (or no page) can go to the server. */
    fun fitsSync(text: String?): Boolean = text == null || text.encodeToByteArray().size <= MAX_SYNCED_BYTES

    fun hex(color: Long): String = "%08X".format(color and 0xFFFFFFFFL)

    fun parseHex(text: String): Long? {
        val clean = text.removePrefix("#")
        return when (clean.length) {
            8 -> clean.toLongOrNull(16)
            6 -> clean.toLongOrNull(16)?.let { (it shl 8) or 0xFF }
            else -> null
        }
    }

    /** Two decimals at most, and whole numbers without a fraction, so pages stay small. */
    private fun number(value: Double): JsonPrimitive {
        val rounded = (value * 100).roundToLong() / 100.0
        return if (rounded == rounded.toLong().toDouble() && abs(rounded) < 1e15) JsonPrimitive(rounded.toLong()) else JsonPrimitive(rounded)
    }
}

/**
 * The curve through a stroke's control points: a uniform cubic B-spline, as
 * PencilKit's PKStrokePath. Android draws strokes by sampling it.
 */
object InkSpline {
    /** Points along the stroke, about [step] page points apart (a single control point is a dot). */
    fun sample(points: List<InkPoint>, step: Double = 2.0): List<InkPoint> {
        if (points.size <= 1) return points
        if (points.size < 4) {
            // Too few for a cubic segment: pad the ends as writers do.
            return sample(pad(points), step)
        }
        val out = ArrayList<InkPoint>()
        for (i in 0 until points.size - 3) {
            val p0 = points[i]; val p1 = points[i + 1]; val p2 = points[i + 2]; val p3 = points[i + 3]
            val length = hypot(p2.x - p1.x, p2.y - p1.y)
            val steps = (length / step).toInt().coerceIn(1, 64)
            val first = if (i == 0) 0 else 1
            for (k in first..steps) out += at(p0, p1, p2, p3, k.toDouble() / steps)
        }
        return out
    }

    /** One point of the segment between p1 and p2, t in 0..1. */
    fun at(p0: InkPoint, p1: InkPoint, p2: InkPoint, p3: InkPoint, t: Double): InkPoint {
        val t2 = t * t
        val t3 = t2 * t
        val b0 = (1 - t) * (1 - t) * (1 - t) / 6
        val b1 = (3 * t3 - 6 * t2 + 4) / 6
        val b2 = (-3 * t3 + 3 * t2 + 3 * t + 1) / 6
        val b3 = t3 / 6
        fun mix(f: (InkPoint) -> Double) = b0 * f(p0) + b1 * f(p1) + b2 * f(p2) + b3 * f(p3)
        return InkPoint(mix { it.x }, mix { it.y }, mix { it.size }, mix { it.opacity })
    }

    /** The first and last points repeated twice more, so the curve reaches both ends. */
    fun pad(points: List<InkPoint>): List<InkPoint> {
        if (points.isEmpty()) return points
        return listOf(points.first(), points.first()) + points + listOf(points.last(), points.last())
    }
}

/**
 * Turns finger or stylus samples into a stroke: drops points closer than
 * half a point to the last one kept, then pads the ends.
 */
object InkCapture {
    fun stroke(ink: InkType, color: Long, samples: List<InkPoint>): InkStroke? {
        if (samples.isEmpty()) return null
        val kept = ArrayList<InkPoint>(samples.size)
        for (sample in samples) {
            val last = kept.lastOrNull()
            if (last == null || hypot(sample.x - last.x, sample.y - last.y) >= 0.5) kept += sample
        }
        if (kept.last() != samples.last()) kept[kept.lastIndex] = samples.last()
        return InkStroke(ink, color, if (kept.size == 1) kept else InkSpline.pad(kept))
    }

    /** The nib's width for a pressure (0..1) and the chosen width, as PencilKit's pen roughly does. */
    fun size(ink: InkType, width: Double, pressure: Double): Double {
        val p = pressure.coerceIn(0.0, 1.0)
        return when (ink) {
            InkType.MARKER, InkType.MONOLINE -> width
            InkType.PENCIL, InkType.CRAYON -> width * (0.6 + 0.6 * p)
            else -> width * (0.55 + 0.9 * p)
        }
    }
}

/** Erasing whole strokes, as PencilKit's object eraser: any stroke passing within [radius] of the point. */
object InkEraser {
    fun erase(page: InkPage, x: Double, y: Double, radius: Double): InkPage {
        val kept = page.strokes.filterNot { stroke ->
            InkSpline.sample(stroke.points, 4.0).any { hypot(it.x - x, it.y - y) <= radius + it.size / 2 }
        }
        return if (kept.size == page.strokes.size) page else page.copy(strokes = kept)
    }
}
