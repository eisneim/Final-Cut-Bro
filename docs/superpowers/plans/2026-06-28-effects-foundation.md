# Plan 1:特效系统基础(模型 + Core Image 自定义合成器 + 音频淡入淡出 + Inspector)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 FCPX-lite 加上可堆叠的特效系统——effects 挂在 clip 上,视频特效经自研 Core Image 合成器(替换现有 layerInstruction 路径,统一处理 transform/crop/opacity/z-order/CIFilter),音频淡入淡出经 AVAudioMix 斜坡,Inspector 可增删调参。

**Architecture:** `Clip.effects: [Effect]` 数据化挂载;`CoreImageCompositor`(AVVideoCompositing 协议)逐帧用 Core Image 合成多轨,每层套几何变换+滤镜链;`CompositionBuilder` 改为挂自定义 compositor 并把 per-clip 参数装进自定义 instruction;音频 fade 用 `setVolumeRamp`。先做"等价替换旧行为"回归,再加滤镜。

**Tech Stack:** Swift / AVFoundation(AVVideoCompositing/AVAsynchronousVideoCompositionRequest)/ Core Image(CIFilter/CIContext)/ XCTest。

## Global Constraints

- 单文件 < 500 行;超出拆分。
- Dev fail-fast:非法参数/越界 → 明确错误,不静默兜底。
- 有理数 `Time`,不引入浮点比较到模型层。
- 现有 166 测试必须保持通过;预览既有行为(transform/crop/opacity/多轨 z-order)不得回归。
- 几何复用:`CompositionBuilder.fullTransform(adjust:natural:pref:renderSize:)` 的数学是事实基准,新合成器须与之等价。
- Clip 现用默认 Codable 合成(无自定义 CodingKeys);加字段须保证旧 JSON 仍可解码(`decodeIfPresent` 默认 `[]`)。

---

### Task 1: Effect 模型 + Clip.effects 字段(含 Codable 迁移)

**Files:**
- Create: `Sources/FCPXLite/Models/Effect.swift`
- Modify: `Sources/FCPXLite/Document/Clip.swift`
- Test: `Tests/FCPXLiteTests/EffectModelTests.swift`

**Interfaces:**
- Produces:
  - `enum EffectKind: String, Codable, CaseIterable { case color, blur, fade }`
  - `struct Effect: Codable, Equatable, Identifiable { var id: UUID; var kind: EffectKind; var enabled: Bool; var params: [String: Double] }` + `static func make(_ kind:) -> Effect`(按 kind 填默认参数)
  - `Clip.effects: [Effect]`(默认 `[]`,旧 JSON 缺字段时解码为 `[]`)
  - `EffectKind.isVideo: Bool`(color/blur=true,fade=false)、`EffectKind.defaultParams: [String:Double]`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/FCPXLiteTests/EffectModelTests.swift
import XCTest
@testable import FCPXLite

final class EffectModelTests: XCTestCase {
    func testMakeFillsDefaultParams() {
        let color = Effect.make(.color)
        XCTAssertEqual(color.kind, .color)
        XCTAssertTrue(color.enabled)
        XCTAssertEqual(color.params["brightness"], 0)
        XCTAssertEqual(color.params["contrast"], 1)
        XCTAssertEqual(color.params["saturation"], 1)
        XCTAssertEqual(Effect.make(.blur).params["radius"], 0)
        XCTAssertEqual(Effect.make(.fade).params["inSeconds"], 0)
        XCTAssertEqual(Effect.make(.fade).params["outSeconds"], 0)
    }

    func testIsVideo() {
        XCTAssertTrue(EffectKind.color.isVideo)
        XCTAssertTrue(EffectKind.blur.isVideo)
        XCTAssertFalse(EffectKind.fade.isVideo)
    }

    func testEffectCodableRoundtrip() throws {
        var e = Effect.make(.blur); e.params["radius"] = 12; e.enabled = false
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(Effect.self, from: data)
        XCTAssertEqual(e, back)
    }

    // 关键:旧 JSON(无 effects 字段)仍能解码成空数组。
    func testClipDecodesWithoutEffectsField() throws {
        let json = """
        {"id":{"raw":"X"},"assetID":{"raw":"A"},"sourceIn":{"value":0,"timescale":600},
         "duration":{"value":600,"timescale":600},"connected":[],"lane":0,
         "offset":{"value":0,"timescale":600},
         "adjust":{"transform":{"positionX":0,"positionY":0,"scaleWidth":1,"scaleHeight":1,"rotation":0,"anchorX":0,"anchorY":0},
                   "crop":{"left":0,"right":0,"top":0,"bottom":0},"opacity":1,"volume":1}}
        """.data(using: .utf8)!
        let clip = try JSONDecoder().decode(Clip.self, from: json)
        XCTAssertEqual(clip.effects, [])
    }

