package joy.pinyintone.core.audio

import kotlin.math.roundToInt

/**
 * 录音链路的平台无关部分：任意采样率的 PCM16 → 16 kHz → 1600 采样一片的 Int16 分片。
 *
 * 对应 iOS `AudioEngine`：硬件格式 → `AVAudioConverter`（16 kHz / Int16）→ 累积满 1600 回调 `onChunk`。
 * Android 的 `AudioRecord` 回调把原始 PCM16 交给 [feed]，每凑满一片回调 [onChunk]，
 * 下游与 iOS 完全相同：`AudioFramer` → `F0Extractor`。
 *
 * 量化回 Int16 是有意的：iOS 也是先转成 Int16 分片再交给帧化层，两端走同一条路。
 * 不是线程安全的；只在录音线程里用。
 */
class PcmChunker(inputRate: Int, val chunkSize: Int = AspirationDetector.CHUNK_SIZE) {

    private val resampler = Resampler(inputRate)
    private val pending = ShortArray(chunkSize)
    private var filled = 0

    /** 每凑满 [chunkSize]（0.1 s @16 kHz）回调一次 */
    var onChunk: ((ShortArray) -> Unit)? = null

    /** 送入一段原始 PCM16（硬件采样率）。 */
    fun feed(pcm: ShortArray, length: Int = pcm.size) {
        val f = FloatArray(length) { pcm[it] / 32768f }
        val resampled = resampler.process(f)
        for (x in resampled) {
            pending[filled++] = toInt16(x)
            if (filled == chunkSize) {
                onChunk?.invoke(pending.copyOf())
                filled = 0
            }
        }
    }

    /** 录音结束或开始前清空（不足一片的尾巴丢弃，与 iOS 相同）。 */
    fun reset() {
        resampler.reset()
        filled = 0
    }

    companion object {
        fun toInt16(x: Float): Short = (x * 32767f).roundToInt().coerceIn(-32768, 32767).toShort()
    }
}
