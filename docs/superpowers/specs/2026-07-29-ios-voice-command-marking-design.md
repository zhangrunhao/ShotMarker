# iOS 26 语音口令打点与技术统计设计

日期：2026-07-29

状态：已确认

目标平台：iOS 26.4 及以上

## 背景

ShotMarker 当前通过 Apple Watch 记录绝对时间打点。训练结束后，iPhone 端接收训练记录，用户选择对应视频，应用根据视频开始时间和打点时间自动规划片段、生成集锦。

新的输入方式是在球员领口佩戴小型无线麦克风。球员在进球或精彩回合后喊出简短口令，例如：

- `好球`
- `篮板`
- `盖帽`
- `十佳球`
- `柯凡两分`
- `领袖三分`

麦克风音频直接录入训练视频。训练结束后，ShotMarker 在本地分析视频音轨，提取口令和对应时间，生成打点，并按球员汇总进球数、得分和其他技术统计。

用户已确认球场内相同口令很少被其他人重复喊出，因此第一版不增加唤醒词，也不做说话人识别。

## 产品决策

- 第一版采用赛后离线分析，不做后台实时监听。
- 领夹麦音频必须直接保存在训练视频音轨中。
- ShotMarker 直接分析用户选择的视频，不要求用户单独导出音频文件。
- 使用 iOS 26 的 `SpeechAnalyzer`、`SpeechTranscriber` 和 `AssetInputSequenceProvider`。
- 语音转写和命令解析全部在设备本地完成，不依赖业务服务器或第三方语音服务。
- 只把符合已定义语法的文字转换为事件，其他转写内容直接忽略。
- 不要求唤醒词，不因为不同时间出现相同口令而去重。
- 用户确认识别结果后，语音事件才进入训练记录和技术统计。
- Apple Watch 原有双击和 Digital Crown 打点继续保留。
- 语音事件与 Watch 打点使用同一个现有剪辑规划流程。

## 目标

1. 从训练视频音轨中识别中文篮球口令及其时间范围。
2. 把精彩球、篮板、盖帽和得分口令转换为结构化事件。
3. 根据视频录制开始时间，把音频时间转换为现有的绝对 `markedAt`。
4. 按球员汇总进球数、两分球数、三分球数和总得分。
5. 允许用户在应用识别结果前检查、修改或排除错误事件。
6. 复用现有视频准备、片段规划、片段合并、集锦导出和任务队列。
7. 保持本地优先和可解释性，保存原始识别文字、置信度和时间范围。

## 非目标

- 不做实时比分直播。
- 不开发 ShotMarker 自有相机。
- 不让 ShotMarker 和系统相机在同一台 iPhone 上同时争用麦克风。
- 不做说话人声纹识别。
- 不判断视频画面中的投篮是否真实命中。
- 不统计投篮出手数、未命中次数或命中率。
- 不自动区分两分球、三分球和罚球，分值完全以口令为准。
- 不做多人联网计分或云端同步。
- 不删除或替换现有 Watch 打点。
- 不为每类口令设置不同的剪辑窗口，第一版继续使用统一的前后时长。

## 用户流程

### 录制前

1. 球员把无线领夹麦发射器固定在领口。
2. 麦克风接收器连接负责拍摄的 iPhone。
3. 用户在 ShotMarker 中为本次训练配置球员名称和可选别名。
4. 用户确认拍摄设备能收到领夹麦声音。

第一版不在 ShotMarker 内控制系统相机，也不能在录制开始前直接读取系统相机将使用的输入路由。产品说明需要提示用户先录制一段短视频并回放检查声音。

### 训练中

球员在目标事件发生后喊出口令：

- 精彩片段：`好球`、`十佳球`
- 通用技术动作：`篮板`、`盖帽`
- 个人得分：`柯凡两分`、`领袖三分`
- 个人技术动作：`柯凡篮板`、`领袖盖帽`

同一个口令在不同时间重复出现时，每次都代表一个独立事件。

### 训练后

1. 用户进入一条训练记录并选择对应视频。
2. 现有视频准备流程确保视频已下载到本地且包含可读音轨。
3. 用户点击“分析语音口令”。
4. 应用加载本地中文语音模型并分析视频。
5. 页面持续展示分析进度和当前找到的口令数量。
6. 分析完成后展示识别结果列表和球员技术统计预览。
7. 用户可以修改球员、事件类型或分值，也可以排除错误事件。
8. 用户确认后，应用把语音事件合并到训练记录。
9. 现有集锦流程使用 Watch 打点和已确认语音事件生成视频。