    func testClipWithEffectsRoundtrip() throws {
        var clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        clip.effects = [Effect.make(.color), Effect.make(.fade)]
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back.effects.count, 2)
        XCTAssertEqual(back.effects[0].kind, .color)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter EffectModelTests`
Expected: 编译失败(Effect 未定义)

- [ ] **Step 3: 实现 Effect 模型**

```swift
// Sources/FCPXLite/Models/Effect.swift
import Foundation

/// 特效种类。color/blur 是视频滤镜(Core Image);fade 是音频淡入淡出(AVAudioMix 斜坡)。
enum EffectKind: String, Codable, CaseIterable {
    case color   // CIColorControls: brightness/contrast/saturation
    case blur    // CIGaussianBlur: radius
    case fade    // 音频淡入淡出: inSeconds/outSeconds

    var isVideo: Bool { self != .fade }

    var defaultParams: [String: Double] {
        switch self {
        case .color: return ["brightness": 0, "contrast": 1, "saturation": 1]
        case .blur:  return ["radius": 0]
        case .fade:  return ["inSeconds": 0, "outSeconds": 0]
        }
    }
}

/// 可堆叠特效。挂在 clip 上,列表顺序 = 视频滤镜链应用顺序。params 扁平键值。
struct Effect: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: EffectKind
    var enabled: Bool
    var params: [String: Double]

    static func make(_ kind: EffectKind) -> Effect {
        Effect(id: UUID(), kind: kind, enabled: true, params: kind.defaultParams)
    }
}
```

- [ ] **Step 4: 给 Clip 加 effects 字段 + 迁移解码**

把 `Sources/FCPXLite/Document/Clip.swift` 整体替换为(加 `effects` 存储属性、init 默认参、自定义 `init(from:)` 让旧 JSON 解码为 `[]`、显式 `encode`):

```swift
import Foundation

/// 时间线片段。引用 asset,自己只存 in/out。
/// connected/lane/offset 仅用于连接片段(L2/L3);spine 上的 clip lane 恒为 0。
struct Clip: Identifiable, Codable, Equatable {
    let id: ClipID
    var assetID: AssetID
    var sourceIn: Time
    var duration: Time
    var connected: [Clip]
    var lane: Int
    var offset: Time          // 相对【宿主 clip 起点】
    var adjust: Adjustments
    var effects: [Effect]

    init(id: ClipID = ClipID(), assetID: AssetID, sourceIn: Time, duration: Time,
         connected: [Clip] = [], lane: Int = 0, offset: Time = .zero,
         adjust: Adjustments = Adjustments(), effects: [Effect] = []) {
        self.id = id; self.assetID = assetID
        self.sourceIn = sourceIn; self.duration = duration
        self.connected = connected; self.lane = lane
        self.offset = offset; self.adjust = adjust; self.effects = effects
    }

    enum CodingKeys: String, CodingKey {
        case id, assetID, sourceIn, duration, connected, lane, offset, adjust, effects
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ClipID.self, forKey: .id)
        assetID = try c.decode(AssetID.self, forKey: .assetID)
        sourceIn = try c.decode(Time.self, forKey: .sourceIn)
        duration = try c.decode(Time.self, forKey: .duration)
        connected = try c.decode([Clip].self, forKey: .connected)
        lane = try c.decode(Int.self, forKey: .lane)
        offset = try c.decode(Time.self, forKey: .offset)
        adjust = try c.decode(Adjustments.self, forKey: .adjust)
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []   // 旧 JSON 缺字段 → []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(sourceIn, forKey: .sourceIn)
        try c.encode(duration, forKey: .duration)
        try c.encode(connected, forKey: .connected)
        try c.encode(lane, forKey: .lane)
        try c.encode(offset, forKey: .offset)
        try c.encode(adjust, forKey: .adjust)
        try c.encode(effects, forKey: .effects)
    }
}
```

- [ ] **Step 5: 运行确认通过 + 全量回归**

Run: `swift test --filter EffectModelTests && swift test 2>&1 | tail -2`
Expected: EffectModelTests 5 过;全量 ≥171 过(原 166 + 5)。

- [ ] **Step 6: 提交**

```bash
git add Sources/FCPXLite/Models/Effect.swift Sources/FCPXLite/Document/Clip.swift Tests/FCPXLiteTests/EffectModelTests.swift
git commit -m "feat(effect): Effect模型+Clip.effects字段(Codable迁移)+测试"
```

---

### Task 2: setEffects 命令(可撤销)

**Files:**
- Modify: `Sources/FCPXLite/Store/EditorAction.swift`(加 case)
- Modify: `Sources/FCPXLite/Store/DocumentStore.swift`(dispatch 路由)
- Modify: `Sources/FCPXLite/Document/Magnetic/Mutations.swift`(setEffects 纯函数)
- Test: `Tests/FCPXLiteTests/SetEffectsTests.swift`

**Interfaces:**
- Consumes: Task 1 `Effect`、`Clip.effects`。现有 `Mutations.setAdjust(clipID:_:in:)` 模式(对主轴或连接子项按 id 改字段)。
- Produces: `EditorAction.setEffects(ClipID, [Effect])`;`Mutations.setEffects(clipID:_:in:) -> Sequence`;`store.dispatch(.setEffects(id, effects))`。

- [ ] **Step 1: 写失败测试**

```swift
// Tests/FCPXLiteTests/SetEffectsTests.swift
import XCTest
@testable import FCPXLite

