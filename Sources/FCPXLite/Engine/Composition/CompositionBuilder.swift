import AVFoundation
import CoreGraphics

/// 文档 → 可播放合成。每个 clip(主轴或连接)各自一条视频轨 + 音频轨:
/// - AVMutableVideoComposition 按 lane 由低到高排 layerInstruction(高 lane 在上),
///   每层套用该 clip 的 transform(缩放/位移,绕中心)+ opacity → inspector 调任意 clip 都生效,
///   缩小/降透明度上层即可看见下层(真层级)。
/// - AVAudioMix 逐 clip 音量,所有轨混音播放。
/// 静止图片暂跳过;空内容返回 nil。AVPlayer 实时解码合成,不重新编码。
enum CompositionBuilder {

    private static func cm(_ t: Time) -> CMTime { CMTime(value: t.value, timescale: t.timescale) }

    static func build(document: Document) -> AVPlayerItem? {
        let composition = AVMutableComposition()
        let library = Dictionary(uniqueKeysWithValues: document.assetLibrary.map { ($0.id, $0) })
        var inserted = false
        // 每段:轨 + lane + adjust + 在合成时间轴上的 [start,end)
        var segments: [(track: AVMutableCompositionTrack, lane: Int, adjust: Adjustments, start: CMTime, end: CMTime)] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []

        func place(_ clip: Clip, at start: CMTime, lane: Int) {
            guard let asset = library[clip.assetID], asset.kind != .image else { return }
            let av = AVURLAsset(url: asset.url)
            let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))
            if let v = av.tracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try track.insertTimeRange(range, of: v, at: start)
                     inserted = true
                     segments.append((track, lane, clip.adjust, start, start + cm(clip.duration)))
                } catch { print("[CompositionBuilder] video: \(error)") }
            }
            if asset.hasAudio, let a = av.tracks(withMediaType: .audio).first,
               let at = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try at.insertTimeRange(range, of: a, at: start)
                     let p = AVMutableAudioMixInputParameters(track: at)
                     p.setVolume(Float(clip.adjust.volume), at: .zero)
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

        guard inserted, !segments.isEmpty else { return nil }

        let item = AVPlayerItem(asset: composition)
        let renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)

        // 分段构建 instruction:在每个编辑点(各段 start/end)切一段,每段只含该时刻活跃的轨。
        // 单条覆盖全程的 instruction 在 clip 时间错开时会让变换串掉(bug6),故必须分段。
        var bounds = Set<CMTime>()
        for s in segments { bounds.insert(s.start); bounds.insert(s.end) }
        let sorted = bounds.sorted { $0 < $1 }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for i in 0..<max(0, sorted.count - 1) {
            let t0 = sorted[i], t1 = sorted[i + 1]
            guard t1 > t0 else { continue }
            // 该区间活跃的段(start<=t0 且 end>=t1),按 lane 升序(数组末=最上层)。
            let active = segments.filter { $0.start <= t0 && $0.end >= t1 }.sorted { $0.lane < $1.lane }
            guard !active.isEmpty else { continue }
            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: t0, end: t1)
            inst.layerInstructions = active.map { seg in
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: seg.track)
                li.setTransform(transform(for: seg.adjust, renderSize: renderSize), at: .zero)
                li.setOpacity(Float(seg.adjust.opacity), at: .zero)
                return li
            }
            instructions.append(inst)
        }

        let vc = AVMutableVideoComposition()
        vc.instructions = instructions
        vc.renderSize = renderSize
        let fps = document.frameRate > 0 ? document.frameRate : 25
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
        item.videoComposition = vc

        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix(); mix.inputParameters = audioParams; item.audioMix = mix
        }
        return item
    }

    /// 绕中心的 缩放 + 位移(显式仿射矩阵)。x' = sw·x + tx,保持中心不动:tx = cx·(1−sw) + posX。
    private static func transform(for adj: Adjustments, renderSize: CGSize) -> CGAffineTransform {
        let cx = renderSize.width / 2, cy = renderSize.height / 2
        let sw = adj.transform.scale.width, sh = adj.transform.scale.height
        let tx = cx * (1 - sw) + adj.transform.position.x
        let ty = cy * (1 - sh) + adj.transform.position.y
        return CGAffineTransform(a: sw, b: 0, c: 0, d: sh, tx: tx, ty: ty)
    }

    private static func collectConnected(_ seq: Sequence) -> [ClipID: Clip] {
        var out: [ClipID: Clip] = [:]
        for el in seq.spine {
            if case .clip(let c) = el { for child in c.connected { out[child.id] = child } }
        }
        return out
    }
}
