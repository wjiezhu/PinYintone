// 「读平也通关」修法对比实验。只在实验里实现候选修法，复用 :core 的正式实现作基线。
// 运行：./gradlew :scoring-study:run   （需先跑 tts/generate.sh 生成 TTS 音频，否则跳过 TTS 部分）
plugins {
    alias(libs.plugins.kotlin.jvm)
    application
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core"))
}

application {
    mainClass.set("joy.pinyintone.study.MainKt")
}

tasks.named<JavaExec>("run") {
    workingDir = projectDir
    jvmArgs("-Xmx2g")
}
