pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "PinYintone"

// 评分核心：纯 JVM，不依赖 Android SDK，任何装了 JDK 17 的机器都能跑对照测试。
include(":core")

// 评分修法对比实验（docs/SCORING_FLAT_READING_STUDY.md）。只读 :core，不进 App。
include(":scoring-study")

// App 模块需要 Android SDK。没有 SDK 的机器（如只想跑评分对照的 CI / 开发机）
// 不纳入 :app，避免配置阶段就因 "SDK location not found" 整个失败。
val localProps = java.util.Properties().apply {
    val f = file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasAndroidSdk = listOf(
    localProps.getProperty("sdk.dir"),
    System.getenv("ANDROID_HOME"),
    System.getenv("ANDROID_SDK_ROOT"),
).any { !it.isNullOrBlank() && file(it).isDirectory }

if (hasAndroidSdk) {
    include(":app")
} else {
    logger.warn("未找到 Android SDK（local.properties 的 sdk.dir / ANDROID_HOME），本次只配置 :core。")
}
