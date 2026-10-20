import joy.pinyintone.buildlogic.CopySharedCorpusTask
import joy.pinyintone.buildlogic.GenerateIosStringsTask

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
    }

    buildTypes {
        release {
            isMinifyEnabled = false
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