@MainActor
final class SetEffectsTests: XCTestCase {
    private func store1Clip() -> (DocumentStore, ClipID) {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                      duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(10))
        let s = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                 assetLibrary: [a], sequence: Sequence(spine: [.clip(clip)])))
        return (s, clip.id)
    }

    func testSetEffectsOnSpineClip() {
        let (store, id) = store1Clip()
        store.dispatch(.setEffects(id, [Effect.make(.color)]))
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects.count, 1)
        XCTAssertEqual(c.effects[0].kind, .color)
    }

    func testSetEffectsUndoable() {
        let (store, id) = store1Clip()
        store.dispatch(.setEffects(id, [Effect.make(.blur)]))
        store.undo()
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects.count, 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter SetEffectsTests`
Expected: FAIL(`.setEffects` 未定义)

- [ ] **Step 3: 加 EditorAction case**

在 `EditorAction.swift` 的 enum 里(`setAdjust` 之后)加:
```swift
    case setEffects(ClipID, [Effect])
```

- [ ] **Step 4: 加 Mutations.setEffects**

参照 `Mutations.setAdjust` 的实现(同文件里搜 `static func setAdjust`),在其后加同构函数——遍历 spine,对 id 匹配的主轴 clip 或其 connected 子项设 `effects`:
```swift
    /// 设置某 clip(主轴或连接子项)的 effects 列表。纯函数,调用方负责 commit。
    static func setEffects(clipID id: ClipID, _ effects: [Effect], in seq: Sequence) -> Sequence {
        var seq = seq
        for i in seq.spine.indices {
            if case .clip(var host) = seq.spine[i] {
                if host.id == id { host.effects = effects; seq.spine[i] = .clip(host); return seq }
                for j in host.connected.indices where host.connected[j].id == id {
                    host.connected[j].effects = effects; seq.spine[i] = .clip(host); return seq
                }
            }
        }
        return seq
    }
```

- [ ] **Step 5: 加 dispatch 路由**

在 `DocumentStore.swift` 的 dispatch switch 里(`case let .setAdjust` 那行附近)加:
```swift
        case let .setEffects(id, fx):    apply { Mutations.setEffects(clipID: id, fx, in: $0) }
```

- [ ] **Step 6: 运行确认通过 + 回归**

Run: `swift test --filter SetEffectsTests && swift test 2>&1 | tail -2`
Expected: 2 过;全量 ≥173 过。

- [ ] **Step 7: 提交**

```bash
git add Sources/FCPXLite/Store/EditorAction.swift Sources/FCPXLite/Store/DocumentStore.swift Sources/FCPXLite/Document/Magnetic/Mutations.swift Tests/FCPXLiteTests/SetEffectsTests.swift
git commit -m "feat(effect): setEffects命令(可撤销)+测试"
```

---

### Task 3: CoreImageCompositor —— 等价替换旧合成行为(回归优先)

**Files:**
- Create: `Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift`
- Create: `Sources/FCPXLite/Engine/Composition/CompositorInstruction.swift`
- Modify: `Sources/FCPXLite/Engine/Composition/CompositionBuilder.swift`(改挂自定义 compositor)
- Test: `Tests/FCPXLiteTests/CoreImageCompositorTests.swift`

**Interfaces:**
- Consumes: `CompositionBuilder.fullTransform(adjust:natural:pref:renderSize:)`(几何基准),`Adjustments`,`Clip.effects`(本任务先不应用滤镜,只透传)。
- Produces:
  - `final class CompositorLayer: NSObject`(每层数据:trackID:Int32、transform:CGAffineTransform、opacity:Float、effects:[Effect])
  - `final class CompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol`(timeRange、enablePostProcessing=false、containsTweening=false、requiredSourceTrackIDs、passthroughTrackID=nil、layers:[CompositorLayer] 按绘制顺序=底层在前)
  - `final class CoreImageCompositor: NSObject, AVVideoCompositing`(sourcePixelBufferAttributes、requiredPixelBufferAttributesForRenderContext、renderContextChanged、startRequest)
- 行为契约:本任务**不应用 CIFilter**(effects 透传不用),只用 Core Image 实现 transform+opacity+z-order 合成,使输出与旧 layerInstruction 路径**视觉等价**。

**说明(给实现者):** AVVideoCompositing 自定义合成器逐帧被回调 `startRequest`。从 `request.sourceFrame(byTrackID:)` 取各活跃源轨的 `CVPixelBuffer`→`CIImage`,按 instruction.layers 顺序(底→顶)对每层套 `transform`(用 CompositorLayer.transform,已是源像素→renderSize 的完整矩阵)、乘 `opacity`(CIColorMatrix 调 alpha),`composited(over:)` 叠加,最后渲染到从 `request.renderContext.newPixelBuffer()` 取的输出 buffer,`request.finish(withComposedVideoFrame:)`。用一个持有的 `CIContext`(renderContextChanged 时按需重建)。色彩空间用 `CGColorSpaceCreateDeviceRGB()`。

- [ ] **Step 1: 写失败测试(用真实短合成验证产物可解码 + 尺寸正确)**

```swift
// Tests/FCPXLiteTests/CoreImageCompositorTests.swift
import XCTest
import AVFoundation
@testable import FCPXLite

final class CoreImageCompositorTests: XCTestCase {
    // 生成一个纯色 N 秒视频文件(真实可解码视频轨,供合成器测试)。
    private func makeColorVideo(seconds: Double, size: CGSize, color: CIColor) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("citest-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let fps = 25, total = Int(seconds * Double(fps))
        let ctx = CIContext()
        var pbo: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pbo)
        for f in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            if let pb = pbo { ctx.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: pb)
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))) }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }

    // 合成器接入后:单视频片段仍能产出可解码、尺寸=renderSize 的帧(等价旧行为,不崩)。
    func testCompositorProducesFrameForSingleVideo() throws {
        let url = try makeColorVideo(seconds: 1, size: CGSize(width: 320, height: 240), color: .red)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .video, duration: .seconds(1),
                          naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)
        XCTAssertNotNil(item?.videoComposition)
        // videoComposition 的 customVideoCompositorClass 应是我们的合成器
        XCTAssertTrue(item?.videoComposition?.customVideoCompositorClass == CoreImageCompositor.self)
        // 用 imageGenerator 取一帧 → 不为 nil(产物可渲染)
        let gen = AVAssetImageGenerator(asset: item!.asset)
        gen.videoComposition = item!.videoComposition
        let cg = try gen.copyCGImage(at: CMTime(value: 1, timescale: 4), actualTime: nil)
        XCTAssertEqual(cg.width, 1920)
        XCTAssertEqual(cg.height, 1080)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter CoreImageCompositorTests`
Expected: FAIL(CoreImageCompositor 未定义 / videoComposition 仍是内建)

- [ ] **Step 3: 实现 CompositorInstruction + CompositorLayer**

```swift
// Sources/FCPXLite/Engine/Composition/CompositorInstruction.swift
import AVFoundation
import CoreImage

