package com.genesis.app.features

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.features.OptionalFeature

/**
 * A link (widget, notification) to a feature the person hid, as
 * FeatureOffView on iOS: "Prayer Journal is turned off", with its switch.
 * Nothing was deleted.
 */
@Composable
fun FeatureOffScreen(feature: OptionalFeature, onTurnOn: () -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val title = stringResource(feature.titleRes)
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Box(Modifier.weight(1f).padding(24.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.feature_is_off, title),
                    style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.feature_off_message), color = colors.secondaryText, textAlign = TextAlign.Center)
                Spacer(Modifier.height(6.dp))
                Button(onClick = onTurnOn, colors = ButtonDefaults.buttonColors(containerColor = colors.accent)) {
                    Text(stringResource(R.string.whats_new_turn_on, title))
                }
            }
        }
    }
}
