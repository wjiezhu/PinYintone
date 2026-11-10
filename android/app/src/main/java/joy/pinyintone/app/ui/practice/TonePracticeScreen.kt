package joy.pinyintone.app.ui.practice

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.speech.tts.TextToSpeech
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import joy.pinyintone.app.PinyintoneApp
import joy.pinyintone.app.R
import joy.pinyintone.app.audio.SamplePlayer
import joy.pinyintone.app.ui.settings.UpdateBanner
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.core.practice.FeedbackStyle
import joy.pinyintone.core.practice.TonePracticeSession
import joy.pinyintone.core.practice.TonePracticeSession.Mode
import joy.pinyintone.core.practice.TonePracticeSession.Stage

/**
 * 声调练习页（需求 U03 / R06）。对应 iOS `ToneTrainingView`。
 *
 * 自上而下：汉字、拼音、释义 → 曲线 / 颜色切换 → 反馈图 → 本次结果或失败说明 → 底部固定操作栏。
 * **底部操作栏**：听示范 · 录音/停止 · 下一词，三格等宽，录音键恒在正中，任何状态都不动；
 * 自测里用不上的两格留空占位。内容多了由上面滚动，不缩字。
 * 打开就是普通练习；自测在右上角的次级菜单里，由学习者主动开始，可随时退出。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TonePracticeScreen(vm: TonePracticeViewModel, onOpenSettings: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val style by vm.style.collectAsStateWithLifecycle()
    val sampleAvailability by vm.player.availability.collectAsStateWithLifecycle()
    val samplePlaying by vm.player.playing.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val app = context.applicationContext as PinyintoneApp
    val c = Pt.colors
    val updatePrompt by app.updates.prompt.collectAsStateWithLifecycle()

    var showWordPicker by rememberSaveable { mutableStateOf(false) }
    var showMicExplanation by rememberSaveable { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var sampleProblem by remember { mutableStateOf<SamplePlayer.Availability?>(null) }

    // ---- 麦克风权限：首次实际录音前申请（不在启动时）；先用所选语言说明用途 ----
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        app.practiceStore.micPermissionRequested = true
        if (granted) vm.toggleRecording() else vm.onPermissionDenied()
    }
    fun onRecordTap() {
        if (ui.isRecording) { vm.toggleRecording(); return }
        val granted = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val activity = context as? Activity
        when {
            granted -> vm.toggleRecording()
            // 还没问过，或者系统允许再解释一次：先说明用途，再弹系统授权框
            !app.practiceStore.micPermissionRequested ||
                activity?.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) == true ->
                showMicExplanation = true
            // 已被永久拒绝：系统不会再弹框。给出去系统设置的入口（失败块里的按钮），不静默
            else -> vm.onPermissionDenied()
        }
    }

    BackHandler(enabled = ui.mode == Mode.SELF_TEST) { vm.endSelfTest() }

    val title = stringResource(if (ui.mode == Mode.SELF_TEST) R.string.self_test_title else R.string.stage2_title)
    Scaffold(
        containerColor = c.background,
        topBar = {
            PtTopBar(
                title = title,
                navigationIcon = {
                    if (ui.mode == Mode.SELF_TEST) {
                        IconButton(onClick = { vm.endSelfTest() }) {
                            Icon(Icons.Filled.Close, stringResource(R.string.self_test_exit), tint = c.textPrimary)
                        }
                    }
                },
                actions = {
                    if (ui.mode == Mode.PRACTICE) {
                        TextButton(onClick = { showWordPicker = true }, enabled = !ui.isBusy) {
                            Text(stringResource(R.string.word_picker_short), color = c.primary)
                        }
                        Box {
                            IconButton(onClick = { showMenu = true }, enabled = !ui.isBusy) {
                                Icon(Icons.Filled.MoreVert, stringResource(R.string.common_more), tint = c.textPrimary)
                            }
                            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.self_test_start)) },
                                    onClick = { showMenu = false; vm.beginSelfTest() },
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.settings_title)) },
                                    onClick = { showMenu = false; onOpenSettings() },
                                    modifier = Modifier.testTag("menu.settings"),
                                )
                            }
                        }
                    }
                },
            )
        },
        bottomBar = {
            ActionBar(
                ui = ui, samplePlaying = samplePlaying,
                onSample = {
                    when (sampleAvailability) {
                        SamplePlayer.Availability.READY -> { sampleProblem = null; vm.toggleSample() }
                        SamplePlayer.Availability.INITIALIZING -> Unit
                        else -> sampleProblem = sampleAvailability
                    }
                },
                onRecord = ::onRecordTap,
                onNext = { sampleProblem = null; vm.next() },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            if (ui.mode == Mode.SELF_TEST) {
                SelfTestContent(ui, onBack = { vm.endSelfTest() }, onOpenSettings = { openAppSettings(context) })
            } else {
                val lexeme = ui.lexeme
                if (lexeme == null) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center))
                } else {
                    // 结果或失败说明出现时滚进视野：放大文字时它可能在操作栏下面，不该让人自己去找
                    val scroll = rememberScrollState()
                    LaunchedEffect(ui.stage) {
                        if (ui.stage == Stage.Feedback || ui.stage is Stage.Failed) scroll.animateScrollTo(scroll.maxValue)
                    }
                    Column(
                        Modifier.fillMaxSize().verticalScroll(scroll)
                            .padding(horizontal = 20.dp).padding(bottom = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        // 新版本提示：只在普通练习里、不在录音分析中出现；失败或没有新版本时什么也没有
                        updatePrompt?.let { prompt ->
                            UpdateBanner(prompt, onDismiss = { app.updates.dismiss() }, Modifier.padding(top = 8.dp))
                        }
                        LexemeCard(lexeme, Modifier.padding(top = 8.dp))
                        ModeTabs(style, enabled = !ui.isBusy, onSelect = vm::setStyle)
                        Box(Modifier.fillMaxWidth().height(220.dp)) {
                            when (style) {
                                FeedbackStyle.DYNAMIC_F0 -> F0Chart(ui.reference, ui.learner, Modifier.fillMaxSize())
                                FeedbackStyle.STATIC_COLOR -> StaticColorView(lexeme, Modifier.fillMaxSize())
                            }
                        }
                        sampleProblem?.let { problem ->
                            FailureBlock(
                                message = stringResource(
                                    if (problem == SamplePlayer.Availability.MISSING_CHINESE_VOICE) R.string.tts_missing_voice
                                    else R.string.tts_unavailable),
                                actionLabel = if (problem == SamplePlayer.Availability.MISSING_CHINESE_VOICE)
                                    stringResource(R.string.tts_open_settings) else null,
                                onAction = { openTtsSettings(context) },
                            )
                        }
                        StatusArea(ui, onTryAgain = vm::tryAgain, onOpenSettings = { openAppSettings(context) })
                    }
                }
            }
        }
    }

    if (showWordPicker) {
        WordPickerSheet(ui, onDismiss = { showWordPicker = false }, onPick = {
            showWordPicker = false
            vm.select(it)
        })
    }

    if (showMicExplanation) {
        AlertDialog(
            onDismissRequest = { showMicExplanation = false },
            title = { Text(stringResource(R.string.mic_explain_title)) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.onboarding_mic_body), color = c.textPrimary)
                    Text(stringResource(R.string.onboarding_mic_privacy), color = c.textSecondary,
                         style = MaterialTheme.typography.bodyMedium)
                }
            },
            confirmButton = {
                Button(onClick = {
                    showMicExplanation = false
                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                }) { Text(stringResource(R.string.onboarding_mic_allow)) }
            },
            dismissButton = {
                TextButton(onClick = { showMicExplanation = false }) { Text(stringResource(R.string.cancel)) }
            },
            containerColor = c.surface,
        )
    }
}

/** 曲线 / 颜色。顺序固定，曲线（默认）在前。录音、分析中禁用 */
@Composable
private fun ModeTabs(style: FeedbackStyle, enabled: Boolean, onSelect: (FeedbackStyle) -> Unit) {
    val c = Pt.colors
    Row(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f)) {
        for ((s, label) in listOf(FeedbackStyle.DYNAMIC_F0 to R.string.condition_dynamicF0,
                                  FeedbackStyle.STATIC_COLOR to R.string.condition_staticColor)) {
            val selected = s == style
            Column(
                Modifier.weight(1f).heightIn(min = 48.dp)
                    .clickable(enabled = enabled) { onSelect(s) }
                    .semantics { this.selected = selected },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Bottom,
            ) {
                Text(stringResource(label), Modifier.padding(vertical = 10.dp),
                     color = if (selected) c.primary else c.textSecondary,
                     fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                     textAlign = TextAlign.Center)
                Box(Modifier.fillMaxWidth().height(if (selected) 2.dp else 1.dp)
                        .background(if (selected) c.primary else c.border))
            }
        }
    }
}