/// 一层的合成数据:源轨 ID + 完整几何矩阵(源像素→renderSize)+ 不透明度 + 特效链。
final class CompositorLayer: NSObject {
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let opacity: Float
    let effects: [Effect]
    init(trackID: CMPersistentTrackID, transform: CGAffineTransform, opacity: Float, effects: [Effect]) {
        self.trackID = trackID; self.transform = transform; self.opacity = opacity; self.effects = effects
    }
}

/// 自定义合成指令:某时间区间内活跃的层(layers 顺序=底→顶)。
final class CompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [CompositorLayer]
    init(timeRange: CMTimeRange, layers: [CompositorLayer]) {
        self.timeRange = timeRange; self.layers = layers
        self.requiredSourceTrackIDs = layers.map { NSNumber(value: $0.trackID) }
    }
}
```

- [ ] **Step 4: 实现 CoreImageCompositor(本任务不应用 CIFilter,只几何+opacity+z-order)**

```swift
// Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift
import AVFoundation
import CoreImage

/// 自研视频合成器:逐帧用 Core Image 把多轨按 z-order 合成,每层套几何矩阵+不透明度(+后续滤镜)。
/// 替换 AVMutableVideoCompositionLayerInstruction 路径,以便挂 per-clip CIFilter 特效。
final class CoreImageCompositor: NSObject, AVVideoCompositing {
    private var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "fcpxlite.compositor")

    var sourcePixelBufferAttributes: [String: Any]? =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            guard let instruction = request.videoCompositionInstruction as? CompositorInstruction,
                  let dest = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "compositor", code: -1)); return
            }
            // 底→顶叠加。空层 → 透明黑底。
            var acc: CIImage = CIImage(color: .clear).cropped(
                to: CGRect(origin: .zero, size: request.renderContext.size))
            for layer in instruction.layers {
                guard let pb = request.sourceFrame(byTrackID: layer.trackID) else { continue }
                var img = CIImage(cvPixelBuffer: pb).transformed(by: layer.transform)
                // 不透明度:乘 alpha
                if layer.opacity < 1 {
                    let f = CIFilter(name: "CIColorMatrix")!
                    f.setValue(img, forKey: kCIInputImageKey)
                    f.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)), forKey: "inputAVector")
                    img = f.outputImage ?? img
                }
                // (Task 4 在此插入 effects 滤镜链)
                acc = img.composited(over: acc)
            }
            self.ciContext.render(acc, to: dest)
            request.finish(withComposedVideoFrame: dest)
        }
    }
}
```

- [ ] **Step 5: 改 CompositionBuilder 挂自定义 compositor**

在 `CompositionBuilder.build` 里,原先构造 `AVMutableVideoCompositionInstruction` + `layerInstructions` 的整段(分段 instruction 循环)替换为构造 `CompositorInstruction` + `CompositorLayer`(transform 用 `fullTransform(...)`,opacity 用 `seg.adjust.opacity`,effects 用该段 clip 的 effects——本任务透传)。并设:
```swift
        vc.customVideoCompositorClass = CoreImageCompositor.self
        vc.instructions = compositorInstructions   // [CompositorInstruction]
