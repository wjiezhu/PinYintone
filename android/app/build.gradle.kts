import java.util.Properties
import joy.pinyintone.buildlogic.CopySharedCorpusTask
import joy.pinyintone.buildlogic.GenerateIosStringsTask

// ---- 正式签名：密钥库与密码绝不进 git ----
// 依次找：环境变量 PT_RELEASE_STORE_FILE / PT_RELEASE_STORE_PASSWORD / PT_RELEASE_KEY_ALIAS / PT_RELEASE_KEY_PASSWORD；
// 或一个 properties 文件（storeFile / storePassword / keyAlias / keyPassword），路径来自环境变量
// PT_SIGNING_PROPERTIES 或 android/local.properties 的 `pinyintone.signing.properties`。
// 都没有时 release 照样能配置、能 lint，只有打包那一步报错——绝不产出未签名或用调试密钥签的正式包。
fun loadProperties(f: File): Properties = Properties().apply { f.inputStream().use { load(it) } }
val localProps: Properties = rootProject.file("local.properties").let { if (it.exists()) loadProperties(it) else Properties() }

data class ReleaseSigning(val storeFile: File, val storePassword: String, val keyAlias: String, val keyPassword: String)

fun findReleaseSigning(): ReleaseSigning? {
    val env = System.getenv()
    val envStore = env["PT_RELEASE_STORE_FILE"]
    if (!envStore.isNullOrBlank()) {
        return ReleaseSigning(file(envStore), env["PT_RELEASE_STORE_PASSWORD"].orEmpty(),
            env["PT_RELEASE_KEY_ALIAS"].orEmpty(), env["PT_RELEASE_KEY_PASSWORD"].orEmpty())
    }
    val path = listOf(env["PT_SIGNING_PROPERTIES"], localProps.getProperty("pinyintone.signing.properties"))
        .firstOrNull { !it.isNullOrBlank() } ?: return null
    val f = file(path)
    if (!f.exists()) throw GradleException("签名配置文件不存在：$path")
    val p = loadProperties(f)
    return ReleaseSigning(file(p.getProperty("storeFile")), p.getProperty("storePassword").orEmpty(),
        p.getProperty("keyAlias").orEmpty(), p.getProperty("keyPassword").orEmpty())
}
val releaseSigning: ReleaseSigning? = findReleaseSigning()

// ---- 后端地址 ----
// 发布构建默认连线上后端，**不连任何测试地址**。本地验证时可用 -Ppt.apiBaseUrl=http://10.0.2.2:8765
// 打一份临时包（只有这时才允许明文 http）；这样的包不得分发。
val productionApiBaseUrl = "https://pinyintone-backend.onrender.com"
val apiBaseUrlOverride: String? = (findProperty("pt.apiBaseUrl") as String?)?.trim()?.takeIf { it.isNotEmpty() }

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    // 从 iOS 的 Localizable.strings 生成字符串资源、复制两端共用的语料（见 build-logic）
    id("pinyintone.ios-strings")
}

android {
    namespace = "joy.pinyintone.app"
    compileSdk = 35

    defaultConfig {
        // 参照 iOS 的 bundle id `Joy.PinYintone`；Android 惯例用小写
        applicationId = "joy.pinyintone"
        // API 26 = Android 8。ICU 拼音 / 分词（自由文本关卡）只在 API 29+ 启用
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        val apiBaseUrl = apiBaseUrlOverride ?: productionApiBaseUrl
        buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
        // 明文 http 只在显式覆盖成 http 地址时打开（本地后端验证）；默认包只走 https
        manifestPlaceholders["usesCleartextTraffic"] = apiBaseUrl.startsWith("http://").toString()
        // 合成麦克风（模拟器验证）只给 debug 与 r8check，正式包恒为 false
        buildConfigField("boolean", "SYNTHETIC_MIC_ALLOWED", "false")
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = releaseSigning.storeFile
                storePassword = releaseSigning.storePassword
                keyAlias = releaseSigning.keyAlias
                keyPassword = releaseSigning.keyPassword
                // minSdk 26 只用 v2 / v3（AGP 对 minSdk ≥ 24 不写 v1）；v3 以后可做密钥轮换
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("boolean", "SYNTHETIC_MIC_ALLOWED", "true")
        }
        release {
            // R8：压缩 + 混淆。Room / 评分不靠反射取类名，规则见 proguard-rules.pro；
            // 混淆后的评分用 r8check 包在模拟器上走通（见 README「正式版安装包」）
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
        // 与 release 完全相同的 R8 处理，但用调试密钥签、允许合成麦克风：只用于验证混淆后评分与 Room 照常
        create("r8check") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
            buildConfigField("boolean", "SYNTHETIC_MIC_ALLOWED", "true")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(17)
}

// 没有签名配置时，正式包打包这一步明确失败（不悄悄产出未签名的包）
tasks.matching { it.name == "packageRelease" }.configureEach {
    doFirst {
        if (releaseSigning == null) {
            throw GradleException(
                "没有正式签名配置：设置 PT_SIGNING_PROPERTIES，或在 android/local.properties 写 " +
                    "pinyintone.signing.properties=<路径>（见 android/README.md「正式版安装包」）")
        }
    }
}

// 生成的资源与资产挂到每个变体上：源头分别是 iOS 的 Localizations 与 Resources/Corpus，仓库里不另存一份
androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(
            tasks.named<GenerateIosStringsTask>("generateIosStrings"), GenerateIosStringsTask::outputDir)
        variant.sources.assets?.addGeneratedSourceDirectory(
            tasks.named<CopySharedCorpusTask>("copySharedCorpus"), CopySharedCorpusTask::outputDir)
    }
}

dependencies {
    implementation(project(":core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
}
