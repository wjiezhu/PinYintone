// 构建期工具：从 iOS 的 Localizable.strings 生成 Android 字符串资源（两端一个源头）。
// 纯 JVM，不需要 Android SDK；单元测试：cd android && ./gradlew -p build-logic test
plugins {
    `java-gradle-plugin`
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(libs.junit)
}

gradlePlugin {
    plugins {
        create("iosStrings") {
            id = "pinyintone.ios-strings"
            implementationClass = "joy.pinyintone.buildlogic.IosStringsPlugin"
        }
    }
}

tasks.test {
    systemProperty("pinyintone.repoRoot", projectDir.resolve("../..").canonicalPath)
}