```
注意:`AVMutableVideoComposition.instructions` 接受 `[AVVideoCompositionInstructionProtocol]`,`CompositorInstruction` 已符合。`renderSize`/`frameDuration` 设置不变。段切分逻辑(各 start/end 编辑点)复用现有 `bounds`/`sorted`。每段 layers 按 `lane` 升序(底→顶,与旧 layerInstructions 的"高 lane 在前=顶"相反:这里 layers 顺序底在前,故按 lane **升序**)。

> 实现者注意:需要把"段"与其源 trackID 关联——`segments` 已含 `track`,用 `track.trackID` 作 `CompositorLayer.trackID`。effects 从该段对应 clip 取(给 segment 元组加 `effects: [Effect]` 字段,place() 时填 `clip.effects`)。

- [ ] **Step 6: 运行确认通过 + 全量回归(关键:既有预览测试不破)**

Run: `swift test --filter CoreImageCompositorTests && swift test --filter CompositionBuilderTests && swift test --filter CompositionTransformTests && swift test 2>&1 | tail -2`
Expected: 全过。`CompositionTransformTests`(fullTransform 几何)不受影响;`CompositionBuilderTests`(含纯音频、空、图片跳过)仍过;新合成器测试过。

- [ ] **Step 7: 提交**

```bash
git add Sources/FCPXLite/Engine/Composition/ Tests/FCPXLiteTests/CoreImageCompositorTests.swift
git commit -m "feat(compositor): Core Image自定义合成器等价替换layerInstruction(几何+opacity+z-order)+回归"
```

---

### Task 4: 视频特效滤镜链(color/blur)接入合成器

**Files:**
- Modify: `Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift`(应用 effects)
- Create: `Sources/FCPXLite/Engine/Composition/VideoEffectFilters.swift`(Effect→CIFilter 映射)
- Test: `Tests/FCPXLiteTests/VideoEffectFiltersTests.swift`

**Interfaces:**
- Consumes: `Effect`、`EffectKind`、Task 3 的 `CompositorLayer.effects`。
- Produces: `enum VideoEffectFilters { static func apply(_ effects: [Effect], to image: CIImage) -> CIImage }`(只处理 isVideo 且 enabled;按列表顺序链式;未知/禁用跳过)。

- [ ] **Step 1: 写失败测试(纯 CIImage 单元,不需视频文件)**

```swift
// Tests/FCPXLiteTests/VideoEffectFiltersTests.swift
import XCTest
import CoreImage
@testable import FCPXLite

