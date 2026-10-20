package joy.pinyintone.core

import java.io.File

/** 测试里读仓库中的 iOS 源头文件（语料、Swift 源码），用来核对两端一致 */
object RepoFiles {
    val root = File(System.getProperty("pinyintone.repoRoot") ?: "../..")
    fun read(path: String): String = File(root, path).readText()
}
