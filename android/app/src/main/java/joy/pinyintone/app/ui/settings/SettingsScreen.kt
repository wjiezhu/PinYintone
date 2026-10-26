package joy.pinyintone.app.ui.settings

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PersistableBundle
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import joy.pinyintone.app.BuildConfig
import joy.pinyintone.app.R
import joy.pinyintone.app.audio.SamplePlayer
import joy.pinyintone.app.diagnostics.Diagnostics
import joy.pinyintone.app.ui.practice.Divider
import joy.pinyintone.app.ui.practice.TonePracticeViewModel
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.core.practice.FeedbackStyle

/**
 * 设置：反馈显示方式（学习者自选的显示偏好，不是实验条件）、诊断信息入口、版本号。
 * 登录、账号、语言等以后接。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(vm: TonePracticeViewModel, onBack: () -> Unit, onOpenDiagnostics: () -> Unit) {
    val c = Pt.colors
    val style by vm.style.collectAsStateWithLifecycle()
    BackHandler(onBack = onBack)
    Scaffold(
        containerColor = c.background,
        topBar = { BackTopBar(stringResource(R.string.settings_title), onBack) },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).navigationBarsPadding(),
        ) {
            SectionTitle(stringResource(R.string.settings_feedback_style))
            for ((s, label) in listOf(FeedbackStyle.DYNAMIC_F0 to R.string.condition_dynamicF0,
                                      FeedbackStyle.STATIC_COLOR to R.string.condition_staticColor)) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .selectable(selected = style == s, role = Role.RadioButton) { vm.setStyle(s) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(selected = style == s, onClick = null)
                    Text(stringResource(label), Modifier.padding(start = 12.dp), color = c.textPrimary)
                }
            }
            Text(stringResource(R.string.settings_feedback_style_footer), Modifier.padding(top = 4.dp, bottom = 16.dp),
                 style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
            Divider()
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(onClick = onOpenDiagnostics)
                    .padding(vertical = 12.dp).testTag("settings.diagnostics"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.diag_title), Modifier.weight(1f), color = c.textPrimary)
                // 箭头随阅读方向镜像（阿拉伯语里指向左）
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.textSecondary)
            }
            Divider()
            Text(stringResource(R.string.settings_app_version, ltr("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")),
                 Modifier.padding(vertical = 16.dp), style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
        }
    }
}

/**
 * 诊断信息：给试用的参与者复制后发给研究者。只有技术信息，没有录音内容与身份信息
 * （见 [Diagnostics]）。屏幕上用界面语言显示；复制出去的是固定英文键名的文本。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DiagnosticsScreen(player: SamplePlayer, onBack: () -> Unit) {
    val c = Pt.colors
    val context = LocalContext.current
    val tts by player.availability.collectAsStateWithLifecycle()
    var info by remember { mutableStateOf<Diagnostics?>(null) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(tts) { info = Diagnostics.collect(context, player) }
    BackHandler(onBack = onBack)

    Scaffold(
        containerColor = c.background,
        topBar = { BackTopBar(stringResource(R.string.diag_title), onBack) },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.diag_intro), color = c.textSecondary, style = MaterialTheme.typography.bodyMedium)
            val d = info ?: return@Column
            Column {
                Row(stringResource(R.string.diag_app_version), ltr(d.appVersion))
                Row(stringResource(R.string.diag_device), ltr("${d.manufacturer} ${d.model}"))
                Row(stringResource(R.string.diag_android), ltr("${d.androidVersion} (API ${d.apiLevel})"))
                val none = stringResource(R.string.diag_not_yet)
                Row(stringResource(R.string.diag_sample_rate), if (d.inputSampleRate == 0) none else ltr("${d.inputSampleRate} Hz"))
                Row(stringResource(R.string.diag_resampled), when (d.resampled) {
                    null -> none
                    true -> stringResource(R.string.diag_yes)
                    false -> stringResource(R.string.diag_no)
                })
                Row(stringResource(R.string.diag_audio_source), d.audioSource?.let(::ltr) ?: none)
                Row(stringResource(R.string.diag_last_voiced), d.latestAttempt?.voicedFrameCount?.toString() ?: none)
                Row(stringResource(R.string.diag_last_status), d.latestAttempt?.let { statusText(it) } ?: none)
                Row(stringResource(R.string.diag_chinese_tts), stringResource(when (d.chineseTts) {
                    SamplePlayer.Availability.READY -> R.string.diag_tts_ready
                    SamplePlayer.Availability.MISSING_CHINESE_VOICE -> R.string.diag_tts_missing
                    SamplePlayer.Availability.UNAVAILABLE -> R.string.diag_tts_unavailable
                    SamplePlayer.Availability.INITIALIZING -> R.string.diag_tts_checking
                }))
                Row(stringResource(R.string.diag_ui_language), ltr("${d.uiLanguage} (${d.systemLocale})"))
                Row(stringResource(R.string.diag_font_scale), ltr("×${d.fontScale}"))
            }
            // 按钮放不下时换行，不缩字
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { copy(context, d.asText()); copied = true },
                       Modifier.testTag("diagnostics.copy")) { Text(stringResource(R.string.diag_copy)) }
                OutlinedButton(onClick = { share(context, d.asText(), context.getString(R.string.diag_share_chooser)) },
                               Modifier.testTag("diagnostics.share")) { Text(stringResource(R.string.diag_share)) }
            }
            if (copied) {
                Text(stringResource(R.string.diag_copied), color = c.textPrimary, style = MaterialTheme.typography.bodyMedium)
            }
            Text(stringResource(R.string.diag_copy_note), color = c.textSecondary, style = MaterialTheme.typography.bodySmall)
            // 复制出去的原文（英文技术文本），左到右显示
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Text(d.asText(), Modifier.fillMaxWidth().background(c.secondaryBackground, RoundedCornerShape(6.dp))
                    .padding(12.dp).testTag("diagnostics.text"),
                     fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, color = c.textPrimary)
            }
        }
    }
}

/**
 * 技术值（版本号、型号、采样率）按左到右排：放进阿拉伯语界面时，括号与单位不被双向算法挪到另一头
 * （「Hz 16000」「(1) 0.1.0」那种）。用 Unicode 的左到右隔离符，不影响周围文字的方向。
 */