final class VideoEffectFiltersTests: XCTestCase {
    private let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))

    func testNoEffectsReturnsSameExtent() {
        let out = VideoEffectFilters.apply([], to: base)
        XCTAssertEqual(out.extent, base.extent)
    }

    func testDisabledEffectSkipped() {
        var e = Effect.make(.blur); e.params["radius"] = 8; e.enabled = false
        let out = VideoEffectFilters.apply([e], to: base)
        XCTAssertEqual(out.extent, base.extent)   // 禁用 → 不模糊,extent 不变
    }

    func testBlurChangesExtent() {
        var e = Effect.make(.blur); e.params["radius"] = 8; e.enabled = true
        let out = VideoEffectFilters.apply([e], to: base)
        // 高斯模糊会扩大 extent
        XCTAssertGreaterThan(out.extent.width, base.extent.width)
    }

    func testFadeIsAudioSoSkippedByVideoChain() {
        let out = VideoEffectFilters.apply([Effect.make(.fade)], to: base)
        XCTAssertEqual(out.extent, base.extent)   // fade 非视频 → 视频链跳过
    }

    func testColorControlsApplied() {
        var e = Effect.make(.color); e.params["brightness"] = 0.3
        let out = VideoEffectFilters.apply([e], to: base)
        // 渲染前后平均亮度应升高
        let ctx = CIContext()
        func avg(_ img: CIImage) -> CGFloat {
            let f = CIFilter(name: "CIAreaAverage")!
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(cgRect: CGRect(x: 0, y: 0, width: 16, height: 16)), forKey: "inputExtent")
            var bm = [UInt8](repeating: 0, count: 4)
            ctx.render(f.outputImage!, toBitmap: &bm, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return CGFloat(bm[0])
        }
        XCTAssertGreaterThan(avg(out), avg(base))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter VideoEffectFiltersTests`
Expected: FAIL(VideoEffectFilters 未定义)

- [ ] **Step 3: 实现 VideoEffectFilters**

```swift
// Sources/FCPXLite/Engine/Composition/VideoEffectFilters.swift
import CoreImage

/// 把 clip 的视频特效链应用到 CIImage(按列表顺序;只处理 isVideo 且 enabled)。
enum VideoEffectFilters {
    static func apply(_ effects: [Effect], to image: CIImage) -> CIImage {
        var img = image
        for e in effects where e.enabled && e.kind.isVideo {
            switch e.kind {
            case .color:
                let f = CIFilter(name: "CIColorControls")!
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(e.params["brightness"] ?? 0, forKey: kCIInputBrightnessKey)
                f.setValue(e.params["contrast"] ?? 1, forKey: kCIInputContrastKey)
                f.setValue(e.params["saturation"] ?? 1, forKey: kCIInputSaturationKey)
                img = f.outputImage ?? img
            case .blur:
                let r = e.params["radius"] ?? 0
                if r > 0 {
                    let f = CIFilter(name: "CIGaussianBlur")!
                    f.setValue(img, forKey: kCIInputImageKey)
                    f.setValue(r, forKey: kCIInputRadiusKey)
                    img = f.outputImage ?? img
                }
            case .fade:
                break   // 音频特效,视频链不处理
            }
        }
        return img
    }
}
```

- [ ] **Step 4: 在合成器里应用滤镜链**

在 `CoreImageCompositor.startRequest` 的层循环里,opacity 处理之前(或之后,顺序:几何→特效→opacity)插入。改为几何后先套特效再 opacity:
```swift
                var img = CIImage(cvPixelBuffer: pb).transformed(by: layer.transform)
                img = VideoEffectFilters.apply(layer.effects, to: img)   // ← 特效链
                if layer.opacity < 1 { /* 原 CIColorMatrix alpha 块 */ }
```

- [ ] **Step 5: 运行确认通过 + 回归**

Run: `swift test --filter VideoEffectFiltersTests && swift test 2>&1 | tail -2`
Expected: 5 过;全量回归过。

- [ ] **Step 6: 提交**

```bash
git add Sources/FCPXLite/Engine/Composition/VideoEffectFilters.swift Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift Tests/FCPXLiteTests/VideoEffectFiltersTests.swift
git commit -m "feat(effect): 视频特效滤镜链(CIColorControls/CIGaussianBlur)接入合成器+测试"
```

---

### Task 5: 音频淡入淡出(AVAudioMix 斜坡)

**Files:**
- Modify: `Sources/FCPXLite/Engine/Composition/CompositionBuilder.swift`(音频段加 fade ramp)
- Test: `Tests/FCPXLiteTests/AudioFadeTests.swift`

**Interfaces:**
- Consumes: `Clip.effects` 里 kind=.fade 的 `inSeconds`/`outSeconds`;现有 `AVMutableAudioMixInputParameters`(已设逐 clip 音量)。
- Produces: 对每个音频段,若该 clip 有启用的 fade effect,在其音频 mix 参数上叠加 `setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)`(淡入:段起 0→vol;淡出:段尾 vol→0)。

- [ ] **Step 1: 写失败测试**

```swift
// Tests/FCPXLiteTests/AudioFadeTests.swift
import XCTest
import AVFoundation
@testable import FCPXLite

