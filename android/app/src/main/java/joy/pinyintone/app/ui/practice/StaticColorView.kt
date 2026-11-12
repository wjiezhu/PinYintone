package joy.pinyintone.app.ui.practice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import joy.pinyintone.app.R
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.core.corpus.Lexeme

/**
 * 颜色模式：每个音节一格，**颜色 + 声调形状 + 调号 + 调类名**，不画实时曲线。
 * 对应 iOS `ModeA_StaticView`。与曲线模式是学习者自选的两种显示，通关标准完全一致。
 * 音节顺序固定从左到右：阿拉伯语界面也不镜像（否则「喝水」会排成「水喝」）。
 */
@Composable
fun StaticColorView(lexeme: Lexeme, modifier: Modifier = Modifier) {
    val chars = lexeme.hanzi.codePoints().toArray().map { String(Character.toChars(it)) }
        .takeIf { it.size == lexeme.tones.size } ?: emptyList()
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            lexeme.tones.forEachIndexed { idx, tone ->
                val name = toneName(tone)
                val a11y = if (tone in 1..4) stringResource(R.string.tone_slot_a11y, idx + 1, tone, name)
                           else stringResource(R.string.tone_slot_neutral_a11y, idx + 1, name)
                Column(
                    Modifier.weight(1f).fillMaxHeight()
                        .background(Pt.colors.tone(tone).copy(alpha = 0.09f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 4.dp, vertical = 8.dp)
                        .clearAndSetSemantics { contentDescription = a11y },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
                ) {
                    chars.getOrNull(idx)?.let {
                        Text(it, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
                             color = Pt.colors.textPrimary)
                    }
                    ToneGlyph(tone, Modifier.size(64.dp, 44.dp), lineWidthDp = 5f)
                    if (tone in 1..4) {
                        Text("$tone", style = MaterialTheme.typography.titleMedium, color = Pt.colors.tone(tone))
                    }
                    Text(name, style = MaterialTheme.typography.bodySmall, color = Pt.colors.textSecondary,
                         textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun toneName(tone: Int): String = when (tone) {
    1 -> stringResource(R.string.tone_name_1)
    2 -> stringResource(R.string.tone_name_2)
    3 -> stringResource(R.string.tone_name_3)
    4 -> stringResource(R.string.tone_name_4)
    5 -> stringResource(R.string.tone_name_5)
    else -> "—"
}

/** 声调形状（代码线描，不用位图）。对应 iOS `ToneGlyph` */
@Composable
fun ToneGlyph(tone: Int, modifier: Modifier = Modifier, lineWidthDp: Float = 2.5f) {
    val color = Pt.colors.tone(tone)
    Canvas(modifier) {
        val lw = lineWidthDp * density
        val w = size.width - lw * 2
        val h = size.height - lw * 2
        fun pt(x: Float, y: Float) = Offset(lw + x * w, lw + y * h)
        val path = Path()
        when (tone) {
            1 -> { path.moveTo(pt(0f, 0.2f).x, pt(0f, 0.2f).y); path.lineTo(pt(1f, 0.2f).x, pt(1f, 0.2f).y) }
            2 -> { path.moveTo(pt(0f, 0.85f).x, pt(0f, 0.85f).y); path.lineTo(pt(1f, 0.1f).x, pt(1f, 0.1f).y) }
            3 -> {
                path.moveTo(pt(0f, 0.4f).x, pt(0f, 0.4f).y)
                path.quadraticTo(pt(0.22f, 0.9f).x, pt(0.22f, 0.9f).y, pt(0.45f, 0.9f).x, pt(0.45f, 0.9f).y)
                path.quadraticTo(pt(0.7f, 0.9f).x, pt(0.7f, 0.9f).y, pt(1f, 0.2f).x, pt(1f, 0.2f).y)
            }
            4 -> { path.moveTo(pt(0f, 0.1f).x, pt(0f, 0.1f).y); path.lineTo(pt(1f, 0.9f).x, pt(1f, 0.9f).y) }
            else -> {
                drawCircle(color, radius = maxOf(lw, 2 * density), center = Offset(size.width / 2, size.height / 2))
                return@Canvas
            }
        }
        drawPath(path, color, style = Stroke(width = lw, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}
