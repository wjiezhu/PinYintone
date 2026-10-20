package joy.pinyintone.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import joy.pinyintone.core.theme.ThemeTokens

/**
 * 语义颜色（需求 2.3 版 U01）。色值只在 core 的 [ThemeTokens] 里定义一次（与 iOS Theme.swift 相同，
 * 有测试核对）；这里按浅色 / 深色挑一套。**页面里不写色值**（CLAUDE.md 禁令 24）。
 */
@Immutable
data class PtColors(
    val background: Color,
    val secondaryBackground: Color,
    val surface: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val primary: Color,
    val onPrimary: Color,
    val learnerAccent: Color,
    val onLearnerAccent: Color,
    val blueAccent: Color,
    val sageSurface: Color,
    val blueSurface: Color,
    val border: Color,
    val ochre: Color,
) {
    /** 出错图标沿用陶红；出错**文字**用 textPrimary */
    val warning: Color get() = learnerAccent

    /** 颜色模式里各声调的颜色（颜色不是唯一通道：另有形状、调号、调类名） */
    fun tone(tone: Int): Color = when (tone) {
        1 -> primary
        2 -> blueAccent
        3 -> ochre
        4 -> learnerAccent
        else -> textSecondary
    }

    companion object {
        fun of(dark: Boolean): PtColors {
            fun c(p: ThemeTokens.Pair) = Color(0xFF000000.toInt() or (if (dark) p.dark else p.light))
            val t = ThemeTokens
            return PtColors(
                c(t.background), c(t.secondaryBackground), c(t.surface), c(t.textPrimary), c(t.textSecondary),
                c(t.primary), c(t.onPrimary), c(t.learnerAccent), c(t.onLearnerAccent), c(t.blueAccent),
                c(t.sageSurface), c(t.blueSurface), c(t.border), c(t.ochre),
            )
        }
    }
}

val LocalPtColors = staticCompositionLocalOf { PtColors.of(dark = false) }

object Pt {
    val colors: PtColors
        @Composable get() = LocalPtColors.current
}

@Composable
fun PinyintoneTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val c = PtColors.of(dark)
    // Material 组件（对话框、底部弹层、开关）也走同一套 token
    val scheme = if (dark) {
        darkColorScheme(
            primary = c.primary, onPrimary = c.onPrimary, background = c.background, onBackground = c.textPrimary,
            surface = c.surface, onSurface = c.textPrimary, surfaceVariant = c.secondaryBackground,
            onSurfaceVariant = c.textSecondary, outline = c.border, outlineVariant = c.border,
            error = c.learnerAccent, onError = c.onLearnerAccent, surfaceContainerHigh = c.surface,
            surfaceContainer = c.surface, surfaceContainerLow = c.secondaryBackground,
        )
    } else {
        lightColorScheme(
            primary = c.primary, onPrimary = c.onPrimary, background = c.background, onBackground = c.textPrimary,
            surface = c.surface, onSurface = c.textPrimary, surfaceVariant = c.secondaryBackground,
            onSurfaceVariant = c.textSecondary, outline = c.border, outlineVariant = c.border,
            error = c.learnerAccent, onError = c.onLearnerAccent, surfaceContainerHigh = c.surface,
            surfaceContainer = c.surface, surfaceContainerLow = c.secondaryBackground,
        )
    }
    CompositionLocalProvider(LocalPtColors provides c) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
