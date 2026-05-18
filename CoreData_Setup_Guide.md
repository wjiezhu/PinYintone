# Core Data 建表操作指南

在 Xcode 中打开 `Pinyintone.xcdatamodeld`，按以下步骤创建三个实体。

---

## 全局设置（先做一次）

1. 选中 `.xcdatamodeld` 文件
2. 右侧 Inspector → **Codegen** 改为 **Manual/None**（因为我们已手写 NSManagedObject 子类）

---

## 实体一：TrainingSession（声调训练记录）

**Add Entity** → 命名 `TrainingSession`

### Attributes

| 字段名 | 类型 | Optional | 备注 |
|--------|------|----------|------|
| `id` | UUID | ✗ | 主键 |
| `deviceID` | String | ✗ | iOS identifierForVendor |
| `classCode` | String | ✓ | nil = 游客 |
| `role` | String | ✗ | "guest" \| "student" |
| `groupAssignment` | String | ✗ | "staticColor" \| "dynamicF0" |
| `lexemeID` | String | ✗ | 词条 id |
| `dtwScore` | Double | ✗ | 归一化 DTW 值 |
| `grade` | String | ✗ | FeedbackGrade.rawValue |
| `attemptNumber` | Integer 32 | ✗ | 第几次尝试 |
| `synced` | Boolean | ✗ | 默认值 `NO` |
| `timestamp` | Date | ✗ | |

### 无 Relationship

---

## 实体二：AspirationAttempt（送气训练记录）

**Add Entity** → 命名 `AspirationAttempt`

### Attributes

| 字段名 | 类型 | Optional | 备注 |
|--------|------|----------|------|
| `id` | UUID | ✗ | 主键 |
| `deviceID` | String | ✗ | |
| `classCode` | String | ✓ | nil = 游客 |
| `role` | String | ✗ | |
| `targetWord` | String | ✗ | 练习的词，如 "爸爸" |
| `triggerRate` | Double | ✗ | 0.0 – 1.0 |
| `passed` | Boolean | ✗ | triggerRate ≥ 0.6 |
| `synced` | Boolean | ✗ | 默认值 `NO` |
| `timestamp` | Date | ✗ | |

### 无 Relationship

---

## 实体三：FreeTextRecord（自由文本练习记录）

**Add Entity** → 命名 `FreeTextRecord`

### Attributes

| 字段名 | 类型 | Optional | 备注 |
|--------|------|----------|------|
| `id` | UUID | ✗ | 主键 |
| `deviceID` | String | ✗ | |
| `classCode` | String | ✓ | nil = 游客 |
| `role` | String | ✗ | |
| `originalText` | String | ✗ | 用户输入的原始中文文本 |
| `tokenizedWord` | String | ✗ | 当前练习的词 |
| `pinyin` | String | ✗ | 该词的拼音 |
| `toneSequenceData` | Binary Data | ✓ | 存 [Int] JSON；见下方说明 |
| `f0TrackData` | Binary Data | ✓ | 存 [Float] JSON；见下方说明 |
| `duration` | Double | ✗ | 录音时长（秒） |
| `timestamp` | Date | ✗ | |
| `synced` | Boolean | ✗ | 默认值 `NO` |

### toneSequenceData / f0TrackData 特殊配置

`Binary Data` 类型选中后，右侧 Inspector 勾选：

> ☑ **Allows External Storage**（大数据时自动外部存储，f0Track 可能较长）

代码层的编解码逻辑已在 `FreeTextRecord+CoreData.swift` 的计算属性中处理（JSON encode/decode）。

### 无 Relationship

---

## 添加索引（性能优化）

对 `TrainingSession` 和 `FreeTextRecord` 添加复合索引，加速教师面板查询：

1. 选中 `TrainingSession` 实体
2. 底部 **Add Index** → 添加索引 `classCode`
3. 同样为 `FreeTextRecord` 添加 `classCode` 索引

---

## 验证步骤

完成所有实体创建后：

1. `Cmd+B` 编译，确认无报错
2. 如出现 `"The model used to open the store is incompatible"`：删除模拟器 App 重装（开发阶段正常现象）

---

## Swift 代码与实体对应关系

| Swift 文件 | Core Data 实体 |
|------------|----------------|
| `TrainingSession+CoreData.swift` | `TrainingSession` |
| `AspirationAttempt+CoreData.swift` | `AspirationAttempt` |
| `FreeTextRecord+CoreData.swift` | `FreeTextRecord` |
| `CoreDataStack.swift` | 容器名 = `"Pinyintone"` |