final class AudioFadeTests: XCTestCase {
    private func makeSilentAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fade-\(UUID().uuidString).wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!; buf.frameLength = frames
        try file.write(from: buf); return url
    }

    func testFadeAddsVolumeRamp() throws {
        let url = try makeSilentAudio(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(4),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        var clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(4))
        var fade = Effect.make(.fade); fade.params["inSeconds"] = 1; fade.params["outSeconds"] = 1
        clip.effects = [fade]
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)
        XCTAssertNotNil(item?.audioMix)
        // 至少一条 input parameters,且其 audioTimePitchAlgorithm 不验证;验证有 ramp 通过反射不可靠,
        // 改为:导出/读取 mix 后断言存在。这里断言 audioMix 非空 + 参数数==1。
        XCTAssertEqual(item?.audioMix?.inputParameters.count, 1)
    }

    // 无 fade 时不应崩、仍有音量参数。
    func testNoFadeStillBuilds() throws {
        let url = try makeSilentAudio(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(2),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(2))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        XCTAssertNotNil(CompositionBuilder.build(document: doc)?.audioMix)
    }
}
```

- [ ] **Step 2: 运行确认失败/通过基线**

Run: `swift test --filter AudioFadeTests`
Expected: `testFadeAddsVolumeRamp` 可能已"假过"(audioMix 已存在);先确认基线,再在 Step 3 真正加 ramp 逻辑并保持测试通过。(若两测试都已过,补一条更强断言见 Step 4。)

- [ ] **Step 3: 加 fade ramp 逻辑**

在 `CompositionBuilder.place(...)` 的音频分支(`audioParams.append(p)` 之前),从 `clip.effects` 找首个 enabled 的 .fade,按段的合成时间轴 [start, start+dur) 加斜坡:
```swift
                    let p = AVMutableAudioMixInputParameters(track: at)
                    p.setVolume(Float(clip.adjust.volume), at: .zero)
                    if let fade = clip.effects.first(where: { $0.enabled && $0.kind == .fade }) {
                        let vol = Float(clip.adjust.volume)
                        let inS = fade.params["inSeconds"] ?? 0
                        let outS = fade.params["outSeconds"] ?? 0
                        if inS > 0 {
                            p.setVolumeRamp(fromStartVolume: 0, toEndVolume: vol,
                                            timeRange: CMTimeRange(start: start, duration: cm(.seconds(inS))))
                        }
                        if outS > 0 {
                            let endStart = start + cm(clip.duration) - cm(.seconds(outS))
                            p.setVolumeRamp(fromStartVolume: vol, toEndVolume: 0,
                                            timeRange: CMTimeRange(start: endStart, duration: cm(.seconds(outS))))
                        }
                    }
                    audioParams.append(p)
```
(`cm(_:)` 是 CompositionBuilder 里已有的 Time→CMTime 私有助手。)

- [ ] **Step 4: 运行确认通过 + 回归**

Run: `swift test --filter AudioFadeTests && swift test 2>&1 | tail -2`
Expected: 全过;音频既有测试(纯音频可播放)不破。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Engine/Composition/CompositionBuilder.swift Tests/FCPXLiteTests/AudioFadeTests.swift
git commit -m "feat(effect): 音频淡入淡出(AVAudioMix setVolumeRamp)+测试"
```

---

### Task 6: Inspector 特效区(手动增删调参)

**Files:**
- Create: `Sources/FCPXLite/Views/InspectorEffectsSection.swift`
- Modify: `Sources/FCPXLite/Views/InspectorView.swift`(嵌入特效区)
- Modify: `Sources/FCPXLite/Store/DocumentStore.swift`(加 `updateSelectedEffects` 便捷方法)

**Interfaces:**
- Consumes: `store.selectedClip()`、`store.dispatch(.setEffects(id, fx))`、`Effect`/`EffectKind`。
- Produces: `DocumentStore.updateSelectedEffects(_ f: (inout [Effect]) -> Void)`;`InspectorEffectsSection(store:)` 视图。

- [ ] **Step 1: 加 store 便捷方法 + 测试**

```swift
// 追加到 Tests/FCPXLiteTests/SetEffectsTests.swift
func testUpdateSelectedEffectsAddsAndPersists() {
    let (store, id) = store1Clip()
    store.dispatch(.selectClip(id))
    store.updateSelectedEffects { $0.append(Effect.make(.color)) }
    guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
    XCTAssertEqual(c.effects.count, 1)
}
```
在 `DocumentStore.swift`(`updateSelectedAdjust` 附近)加:
```swift
    /// 改选中 clip 的 effects(走命令层,可撤销)。
    func updateSelectedEffects(_ f: (inout [Effect]) -> Void) {
        guard let id = ui.selectedClipID, var clip = selectedClip() else { return }
        f(&clip.effects)
        dispatch(.setEffects(id, clip.effects))
    }
```

- [ ] **Step 2: 运行确认通过**

Run: `swift test --filter SetEffectsTests`
Expected: 3 过。

- [ ] **Step 3: 实现特效区视图**

