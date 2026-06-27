import AVFoundation
import CoreGraphics

/// 文档 → 可播放合成。
/// - 主轴(lane 0)视频+音频按 absStart 拼到基础视频轨 V0 + 音频轨 A0。
/// - 连接片段(lane!=0)各自一条视频轨 + 音频轨,叠加合成:
///   AVMutableVideoComposition 按 lane 由低到高(负→0→正)排 layerInstruction(高 lane 在上),
///   每层套用该 clip 的 transform(缩放/位移,绕中心),缩小上层即可看见下层 → 真正的层级。
/// - 所有轨道音频经 AVAudioMix 混音播放(逐 clip 音量)。
/// 静止图片暂跳过;空内容返回 nil。AVPlayer 实时解码合成,不重新编码。
enum CompositionBuilder {

    private static func cm(_ t: Time) -> CMTime { CMTime(value: t.value, timescale: t.timescale) }

    private struct VideoLayer { let track: AVMutableCompositionTrack; let lane: Int; let adjust: Adjustments }

    static func build(document: Document) -> AVPlayerItem? {
        let composition = AVMutableComposition()
        guard let spineVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let spineAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let library = Dictionary(uniqueKeysWithValues: document.assetLibrary.map { ($0.id, $0) })
        var inserted = false
        var videoLayers: [VideoLayer] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []

        func insertClip(_ clip: Clip, at start: CMTime, into video: AVMutableCompositionTrack, _ audio: AVMutableCompositionTrack) -> Bool {
            guard let asset = library[clip.assetID], asset.kind != .image else { return false }
            let av = AVURLAsset(url: asset.url)
            let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))
            var did = false
            if let v = av.tracks(withMediaType: .video).first {     // deprecated sync API, v1 可用
                do { try video.insertTimeRange(range, of: v, at: start); did = true }
                catch { print("[CompositionBuilder] video insert: \(error)") }
            }
            if asset.hasAudio, let a = av.tracks(withMediaType: .audio).first {
                do { try audio.insertTimeRange(range, of: a, at: start)
                     let p = AVMutableAudioMixInputParameters(track: audio)
                     p.setVolume(Float(clip.adjust.volume), at: .zero)
                     audioParams.append(p)
                } catch { print("[CompositionBuilder] audio insert: \(error)") }
            }
            return did
        }

        // 主轴(lane 0)
        var cursor = CMTime.zero
        for element in document.sequence.spine {
            let dur = cm(element.duration)
            defer { cursor = cursor + dur }
            guard case .clip(let clip) = element else { continue }
            if insertClip(clip, at: cursor, into: spineVideo, spineAudio) { inserted = true }
        }
        videoLayers.append(VideoLayer(track: spineVideo, lane: 0, adjust: Adjustments()))

        // 连接片段(各自一条轨,叠加)
        let placed = Layout.compute(document.sequence).filter { $0.isConnected }
        let connectedClips = collectConnected(document.sequence)   // id → Clip
        for p in placed {
            guard let clip = connectedClips[p.clipID] else { continue }
            guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            if insertClip(clip, at: cm(p.absStart), into: v, a) {
                inserted = true
                videoLayers.append(VideoLayer(track: v, lane: p.lane, adjust: clip.adjust))
            }
        }

        guard inserted else { return nil }

        let item = AVPlayerItem(asset: composition)

        // 仅当有叠加层时才构建 videoComposition(简单情形保持稳健)
        if videoLayers.count > 1 {
            let renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)
            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            // 由低 lane 到高 lane 排(数组先画=底层)
            inst.layerInstructions = videoLayers.sorted { $0.lane < $1.lane }.map { layer in
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: layer.track)
                li.setTransform(transform(for: layer.adjust, renderSize: renderSize), at: .zero)
                li.setOpacity(Float(layer.adjust.opacity), at: .zero)
                return li
            }
            let vc = AVMutableVideoComposition()
            vc.instructions = [inst]
            vc.renderSize = renderSize
            let fps = document.frameRate > 0 ? document.frameRate : 25
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            item.videoComposition = vc
        }

        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParams
            item.audioMix = mix
        }

        return item
    }

    /// 绕中心的 缩放 + 位移(v1 层级变换)。默认 scale=1/pos=0 → 单位变换(满屏覆盖)。
    /// 绕中心的 缩放 + 位移(显式仿射矩阵,避免链式拼接歧义)。
    /// x' = sw·x + tx,保持中心 (cx,cy) 不动:tx = cx·(1−sw) + posX。
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
            if case .clip(let c) = el {
                for child in c.connected { out[child.id] = child }
            }
        }
        return out
    }
}
