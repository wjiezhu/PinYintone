package joy.pinyintone.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import joy.pinyintone.app.audio.SyntheticMic
import joy.pinyintone.app.ui.practice.TonePracticeScreen
import joy.pinyintone.app.ui.practice.TonePracticeViewModel
import joy.pinyintone.app.ui.settings.DiagnosticsScreen
import joy.pinyintone.app.ui.settings.SettingsScreen
import joy.pinyintone.app.ui.theme.PinyintoneTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue

/**
 * 这一阶段只有声调练习页、设置与诊断信息（登录、首页、上传同步、研究流程都还没做）。
 */
class MainActivity : ComponentActivity() {

    private val practice: TonePracticeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        // 调试构建与 r8check：adb shell am start -n joy.pinyintone/.MainActivity --es pt_mic tones|flat|silent
        // 用合成信号代替麦克风，在模拟器上走通整条链路。正式包（release）不读这个参数
        if (BuildConfig.SYNTHETIC_MIC_ALLOWED) {
            TonePracticeViewModel.syntheticKind = when (intent.getStringExtra("pt_mic")) {
                "tones" -> SyntheticMic.Kind.TONES
                "flat" -> SyntheticMic.Kind.FLAT
                "silent" -> SyntheticMic.Kind.SILENT
                else -> null
            }
        }
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            // 不在后台录音：切走时正在录的这一次如实记为中断
            override fun onStop(owner: LifecycleOwner) = practice.onBackgrounded()
            // 从系统设置回来：重查麦克风权限与中文语音，不需要重启
            override fun onResume(owner: LifecycleOwner) = practice.onResumed(
                checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
        })
        // 启动时查一次新版本；失败静默，不打扰练习
        (application as PinyintoneApp).updates.checkOnce()
        setContent {
            PinyintoneTheme {
                // 页面少，不引导航库：练习 → 设置 → 诊断信息
                var route by rememberSaveable { mutableStateOf(Route.PRACTICE) }
                when (route) {
                    Route.PRACTICE -> TonePracticeScreen(practice, onOpenSettings = { route = Route.SETTINGS })
                    Route.SETTINGS -> SettingsScreen(practice, onBack = { route = Route.PRACTICE },
                                                     onOpenDiagnostics = { route = Route.DIAGNOSTICS })
                    Route.DIAGNOSTICS -> DiagnosticsScreen(practice.player, onBack = { route = Route.SETTINGS })
                }
            }
        }
    }

    private enum class Route { PRACTICE, SETTINGS, DIAGNOSTICS }
}