internal fun ltr(value: String): String = "\u2066$value\u2069"

@Composable
private fun statusText(a: Diagnostics.Attempt): String = when (a.resultStatus) {
    "valid_result" -> stringResource(R.string.diag_status_valid)
    "quality_flagged" -> stringResource(R.string.diag_status_flagged)
    "technical_retry" -> stringResource(R.string.diag_status_retry, when (a.failureReason) {
        "insufficient_voiced_frames" -> stringResource(R.string.diag_reason_insufficient_voiced_frames)
        "permission_denied" -> stringResource(R.string.diag_reason_permission_denied)
        "recording_interrupted" -> stringResource(R.string.diag_reason_recording_interrupted)
        "low_signal_quality" -> stringResource(R.string.diag_reason_low_signal_quality)
        "analysis_error" -> stringResource(R.string.diag_reason_analysis_error)
        else -> a.failureReason ?: "?"
    })
    else -> a.resultStatus ?: "?"
}

/** 一行：标签在上、值在下（长型号、放大字号时都不挤，不缩字） */
@Composable
private fun Row(label: String, value: String) {
    val c = Pt.colors
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp).semantics(mergeDescendants = true) {}) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = c.textPrimary)
    }
    Divider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BackTopBar(title: String, onBack: () -> Unit) {
    val c = Pt.colors
    TopAppBar(
        title = { Text(title, color = c.textPrimary) },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = c.background),
        navigationIcon = {
            IconButton(onClick = onBack) {
                // 返回箭头随阅读方向镜像
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close), tint = c.textPrimary)
            }
        },
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, Modifier.padding(top = 16.dp, bottom = 4.dp).semantics { heading() },
         style = MaterialTheme.typography.titleSmall, color = Pt.colors.textPrimary)
}

private fun copy(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText("Pinyintone diagnostics", text)
    // 诊断文本不敏感：Android 13+ 剪贴板预览照常显示
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) }
    }
    cm.setPrimaryClip(clip)
}

private fun share(context: Context, text: String, chooserTitle: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, chooserTitle))
}
