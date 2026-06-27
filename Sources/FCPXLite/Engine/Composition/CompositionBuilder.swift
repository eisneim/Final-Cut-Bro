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
        var layers: [(track: AVMutableCompositionTrack, lane: Int, adjust: Adjustments)] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []

        func place(_ clip: Clip, at start: CMTime, lane: Int) {
            guard let asset = library[clip.assetID], asset.kind != .image else { return }
            let av = AVURLAsset(url: asset.url)
            let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))
            if let v = av.tracks(withMediaType: .video).first,   // deprecated 同步取轨,v1 可用
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try track.insertTimeRange(range, of: v, at: start)
                     inserted = true
                     layers.append((track, lane, clip.adjust))
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

        // 主轴(lane 0)
        var cursor = CMTime.zero
        for el in document.sequence.spine {
            let dur = cm(el.duration); defer { cursor = cursor + dur }
            if case .clip(let c) = el { place(c, at: cursor, lane: 0) }
        }
        // 连接片段
        let connected = collectConnected(document.sequence)
        for p in Layout.compute(document.sequence).filter({ $0.isConnected }) {
            if let c = connected[p.clipID] { place(c, at: cm(p.absStart), lane: p.lane) }
        }

        guard inserted, !layers.isEmpty else { return nil }

        let item = AVPlayerItem(asset: composition)
        let renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)
        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        inst.layerInstructions = layers.sorted { $0.lane < $1.lane }.map { layer in
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