## 口令语法

### 固定口令

| 口令 | 事件类型 | 是否计入个人统计 | 是否生成剪辑打点 |
| --- | --- | --- | --- |
| `好球` | `highlight` | 否 | 是 |
| `十佳球` | `topHighlight` | 否 | 是 |
| `篮板` | `rebound` | 否 | 是 |
| `盖帽` | `block` | 否 | 是 |

### 球员口令

| 格式 | 示例 | 统计结果 | 是否生成剪辑打点 |
| --- | --- | --- | --- |
| `<球员>两分` | `柯凡两分` | 进球数 +1、两分球 +1、得分 +2 | 是 |
| `<球员>三分` | `领袖三分` | 进球数 +1、三分球 +1、得分 +3 | 是 |
| `<球员>篮板` | `柯凡篮板` | 篮板 +1 | 是 |
| `<球员>盖帽` | `领袖盖帽` | 盖帽 +1 | 是 |

第一版同时接受阿拉伯数字和中文数字：

- `柯凡2分` 等价于 `柯凡两分`
- `领袖3分` 等价于 `领袖三分`

解析前执行以下规范化：

- 去掉空格和常规标点，不删除口令内部文字。
- 把 `2分` 规范化为 `两分`。
- 把 `3分` 规范化为 `三分`。
- 使用球员配置中的正式名称和别名进行匹配。
- 允许一个命令跨相邻的转写结果，但两个片段的音频间隔不能超过 1 秒。

第一版只做确定性语法匹配，不使用大语言模型推断模糊表达。例如 `这球算他的`、`刚才进了三个` 不会自动转换为事件。

## 技术架构

依赖方向：

```text
TrainingSessionHighlightView
  -> VoiceCommandAnalysisCoordinator
       -> VoiceTranscriptionService
            -> AssetInputSequenceProvider
            -> SpeechAnalyzer
            -> SpeechTranscriber
            -> AssetInventory
       -> BasketballVoiceCommandParser
       -> VoiceEventTimeMapper
       -> PlayerStatSummaryBuilder
  -> VoiceCommandReviewView
  -> TrainingSessionStore
  -> HighlightJobManager
       -> VideoClipSegmentPlanner
       -> VideoClipEditingService
```

### VoiceTranscriptionService

职责：

- 接收已经准备完成的本地 `AVAsset`。
- 检查视频是否包含音轨。
- 使用 `SpeechTranscriber.supportedLocale(equivalentTo:)` 检查中文 locale。
- 通过 `AssetInventory` 检查并按需下载本地语音模型。
- 创建带有音频时间范围和置信度属性的 `SpeechTranscriber`。
- 通过 `AssetInputSequenceProvider` 直接读取视频音轨。
- 把 provider 的 `analyzerInputs` 交给 `SpeechAnalyzer`。
- 只输出最终转写结果，不把 volatile 中间结果转换成事件。
- 支持进度、取消和明确错误。

服务返回按音频时间排序的转写片段：

```swift
struct VoiceTranscriptSegment: Equatable {
    let text: String
    let audioTimeRange: CMTimeRange
    let confidence: Float?
}
```

`SpeechAnalyzer` 负责分析音频，`SpeechTranscriber` 负责生成文字。应用自己的解析器负责理解篮球业务含义。

### AnalysisContext

开始分析前，把以下内容加入 `AnalysisContext.contextualStrings`：

- 本次训练的球员正式名称。
- 球员别名。
- `好球`、`十佳球`、`篮板`、`盖帽`。
- 每名球员与 `两分`、`三分`、`篮板`、`盖帽` 组合后的短语。

上下文词表用于提高人名和篮球术语的识别概率，但不替代命令解析和用户确认。

### BasketballVoiceCommandParser

解析器是一个不依赖 Speech 或 AVFoundation 的纯 Swift 组件。

输入：

- 按时间排序的 `VoiceTranscriptSegment`。
- 本次训练的球员和别名配置。

输出：

```swift
enum VoiceBasketballCommand: Equatable {
    case highlight(priority: HighlightPriority)
    case score(playerID: UUID, points: Int)
    case rebound(playerID: UUID?)
    case block(playerID: UUID?)
}

struct VoiceCommandCandidate: Identifiable, Equatable {
    let id: UUID
    let command: VoiceBasketballCommand
    let audioTimeRange: CMTimeRange
    let rawText: String
    let normalizedText: String
    let confidence: Float?
}
```

