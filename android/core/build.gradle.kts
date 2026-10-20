plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // 只用 Kotlin 标准库；不引任何第三方（含 JSON 库——对照测试自带一个极小的解析器）
    testImplementation(libs.junit)
}

tasks.test {
    // 两端共用的对照数据（Swift 版导出），见仓库根目录 testdata/scoring/README.md
    systemProperty(
        "pinyintone.scoringTestdata",
        rootProject.projectDir.resolve("../testdata/scoring").canonicalPath,
    )
    inputs.dir(rootProject.projectDir.resolve("../testdata/scoring"))
    // 仓库根：语料、Theme.swift 等 iOS 源头文件，测试直接读来核对两端一致
    systemProperty("pinyintone.repoRoot", rootProject.projectDir.resolve("..").canonicalPath)
    inputs.file(rootProject.projectDir.resolve("../PinYintone/Resources/Corpus/lexemes.json"))
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
