package com.genesis.app.settings

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.reader.PremiumTag
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.theme.AppIconChoice

/** Settings › App Icon, as AppIconPickerView on iOS: the standard icon, Night, the seasons, or Seasons. */
@Composable
fun AppIconScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    var chosen by remember { mutableStateOf(AppIcons.choice(context)) }
    val premium = Entitlements.isPremium
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.app_icon),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp)) {
            AppIconChoice.entries.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { icon ->
                        val locked = icon.isPremium && !premium
                        IconTile(
                            icon = icon,
                            selected = icon == chosen.shown(premium),
                            locked = locked,
                            onClick = {
                                // The paywall comes with Google Play Billing; a locked icon stays a preview.
                                if (!locked) { chosen = icon; AppIcons.choose(context, icon) }
                            },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
                Spacer(Modifier.height(16.dp))
            }
            Text(stringResource(R.string.app_icon_seasons_note), color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
            if (!premium) {
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.app_icon_premium_note), color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun IconTile(icon: AppIconChoice, selected: Boolean, locked: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(
        modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .semantics { role = Role.RadioButton; this.selected = selected }
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(72.dp).clip(RoundedCornerShape(18.dp))
                .then(if (selected) Modifier.border(3.dp, colors.accent, RoundedCornerShape(18.dp)) else Modifier),
        ) {
            Image(
                painterResource(icon.preview),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(stringResource(icon.label), color = colors.text, style = MaterialTheme.typography.labelLarge, textAlign = TextAlign.Center)
        if (locked) PremiumTag() else if (selected) Text("✓", color = colors.accent)
    }
}

@get:StringRes
private val AppIconChoice.label: Int
    get() = when (this) {
        AppIconChoice.STANDARD -> R.string.app_icon_standard
        AppIconChoice.NIGHT -> R.string.theme_night
        AppIconChoice.AUTUMN -> R.string.theme_autumn
        AppIconChoice.WINTER -> R.string.theme_winter
        AppIconChoice.SPRING -> R.string.theme_spring
        AppIconChoice.SUMMER -> R.string.theme_summer
        AppIconChoice.SEASONS -> R.string.theme_seasons
    }

/** The picture shown in the picker (Seasons shows today's season). */
@get:DrawableRes
private val AppIconChoice.preview: Int
    get() = when (icon()) {
        AppIconChoice.NIGHT -> R.mipmap.ic_launcher_night_background
        AppIconChoice.AUTUMN -> R.mipmap.ic_launcher_autumn_background
        AppIconChoice.WINTER -> R.mipmap.ic_launcher_winter_background
        AppIconChoice.SPRING -> R.mipmap.ic_launcher_spring_background
        AppIconChoice.SUMMER -> R.mipmap.ic_launcher_summer_background
        else -> R.mipmap.ic_launcher
    }
