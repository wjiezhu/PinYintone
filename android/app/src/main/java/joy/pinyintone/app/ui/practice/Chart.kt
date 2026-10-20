package joy.pinyintone.app.ui.practice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import joy.pinyintone.app.R
import joy.pinyintone.app.ui.theme.Pt
import joy.pinyintone.core.practice.ChartGeometry
import joy.pinyintone.core.theme.ThemeTokens

/**
 * 曲线模式：参考曲线（深松绿实线）+ 学习者曲线（陶红虚线），文字图例。对应 iOS `ModeB_F0WaveformView`。
 *
 * 取点与 DTW 同源（去无声帧、共用横轴），见 core 的 [ChartGeometry]。
 * 横轴只是时间：**不按音节分段、不标声调**（禁令 25）。时间方向固定从左到右，阿拉伯语界面也不镜像。
 * 没有可画的基频时显示中性的空状态，不画假曲线。
 */
@Composable
fun F0Chart(reference: FloatArray, learner: FloatArray, modifier: Modifier = Modifier) {
    val c = Pt.colors
    val curves = remember(reference, learner) { ChartGeometry.curves(reference, learner) }
    val a11y = stringResource(
        if (curves.learner.size > 1) R.string.chart_a11y_with_yours else R.string.chart_a11y_reference_only)
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Column(modifier.semantics(mergeDescendants = true) { contentDescription = a11y }) {
            Box(Modifier.fillMaxWidth().weight(1f)) {
                Canvas(Modifier.fillMaxSize()) {
                    drawGuides(c.border)
                    drawCurve(curves.reference, c.primary, ThemeTokens.Curve.REFERENCE_WIDTH, ThemeTokens.Curve.referenceDash)
                    drawCurve(curves.learner, c.learnerAccent, ThemeTokens.Curve.LEARNER_WIDTH, ThemeTokens.Curve.learnerDash)
                }
                if (curves.isEmpty) {
                    Text(
                        stringResource(R.string.chart_empty),
                        Modifier.align(Alignment.Center).padding(16.dp),
                        color = c.textSecondary, style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            Row(
                Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LegendItem(c.primary, dashed = false, text = stringResource(R.string.legend_native))
                LegendItem(c.learnerAccent, dashed = true, text = stringResource(R.string.legend_you))
            }
        }
    }
}

private fun DrawScope.drawGuides(color: Color) {
    val dash = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx()))
    for (frac in listOf(0f, 0.25f, 0.5f, 0.75f)) {
        val y = maxOf(0.5f, size.height * frac)
        drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx(), pathEffect = dash)
    }
    drawLine(color, Offset(0f, size.height - 0.5f), Offset(size.width, size.height - 0.5f), 1.dp.toPx())
}

private fun DrawScope.drawCurve(points: List<Pair<Float, Float>>, color: Color, widthDp: Float, dashDp: FloatArray) {
    if (points.size < 2) return
    val path = Path()
    points.forEachIndexed { i, (x, y) ->
        val px = x * size.width
        val py = y * size.height
        if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
    }
    val effect = if (dashDp.isEmpty()) null
                 else PathEffect.dashPathEffect(FloatArray(dashDp.size) { dashDp[it] * density })
    drawPath(path, color, style = Stroke(width = widthDp * density, cap = StrokeCap.Round,
                                          join = StrokeJoin.Round, pathEffect = effect))
}

/** 图例一项：按真实线型画的一小段线 + 文字（不单靠颜色） */
@Composable
private fun LegendItem(color: Color, dashed: Boolean, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(30.dp, 10.dp)) {
            drawLine(
                color, Offset(1f, size.height / 2), Offset(size.width - 1f, size.height / 2),
                strokeWidth = 2.5.dp.toPx(), cap = StrokeCap.Round,
                pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx())) else null,
            )
        }
        Text(text, Modifier.padding(start = 8.dp), color = Pt.colors.textSecondary,
             style = MaterialTheme.typography.bodySmall)
    }
}
