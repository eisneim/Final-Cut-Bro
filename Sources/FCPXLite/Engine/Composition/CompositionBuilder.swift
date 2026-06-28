import AVFoundation
import CoreGraphics

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
        // 每段:轨 + lane + adjust + 在合成时间轴上的 [start,end) + 源视频原生尺寸/方向 + clip effects
        var segments: [(track: AVMutableCompositionTrack, lane: Int, adjust: Adjustments, start: CMTime, end: CMTime, natural: CGSize, pref: CGAffineTransform, effects: [Effect])] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []

        func place(_ clip: Clip, at start: CMTime, lane: Int) {
            guard clip.enabled else { return }   // 停用片段不参与预览/导出(时间线仍显示,只是变暗)
            guard let asset = library[clip.assetID], asset.kind != .image else { return }
            let av = AVURLAsset(url: asset.url)
            let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))
            if let v = av.tracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try track.insertTimeRange(range, of: v, at: start)
                     inserted = true
                     segments.append((track, lane, clip.adjust, start, start + cm(clip.duration),
                                      v.naturalSize, v.preferredTransform, clip.effects))
                } catch { print("[CompositionBuilder] video: \(error)") }
            }
            if asset.hasAudio, let a = av.tracks(withMediaType: .audio).first,
               let at = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try at.insertTimeRange(range, of: a, at: start)
                     inserted = true   // 纯音频也算"有内容":否则下面 guard 会让纯音乐轨返回 nil(无法播放)
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

        guard inserted else { return nil }   // 有任何视频或音频内容即可(纯音频不需要 videoComposition)

        let item = AVPlayerItem(asset: composition)
        let renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)

        // 分段构建 instruction:在每个编辑点(各段 start/end)切一段,每段只含该时刻活跃的轨。
        // 单条覆盖全程的 instruction 在 clip 时间错开时会让变换串掉(bug6),故必须分段。
        var bounds = Set<CMTime>()
        for s in segments { bounds.insert(s.start); bounds.insert(s.end) }
        let sorted = bounds.sorted { $0 < $1 }
        var instructions: [CompositorInstruction] = []
        for i in 0..<max(0, sorted.count - 1) {
            let t0 = sorted[i], t1 = sorted[i + 1]
            guard t1 > t0 else { continue }
            // 该区间活跃的段(start<=t0 且 end>=t1)。CoreImageCompositor 底→顶叠加:
            // 按 lane 升序(低 lane 在前=底层, 高 lane 在后=顶层)。
            let active = segments.filter { $0.start <= t0 && $0.end >= t1 }.sorted { $0.lane < $1.lane }
            guard !active.isEmpty else { continue }
            let layers = active.map { seg -> CompositorLayer in
                let xf = fullTransform(adjust: seg.adjust, natural: seg.natural,
                                       pref: seg.pref, renderSize: renderSize)
                return CompositorLayer(trackID: seg.track.trackID,
                                       transform: xf,
                                       opacity: Float(seg.adjust.opacity),
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

    /// 完整层变换:源像素 → 渲染坐标,链式 = preferred(方向) → 裁剪+居中 aspect-fit(归一化到 renderSize) → 用户变换。
    /// 这是关键修复:不同分辨率/方向的素材都先按比例填满画布并居中,叠加层不再因原生尺寸小而显小;裁剪在此真实生效。
    static func fullTransform(adjust: Adjustments, natural: CGSize,
                              pref: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        // 1) 应用 preferredTransform 后内容的显示尺寸(竖屏视频会旋成 H×W)。
        let oriented = CGRect(origin: .zero, size: natural).applying(pref)
        let dispW = abs(oriented.width), dispH = abs(oriented.height)
        guard dispW > 0, dispH > 0 else { return transform(for: adjust, renderSize: renderSize) }

        // 2) 裁剪(显示坐标,px):保留区域 = 去掉 上/下/左/右 后的子矩形。
        let cl = CGFloat(max(0, adjust.crop.left)),  cr = CGFloat(max(0, adjust.crop.right))
        let ct = CGFloat(max(0, adjust.crop.top)),   cb = CGFloat(max(0, adjust.crop.bottom))
        let cropW = max(1, dispW - cl - cr)
        let cropH = max(1, dispH - ct - cb)

        // 3) 缩放因子:
        //    - 无裁剪 → aspect-fit(min):整帧等比放进画布并居中(保持比例,不裁画面,修复"没占满/叠加层显小")。
        //    - 有裁剪 → aspect-fill(max):保留区铺满画布,被裁掉的边缘必然溢出 renderSize,由合成自然裁掉(真实裁剪)。
        let cropping = cl > 0 || cr > 0 || ct > 0 || cb > 0
        let f = cropping
            ? max(renderSize.width / cropW, renderSize.height / cropH)
            : min(renderSize.width / dispW, renderSize.height / dispH)
        let fit = CGAffineTransform(a: f, b: 0, c: 0, d: f,
                                    tx: (renderSize.width - f * cropW) / 2 - f * cl,
                                    ty: (renderSize.height - f * cropH) / 2 - f * ct)

        // 4) 用户变换(inspector 的缩放/位移,绕渲染中心)。
        let user = transform(for: adjust, renderSize: renderSize)
        return pref.concatenating(fit).concatenating(user)
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