/** 图下方：按状态说明「现在是什么情况、下一步做什么」。技术失败**不显示成低分** */
@Composable
private fun StatusArea(ui: PracticeUi, onTryAgain: () -> Unit, onOpenSettings: () -> Unit) {
    val c = Pt.colors
    when (val stage = ui.stage) {
        Stage.Preparing -> StatusLine(stringResource(R.string.tone_stage_preparing), spinning = true)
        Stage.Ready -> StatusLine(stringResource(R.string.tone_stage_ready))
        Stage.Recording -> StatusLine(stringResource(R.string.tone_stage_recording), color = c.textPrimary)
        Stage.Analyzing -> StatusLine(stringResource(R.string.tone_stage_analyzing), spinning = true)
        Stage.Feedback -> ui.feedback?.let { ResultBlock(it, ui.consecutiveFailures, onTryAgain) }
        is Stage.Failed -> FailureBlock(
            message = stringResource(failureMessage(stage.failure)),
            actionLabel = if (stage.failure.offersSettings) stringResource(R.string.onboarding_open_settings) else null,
            onAction = onOpenSettings,
        )
        Stage.SelfTestRecorded -> Unit
    }
}

@Composable
private fun StatusLine(text: String, spinning: Boolean = false, color: androidx.compose.ui.graphics.Color = Pt.colors.textSecondary) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically) {
        if (spinning) CircularProgressIndicator(Modifier.size(18.dp).padding(end = 0.dp), strokeWidth = 2.dp)
        Text(text, Modifier.padding(start = if (spinning) 8.dp else 0.dp), color = color,
             style = MaterialTheme.typography.bodyMedium)
    }
}

