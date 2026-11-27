package com.genesis.app.widget

import android.content.Context
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.genesis.app.R
import com.genesis.core.domain.link.GenesisLink
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.genesis.core.domain.widgets.GroupWidgetSnapshot
import java.io.File
import java.time.LocalDate

/** Where the Group Progress widget's snapshot lives (the app's own files: the widget runs in its process). */
object GroupWidgetStore {
    private const val TAG = "GroupWidget"

    private fun file(context: Context) = File(context.noBackupFilesDir, "group-widget.json")

    suspend fun write(context: Context, snapshot: GroupWidgetSnapshot) {
        withContext(Dispatchers.IO) {
            runCatching { file(context).writeText(snapshot.encoded()) }.onFailure { Log.w(TAG, "Couldn't save the group widget", it) }
        }
        runCatching { GroupProgressWidget().updateAll(context) }
    }

    suspend fun clear(context: Context) {
        withContext(Dispatchers.IO) { file(context).delete() }
        runCatching { GroupProgressWidget().updateAll(context) }
    }

    fun read(context: Context): GroupWidgetSnapshot? =
        runCatching { file(context).takeIf { it.exists() }?.readText()?.let(GroupWidgetSnapshot::decode) }.getOrNull()
}

/** Your group's reading plan: who has read today and how far everyone has come. Free. */
class GroupProgressWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val first = withContext(Dispatchers.IO) { GroupWidgetStore.read(context) }
        provideContent { Content(reloaded(first) { withContext(Dispatchers.IO) { GroupWidgetStore.read(context) } }) }
    }

    @Composable
    private fun Content(snapshot: GroupWidgetSnapshot?) {
        val size = LocalSize.current
        val small = size.width < 250.dp
        if (snapshot == null) {
            WidgetCard(GenesisLink.HOME, small = small) {
                Symbol(R.drawable.ic_widget_book, size = 22)
                Spacer(GlanceModifier.height(8.dp))
                Text(string(R.string.widget_group_empty), style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontSize = 13.sp))
            }
            return
        }
        // A day later, nobody has read "today" yet as far as the widget knows.
        val current = snapshot.writtenOn == LocalDate.now().toString()
        val readToday = if (current) snapshot.readTodayCount else 0
        WidgetCard(GenesisLink.group(snapshot.groupId), small = small) {
            Text(snapshot.groupName.uppercase(), maxLines = 1, style = TextStyle(color = WidgetPalette.accent, fontWeight = FontWeight.Bold, fontSize = 10.sp))
            Spacer(GlanceModifier.height(8.dp))
            if (small) {
                Spacer(GlanceModifier.defaultWeight())
                Text(string(R.string.count_of_total, readToday, snapshot.memberCount), style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 26.sp))
                Caption(string(R.string.read_today_label))
                Spacer(GlanceModifier.defaultWeight())
                if (snapshot.day > 0) Caption(string(R.string.day_of_days, snapshot.day, snapshot.dayCount), size = 11)
                return@WidgetCard
            }
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    (if (current) snapshot.dayTitle else null) ?: snapshot.planTitle,
                    maxLines = 1,
                    style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 16.sp),
                    modifier = GlanceModifier.defaultWeight(),
                )
                if (snapshot.day > 0) Caption(string(R.string.day_of_days, snapshot.day, snapshot.dayCount), size = 11)
            }
            Spacer(GlanceModifier.height(8.dp))
            val rows = if (size.height >= 250.dp) 8 else 3
            for (member in snapshot.members.take(rows)) {
                val read = current && member.readToday
                Row(GlanceModifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
                    Symbol(if (read) R.drawable.ic_widget_check else R.drawable.ic_widget_circle, size = 12)
                    Spacer(GlanceModifier.width(8.dp))
                    Text(member.name, maxLines = 1, style = TextStyle(color = WidgetPalette.text, fontSize = 12.sp), modifier = GlanceModifier.width(80.dp))
                    Spacer(GlanceModifier.width(6.dp))
                    androidx.glance.layout.Box(GlanceModifier.defaultWeight()) { ProgressBar(member.fraction) }
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Caption(string(R.string.read_today_count, readToday, snapshot.memberCount), size = 11)
        }
    }
}

class GroupProgressReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GroupProgressWidget()
}
