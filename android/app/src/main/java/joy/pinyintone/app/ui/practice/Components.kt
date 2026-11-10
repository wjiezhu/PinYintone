package joy.pinyintone.app.ui.practice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.core.corpus.Lexeme

/**
 * 目标词：汉字 + 拼音 + 释义。汉字与拼音固定从左到右（阿拉伯语界面不镜像字序）。
 * 汉字 40sp 起，随系统字号放大；放不下时换行，不缩字。对应 iOS `LexemeCardView`。
 */
@Composable
fun LexemeCard(lexeme: Lexeme, modifier: Modifier = Modifier) {
    val language = LocalConfiguration.current.locales[0].language
    val (primary, secondary) = lexeme.glosses(language)
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
           horizontalAlignment = Alignment.CenterHorizontally) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Text(lexeme.hanzi, fontSize = 40.sp, fontWeight = FontWeight.Bold, color = Pt.colors.textPrimary,
                 textAlign = TextAlign.Center)
            Text(lexeme.pinyin, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Medium,
                 color = Pt.colors.textSecondary, textAlign = TextAlign.Center)
        }
        if (primary.isNotEmpty()) {
            Text(primary, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.bodyLarge,
                 color = Pt.colors.textPrimary, textAlign = TextAlign.Center)
        }
        secondary?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = Pt.colors.textSecondary,
                 textAlign = TextAlign.Center)
        }
        // 不显示 lexeme.focus（面向研究者的考察重点；自测时等于提前告知这题考什么）
    }
}

/** 状态行：图标 + 文字。成功、失败都同时给图标和文字，不单靠颜色 */
enum class StatusKind { SUCCESS, NEUTRAL, WARNING }

@Composable
fun StatusLabel(kind: StatusKind, text: String, prominent: Boolean = false) {
    val c = Pt.colors
    val (icon, iconColor) = when (kind) {
        StatusKind.SUCCESS -> Icons.Filled.CheckCircle to c.primary
        StatusKind.NEUTRAL -> Icons.Filled.Refresh to c.textPrimary
        StatusKind.WARNING -> Icons.Filled.Warning to c.warning
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = iconColor)
        Text(
            text, Modifier.padding(start = 8.dp),
            // 只有「通过」用深松绿写字；出错提示用主文字色（陶红写字对比度不够）
            color = if (kind == StatusKind.SUCCESS) c.primary else c.textPrimary,
            style = if (prominent) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge,
            fontWeight = if (prominent) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

/** 技术失败说明：**不显示成低分**，给出下一步；需要时带「打开设置」 */
@Composable
fun FailureBlock(message: String, actionLabel: String?, onAction: () -> Unit, modifier: Modifier = Modifier) {
    val c = Pt.colors
    Column(
        modifier.fillMaxWidth()
            .background(c.secondaryBackground, RoundedCornerShape(6.dp))
            .border(1.dp, c.warning.copy(alpha = 0.55f), RoundedCornerShape(6.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        StatusLabel(StatusKind.WARNING, message)
        if (actionLabel != null) {
            OutlinedButton(onClick = onAction) { Text(actionLabel, color = c.primary) }
        }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.fillMaxWidth().semantics { heading() }, style = MaterialTheme.typography.titleMedium,
         color = Pt.colors.textPrimary)
}

@Composable
fun Divider() {
    Box(Modifier.fillMaxWidth().padding(vertical = 0.dp).background(Pt.colors.border).heightIn(min = 1.dp, max = 1.dp))
}

/**
 * 录音键：点一下开始、再点一下停止。直径 72dp，录音中变成陶红停止键。
 * 位置由操作栏固定，任何状态下都不动。
 */
@Composable
fun RecordButton(
    isRecording: Boolean, enabled: Boolean, label: String, caption: String, state: String,
    onClick: () -> Unit,
) {
    val c = Pt.colors
    val bg = if (isRecording) c.learnerAccent else c.primary
    val fg = if (isRecording) c.onLearnerAccent else c.onPrimary
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(72.dp).alpha(if (enabled) 1f else 0.4f).background(bg, CircleShape)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                .semantics { contentDescription = label; stateDescription = state },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(28.dp)) {
                if (isRecording) {
                    drawRoundRect(fg, Offset(size.width * 0.18f, size.height * 0.18f),
                                  Size(size.width * 0.64f, size.height * 0.64f), CornerRadius(3.dp.toPx()))
                } else {
                    drawMic(fg)
                }
            }
        }
        Text(caption, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.labelMedium,
             color = c.textPrimary, textAlign = TextAlign.Center)
    }
}

/** 代码画的话筒（不用位图、不用第三方图形） */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawMic(color: Color) {
    val w = size.width
    val h = size.height
    val sw = w * 0.09f
    drawRoundRect(color, Offset(w * 0.35f, 0f), Size(w * 0.3f, h * 0.6f), CornerRadius(w * 0.15f))
    drawArc(color, 0f, 180f, false, Offset(w * 0.2f, h * 0.25f), Size(w * 0.6f, h * 0.5f),
            style = Stroke(sw, cap = StrokeCap.Round))
    drawLine(color, Offset(w / 2, h * 0.75f), Offset(w / 2, h * 0.92f), sw, StrokeCap.Round)
    drawLine(color, Offset(w * 0.32f, h * 0.95f), Offset(w * 0.68f, h * 0.95f), sw, StrokeCap.Round)
}

/** 操作栏两侧的按钮：图标 + 一个短词。用不上时留空占位，录音键不横跳 */
@Composable
fun BarButton(icon: @Composable () -> Unit, caption: String, label: String, enabled: Boolean, onClick: () -> Unit,
              modifier: Modifier = Modifier) {
    Column(
        modifier.heightIn(min = 48.dp).alpha(if (enabled) 1f else 0.4f)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = label }
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        icon()
        Text(caption, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.labelMedium,
             color = Pt.colors.textPrimary, textAlign = TextAlign.Center)
    }
}

/**
 * 顶栏。不用 Material 的 TopAppBar：它高度固定，放大字号时较长的标题（如西班牙语
 * 「Práctica de tonos」「Información de diagnóstico」）会被截掉一半。这里标题换行、顶栏随之长高，不缩字。
 */
@Composable
fun PtTopBar(
    title: String,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
) {
    val c = Pt.colors
    Row(
        Modifier.fillMaxWidth().background(c.background)
            .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .heightIn(min = 64.dp).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        navigationIcon()
        Text(
            title,
            Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 8.dp).semantics { heading() },
            style = MaterialTheme.typography.titleLarge, color = c.textPrimary,
        )
        actions()
    }
}