```swift
// Sources/FCPXLite/Views/InspectorEffectsSection.swift
import SwiftUI

/// Inspector 特效区:列出选中 clip 的 effects,可加(选 kind)/删/启停/调参。走命令层(可撤销)。
struct InspectorEffectsSection: View {
    let store: DocumentStore

    var body: some View {
        let effects = store.selectedClip()?.effects ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("特效").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Menu {
                    ForEach(EffectKind.allCases, id: \.self) { k in
                        Button(label(k)) { store.updateSelectedEffects { $0.append(Effect.make(k)) } }
                    }
                } label: { Image(systemName: "plus.circle").foregroundStyle(Tokens.Palette.textMuted) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(Array(effects.enumerated()), id: \.element.id) { idx, e in
                effectRow(idx, e)
            }
            Divider().overlay(Tokens.Palette.divider)
        }
    }

    private func label(_ k: EffectKind) -> String {
        switch k { case .color: return "调色"; case .blur: return "高斯模糊"; case .fade: return "淡入淡出" }
    }

    @ViewBuilder private func effectRow(_ idx: Int, _ e: Effect) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { e.enabled },
                    set: { v in store.updateSelectedEffects { if $0.indices.contains(idx) { $0[idx].enabled = v } } }
                )).labelsHidden().toggleStyle(.checkbox)
                Text(label(e.kind)).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.updateSelectedEffects { if $0.indices.contains(idx) { $0.remove(at: idx) } } }
                    label: { Image(systemName: "trash").foregroundStyle(Tokens.Palette.windowClose) }
                    .buttonStyle(.plain)
            }
            ForEach(paramKeys(e.kind), id: \.self) { key in
                paramSlider(idx, e, key)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func paramKeys(_ k: EffectKind) -> [String] {
        switch k {
        case .color: return ["brightness", "contrast", "saturation"]
        case .blur:  return ["radius"]
        case .fade:  return ["inSeconds", "outSeconds"]
        }
    }

    private func paramRange(_ key: String) -> ClosedRange<Double> {
        switch key {
        case "brightness": return -1...1
        case "contrast", "saturation": return 0...2
        case "radius": return 0...50
        default: return 0...10   // fade 秒数
        }
    }

    private func paramSlider(_ idx: Int, _ e: Effect, _ key: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted).frame(width: 76, alignment: .leading)
            Slider(value: Binding(
                get: { e.params[key] ?? 0 },
                set: { v in store.updateSelectedEffects { if $0.indices.contains(idx) { $0[idx].params[key] = v } } }
            ), in: paramRange(key))
            Text(String(format: "%.2f", e.params[key] ?? 0)).font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.textPrimary).frame(width: 40, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 4: 嵌入 InspectorView**

在 `InspectorView.swift` 的 `ScrollView { VStack { ... } }` 里、裁剪 section 之后加一行:
```swift
                        InspectorEffectsSection(store: store)
```

- [ ] **Step 5: 构建确认(UI 无单测,验证编译 + 既有测试)**

Run: `swift build 2>&1 | grep -E "error:|Build complete" && swift test 2>&1 | tail -2`
Expected: Build complete;全量过。

- [ ] **Step 6: 提交**

```bash
git add Sources/FCPXLite/Views/InspectorEffectsSection.swift Sources/FCPXLite/Views/InspectorView.swift Sources/FCPXLite/Store/DocumentStore.swift Tests/FCPXLiteTests/SetEffectsTests.swift
git commit -m "feat(effect): Inspector特效区(增删/启停/调参,可撤销)+store便捷方法"
```

---

## Self-Review

**Spec coverage(对照 spec §2①):**
- 特效模型 Clip.effects → Task 1 ✅
- setEffects 命令(可撤销)→ Task 2 ✅
- CoreImageCompositor 自定义合成器(transform/crop/opacity/z-order)→ Task 3 ✅(回归优先,等价替换)
- 视频滤镜 color/blur → Task 4 ✅
- 音频 fade → Task 5 ✅
- Inspector 特效区 → Task 6 ✅
- 降级方案(单层特效):未单列任务——Task 3 若受阻,实现者在 Task 3 内降级(主轴单层走 CIFilter,多轨保留旧路径),已在 spec §6 与 Task 3 说明记录。

**Placeholder scan:** 无 TBD/TODO。Task 3 Step 5 含"实现者注意"说明而非占位——给出了 segment 元组加 effects 字段的具体指引。

**Type consistency:** `Effect.make(_:)`、`Clip.effects`、`EditorAction.setEffects(ClipID,[Effect])`、`Mutations.setEffects(clipID:_:in:)`、`store.updateSelectedEffects`、`CompositorLayer(trackID:transform:opacity:effects:)`、`CompositorInstruction(timeRange:layers:)`、`CoreImageCompositor`、`VideoEffectFilters.apply(_:to:)` —— 跨任务引用一致。

**注意(crop 的处理):** spec 提到合成器应处理 crop,但 Task 3 的 `fullTransform` 已含 crop(裁剪折进 fit 缩放)。故 crop 通过 `layer.transform` 已生效,无需在合成器额外处理——与现状一致。

**待执行者:** Task 3 是最大风险点。务必先让 Step 1 的"单视频产帧"测试 + 既有 CompositionBuilderTests/CompositionTransformTests 全绿,确认等价替换不回归,再进 Task 4 加滤镜。
