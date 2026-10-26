# Pinyintone 发布构建的 R8 规则。
#
# 评分（:core）是纯 Kotlin 计算，不用反射、不按名字取类；Room 由 KSP 生成实现类，
# 它自带的 consumer 规则已保留 AppDatabase_Impl 等。所以这里不需要大段 keep。
# 若以后改用反射 / 按名字序列化，在这里补规则，并重跑 r8check 包的模拟器验证。

# 崩溃报告里能对得上行号（映射文件在 app/build/outputs/mapping/release/，随每个正式包存档）
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