解析器先在单个转写片段内匹配，再检查相邻且连续的片段。例如识别器分别返回 `柯凡` 和 `两分` 时，只要两个片段的音频间隔不超过 1 秒，就可以组合为 `柯凡两分`。

### VoiceEventTimeMapper

语音识别结果使用视频音频时间轴，现有 `VideoClipSegmentPlanner` 使用绝对时间。时间映射规则为：

```text
markedAt = video.recordedStartAt + command.audioTimeRange.end
```

选择口令结束时间，是因为只有完整口令结束后才能确认命令语义，也最接近用户完成一次语音打点的时刻。现有默认剪辑窗口会保留打点前 9 秒和打点后 4 秒，能够覆盖发生在口令之前的进球或精彩动作。

每个语音候选事件同时保留：

- 视频标识。
- 视频内相对时间范围。
- 映射后的绝对 `markedAt`。

如果视频缺少可靠的 `recordedStartAt`，应用可以展示转写结果和相对时间，但不能把事件合并到现有训练记录或进入自动剪辑。

### PlayerStatSummaryBuilder

统计器只读取用户已确认的结构化事件。

每名球员输出：

```swift
struct PlayerStatSummary: Equatable {
    let playerID: UUID
    let madeFieldGoals: Int
    let madeTwoPointers: Int
    let madeThreePointers: Int
    let points: Int
    let rebounds: Int
    let blocks: Int
}
```

计算规则：

- 两分事件：`madeFieldGoals +1`、`madeTwoPointers +1`、`points +2`
- 三分事件：`madeFieldGoals +1`、`madeThreePointers +1`、`points +3`
- 个人篮板事件：`rebounds +1`
- 个人盖帽事件：`blocks +1`
- 没有球员的 `篮板` 或 `盖帽` 只生成剪辑打点，不计入个人统计
- `好球` 和 `十佳球` 只生成剪辑打点
- Watch 打点只生成剪辑，不计入语音技术统计

## 数据模型

### 训练记录事件

现有 `ShotMarkerEvent` 只有 `id` 和 `markedAt`。为了兼容已有 JSON、Watch 同步和剪辑规划，新增字段应具有向后兼容默认值：

```swift
struct ShotMarkerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let markedAt: Date
    let source: ShotMarkerEventSource
    let details: ShotMarkerEventDetails?
}

enum ShotMarkerEventSource: String, Codable {
    case watch
    case voice
}

enum ShotMarkerEventDetails: Codable, Equatable {
    case highlight(priority: HighlightPriority)
    case score(playerID: UUID, playerName: String, points: Int)
    case rebound(playerID: UUID?, playerName: String?)
    case block(playerID: UUID?, playerName: String?)
}
```

旧训练数据缺少 `source` 时按 `.watch` 解码，缺少 `details` 时按 `nil` 解码。Watch 同步 payload 保持现状，iPhone 导入 Watch 事件时写入 `.watch`。

### 语音分析结果

语音分析先保存为独立结果，不直接修改训练记录：

```swift
struct VoiceAnalysisResult: Identifiable, Codable, Equatable {
    let id: UUID
    let trainingSessionID: UUID
    let videos: [VoiceAnalyzedVideo]
    var candidates: [PersistedVoiceCommandCandidate]
    let localeIdentifier: String
    let analyzerVersion: Int
    let analyzedAt: Date
    var confirmedAt: Date?
}
```

这样可以：

- 在确认页面退出后恢复分析结果。
- 避免长视频被重复转写。
- 允许用户重新编辑候选事件。
- 在解析规则升级后通过 `analyzerVersion` 主动重新分析。

每个视频保存稳定标识、时长和录制开始时间。再次选择同一视频时，如果这些信息和 analyzer 版本一致，则复用已完成分析；否则重新分析。

### 确认与去重

用户确认时，为每个被保留的候选事件生成稳定指纹：

```text
videoID + audioTimeRange + normalizedCommand
```

同一个训练记录再次确认同一份分析结果时，先替换该分析结果此前生成的语音事件，不做追加。这样不会因为重复进入确认页导致比分和打点翻倍。

不同音频时间范围内出现相同命令时必须保留。例如两次不同时间的 `柯凡两分` 代表两个进球。

## 与现有剪辑流程的集成

确认语音分析结果后：

