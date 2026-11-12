package joy.pinyintone.core.audio

/**
 * 帧化适配层：把录音的 16-bit PCM 分片（1600 采样 / 0.1 s）重组为 [F0Extractor] 所需的滑动帧。
 * 参数遵循 CLAUDE.md：帧长 512、帧移 128（75% 重叠）。
 *
 * 对应 Swift：`PinYintone/Core/Audio/AudioFramer.swift`；
 * [floatSamples] 对应 `AudioEngine.floatSamples(from:)`。
 */
class AudioFramer(
    val frameSize: Int = F0Extractor.FRAME_SIZE,  // 512（CLAUDE.md）
    val hopSize: Int = F0Extractor.HOP_SIZE,      // 128（CLAUDE.md）
) {
    /** 每凑满一帧（512 样本）回调一次，已归一化为 [-1, 1] 的 Float */
    var onFrame: ((FloatArray) -> Unit)? = null

    private var buffer = FloatArray(0)

    /** 送入一段 16-bit PCM。 */
    fun feed(pcm: ShortArray) {
        buffer += floatSamples(pcm)
        var start = 0
        while (buffer.size - start >= frameSize) {
            onFrame?.invoke(buffer.copyOfRange(start, start + frameSize))
            start += hopSize
        }
        if (start > 0) buffer = buffer.copyOfRange(start, buffer.size)
    }

    /** 清空内部缓冲（每次录音开始前调用）。 */
    fun reset() {
        buffer = FloatArray(0)
    }

    companion object {
        /** Int16 → [-1, 1) Float，与 iOS 的 `Float($0) / 32768.0` 逐位一致。 */
        fun floatSamples(pcm: ShortArray): FloatArray =
            FloatArray(pcm.size) { pcm[it].toFloat() / 32768.0f }

        /**
         * 整段采样直接切帧（帧长 512、帧移 128，尾部不足一帧丢弃）。
         * 与逐片 [feed] 的结果完全相同；对应 `SpeechService.f0Track` 里的切帧循环。
         */
        fun frames(samples: FloatArray, frameSize: Int = F0Extractor.FRAME_SIZE,
                   hopSize: Int = F0Extractor.HOP_SIZE): List<FloatArray> {
            val out = ArrayList<FloatArray>()
            var i = 0
            while (i + frameSize <= samples.size) {
                out.add(samples.copyOfRange(i, i + frameSize))
                i += hopSize
            }
            return out
        }
    }
}