/** 本次结果：只说这一次录音，不称「能力评分」。分数是形成性反馈 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun ResultBlock(fb: TonePracticeSession.Feedback, consecutiveFailures: Int, onTryAgain: () -> Unit) {
    val c = Pt.colors
    Column(Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.result_title), Modifier.semantics { heading() },
             style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
        Divider()
        // 一行放得下就左右排；放大文字时 FlowRow 自动换到下一行（不缩字）
        androidx.compose.foundation.layout.FlowRow(
            Modifier.fillMaxWidth().padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            StatusLabel(if (fb.passed) StatusKind.SUCCESS else StatusKind.NEUTRAL,
                        stringResource(if (fb.passed) R.string.result_passed else R.string.result_not_passed),
                        prominent = true)
            val a11y = stringResource(R.string.result_score_a11y, fb.score)
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Row(Modifier.semantics(mergeDescendants = true) { contentDescription = a11y },
                    verticalAlignment = Alignment.Bottom) {
                    Text("${fb.score}", style = MaterialTheme.typography.headlineSmall,
                         fontWeight = FontWeight.SemiBold, color = c.textPrimary)
                    Text(" / 100", style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
                }
            }
        }
        // 被闸门拦下时，逐字 / 分数都说明不了原因，给一句整词提示（与 iOS 结果区相同）
        val gateHint = when {
            fb.flatContour -> R.string.advice_add_movement
            fb.levelToneDropped -> R.string.advice_keep_level
            else -> null
        }
        if (gateHint != null) {
            Text(stringResource(gateHint), Modifier.padding(bottom = 8.dp).testTag("practice.gateHint"),
                 style = MaterialTheme.typography.bodyMedium, color = c.textPrimary)
        }
        if (consecutiveFailures >= TonePracticeSession.SKIP_HINT_THRESHOLD) {
            Text(stringResource(R.string.feedback_skip_hint), Modifier.padding(bottom = 8.dp),
                 style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
        }
        Divider()
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onTryAgain).padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Refresh, contentDescription = null, tint = c.primary)
            Text(stringResource(R.string.result_try_again), Modifier.padding(start = 8.dp), color = c.textPrimary)
        }
        Divider()
    }
}

/** 底部操作栏：听示范 · 录音/停止 · 下一词。三格等宽，左右顺序不镜像 */
@Composable
private fun ActionBar(ui: PracticeUi, samplePlaying: Boolean, onSample: () -> Unit, onRecord: () -> Unit,
                      onNext: () -> Unit) {
    val c = Pt.colors
    val practice = ui.mode == Mode.PRACTICE
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Column(Modifier.fillMaxWidth().background(c.background).navigationBarsPadding()) {
            Divider()
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    if (practice) {
                        BarButton(
                            icon = { Icon(if (samplePlaying) Icons.Filled.Close else Icons.Filled.PlayArrow, null, tint = c.primary) },
                            caption = stringResource(if (samplePlaying) R.string.bar_stop else R.string.bar_listen),
                            label = stringResource(if (samplePlaying) R.string.sample_stop else R.string.play_sample),
                            enabled = !ui.isBusy, onClick = onSample,
                        )
                    }
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    RecordButton(
                        isRecording = ui.isRecording, enabled = ui.canRecord,
                        label = stringResource(if (ui.isRecording) R.string.record_stop else R.string.record_start),
                        caption = stringResource(if (ui.isRecording) R.string.bar_stop else R.string.record_short),
                        state = stageDescription(ui.stage),
                        onClick = onRecord,
                    )
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    if (practice) {
                        BarButton(
                            icon = { Icon(Icons.Filled.ArrowForward, null, tint = c.primary) },
                            caption = stringResource(R.string.bar_next),
                            label = stringResource(R.string.tone_next_word),
                            enabled = !ui.isBusy, onClick = onNext,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun stageDescription(stage: Stage): String = when (stage) {
    Stage.Preparing -> stringResource(R.string.tone_stage_preparing)
    Stage.Ready -> ""
    Stage.Recording -> stringResource(R.string.tone_stage_recording)
    Stage.Analyzing -> stringResource(R.string.tone_stage_analyzing)
    Stage.Feedback -> stringResource(R.string.result_title)
    Stage.SelfTestRecorded -> stringResource(R.string.self_test_recorded)
    is Stage.Failed -> stringResource(failureMessage(stage.failure))
}

fun failureMessage(f: TonePracticeSession.Failure): Int = when (f) {
    TonePracticeSession.Failure.MICROPHONE_DENIED -> R.string.tone_fail_mic_denied
    TonePracticeSession.Failure.MICROPHONE_UNAVAILABLE -> R.string.tone_retry_mic_unavailable
    TonePracticeSession.Failure.NO_VOICE -> R.string.tone_retry_no_voice
    TonePracticeSession.Failure.INTERRUPTED -> R.string.tone_fail_interrupted
    TonePracticeSession.Failure.ANALYSIS -> R.string.tone_fail_analysis
}

/**
 * 自测（需求 U04）：中性的「自测 · 第 x / n 词」，只推进录音。
 * **不呈现任何评价**：没有分数、等级、评价颜色、曲线、示范或建议（CLAUDE.md 禁令 6）。
 */
@Composable
private fun SelfTestContent(ui: PracticeUi, onBack: () -> Unit, onOpenSettings: () -> Unit) {
    val c = Pt.colors
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        val st = ui.selfTest
        if (ui.selfTestFinished) {
            Icon(Icons.Filled.Check, null, Modifier.size(56.dp), tint = c.textSecondary)
            Text(stringResource(R.string.self_test_done_title), style = MaterialTheme.typography.titleLarge,
                 color = c.textPrimary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.self_test_done_body), color = c.textSecondary, textAlign = TextAlign.Center)
            Button(onClick = onBack) { Text(stringResource(R.string.self_test_back_to_practice)) }
            return@Column
        }
        val lexeme = ui.lexeme ?: return@Column
        if (st != null) {
            // 进度只表示录到第几个，不表示录得怎么样：中性灰，不用评价色
            Text(stringResource(R.string.self_test_progress, st.position, st.total),
                 style = MaterialTheme.typography.titleSmall, color = c.textSecondary)
            Row(Modifier.widthIn(max = 220.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                repeat(maxOf(st.total, 1)) { i ->
                    Box(Modifier.weight(1f).height(4.dp)
                        .background(if (i < st.position) c.textSecondary else c.border, RoundedCornerShape(2.dp)))
                }
            }
        }
        LexemeCard(lexeme)
        Column(
            Modifier.fillMaxWidth().heightIn(min = 132.dp).background(c.secondaryBackground, RoundedCornerShape(6.dp))
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        ) {
            when (val stage = ui.stage) {
                is Stage.Failed -> FailureBlock(
                    stringResource(failureMessage(stage.failure)),
                    if (stage.failure.offersSettings) stringResource(R.string.onboarding_open_settings) else null,
                    onOpenSettings,
                )
                else -> {
                    if (stage == Stage.SelfTestRecorded) Icon(Icons.Filled.CheckCircle, null, tint = c.textSecondary)
                    Text(
                        stringResource(when (stage) {
                            Stage.Preparing -> R.string.tone_stage_preparing
                            Stage.Recording -> R.string.tone_stage_recording
                            Stage.Analyzing -> R.string.self_test_saving
                            Stage.SelfTestRecorded -> R.string.self_test_recorded
                            else -> R.string.self_test_ready
                        }),
                        color = c.textSecondary, textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

/** 选词：全部声调词条，可搜索汉字或拼音。录音、分析中不能打开 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WordPickerSheet(ui: PracticeUi, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    val c = Pt.colors
    var query by rememberSaveable { mutableStateOf("") }
    val q = query.trim().lowercase()
    val words = ui.words.filter {
        q.isEmpty() || it.hanzi.contains(q) || it.pinyin.lowercase().contains(q) ||
            stripTones(it.pinyin).contains(stripTones(q))
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = c.background) {
        Column(Modifier.padding(horizontal = 20.dp)) {
            Text(stringResource(R.string.word_picker_title), style = MaterialTheme.typography.titleMedium,
                 color = c.textPrimary, modifier = Modifier.semantics { heading() })
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(vertical = 12.dp),
                              placeholder = { Text(stringResource(R.string.word_picker_search)) }, singleLine = true)
            if (words.isEmpty()) {
                Text(stringResource(R.string.word_picker_empty), Modifier.padding(vertical = 24.dp),
                     color = c.textSecondary)
            }
            LazyColumn(Modifier.fillMaxWidth()) {
                items(words, key = { it.id }) { w ->
                    val current = w.id == ui.lexeme?.id
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable { onPick(w.id) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                                Text(w.hanzi, style = MaterialTheme.typography.titleLarge, color = c.textPrimary)
                                Text(w.pinyin, Modifier.padding(start = 12.dp), color = c.textSecondary)
                            }
                        }
                        if (current) {
                            Icon(Icons.Filled.Check, stringResource(R.string.word_current), tint = c.primary)
                        }
                    }
                    Divider()
                }
            }
        }
    }
}

private fun stripTones(s: String): String =
    java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").replace(" ", "").lowercase()

private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
    try { context.startActivity(intent) } catch (_: ActivityNotFoundException) {}
}

/** 去系统里下载中文语音：先试引擎的「安装语音数据」，不行就开系统的文字转语音设置 */
private fun openTtsSettings(context: Context) {
    val candidates = listOf(
        Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA),
        Intent("com.android.settings.TTS_SETTINGS"),
        Intent(Settings.ACTION_SETTINGS),
    )
    for (intent in candidates) {
        try { context.startActivity(intent); return } catch (_: ActivityNotFoundException) {}
    }
}