1. 把确认的候选转换为带绝对 `markedAt` 的 `ShotMarkerEvent`。
2. 将其与原有 Watch 事件合并并按时间排序。
3. 保存更新后的 `TrainingSession`。
4. 现有 `VideoClipSegmentPlanner` 不需要理解事件类型，只继续读取 `id` 和 `markedAt`。
5. Watch 打点和语音事件产生的片段重叠时，继续使用现有“重叠或间隔不超过 1 秒则合并”的规则。
6. 创建 `HighlightJob` 时保存已确认事件的训练记录快照。

语音事件类型和球员统计不会改变剪辑算法。第一版所有语音事件都使用当前统一的 `ClipSettings`。

## 识别结果确认

确认页必须展示：

- 视频相对时间。
- 原始识别文字。
- 解析后的球员和事件类型。
- 两分或三分事件的分值。
- 置信度较低提示。
- 是否包含在本次结果中。

用户可以：

- 修改球员。
- 在两分和三分之间修改。
- 修改事件类型。
- 排除误识别事件。
- 恢复被排除事件。

页面顶部展示根据当前保留事件实时计算的个人统计。只有用户点击确认后，训练记录和统计结果才会更新。

## 进度与取消

长视频转写不能阻塞主线程。

分析状态：

- `preparingVideo`
- `preparingSpeechModel`
- `transcribing`
- `parsing`
- `readyForReview`
- `failed`
- `cancelled`

UI 至少展示：

- 当前阶段。
- 已分析音频时长与视频总时长。
- 当前已找到口令数量。
- 取消按钮。

用户取消时：

- 取消当前 Swift `Task`。
- 结束或取消 `SpeechAnalyzer`。
- 不生成可确认的半成品结果。
- 已经完成并持久化的旧分析结果不受影响。

## 错误处理

### 视频没有音轨

提示：

`所选视频没有可分析的声音，请确认拍摄时领夹麦已正常录音。`

允许用户返回重新选择视频，Watch 打点流程仍可继续。

### 中文 locale 不受支持

在运行时调用 `SpeechTranscriber.supportedLocale(equivalentTo:)`，不能假设所有系统配置和设备都支持目标中文 locale。

提示：

`这台设备暂不支持所选语言的本地语音识别。`

保留 Watch 打点和原有集锦功能。

### 语音模型未安装

通过 `AssetInventory` 请求下载并展示系统模型准备进度。下载失败时保留重试入口，不把网络失败误报为视频问题。

### 没有匹配口令

转写成功但没有匹配到命令时提示：

`没有识别到已配置的篮球口令。你仍然可以使用 Apple Watch 打点生成集锦。`

### 低置信度

语法完整但综合置信度低于 `0.6` 的命令仍进入确认页，并显示警告，不在服务层静默删除。一个命令跨多个词时，使用匹配范围内最低的词置信度作为综合置信度；系统没有提供置信度时显示“置信度不可用”，不因此排除事件。最终是否保留由用户决定。

### 视频时间无效

如果视频缺少可靠录制开始时间：

- 保留相对时间和转写结果。
- 禁止合并到绝对时间训练记录。
- 提示用户重新选择带录制时间的视频。

## 硬件与录音建议

推荐使用：

- 2.4 GHz 无线领夹麦。
- 连接拍摄 iPhone 的 USB-C 接收器。
- 发射器夹在靠近嘴部、尽量避免衣物摩擦的位置。

不把普通蓝牙 HFP 麦克风作为默认方案。USB 音频输入通常更适合长时间、嘈杂球场环境。ShotMarker 的第一版离线方案只读取视频最终音轨，因此实际麦克风兼容性以系统相机录制结果为准。

产品说明需要强调：

1. 正式训练前录制一段测试视频。
2. 回放确认人声清晰。
3. 确认长时间录制所需电量和存储空间。

## 权限与隐私

- `SpeechAnalyzer` 转写在设备本地完成，语音不发送到 Apple 服务器。
- 应用仍按 Apple 要求配置清晰的 Speech 使用说明。
- 第一版不直接打开摄像头或麦克风，因此不因为语音分析额外申请实时麦克风权限。
- 视频继续通过现有系统 picker 和本地视频准备流程提供。
- 原始视频、转写结果、口令事件和球员统计默认只保存在设备内。
- 用户删除训练记录时，应同时清理关联的语音分析结果。
- 产品说明应提醒用户遵守拍摄场地和同场人员的录音同意要求。

## 性能策略

