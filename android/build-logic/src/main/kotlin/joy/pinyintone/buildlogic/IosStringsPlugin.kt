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

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val keysFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun run() {
        val root = localizationsDir.get().asFile
        val sources = IosStrings.LANGUAGES.keys.associateWith {
            File(root, "$it.lproj/Localizable.strings").readText()
        }
        val keys = IosStrings.parseKeys(keysFile.get().asFile.readText())
        val out = outputDir.get().asFile
        out.deleteRecursively()
        for ((dir, xml) in IosStrings.generate(sources, keys)) {
            File(out, dir).apply { mkdirs() }.resolve("strings_ios.xml").writeText(xml)
        }
    }
}

class IosStringsPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        project.tasks.register("generateIosStrings", GenerateIosStringsTask::class.java) {
            it.group = "pinyintone"
            it.description = "从 iOS 的 Localizable.strings 生成 Android 字符串资源"
            it.localizationsDir.set(project.rootProject.layout.projectDirectory.dir("../PinYintone/Resources/Localizations"))
            it.keysFile.set(project.layout.projectDirectory.file("ios-strings.keys"))
            it.outputDir.set(project.layout.buildDirectory.dir("generated/iosStrings/res"))
        }
    }
}
