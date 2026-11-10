package joy.pinyintone.buildlogic

import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import java.io.File

/** 生成任务：读 iOS Localizations 目录与键名单，写出各语言 res 目录下的 strings_ios.xml */
abstract class GenerateIosStringsTask : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val localizationsDir: DirectoryProperty

    /** 只有 Android 有的语言（见 [IosStrings.ANDROID_ONLY]） */
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val androidOnlyLocalizationsDir: DirectoryProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val keysFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun run() {
        val sources = IosStrings.LANGUAGES.keys.associateWith {
            val root = if (it in IosStrings.ANDROID_ONLY) androidOnlyLocalizationsDir else localizationsDir
            File(root.get().asFile, "$it.lproj/Localizable.strings").readText()
        }
        val keys = IosStrings.parseKeys(keysFile.get().asFile.readText())
        val out = outputDir.get().asFile
        out.deleteRecursively()
        for ((dir, xml) in IosStrings.generate(sources, keys)) {
            File(out, dir).apply { mkdirs() }.resolve("strings_ios.xml").writeText(xml)
        }
    }
}

/**
 * 把两端共用的语料（`PinYintone/Resources/Corpus/lexemes.json`）复制进 App 的 assets。
 * 构建时复制，仓库里不另存一份——改语料只改 iOS 那一份，两端同时生效。
 */
abstract class CopySharedCorpusTask : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val lexemesFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun run() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        lexemesFile.get().asFile.copyTo(File(out, "lexemes.json"))
    }
}

class IosStringsPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        project.tasks.register("generateIosStrings", GenerateIosStringsTask::class.java) {
            it.group = "pinyintone"
            it.description = "从 iOS 的 Localizable.strings 生成 Android 字符串资源"
            it.localizationsDir.set(project.rootProject.layout.projectDirectory.dir("../PinYintone/Resources/Localizations"))
            it.androidOnlyLocalizationsDir.set(project.layout.projectDirectory.dir("localizations"))
            it.keysFile.set(project.layout.projectDirectory.file("ios-strings.keys"))
            it.outputDir.set(project.layout.buildDirectory.dir("generated/iosStrings/res"))
        }
        project.tasks.register("copySharedCorpus", CopySharedCorpusTask::class.java) {
            it.group = "pinyintone"
            it.description = "把两端共用的 lexemes.json 复制进 assets"
            it.lexemesFile.set(project.rootProject.layout.projectDirectory.file("../PinYintone/Resources/Corpus/lexemes.json"))
            it.outputDir.set(project.layout.buildDirectory.dir("generated/sharedCorpus/assets"))
        }
    }
}
