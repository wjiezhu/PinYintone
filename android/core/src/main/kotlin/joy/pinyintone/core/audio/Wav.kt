package joy.pinyintone.core.audio

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 最小的 WAV 读取：只接受 16-bit PCM、单声道、16 kHz（CLAUDE.md 锁定采样率）。
 * 两端共用的对照输入与以后的母语者参考音都按这个格式存放；其它格式先离线转换。
 */
object Wav {

    fun readPcm16Mono16k(file: File): ShortArray = readPcm16Mono16k(file.readBytes())

    fun readPcm16Mono16k(bytes: ByteArray): ShortArray {
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(bytes.size >= 12 && tag(bytes, 0) == "RIFF" && tag(bytes, 8) == "WAVE") { "不是 WAV 文件" }
        var pos = 12
        var fmtOk = false
        while (pos + 8 <= bytes.size) {
            val id = tag(bytes, pos)
            val size = buf.getInt(pos + 4)
            val body = pos + 8
            when (id) {
                "fmt " -> {
                    val format = buf.getShort(body).toInt()
                    val channels = buf.getShort(body + 2).toInt()
                    val rate = buf.getInt(body + 4)
                    val bits = buf.getShort(body + 14).toInt()
                    require(format == 1 && channels == 1 && rate == 16_000 && bits == 16) {
                        "只支持 16-bit PCM 单声道 16 kHz（实为 format=$format ch=$channels rate=$rate bits=$bits）"
                    }
                    fmtOk = true
                }
                "data" -> {
                    require(fmtOk) { "data 块出现在 fmt 之前" }
                    val n = minOf(size, bytes.size - body) / 2
                    return ShortArray(n) { buf.getShort(body + it * 2) }
                }
            }
            pos = body + size + (size and 1)
        }
        error("WAV 里没有 data 块")
    }

    private fun tag(bytes: ByteArray, at: Int) = String(bytes, at, 4, Charsets.US_ASCII)
}