- 每次只分析一个视频音轨。
- 多视频按录制时间顺序串行分析，避免语音模型、视频读取和集锦导出同时争抢资源。
- 分析期间不自动启动集锦导出。
- 已完成结果按视频和 analyzer 版本缓存，避免重复处理长视频。
- 应用进入后台时不承诺分析持续完成；如果系统暂停或终止任务，下次打开后允许重新开始。
- 语音模型准备和视频 iCloud 下载复用明确、可取消的准备阶段。

## 测试策略

### 口令解析单元测试

- `好球` 解析为普通精彩事件。
- `十佳球` 解析为高优先级精彩事件。
- `篮板` 和 `盖帽` 解析为无球员技术事件。
- `柯凡两分`、`柯凡2分` 都解析为柯凡两分。
- `领袖三分`、`领袖3分` 都解析为领袖三分。
- `柯凡篮板` 和 `领袖盖帽` 解析为个人技术统计。
- 球员别名能够映射到正式球员。
- 相邻片段中的 `柯凡` 和 `两分` 可以组合。
- 相距过远的片段不能错误组合。
- 普通对话中不符合语法的文字被忽略。
- 不同时间出现相同口令时生成两个事件。
- 同一音频时间范围的 volatile 和 final 结果不会生成重复事件。

### 时间映射单元测试

- 音频时间范围结束时间正确转换为绝对 `markedAt`。
- 不同时长、不同视频开始时间的映射正确。
- 多视频事件按绝对时间排序。
- 语音事件落在视频边界时可以进入现有剪辑规划。
- 缺少录制开始时间时不生成绝对事件。

### 统计单元测试

- 两分事件正确累计进球数、两分球和总得分。
- 三分事件正确累计进球数、三分球和总得分。
- 篮板和盖帽分别累计。
- 无球员事件不进入个人统计。
- 被用户排除的候选不进入统计。
- 修改两分为三分后统计立即更新。
- 重复确认同一分析结果不会重复累计。

### 持久化兼容测试

- 旧版 `ShotMarkerEvent` JSON 缺少新字段时按 Watch 普通打点解码。
- 新版语音事件编码和解码保持一致。
- 旧训练记录升级后仍能生成集锦。
- 删除训练记录时清理语音分析缓存。

### 集成和真机测试

- 使用包含标准中文口令的短视频验证文字和时间范围。
- 使用完整篮球训练视频验证长时间分析、取消和重新开始。
- 在有球鞋声、篮球撞击声、音乐和其他人说话的环境测试。
- 测试 USB-C 领夹麦、手机内置麦和可用的蓝牙输入录制视频。
- 验证视频在 iCloud 时先准备本地文件再分析。
- 验证分析完成后语音事件能和 Watch 打点一起生成集锦。
- 验证录制两次相同得分口令会正确计为两个进球。

## 验收标准

- 用户可以对已选择的本地视频启动语音分析。
- 应用能识别并定位已定义的中文篮球口令。
- `柯凡两分` 和 `领袖三分` 等口令能正确生成球员得分统计。
- 相同口令在不同时间出现时分别计数。
- 用户能在确认前修改或排除事件。
- 确认同一分析结果多次不会造成重复计分或重复打点。
- 已确认语音事件能复用现有剪辑规划和集锦任务队列。
- 旧训练记录和 Watch 同步 payload 保持兼容。
- 没有音轨、模型不可用、没有匹配口令和用户取消都有明确结果。
- 语音分析失败时，Watch 打点和原有集锦功能仍可使用。

## 后续演进

第一版稳定后，可以单独设计以下增强，不包含在本方案实现范围：

1. ShotMarker 内置相机。
2. 使用同一个 `AVCaptureSession` 同时保存视频并实时处理音频采样。
3. 实时口令识别和比分展示。
4. Apple Watch 实时震动确认语音打点。
5. 罚球、助攻、抢断和犯规等更多统计口令。
6. 针对不同事件类型使用不同剪辑窗口。
7. 在集锦中叠加球员姓名、分值和比分字幕。

## Apple 官方参考

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AssetInputSequenceProvider](https://developer.apple.com/documentation/speech/assetinputsequenceprovider)
- [SpeechTranscriber.Result](https://developer.apple.com/documentation/speech/speechtranscriber/result)
- [AnalysisContext](https://developer.apple.com/documentation/speech/analysiscontext)
- [Asking Permission to Use Speech Recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [AVAudioSession audio routing](https://developer.apple.com/documentation/avfaudio/audio-routing)
- [Enhance your app’s audio recording capabilities](https://developer.apple.com/videos/play/wwdc2025/251/)
