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
import joy.pinyintone.app.ui.practice.TonePracticeScreen
import joy.pinyintone.app.ui.practice.TonePracticeViewModel
import joy.pinyintone.app.ui.theme.PinyintoneTheme

/**
 * 这一阶段只有声调练习页（登录、首页、上传同步、研究流程都还没做）。
 */
class MainActivity : ComponentActivity() {

    private val practice: TonePracticeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            // 不在后台录音：切走时正在录的这一次如实记为中断
            override fun onStop(owner: LifecycleOwner) = practice.onBackgrounded()
            // 从系统设置回来：重查麦克风权限与中文语音，不需要重启
            override fun onResume(owner: LifecycleOwner) = practice.onResumed(
                checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
        })
        setContent {
            PinyintoneTheme {
                TonePracticeScreen(practice)
            }
        }
    }
}
