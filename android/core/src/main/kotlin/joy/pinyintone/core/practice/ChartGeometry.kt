package joy.pinyintone.core.practice

/**
 * 曲线模式的几何（对应 Swift `ModeB_F0WaveformView` 的取点逻辑）。
 *
 * - **显示与评分同源**：与 DTW 相同，丢弃 0（无声）帧；非有限值一并滤掉。
 * - 两条线**共用横轴刻度**（分母取两者较长者），说得快线就短，不各自拉伸铺满。
 * - 横轴只是时间：**不按音节分段、不标声调**（CLAUDE.md 禁令 25）。
 * - 纵轴是归一化值，夹在 ±2.5。返回的坐标都在 0..1，x 从左到右（阿拉伯语界面也不镜像），y 向下。
 */
object ChartGeometry {
    const val V_MIN = -2.5f
    const val V_MAX = 2.5f

    data class Curves(val reference: List<Pair<Float, Float>>, val learner: List<Pair<Float, Float>>) {
        /** 两条都画不出来（< 2 点）时显示中性的空状态，**不画假曲线** */
        val isEmpty: Boolean get() = reference.size < 2 && learner.size < 2
    }

    fun curves(reference: FloatArray, learner: FloatArray): Curves {
        val ref = reference.filter { it != 0f && it.isFinite() }
        val stu = learner.filter { it != 0f && it.isFinite() }
        val denom = maxOf(maxOf(ref.size, stu.size) - 1, 1).toFloat()
        fun pts(v: List<Float>) = v.mapIndexed { i, x ->
            val clamped = x.coerceIn(V_MIN, V_MAX)
            (i / denom) to (1 - (clamped - V_MIN) / (V_MAX - V_MIN))
        }
        return Curves(pts(ref), pts(stu))
    }
}
