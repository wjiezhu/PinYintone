package joy.pinyintone.app.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import joy.pinyintone.app.R
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.app.update.UpdateChecker
import joy.pinyintone.core.update.AppUpdate

/**
 * 新版本提示：练习页顶部的一块，不弹框、不挡练习。
 * 可选更新可以关掉（这个版本不再提示）；低于最低支持版本时关不掉，但练习照常（禁令 19）。
 * 「下载」交给系统浏览器，App 内不下载、不安装。
 */
@Composable
fun UpdateBanner(prompt: AppUpdate.Prompt, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val c = Pt.colors
    val context = LocalContext.current
    val language = LocalConfiguration.current.locales[0].language
    val required = prompt is AppUpdate.Prompt.Required
    val release = prompt.release
    var openFailed by remember { mutableStateOf(false) }
    Column(
        modifier.fillMaxWidth().background(c.blueSurface, RoundedCornerShape(6.dp)).padding(12.dp)
            .testTag(if (required) "update.required" else "update.optional"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Filled.Info, null, Modifier.padding(top = 2.dp, end = 8.dp), tint = c.textPrimary)
            Text(
                if (required) stringResource(R.string.update_required_title)
                else stringResource(R.string.update_available_title, ltr(release.latestVersionName)),
                Modifier.weight(1f).semantics { heading() },
                style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = c.textPrimary,
            )
            if (!required) {
                IconButton(onClick = onDismiss, Modifier.testTag("update.dismiss")) {
                    Icon(Icons.Filled.Close, stringResource(R.string.common_dismiss), tint = c.textSecondary)
                }
            }
        }
        Text(
            if (required) stringResource(R.string.update_required_body, ltr(release.latestVersionName))
            else stringResource(R.string.update_available_body),
            style = MaterialTheme.typography.bodyMedium, color = c.textPrimary,
        )
        release.notesFor(language)?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
        }
        Button(onClick = { openFailed = !UpdateChecker.openInBrowser(context, release.downloadUrl) },
               Modifier.testTag("update.download")) {
            Text(stringResource(R.string.update_download))
        }
        if (openFailed) {
            Text(stringResource(R.string.update_open_failed, ltr(release.downloadUrl)),
                 style = MaterialTheme.typography.bodyMedium, color = c.textPrimary)
        }
    }
}
