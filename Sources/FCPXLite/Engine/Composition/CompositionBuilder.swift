import AVFoundation
import CoreGraphics
import AppKit

/// 文档 → 可播放合成。每个 clip(主轴或连接)各自一条视频轨 + 音频轨:
/// - AVMutableVideoComposition 挂 CoreImageCompositor,按 lane 升序叠加(低 lane 在底,高 lane 在顶),
///   每层套用该 clip 的 transform(缩放/位移,绕中心)+ opacity + effects → inspector 调任意 clip 都生效。
/// - AVAudioMix 逐 clip 音量,所有轨混音播放。
/// 静止图片暂跳过;空内容返回 nil。AVPlayer 实时解码合成,不重新编码。
enum CompositionBuilder {

    private static func cm(_ t: Time) -> CMTime { CMTime(value: t.value, timescale: t.timescale) }

    static func build(document: Document) -> AVPlayerItem? {
        let composition = AVMutableComposition()
        let library = Dictionary(uniqueKeysWithValues: document.assetLibrary.map { ($0.id, $0) })
        var inserted = false
        // 每段:轨ID(图片段为 invalid)+ 可选静帧图 + lane + adjust + [start,end) + 原生尺寸/方向 + effects
        var segments: [(trackID: CMPersistentTrackID, image: CGImage?, lane: Int, adjust: Adjustments, start: CMTime, end: CMTime, natural: CGSize, pref: CGAffineTransform, effects: [Effect])] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []
        var totalEnd = CMTime.zero

        func place(_ clip: Clip, at start: CMTime, lane: Int) {
            guard clip.enabled else { return }   // 停用片段不参与预览/导出(时间线仍显示,只是变暗)
            guard let asset = library[clip.assetID] else { return }
            let end = start + cm(clip.duration)
            if end > totalEnd { totalEnd = end }
            // 图片:作为静帧层直接交给合成器(无轨),不走 AVAsset 轨道。
            if asset.kind == .image {
                guard let cg = NSImage(contentsOf: asset.url)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                inserted = true
                let natural = CGSize(width: cg.width, height: cg.height)
                segments.append((kCMPersistentTrackID_Invalid, cg, lane, clip.adjust, start, end,
                                 natural, .identity, clip.effects))
                return
            }
            let av = AVURLAsset(url: asset.url)
            let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))
            if let v = av.tracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try track.insertTimeRange(range, of: v, at: start)
                     inserted = true
                     segments.append((track.trackID, nil, lane, clip.adjust, start, start + cm(clip.duration),
                                      v.naturalSize, v.preferredTransform, clip.effects))
                } catch { print("[CompositionBuilder] video: \(error)") }
            }
            if asset.hasAudio, let a = av.tracks(withMediaType: .audio).first,
               let at = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try at.insertTimeRange(range, of: a, at: start)
                     inserted = true   // 纯音频也算"有内容":否则下面 guard 会让纯音乐轨返回 nil(无法播放)
                     let p = AVMutableAudioMixInputParameters(track: at)
                     let vol = Float(clip.adjust.volume)
                     let sortedKFs = clip.volumeKeyframes.sorted { $0.time < $1.time }
                     if sortedKFs.isEmpty {
                         // 原有路径:平音量 + fade 斜坡
                         p.setVolume(vol, at: .zero)
                         if let fade = clip.effects.first(where: { $0.enabled && $0.kind == .fade }) {
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
                     } else {
                         // 关键帧路径:分段斜坡
                         // 首关键帧之前:保持首帧音量
                         p.setVolume(Float(sortedKFs[0].value), at: start)
                         // 相邻关键帧之间:线性斜坡
                         for i in 0..<(sortedKFs.count - 1) {
                             let k0 = sortedKFs[i], k1 = sortedKFs[i + 1]
                             let rStart = start + cm(k0.time)
                             let rDur = cm(k1.time - k0.time)
                             if rDur > .zero {
                                 p.setVolumeRamp(fromStartVolume: Float(k0.value),
                                                 toEndVolume: Float(k1.value),
                                                 timeRange: CMTimeRange(start: rStart, duration: rDur))
                             }
                         }
                         // 末关键帧之后:保持末帧音量
                         if let last = sortedKFs.last {
                             p.setVolume(Float(last.value), at: start + cm(last.time))
                         }
                     }
                     audioParams.append(p)
                } catch { print("[CompositionBuilder] audio: \(error)") }
            }
        }

        var cursor = CMTime.zero
        for el in document.sequence.spine {
            let dur = cm(el.duration); defer { cursor = cursor + dur }
            if case .clip(let c) = el { place(c, at: cursor, lane: 0) }
        }
        let connected = collectConnected(document.sequence)
        for p in Layout.compute(document.sequence).filter({ $0.isConnected }) {
            if let c = connected[p.clipID] { place(c, at: cm(p.absStart), lane: p.lane) }
        }

        guard inserted else { return nil }   // 有任何视频或音频内容即可(纯音频不需要 videoComposition)

        // 全是图片(无任何真实音视频轨)→ composition 时长为 0,AVPlayer 无法播放。
        // 插一条真实的 1 帧透明视频(scaleTimeRange 拉伸到总时长)撑起时长,让合成器在这段时间内绘制静帧。
        let hasRealTrack = !composition.tracks(withMediaType: .video).isEmpty
            || !composition.tracks(withMediaType: .audio).isEmpty
        if !hasRealTrack, totalEnd > .zero,
           let blank = blankVideoURL() {
            let blankAsset = AVURLAsset(url: blank)
            if let v = blankAsset.tracks(withMediaType: .video).first,
               blankAsset.duration > .zero,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let srcRange = CMTimeRange(start: .zero, duration: blankAsset.duration)
                try? track.insertTimeRange(srcRange, of: v, at: .zero)
                track.scaleTimeRange(srcRange, toDuration: totalEnd)   // 拉伸 1 帧到整条时间线
            }
        }

        let item = AVPlayerItem(asset: composition)
        let renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)

        // 分段构建 instruction:在每个编辑点(各段 start/end)切一段,每段只含该时刻活跃的轨。
        // 单条覆盖全程的 instruction 在 clip 时间错开时会让变换串掉(bug6),故必须分段。
        // bounds 必须从 0 起,且空洞(gap/前导空白)也要发空 instruction —— 否则 AVFoundation
        // 的 videoComposition 出现未覆盖的时间区间会整体黑屏(只剩声音)。
        var bounds = Set<CMTime>([.zero])
        for s in segments { bounds.insert(s.start); bounds.insert(s.end) }
        let sorted = bounds.sorted { $0 < $1 }
        var instructions: [CompositorInstruction] = []
        for i in 0..<max(0, sorted.count - 1) {
            let t0 = sorted[i], t1 = sorted[i + 1]
            guard t1 > t0 else { continue }
            // 该区间活跃的段(start<=t0 且 end>=t1)。CoreImageCompositor 底→顶叠加:
            // 按 lane 升序(低 lane 在前=底层, 高 lane 在后=顶层)。
            let active = segments.filter { $0.start <= t0 && $0.end >= t1 }.sorted { $0.lane < $1.lane }
            // 空区间(gap):发一个空 layers 的 instruction(渲染黑帧),保证 instructions 连续无空洞。
            let layers = active.map { seg -> CompositorLayer in
                let xf = fullTransform(adjust: seg.adjust, natural: seg.natural,
                                       pref: seg.pref, renderSize: renderSize)
                return CompositorLayer(trackID: seg.trackID,
                                       image: seg.image,
                                       transform: xf,
                                       opacity: Float(seg.adjust.opacity),
                                       crop: seg.adjust.crop,
                                       effects: seg.effects)
            }
            instructions.append(CompositorInstruction(
                timeRange: CMTimeRange(start: t0, end: t1), layers: layers))
        }

        // 仅当有视频段时才建 videoComposition(纯音频轨没有视频,建空 instructions 会让 AVPlayer 报错/黑屏)。
        if !segments.isEmpty {
            let vc = AVMutableVideoComposition()
            vc.customVideoCompositorClass = CoreImageCompositor.self
            vc.instructions = instructions
            vc.renderSize = renderSize
            let fps = document.frameRate > 0 ? document.frameRate : 25
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            item.videoComposition = vc
        }

        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix(); mix.inputParameters = audioParams; item.audioMix = mix
        }
        return item
    }

    /// 完整层变换:源像素 → 渲染坐标,链式 = preferred(方向) → 居中 aspect-fit → 用户变换。
    /// 裁剪不在此处理(改为合成器里对源做矩形修剪 = trim,不缩放),避免"裁一点就跳满全屏"。
    static func fullTransform(adjust: Adjustments, natural: CGSize,
                              pref: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        // 应用 preferredTransform 后内容的显示尺寸(竖屏视频会旋成 H×W)。
        let oriented = CGRect(origin: .zero, size: natural).applying(pref)
        let dispW = abs(oriented.width), dispH = abs(oriented.height)
        guard dispW > 0, dispH > 0 else { return transform(for: adjust, renderSize: renderSize) }

        // 居中 aspect-fit:整帧等比放进画布并居中(保持比例,不裁画面,修复"没占满/叠加层显小")。
        let f = min(renderSize.width / dispW, renderSize.height / dispH)
        let fit = CGAffineTransform(a: f, b: 0, c: 0, d: f,
                                    tx: (renderSize.width - f * dispW) / 2,
                                    ty: (renderSize.height - f * dispH) / 2)

        // 用户变换(inspector 的缩放/旋转/位移,绕渲染中心)。
        let user = transform(for: adjust, renderSize: renderSize)
        return pref.concatenating(fit).concatenating(user)
    }

    /// 绕中心的 缩放 + 旋转 + 位移。先把渲染中心移到原点,套 缩放·旋转,再移回 + 位移。
    private static func transform(for adj: Adjustments, renderSize: CGSize) -> CGAffineTransform {
        let cx = renderSize.width / 2, cy = renderSize.height / 2
        let sw = adj.transform.scale.width, sh = adj.transform.scale.height
        let rot = adj.transform.rotation * .pi / 180
        // T = 移回中心+位移 · 旋转 · 缩放 · 移到原点
        var t = CGAffineTransform(translationX: -cx, y: -cy)
        t = t.concatenating(CGAffineTransform(scaleX: sw, y: sh))
        t = t.concatenating(CGAffineTransform(rotationAngle: rot))
        t = t.concatenating(CGAffineTransform(translationX: cx + adj.transform.position.x,
                                              y: cy + adj.transform.position.y))
        return t
    }

    // 缓存的 1 帧黑视频(供纯图片时间线撑时长)。
    private static var cachedBlankURL: URL?
    private static func blankVideoURL() -> URL? {
        if let u = cachedBlankURL, FileManager.default.fileExists(atPath: u.path) { return u }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fcpxlite-blank.mov")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: 16, AVVideoHeightKey: 16]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { return nil }
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &pb)
        if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 0, CVPixelBufferGetBytesPerRow(pb) * 16)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { usleep(500) }
            adaptor.append(pb, withPresentationTime: .zero)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))   // 视频长度 = 1s(便于按比例拉伸)
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        cachedBlankURL = url
        return url
    }

    private static func collectConnected(_ seq: Sequence) -> [ClipID: Clip] {
        var out: [ClipID: Clip] = [:]
        for el in seq.spine {
            if case .clip(let c) = el { for child in c.connected { out[child.id] = child } }
        }
        return out
    }
}
